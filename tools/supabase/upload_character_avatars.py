#!/usr/bin/env python3
"""Upload local character avatars to Supabase Storage `characters` bucket.

- Reads PNGs from `assets/avatars/*.png`
- Uploads each to `characters/<code>.png` using the Supabase REST API with
  the service-role key (bypasses RLS — required for admin-only writes).
- Updates `characters.avatar_storage_path` for each row to the storage path.

Usage:
    python3 tools/supabase/upload_character_avatars.py --env dev
    python3 tools/supabase/upload_character_avatars.py --env prod --fail-on-existing
    python3 tools/supabase/upload_character_avatars.py --env prod --dry-run

Environment variables consulted (in order):
    SUPABASE_URL_{ENV}
    SUPABASE_SERVICE_ROLE_KEY_{ENV}

ENV defaults to 'dev'. Loaded from .env and .env.ops via python-dotenv if available.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import requests

try:
    # Best-effort; if not installed, expect env vars already exported.
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv(".env.ops")
except ImportError:
    pass


AVATARS_DIR = Path(__file__).resolve().parents[2] / "assets" / "avatars"
BUCKET = "characters"
RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}


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
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> str:
    url = f"{base_url}/storage/v1/object/{bucket}/{storage_path}"
    headers = {
        "Content-Type": "image/png",
        # `x-upsert: true` overwrites an existing object.
        "x-upsert": "true" if overwrite else "false",
        "cache-control": "3600",
    }
    response = request_with_retries(
        session,
        "POST",
        url,
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
        data=png_bytes,
        headers=headers,
    )
    # Supabase Storage quirk: duplicate objects return HTTP 400 with a JSON
    # body `{"statusCode": "409", "error": "Duplicate", ...}`. The top-level
    # status is 400, so we have to peek at the body to detect the dupe case.
    if response.status_code == 409 or _is_duplicate_body(response):
        if not overwrite:
            return "skipped_existing"
        # overwrite=True 였는데도 409 가 나온다면 진짜 예외 상황이니 raise
    if not response.ok:
        raise RuntimeError(
            f"upload failed for {storage_path}: "
            f"{response.status_code} {response.text}"
        )
    return "uploaded"


def request_with_retries(
    session: requests.Session,
    method: str,
    url: str,
    *,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
    **kwargs: object,
) -> requests.Response:
    attempts = max(1, retry_attempts)
    for attempt in range(1, attempts + 1):
        try:
            response = session.request(method, url, timeout=timeout_sec, **kwargs)
        except requests.exceptions.RequestException as exc:
            if attempt >= attempts:
                raise
            print(
                f"  [retry] {method} {url} failed on attempt "
                f"{attempt}/{attempts}: {exc}",
                file=sys.stderr,
            )
            time.sleep(retry_wait_sec)
            continue

        if (
            response.status_code in RETRYABLE_STATUS_CODES
            and attempt < attempts
        ):
            print(
                f"  [retry] {method} {url} returned {response.status_code} "
                f"on attempt {attempt}/{attempts}",
                file=sys.stderr,
            )
            time.sleep(retry_wait_sec)
            continue
        return response

    raise AssertionError("unreachable retry state")


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
    *,
    session: requests.Session,
    base_url: str,
    code: str,
    path: str,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> None:
    """Update the row's avatar_storage_path via PostgREST PATCH."""
    url = f"{base_url}/rest/v1/characters"
    response = request_with_retries(
        session,
        "PATCH",
        url,
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
        params={"code": f"eq.{code}"},
        json={"avatar_storage_path": path},
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
        "--fail-on-existing",
        action="store_true",
        help=(
            "Fail immediately if any object already exists. Use this for "
            "db-init bootstrap uploads where the bucket must be empty."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print what would be uploaded",
    )
    parser.add_argument(
        "--timeout-sec",
        type=int,
        default=60,
        help="HTTP request timeout in seconds (default: 60)",
    )
    parser.add_argument(
        "--retry-attempts",
        type=int,
        default=3,
        help="HTTP retry attempts for timeouts and transient 5xx/429 responses",
    )
    parser.add_argument(
        "--retry-wait-sec",
        type=float,
        default=3.0,
        help="Seconds to wait between retry attempts (default: 3)",
    )
    args = parser.parse_args()
    if args.timeout_sec <= 0:
        print("ERROR: --timeout-sec must be greater than 0", file=sys.stderr)
        return 2
    if args.retry_attempts <= 0:
        print("ERROR: --retry-attempts must be greater than 0", file=sys.stderr)
        return 2
    if args.retry_wait_sec < 0:
        print("ERROR: --retry-wait-sec must be 0 or greater", file=sys.stderr)
        return 2

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
        upload_status = upload_one(
            session=session,
            base_url=base_url,
            bucket=BUCKET,
            storage_path=storage_path,
            png_bytes=data,
            overwrite=args.overwrite,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
        if upload_status == "skipped_existing" and args.fail_on_existing:
            print(
                f"ERROR: {BUCKET}/{storage_path} already exists. "
                "`make upload-character-avatars` purges the characters bucket "
                "before uploading, so this means the purge did not actually "
                "empty the bucket. Check the purge log, or use "
                "`make upload-character-avatars-force` only if you intentionally "
                "want to overwrite existing Storage objects.",
                file=sys.stderr,
            )
            return 1
        update_avatar_path_rpc(
            session=session,
            base_url=base_url,
            code=code,
            path=storage_path,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
        if upload_status == "skipped_existing":
            print(
                f"  [skip] {path.name} already exists; "
                "avatar_storage_path patched"
            )
        else:
            print(f"  [ok] {path.name} -> {BUCKET}/{storage_path}")
        uploaded += 1

    print(f"Done: {uploaded}/{len(avatar_paths)} avatars processed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
