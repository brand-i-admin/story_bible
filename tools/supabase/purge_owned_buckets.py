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

Behaviour if `SUPABASE_SERVICE_ROLE_KEY_<ENV>` is missing:
  Warn and exit 0 so `make db-init` still proceeds. (The 409-skip handler in
  `upload_character_avatars.py` will still keep things safe on next run.)

Usage:
    python3 tools/supabase/purge_owned_buckets.py --env dev
"""

from __future__ import annotations

import argparse
import os
import sys

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass


BUCKETS = ("characters", "proposal-scenes", "proposal-characters")


def env_var(name: str, env_suffix: str) -> str | None:
    return (
        os.environ.get(f"{name}_{env_suffix.upper()}")
        or os.environ.get(name)
    )


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
    if r.status_code == 404:
        return True, "bucket not found (first init?) — skip"
    return False, f"HTTP {r.status_code}: {r.text[:200]}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Empty app-owned Supabase Storage buckets."
    )
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
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
    for bucket in BUCKETS:
        ok, msg = empty_bucket(session, url, bucket)
        if ok:
            print(f"[purge-owned-buckets] {bucket}: {msg}")
        else:
            any_fail = True
            print(f"[purge-owned-buckets] WARN: {bucket}: {msg}")

    return 1 if (any_fail and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
