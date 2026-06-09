#!/usr/bin/env python3
"""Export published events from Supabase back into assets/200_stories/*.json.

DB-first 운영 흐름을 위해 어드민이 published 한 events 를 정기적으로 JSON 으로
역추출한다. 이렇게 하면 빌더 (build_character_meta_json.py / build_characters_seed_sql.py /
build_200_stories_seed_sql.py) 가 변경 사항을 자동으로 따라잡고, git history 로도
콘텐츠 변경을 추적할 수 있다.

사용:
    python tools/export/export_events_to_json.py --output-dir assets/200_stories
    python tools/export/export_events_to_json.py --dry-run   # JSON 파일 안 쓰고 표준출력으로

환경:
    .env 의 SUPABASE_URL_DEV / SUPABASE_ANON_KEY_DEV (또는 PROD) 사용.
    Pure read-only 라 anon key 로 충분 (events RLS: status='published' 공개 SELECT).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

# 키 출력 순서 — 사람이 보던 JSON 포맷과 일치.
_KEY_ORDER = [
    "title",
    "era",
    "characters",
    "place_name",
    "lat",
    "lng",
    "summary",
    "bible_ref",
    "start_year",
    "end_year",
    "time_precision",
    "story_index",
    "story_scenes",
    "scene_characters",
]


def event_row_to_json(row: dict[str, Any]) -> dict[str, Any]:
    """Supabase events row (era_code 가 join 으로 함께 들어온다고 가정) → JSON dict.

    DB 컬럼 매핑:
      - era_code  → "era"
      - character_codes (text[]) → "characters"
      - bible_refs (jsonb)    → "bible_ref"
      - 나머지는 그대로
    """
    out: dict[str, Any] = {
        "title": row.get("title", ""),
        "era": row.get("era_code", ""),
        "characters": list(row.get("character_codes") or []),
        "place_name": row.get("place_name") or "",
        "lat": row.get("lat"),
        "lng": row.get("lng"),
        "summary": row.get("summary") or "",
        "bible_ref": list(row.get("bible_refs") or []),
        "start_year": row.get("start_year"),
        "end_year": row.get("end_year"),
        "time_precision": row.get("time_precision") or "approx",
        "story_index": int(row.get("story_index") or 0),
        "story_scenes": list(row.get("story_scenes") or []),
        "scene_characters": [
            list(s or []) for s in (row.get("scene_characters") or [])
        ],
    }
    # KEY_ORDER 순서로 재구성 (Python 3.7+ dict 는 삽입 순서 유지).
    return {key: out[key] for key in _KEY_ORDER if key in out}


def filename_for_era(era_code: str | None) -> str:
    """Return the era-scoped story source filename.

    Story JSON is intentionally grouped by era so `story_index` can stay
    era-scoped and source diffs line up with the app's era navigation.
    """
    normalized = (era_code or "").strip()
    if not normalized:
        normalized = "unknown_era"
    return f"{normalized}.json"


def group_events_by_era_file(
    rows: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    """rows 를 era 파일명으로 그룹화 + 파일 안에서 story_index 오름차순 정렬."""
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        idx = int(row.get("story_index") or 0)
        if idx <= 0:
            continue
        filename = filename_for_era(row.get("era_code"))
        grouped.setdefault(filename, []).append(event_row_to_json(row))
    for era_rows in grouped.values():
        era_rows.sort(key=lambda r: r.get("story_index", 0))
    return dict(grouped)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default="assets/200_stories",
        help="era JSON 파일을 쓸 디렉토리.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="파일 안 쓰고 표준출력으로 dump.",
    )
    parser.add_argument(
        "--env",
        default="dev",
        choices=["dev", "prod"],
        help="SUPABASE_URL/ANON_KEY 의 suffix (DEV/PROD).",
    )
    parser.add_argument(
        "--env-file",
        default=".env",
        help=".env 파일 경로.",
    )
    return parser.parse_args()


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _fetch_published_events(env_suffix: str) -> list[dict[str, Any]]:
    """Supabase REST 로 events + eras.code 조인해서 가져온다.

    supabase-py 가 있으면 그걸 쓰고, 없으면 가벼운 requests 호출로 대체.
    """
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

    rest = url.rstrip("/") + "/rest/v1/events"
    params = {
        "select": (
            "title,summary,character_codes,bible_refs,story_scenes,scene_characters,"
            "place_name,lat,lng,start_year,end_year,time_precision,story_index,"
            "era:era_id(code)"
        ),
        "status": "eq.published",
        "order": "story_index.asc",
    }
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    rows: list[dict[str, Any]] = []
    offset = 0
    page = 1000
    while True:
        params_paged = dict(params)
        params_paged["limit"] = str(page)
        params_paged["offset"] = str(offset)
        resp = requests.get(rest, params=params_paged, headers=headers, timeout=30)
        resp.raise_for_status()
        chunk = resp.json()
        if not chunk:
            break
        for r in chunk:
            era = r.pop("era", None)
            if isinstance(era, dict):
                r["era_code"] = era.get("code")
            rows.append(r)
        if len(chunk) < page:
            break
        offset += page
    return rows


def main() -> int:
    args = parse_args()
    _load_env_file(Path(args.env_file))
    env_suffix = args.env.upper()

    rows = _fetch_published_events(env_suffix)
    grouped = group_events_by_era_file(rows)

    if args.dry_run:
        json.dump(
            grouped,
            sys.stdout,
            ensure_ascii=False,
            indent=2,
        )
        sys.stdout.write("\n")
        print(
            f"\n# fetched: {len(rows)} events, " f"era files: {sorted(grouped.keys())}",
            file=sys.stderr,
        )
        return 0

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for filename, era_rows in grouped.items():
        path = out_dir / filename
        path.write_text(
            json.dumps(era_rows, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {path} ({len(era_rows)} stories)")

    print(f"done: total {len(rows)} events → {len(grouped)} era files in {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
