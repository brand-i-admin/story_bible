#!/usr/bin/env python3
"""Upload local character avatars to Supabase Storage `characters` bucket.

- Reads PNGs from `assets/avatars/*.png`
- Uploads each to `characters/<code>.png` using the Supabase REST API with
  the service-role key (bypasses RLS — required for admin-only writes).
- Updates `characters.avatar_storage_path` for each row to the storage path.

Usage:
    python3 tools/supabase/upload_character_avatars.py --env dev
    python3 tools/supabase/upload_character_avatars.py --env prod --dry-run

Environment variables consulted (in order):
    SUPABASE_URL_{ENV}
    SUPABASE_SERVICE_ROLE_KEY_{ENV}

ENV defaults to 'dev'. Loaded from .env via python-dotenv if available.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import requests

try:
    # Best-effort; if not installed, expect env vars already exported.
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass


AVATARS_DIR = Path(__file__).resolve().parents[2] / "assets" / "avatars"
BUCKET = "characters"


def env_var(name: str, env_suffix: str) -> str | None:
    key = f"{name}_{env_suffix.upper()}"
    value = os.environ.get(key)
    if value:
        return value
    # Fallback to the unsuffixed variant (e.g., SUPABASE_URL).
    return os.environ.get(name)


def upload_one(
    *,
    session: requests.Session,
    base_url: str,
    bucket: str,
    storage_path: str,
    png_bytes: bytes,
    overwrite: bool,
) -> None:
    url = f"{base_url}/storage/v1/object/{bucket}/{storage_path}"
    headers = {
        "Content-Type": "image/png",
        # `x-upsert: true` overwrites an existing object.
        "x-upsert": "true" if overwrite else "false",
        "cache-control": "3600",
    }
    response = session.post(url, data=png_bytes, headers=headers, timeout=60)
    # Supabase Storage quirk: duplicate objects return HTTP 400 with a JSON
    # body `{"statusCode": "409", "error": "Duplicate", ...}`. The top-level
    # status is 400, so we have to peek at the body to detect the dupe case.
    if response.status_code == 409 or _is_duplicate_body(response):
        if not overwrite:
            print(
                f"  [skip] {storage_path} already exists "
                "(use --overwrite to replace)"
            )
            return
        # overwrite=True 였는데도 409 가 나온다면 진짜 예외 상황이니 raise
    if not response.ok:
        raise RuntimeError(
            f"upload failed for {storage_path}: "
            f"{response.status_code} {response.text}"
        )


def _is_duplicate_body(response: requests.Response) -> bool:
    """Supabase Storage 가 400 + `error: Duplicate` 로 응답하는 케이스 감지."""
    try:
        body = response.json()
    except ValueError:
        return False
    if not isinstance(body, dict):
        return False
    if str(body.get("statusCode", "")) == "409":
        return True
    if body.get("error") == "Duplicate":
        return True
    msg = str(body.get("message", "")).lower()
    return "already exists" in msg or "duplicate" in msg


def update_avatar_path_rpc(
    *, session: requests.Session, base_url: str, code: str, path: str
) -> None:
    """Update the row's avatar_storage_path via PostgREST PATCH."""
    url = f"{base_url}/rest/v1/characters"
    response = session.patch(
        url,
        params={"code": f"eq.{code}"},
        json={"avatar_storage_path": path},
        timeout=30,
    )
    if not response.ok:
        raise RuntimeError(
            f"failed to patch characters.avatar_storage_path for {code}: "
            f"{response.status_code} {response.text}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Upload character avatars to Supabase Storage."
    )
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument(
        "--avatars-dir",
        type=Path,
        default=AVATARS_DIR,
        help="Local avatar PNG directory (default: assets/avatars)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing objects (x-upsert: true)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print what would be uploaded",
    )
    args = parser.parse_args()

    base_url = env_var("SUPABASE_URL", args.env)
    service_key = env_var("SUPABASE_SERVICE_ROLE_KEY", args.env)
    if not base_url:
        print(
            f"ERROR: SUPABASE_URL_{args.env.upper()} (or SUPABASE_URL) not set",
            file=sys.stderr,
        )
        return 2
    if not service_key and not args.dry_run:
        print(
            f"ERROR: SUPABASE_SERVICE_ROLE_KEY_{args.env.upper()} not set. "
            "This script requires the service_role key to upload (it writes to "
            "Storage + patches `characters.avatar_storage_path`).",
            file=sys.stderr,
        )
        return 2

    avatar_paths = sorted(args.avatars_dir.glob("*.png"))
    if not avatar_paths:
        print(f"ERROR: no PNG files found in {args.avatars_dir}", file=sys.stderr)
        return 2

    print(
        f"Uploading {len(avatar_paths)} avatars to "
        f"{base_url} bucket={BUCKET} "
        f"(overwrite={args.overwrite}, dry_run={args.dry_run})"
    )

    session = requests.Session()
    if service_key:
        session.headers.update(
            {
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
            }
        )

    uploaded = 0
    for path in avatar_paths:
        code = path.stem  # e.g. "abraham"
        storage_path = f"{code}.png"
        if args.dry_run:
            print(f"  [dry-run] {path.name} -> {BUCKET}/{storage_path}")
            uploaded += 1
            continue

        data = path.read_bytes()
        upload_one(
            session=session,
            base_url=base_url,
            bucket=BUCKET,
            storage_path=storage_path,
            png_bytes=data,
            overwrite=args.overwrite,
        )
        update_avatar_path_rpc(
            session=session, base_url=base_url, code=code, path=storage_path
        )
        print(f"  [ok] {path.name} -> {BUCKET}/{storage_path}")
        uploaded += 1

    print(f"Done: {uploaded}/{len(avatar_paths)} avatars processed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
