#!/usr/bin/env python3
"""Export quiz_questions from Supabase into assets/quizzes/*.json.

This is the release-sync companion to ``export_events_to_json.py``. Approved
proposal quizzes live in the DB first; this script brings them back into the
canonical per-story quiz JSON files used by the seed builder and app release
workflow.
"""

from __future__ import annotations

import argparse
from datetime import date
import json
import os
import sys
from pathlib import Path
from typing import Any

QUESTION_TYPES = ("fact", "attitude", "story_context")
CONFUSED_CHOICE_LABEL = "헷갈렸어요"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="assets/quizzes")
    parser.add_argument(
        "--events-output",
        default="supabase/quizzes/db_events.json",
        help="DB event snapshot for build_quizzes_seed_sql.py --events-from-json.",
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


def _fetch_published_events_and_quizzes(
    env_suffix: str,
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
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
    base_url = url.rstrip("/")
    events_url = base_url + "/rest/v1/events"
    quiz_url = base_url + "/rest/v1/quiz_questions"

    events = _request_json(
        session,
        events_url,
        params={
            "select": "id,title,story_index,era:era_id(code)",
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

    event_ids = [str(row["id"]) for row in events if row.get("id")]
    quiz_rows: list[dict[str, Any]] = []
    chunk_size = 80
    for offset in range(0, len(event_ids), chunk_size):
        chunk = event_ids[offset : offset + chunk_size]
        if not chunk:
            continue
        quiz_rows.extend(
            _request_json(
                session,
                quiz_url,
                params={
                    "select": (
                        "event_id,question,choice_a,choice_b,choice_c,choice_d,"
                        "answer_index,explanation,display_order"
                    ),
                    "event_id": f"in.({','.join(chunk)})",
                    "order": "display_order.asc",
                },
                label="quiz_questions",
            )
        )

    by_event: dict[str, list[dict[str, Any]]] = {}
    for row in quiz_rows:
        by_event.setdefault(str(row.get("event_id")), []).append(row)
    for rows in by_event.values():
        rows.sort(key=lambda item: int(item.get("display_order") or 0))
    return events, by_event


def filename_for_quiz(era_code: str, story_index: int) -> str:
    return f"{era_code}_n{story_index:03d}.json"


def quiz_row_to_json(row: dict[str, Any]) -> dict[str, Any]:
    order = int(row.get("display_order") or 0)
    question_type = QUESTION_TYPES[order] if order < len(QUESTION_TYPES) else "fact"
    return {
        "type": question_type,
        "display_order": order,
        "question": str(row.get("question") or ""),
        "choices": [
            str(row.get("choice_a") or ""),
            str(row.get("choice_b") or ""),
            str(row.get("choice_c") or ""),
        ],
        "answer_index": int(row.get("answer_index") or 0),
        "explanation": str(row.get("explanation") or ""),
    }


def existing_source_versions(output_dir: Path) -> dict[tuple[str, int], str]:
    versions: dict[tuple[str, int], str] = {}
    for path in output_dir.glob("era_*_n*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        era_code = payload.get("era_code")
        story_index = payload.get("story_index")
        source_version = payload.get("source_version")
        if isinstance(era_code, str) and isinstance(story_index, int):
            if isinstance(source_version, str) and source_version.strip():
                versions[(era_code, story_index)] = source_version
    return versions


def build_quiz_payloads(
    events: list[dict[str, Any]],
    quizzes_by_event: dict[str, list[dict[str, Any]]],
    *,
    source_versions: dict[tuple[str, int], str] | None = None,
    default_source_version: str | None = None,
) -> dict[str, dict[str, Any]]:
    source_versions = source_versions or {}
    default_source_version = default_source_version or date.today().isoformat()
    payloads: dict[str, dict[str, Any]] = {}
    for event in events:
        era_code = str(event.get("era_code") or "").strip()
        story_index = int(event.get("story_index") or 0)
        if not era_code or story_index <= 0:
            continue
        quiz_rows = quizzes_by_event.get(str(event.get("id")), [])
        if not quiz_rows:
            continue
        filename = filename_for_quiz(era_code, story_index)
        payloads[filename] = {
            "era_code": era_code,
            "story_index": story_index,
            "story_title": str(event.get("title") or ""),
            "source_version": source_versions.get(
                (era_code, story_index),
                default_source_version,
            ),
            "questions": [quiz_row_to_json(row) for row in quiz_rows],
        }
    return dict(sorted(payloads.items()))


def main() -> int:
    args = parse_args()
    _load_env_file(Path(args.env_file))
    env_suffix = args.env.upper()
    output_dir = Path(args.output_dir)

    events, quizzes = _fetch_published_events_and_quizzes(env_suffix)
    payloads = build_quiz_payloads(
        events,
        quizzes,
        source_versions=existing_source_versions(output_dir),
    )
    events_snapshot = [
        {
            "era_code": row.get("era_code"),
            "story_index": row.get("story_index"),
            "title": row.get("title"),
        }
        for row in events
    ]

    if args.dry_run:
        json.dump(payloads, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        print(
            f"# fetched {len(events)} events, {len(payloads)} quiz file(s)",
            file=sys.stderr,
        )
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    for filename, payload in payloads.items():
        (output_dir / filename).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {output_dir / filename}")

    events_output = Path(args.events_output)
    events_output.parent.mkdir(parents=True, exist_ok=True)
    events_output.write_text(
        json.dumps(events_snapshot, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"done: {len(payloads)} quiz file(s), event snapshot → {events_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
