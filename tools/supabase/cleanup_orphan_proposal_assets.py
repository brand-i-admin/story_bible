#!/usr/bin/env python3
"""Delete orphan files from `proposal-scenes` and `proposal-characters` buckets.

A file is **orphan** when:
  (1) older than `--min-age-hours` (default 24h), AND
  (2) no `event_proposals` row references its full `bucket/path`.

Why this script exists:
  Edge Functions upload AI-generated images to Storage **immediately** when
  the pastor clicks "이미지 생성" in the proposal form. But `event_proposals`
  is only INSERTed when they click "제안 등록". If the pastor closes the tab
  mid-draft (or regenerates many times), the early uploads become unreachable
  orphans. GCP generation costs are already spent, but Storage keeps billing
  for the bytes. This script sweeps those orphans.

Safety:
  - 24h grace window means "in-progress drafts" (opened this afternoon) stay
    safe overnight. Operators should run this at low-traffic hours.
  - Referenced paths are fetched from **all** event_proposals rows regardless
    of status (pending / approved / rejected). Rejected proposals' images
    are NOT auto-cleaned — if you want them gone, manually delete the row
    first (cascade) or extend this script.
  - `--dry-run` prints what would happen without touching anything.

Usage:
    python3 tools/supabase/cleanup_orphan_proposal_assets.py --env dev [--dry-run]
    python3 tools/supabase/cleanup_orphan_proposal_assets.py --env prod --min-age-hours 48
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from typing import Any

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass


BUCKETS = ["proposal-scenes", "proposal-characters"]


def env_var(name: str, env_suffix: str) -> str | None:
    return os.environ.get(f"{name}_{env_suffix.upper()}") or os.environ.get(name)


def list_bucket_recursively(
    session: requests.Session,
    base_url: str,
    bucket: str,
    prefix: str = "",
) -> list[dict[str, Any]]:
    """Recursively walk a storage bucket and return flat list of file entries.

    Supabase's list API returns "folder" pseudo-entries (with id=null) for any
    path segment that has children. We recurse into those; only entries with a
    concrete `id` are real files. Paging via offset in batches of 1000.
    """
    out: list[dict[str, Any]] = []
    offset = 0
    while True:
        response = session.post(
            f"{base_url}/storage/v1/object/list/{bucket}",
            json={
                "prefix": prefix,
                "limit": 1000,
                "offset": offset,
                "sortBy": {"column": "name", "order": "asc"},
            },
            timeout=60,
        )
        if not response.ok:
            raise RuntimeError(
                f"list {bucket}:{prefix} failed: {response.status_code} {response.text}"
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
                # Folder — recurse
                sub_prefix = f"{full_path}/"
                out.extend(
                    list_bucket_recursively(session, base_url, bucket, sub_prefix)
                )
            else:
                out.append(
                    {
                        "path": full_path,
                        "created_at": item.get("created_at"),
                        "updated_at": item.get("updated_at"),
                        "size": (item.get("metadata") or {}).get("size"),
                    }
                )
        if len(batch) < 1000:
            break
        offset += 1000
    return out


def fetch_referenced_paths(session: requests.Session, base_url: str) -> set[str]:
    """Union of every bucket path referenced anywhere in event_proposals.

    Two sources:
      - event_proposals.scene_image_paths (text[])
      - event_proposals.proposed_characters[*].storage_path (jsonb)

    Both are already `bucket/path` form (see Edge Function response contract).
    """
    url = f"{base_url}/rest/v1/event_proposals"
    response = session.get(
        url,
        params={"select": "scene_image_paths,proposed_characters"},
        timeout=60,
    )
    if not response.ok:
        raise RuntimeError(
            f"GET event_proposals failed: {response.status_code} {response.text}"
        )

    refs: set[str] = set()
    for row in response.json():
        for path in row.get("scene_image_paths") or []:
            if isinstance(path, str) and path:
                refs.add(path)
        for ch in row.get("proposed_characters") or []:
            if not isinstance(ch, dict):
                continue
            path = ch.get("storage_path")
            if isinstance(path, str) and path:
                refs.add(path)
    return refs


def delete_object(
    session: requests.Session, base_url: str, bucket: str, path: str
) -> None:
    response = session.delete(
        f"{base_url}/storage/v1/object/{bucket}/{path}", timeout=30
    )
    if response.status_code not in (200, 204, 404):
        raise RuntimeError(
            f"delete {bucket}/{path} failed: {response.status_code} {response.text}"
        )


def parse_iso(raw: str | None) -> dt.datetime | None:
    if not raw:
        return None
    try:
        # Supabase returns ISO8601 with 'Z' suffix; Python 3.11+ fromisoformat
        # handles it natively, 3.10 needs the manual replace.
        normalized = raw.replace("Z", "+00:00") if raw.endswith("Z") else raw
        return dt.datetime.fromisoformat(normalized)
    except ValueError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Delete orphan proposal assets from Supabase Storage."
    )
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument(
        "--min-age-hours",
        type=int,
        default=24,
        help="Files younger than this are always kept (default 24h grace window)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print what would be deleted; do not modify Storage",
    )
    args = parser.parse_args()

    base_url = env_var("SUPABASE_URL", args.env)
    service_key = env_var("SUPABASE_SERVICE_ROLE_KEY", args.env)
    if not base_url:
        print(
            f"ERROR: SUPABASE_URL_{args.env.upper()} not set",
            file=sys.stderr,
        )
        return 2
    if not service_key and not args.dry_run:
        print(
            f"ERROR: SUPABASE_SERVICE_ROLE_KEY_{args.env.upper()} not set "
            "(required for listing / deleting; --dry-run can run without)",
            file=sys.stderr,
        )
        return 2

    session = requests.Session()
    if service_key:
        session.headers.update(
            {"apikey": service_key, "Authorization": f"Bearer {service_key}"}
        )

    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(hours=args.min_age_hours)
    print(
        f"Cutoff: files older than {args.min_age_hours}h "
        f"(created_at < {cutoff.isoformat()}) considered for cleanup"
    )

    refs = fetch_referenced_paths(session, base_url)
    print(f"Referenced paths in event_proposals: {len(refs)}")

    totals = {"deleted": 0, "kept_referenced": 0, "kept_too_young": 0, "skipped": 0}

    for bucket in BUCKETS:
        print(f"\n== {bucket}")
        try:
            files = list_bucket_recursively(session, base_url, bucket)
        except Exception as exc:  # noqa: BLE001
            print(f"  WARN: could not list {bucket}: {exc}")
            continue
        print(f"  total files: {len(files)}")

        for entry in files:
            full_ref = f"{bucket}/{entry['path']}"
            created = parse_iso(entry.get("created_at"))
            if created is None:
                totals["skipped"] += 1
                continue

            is_referenced = full_ref in refs
            is_old_enough = created < cutoff

            if is_referenced:
                totals["kept_referenced"] += 1
                continue
            if not is_old_enough:
                totals["kept_too_young"] += 1
                continue

            age = now - created
            print(
                f"  [orphan] {full_ref}  age={age}  "
                f"{'(would delete)' if args.dry_run else '(deleting)'}"
            )
            if not args.dry_run:
                try:
                    delete_object(session, base_url, bucket, entry["path"])
                except Exception as exc:  # noqa: BLE001
                    print(f"    ERROR: {exc}")
                    continue
            totals["deleted"] += 1

    print("\n=== Summary ===")
    print(f"  deleted:         {totals['deleted']}")
    print(f"  kept_referenced: {totals['kept_referenced']}")
    print(f"  kept_too_young:  {totals['kept_too_young']}")
    print(f"  skipped:         {totals['skipped']}")
    print(f"  dry_run:         {args.dry_run}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
