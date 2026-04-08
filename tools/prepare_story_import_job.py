#!/usr/bin/env python3
"""Stage a user-provided story JSON as a reviewable import job bundle.

This script does not touch production DB rows or canonical asset directories.
It validates the input JSON, records job metadata, and generates build outputs
using tools/build_200_stories_seed_sql.py inside a job-scoped staging folder.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import shutil
import subprocess
import sys
import uuid
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare a staged import-job bundle from a story JSON payload.",
    )
    parser.add_argument(
        "--input-json",
        required=True,
        help="Path to the user-provided story JSON file.",
    )
    parser.add_argument(
        "--user-id",
        required=True,
        help="Application or operator user id associated with the import request.",
    )
    parser.add_argument(
        "--job-id",
        help="Optional preallocated import job id. When provided, reuse it.",
    )
    parser.add_argument(
        "--job-root",
        default=".omx/import_jobs",
        help="Directory where staged job bundles are written.",
    )
    parser.add_argument(
        "--verse-source-sql",
        default="supabase/seeds/krv_bible_verses.sql",
        help="Verse source SQL passed through to build_200_stories_seed_sql.py.",
    )
    parser.add_argument(
        "--avatar-prompt-json",
        default="tools/avatar_prompts.json",
        help="Avatar prompt JSON passed through to build_200_stories_seed_sql.py.",
    )
    parser.add_argument(
        "--base-normalized-json",
        default="supabase/200_stories/200_stories_normalized.json",
        help="Existing normalized catalog used for diff summary generation.",
    )
    return parser.parse_args()


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json_list(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("Top-level JSON payload must be a list of story rows.")
    rows = [item for item in payload if isinstance(item, dict)]
    if len(rows) != len(payload):
        raise ValueError("Every story row must be a JSON object.")
    return rows


def validate_story_rows(rows: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    seen_codes: set[str] = set()
    seen_numbers: set[int] = set()

    for index, row in enumerate(rows, start=1):
        raw_title = str(row.get("title") or "").strip()
        raw_era = str(row.get("era_code") or row.get("era") or "").strip()
        if not raw_title:
            errors.append(f"row {index}: title is required")
        if not raw_era:
            errors.append(f"row {index}: era or era_code is required")

        raw_persons = row.get("persons")
        if raw_persons is not None and not isinstance(raw_persons, list):
            errors.append(f"row {index}: persons must be a list when provided")

        raw_number = row.get("number")
        if raw_number is not None:
            if not isinstance(raw_number, int):
                errors.append(f"row {index}: number must be an integer when provided")
            elif raw_number in seen_numbers:
                errors.append(f"row {index}: duplicate number {raw_number}")
            else:
                seen_numbers.add(raw_number)

        raw_code = str(row.get("code") or "").strip()
        if raw_code:
            if raw_code in seen_codes:
                errors.append(f"row {index}: duplicate code {raw_code}")
            else:
                seen_codes.add(raw_code)

        raw_timeline_rank = row.get("timeline_rank")
        if raw_timeline_rank is not None:
            try:
                float(raw_timeline_rank)
            except (TypeError, ValueError):
                errors.append(
                    f"row {index}: timeline_rank must be numeric when provided"
                )

    return errors


def build_job_id(source_sha256: str) -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"job_{stamp}_{source_sha256[:10]}_{uuid.uuid4().hex[:8]}"


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_base_catalog(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        return {}
    catalog: dict[str, dict[str, Any]] = {}
    for item in data:
        if not isinstance(item, dict):
            continue
        code = str(item.get("code") or "").strip()
        if code:
            catalog[code] = item
    return catalog


def build_diff_summary(
    base_catalog: dict[str, dict[str, Any]],
    normalized_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    added_codes: list[str] = []
    changed_codes: list[str] = []
    unchanged_codes: list[str] = []

    tracked_fields = (
        "title",
        "era_code",
        "display_number",
        "timeline_rank",
        "start_year",
        "end_year",
        "time_sort_key",
        "persons",
    )

    for row in normalized_rows:
        code = str(row.get("code") or "").strip()
        if not code:
            continue
        existing = base_catalog.get(code)
        if existing is None:
            added_codes.append(code)
            continue
        if any(existing.get(field) != row.get(field) for field in tracked_fields):
            changed_codes.append(code)
        else:
            unchanged_codes.append(code)

    return {
        "input_event_count": len(normalized_rows),
        "added_codes": added_codes,
        "changed_codes": changed_codes,
        "unchanged_codes": unchanged_codes,
    }


def main() -> int:
    args = parse_args()
    input_json = Path(args.input_json)
    if not input_json.exists():
        raise FileNotFoundError(f"Input JSON not found: {input_json}")

    rows = load_json_list(input_json)
    validation_errors = validate_story_rows(rows)
    source_sha256 = sha256_for_file(input_json)
    job_id = args.job_id.strip() if args.job_id else build_job_id(source_sha256)
    if not job_id:
        raise ValueError("job_id must not be empty when provided")

    job_root = Path(args.job_root)
    job_dir = job_root / job_id
    raw_dir = job_dir / "raw"
    build_dir = job_dir / "build"
    review_dir = job_dir / "review"
    raw_dir.mkdir(parents=True, exist_ok=True)
    build_dir.mkdir(parents=True, exist_ok=True)
    review_dir.mkdir(parents=True, exist_ok=True)

    staged_input = raw_dir / input_json.name
    shutil.copy2(input_json, staged_input)

    metadata = {
        "job_id": job_id,
        "user_id": args.user_id,
        "source_name": input_json.name,
        "source_sha256": source_sha256,
        "status": "validated" if not validation_errors else "failed_validation",
        "requested_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_event_count": len(rows),
        "validation_errors": validation_errors,
    }
    write_json(job_dir / "job.json", metadata)

    if validation_errors:
        print(f"job id             : {job_id}")
        print(f"staged input       : {staged_input}")
        print(f"validation errors  : {len(validation_errors)}")
        for error in validation_errors:
            print(f"  - {error}")
        return 1

    missing_prerequisites = [
        str(path)
        for path in (Path(args.verse_source_sql), Path(args.avatar_prompt_json))
        if not path.exists()
    ]
    if missing_prerequisites:
        metadata["status"] = "validated_only"
        metadata["missing_prerequisites"] = missing_prerequisites
        write_json(job_dir / "job.json", metadata)
        print(f"job id             : {job_id}")
        print(f"staged input       : {staged_input}")
        print("status             : validated_only")
        print("missing prerequisites:")
        for path in missing_prerequisites:
            print(f"  - {path}")
        return 0

    build_cmd = [
        sys.executable,
        "tools/build_200_stories_seed_sql.py",
        "--input-dir",
        str(raw_dir),
        "--output-dir",
        str(build_dir),
        "--verse-source-sql",
        args.verse_source_sql,
        "--avatar-prompt-json",
        args.avatar_prompt_json,
        "--split-parts",
        "0",
    ]
    subprocess.run(build_cmd, check=True)

    normalized_path = build_dir / "200_stories_normalized.json"
    normalized_rows = load_json_list(normalized_path)
    diff_summary = build_diff_summary(
        load_base_catalog(Path(args.base_normalized_json)),
        normalized_rows,
    )
    write_json(review_dir / "diff_summary.json", diff_summary)

    metadata["status"] = "build_ready"
    metadata["build_outputs"] = {
        "normalized_json": str(normalized_path),
        "seed_sql": str(build_dir / "200_stories_seed.sql"),
        "report_json": str(build_dir / "200_stories_report.json"),
        "diff_summary_json": str(review_dir / "diff_summary.json"),
    }
    write_json(job_dir / "job.json", metadata)

    print(f"job id             : {job_id}")
    print(f"staged input       : {staged_input}")
    print(f"build dir          : {build_dir}")
    print(f"review summary     : {review_dir / 'diff_summary.json'}")
    print("status             : build_ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
