#!/usr/bin/env python3
"""Export DB event landmark assignments into event_region_mapping.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="assets/landmarks/event_region_mapping.json",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument("--env-file", default=".env")
    return parser.parse_args()


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def _request_json(
    session: Any,
    url: str,
    *,
    params: dict[str, str],
    label: str,
) -> list[dict[str, Any]]:
    response = session.get(url, params=params, timeout=60)
    if not response.ok:
        raise SystemExit(
            f"ERROR: failed to fetch {label}: {response.status_code} {response.text}"
        )
    rows = response.json()
    if not isinstance(rows, list):
        raise SystemExit(f"ERROR: invalid {label} response")
    return [dict(row) for row in rows]


def _fetch_events_and_landmarks(
    env_suffix: str,
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    url = os.environ.get(f"SUPABASE_URL_{env_suffix}")
    key = os.environ.get(f"SUPABASE_ANON_KEY_{env_suffix}")
    if not url or not key:
        raise SystemExit(
            f"ERROR: SUPABASE_URL_{env_suffix} / SUPABASE_ANON_KEY_{env_suffix} "
            "가 .env 에 없습니다."
        )

    try:
        import requests  # type: ignore
    except ImportError as exc:
        raise SystemExit("requests 가 필요합니다: pip install requests") from exc

    session = requests.Session()
    session.headers.update({"apikey": key, "Authorization": f"Bearer {key}"})
    base = url.rstrip("/") + "/rest/v1"

    landmarks = _request_json(
        session,
        f"{base}/landmarks",
        params={"select": "id,code,name,kind,parent_landmark_id", "limit": "2000"},
        label="landmarks",
    )
    landmarks_by_id = {str(row["id"]): row for row in landmarks if row.get("id")}

    events = _request_json(
        session,
        f"{base}/events",
        params={
            "select": "title,story_index,landmark_id,era:era_id(code)",
            "status": "eq.published",
            "deleted_at": "is.null",
            "order": "story_index.asc",
            "limit": "1000",
        },
        label="published events",
    )
    for row in events:
        era = row.pop("era", None)
        row["era_code"] = era.get("code") if isinstance(era, dict) else None
    return events, landmarks_by_id


def event_row_to_mapping(
    event: dict[str, Any],
    landmarks_by_id: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    era_code = str(event.get("era_code") or "").strip()
    story_index = int(event.get("story_index") or 0)
    landmark_id = str(event.get("landmark_id") or "").strip()
    landmark = landmarks_by_id.get(landmark_id)
    if not era_code or story_index <= 0 or not landmark:
        return None
    landmark_code = str(landmark.get("code") or "").strip()
    parent_id = str(landmark.get("parent_landmark_id") or "").strip()
    parent = landmarks_by_id.get(parent_id)
    region_code = (
        landmark_code
        if landmark.get("kind") == "region"
        else str((parent or {}).get("code") or "").strip()
    )
    if not region_code:
        region_code = landmark_code
    return {
        "story_index": story_index,
        "title": str(event.get("title") or ""),
        "era": era_code,
        "place_name": str(landmark.get("name") or ""),
        "region_code": region_code,
        "landmark_code": landmark_code,
    }


def build_mapping_payload(
    events: list[dict[str, Any]],
    landmarks_by_id: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    rows = [
        row
        for row in (event_row_to_mapping(event, landmarks_by_id) for event in events)
        if row is not None
    ]
    rows.sort(key=lambda row: (row["era"], row["story_index"]))
    return {
        "_doc": "사건 → 새 region/landmark 매핑. DB events.landmark_id 기준 export.",
        "rows": rows,
    }


def main() -> int:
    args = parse_args()
    _load_env_file(Path(args.env_file))
    events, landmarks_by_id = _fetch_events_and_landmarks(args.env.upper())
    payload = build_mapping_payload(events, landmarks_by_id)

    if args.dry_run:
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        print(
            f"# fetched {len(events)} events, {len(payload['rows'])} mapping row(s)",
            file=sys.stderr,
        )
        return 0

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {output} ({len(payload['rows'])} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
