#!/usr/bin/env python3
"""Empty the three app-owned Supabase Storage buckets via REST API.

Invoked by `make db-init` **before** psql runs db_init.sql so that the
subsequent `make upload-character-avatars` starts from a clean slate.

Why REST and not SQL:
  Supabase hosts a `storage.protect_delete()` trigger on both storage.objects
  and storage.buckets that rejects direct SQL DELETE
  ("Direct deletion from storage tables is not allowed. Use the Storage API
  instead."). The Storage REST API bypasses the trigger because it coordinates
  metadata + actual file deletion atomically.

Buckets emptied:
  - characters           (canonical cast avatars — uploaded fresh by
                          upload-character-avatars after db-init)
  - proposal-scenes      (AI-generated scene PNGs for proposals)
  - proposal-characters  (AI-generated new-character avatars for proposals)

**profile-images is NOT touched** — user-uploaded content. db-init must not
destroy user data; operators can manually empty it from Dashboard if they're
on a disposable dev project.

**story-image-sources is NOT touched** — release-builder source PNG archive.
It is intentionally preserved across db-init so another machine can restore
`assets/story_images/` without regenerating or reuploading 2GB+ of originals.

Behaviour if `SUPABASE_SERVICE_ROLE_KEY_<ENV>` is missing:
  Default direct script usage warns and exits 0. `make db-init` passes
  `--strict`, so missing keys or purge failures stop the reset before SQL runs.

Usage:
    python3 tools/supabase/purge_owned_buckets.py --env dev
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any
from urllib.parse import quote

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv(".env.ops")
except ImportError:
    pass


BUCKETS = ("characters", "proposal-scenes", "proposal-characters")


def env_var(name: str, env_suffix: str) -> str | None:
    return os.environ.get(f"{name}_{env_suffix.upper()}") or os.environ.get(name)


def empty_bucket(
    session: requests.Session, base_url: str, bucket: str
) -> tuple[bool, str]:
    """Call Supabase `POST /storage/v1/bucket/{name}/empty`.

    Returns (ok, message). 404 is treated as OK (bucket doesn't exist yet
    on first ever init).
    """
    url = f"{base_url.rstrip('/')}/storage/v1/bucket/{bucket}/empty"
    try:
        r = session.post(url, timeout=60)
    except requests.RequestException as exc:
        return False, f"request error: {exc}"
    if r.ok:
        return True, f"emptied"
    if r.status_code == 404 or _is_bucket_not_found_body(r):
        return True, "bucket not found (first init?) — skip"
    return False, f"HTTP {r.status_code}: {r.text[:200]}"


def purge_bucket(
    session: requests.Session,
    base_url: str,
    bucket: str,
) -> tuple[bool, str]:
    """Empty a bucket, then verify and delete any remaining objects directly."""
    ok, message = empty_bucket(session, base_url, bucket)
    if not ok:
        return False, message
    if "bucket not found" in message:
        return True, message

    try:
        remaining = list_bucket_recursively(session, base_url, bucket)
    except BucketNotFound:
        return True, "bucket not found after empty — skip"
    except RuntimeError as exc:
        return False, str(exc)

    if not remaining:
        return True, f"{message}; verified empty"

    deleted = 0
    for item in remaining:
        path = item["path"]
        ok, delete_message = delete_object(session, base_url, bucket, path)
        if not ok:
            return False, delete_message
        deleted += 1

    try:
        after_delete = list_bucket_recursively(session, base_url, bucket)
    except BucketNotFound:
        return True, f"{message}; deleted {deleted} leftover objects"
    except RuntimeError as exc:
        return False, str(exc)

    if after_delete:
        return False, f"{len(after_delete)} objects still remain after delete"
    return True, f"{message}; deleted {deleted} leftover objects"


class BucketNotFound(RuntimeError):
    pass


def list_bucket_recursively(
    session: requests.Session,
    base_url: str,
    bucket: str,
    prefix: str = "",
) -> list[dict[str, Any]]:
    """Recursively list real file objects in a Storage bucket."""
    out: list[dict[str, Any]] = []
    offset = 0
    while True:
        response = session.post(
            f"{base_url.rstrip('/')}/storage/v1/object/list/{bucket}",
            json={
                "prefix": prefix,
                "limit": 1000,
                "offset": offset,
                "sortBy": {"column": "name", "order": "asc"},
            },
            timeout=60,
        )
        if response.status_code == 404 or _is_bucket_not_found_body(response):
            raise BucketNotFound(bucket)
        if not response.ok:
            raise RuntimeError(
                f"list {bucket}:{prefix} failed: "
                f"HTTP {response.status_code}: {response.text[:200]}"
            )

        batch = response.json()
        if not batch:
            break
        for item in batch:
            name = item.get("name")
            if not name:
                continue
            full_path = f"{prefix}{name}" if prefix else name
            if item.get("id") is None:
                out.extend(
                    list_bucket_recursively(
                        session,
                        base_url,
                        bucket,
                        f"{full_path}/",
                    )
                )
            else:
                out.append({"path": full_path})
        if len(batch) < 1000:
            break
        offset += 1000
    return out


def delete_object(
    session: requests.Session,
    base_url: str,
    bucket: str,
    path: str,
) -> tuple[bool, str]:
    encoded_path = quote(path, safe="/")
    response = session.delete(
        f"{base_url.rstrip('/')}/storage/v1/object/{bucket}/{encoded_path}",
        timeout=30,
    )
    if response.status_code in (200, 204, 404) or _is_object_not_found_body(response):
        return True, "deleted"
    return (
        False,
        f"delete {bucket}/{path} failed: "
        f"HTTP {response.status_code}: {response.text[:200]}",
    )


def _is_bucket_not_found_body(response: requests.Response) -> bool:
    """Supabase Storage sometimes returns HTTP 400 with a 404 JSON body."""
    return _is_not_found_body(response, expected_message="bucket not found")


def _is_object_not_found_body(response: requests.Response) -> bool:
    """Supabase Storage may return HTTP 400 with an object 404 JSON body."""
    return _is_not_found_body(response, expected_message="object not found")


def _is_not_found_body(
    response: requests.Response,
    *,
    expected_message: str,
) -> bool:
    try:
        body = response.json()
    except ValueError:
        return False
    if not isinstance(body, dict):
        return False
    status_code = str(body.get("statusCode", ""))
    message = str(body.get("message", "")).lower()
    error = str(body.get("error", "")).lower()
    return status_code == "404" and (
        expected_message in message or expected_message in error
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Empty app-owned Supabase Storage buckets."
    )
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument(
        "--bucket",
        choices=BUCKETS,
        action="append",
        help=(
            "Only purge this bucket. Can be passed multiple times. "
            "Defaults to all app-owned buckets."
        ),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 if keys are missing (default: warn + exit 0)",
    )
    args = parser.parse_args()

    url = env_var("SUPABASE_URL", args.env)
    key = env_var("SUPABASE_SERVICE_ROLE_KEY", args.env)
    if not url or not key:
        print(
            f"[purge-owned-buckets] SUPABASE_URL_{args.env.upper()} or "
            f"SUPABASE_SERVICE_ROLE_KEY_{args.env.upper()} not set — "
            "Storage purge skipped. db-init will proceed; you can run "
            "`make upload-character-avatars-force` later to overwrite any "
            "stale files."
        )
        return 1 if args.strict else 0

    session = requests.Session()
    session.headers.update({"apikey": key, "Authorization": f"Bearer {key}"})

    any_fail = False
    target_buckets = tuple(args.bucket) if args.bucket else BUCKETS
    for bucket in target_buckets:
        ok, msg = purge_bucket(session, url, bucket)
        if ok:
            print(f"[purge-owned-buckets] {bucket}: {msg}")
        else:
            any_fail = True
            print(f"[purge-owned-buckets] WARN: {bucket}: {msg}")

    return 1 if (any_fail and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
