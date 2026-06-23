#!/usr/bin/env python3
"""Upload one local story draft as a pending event proposal.

Input layout:

    assets/story_drafts/20260623_elijah_ravens.json
    assets/story_drafts/20260623_elijah_ravens/
      scene_01.png
      scene_02.png

The script does not publish the event. It uploads scene source images to the
`proposal-scenes` bucket and inserts one `event_proposals` row with
`status='pending'`, so the existing admin approval UI/RPC remains the final
gate.
"""

from __future__ import annotations

import argparse
import glob
import json
import mimetypes
import os
from pathlib import Path
import sys
from typing import Any

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv(".env.ops")
except ImportError:
    pass


REPO_ROOT = Path(__file__).resolve().parents[2]
BUCKET = "proposal-scenes"
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--story",
        action="append",
        default=[],
        help="Draft JSON path, e.g. assets/story_drafts/20260623_slug.json.",
    )
    parser.add_argument(
        "--stories-glob",
        default="",
        help="Optional glob for multiple draft JSON files, e.g. assets/story_drafts/202606*.json.",
    )
    parser.add_argument(
        "--env",
        default="dev",
        choices=["dev", "prod"],
        help="SUPABASE_URL/SERVICE_ROLE_KEY suffix.",
    )
    parser.add_argument(
        "--proposer-user-id",
        default="",
        help=(
            "auth.users.id used as event_proposals.proposer_user_id. Defaults "
            "to STORY_DRAFT_PROPOSER_USER_ID_{ENV} or STORY_DRAFT_PROPOSER_USER_ID."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print payload without uploading or inserting.",
    )
    return parser.parse_args()


def resolve_story_paths(args: argparse.Namespace) -> list[Path]:
    paths: list[Path] = []
    for raw in args.story:
        candidate = Path(raw)
        paths.append(
            candidate if candidate.is_absolute() else (REPO_ROOT / candidate).resolve()
        )
    if args.stories_glob:
        pattern = args.stories_glob
        if Path(pattern).is_absolute():
            matches = [Path(path) for path in glob.glob(pattern)]
        else:
            matches = [Path(path) for path in glob.glob(str(REPO_ROOT / pattern))]
        paths.extend(path.resolve() for path in sorted(matches) if path.is_file())
    unique: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(resolved)
    if not unique:
        raise SystemExit(
            "ERROR: --story or --stories-glob is required. "
            "Example: --story assets/story_drafts/20260623_slug.json"
        )
    return unique


def env_var(name: str, env_suffix: str) -> str | None:
    suffix = env_suffix.upper()
    return os.environ.get(f"{name}_{suffix}") or os.environ.get(name)


def proposer_user_id(env_suffix: str, explicit: str) -> str:
    candidates = [
        explicit,
        env_var("STORY_DRAFT_PROPOSER_USER_ID", env_suffix) or "",
        env_var("SUPABASE_PROPOSER_USER_ID", env_suffix) or "",
        env_var("SUPABASE_ADMIN_USER_ID", env_suffix) or "",
    ]
    for value in candidates:
        value = value.strip()
        if value:
            return value
    raise SystemExit(
        "ERROR: proposer user id is required. Set "
        "STORY_DRAFT_PROPOSER_USER_ID_DEV/PROD in .env.ops or pass "
        "--proposer-user-id."
    )


def service_session(env_suffix: str) -> tuple[requests.Session, str]:
    base_url = env_var("SUPABASE_URL", env_suffix)
    service_key = env_var("SUPABASE_SERVICE_ROLE_KEY", env_suffix)
    if not base_url or not service_key:
        raise SystemExit(
            f"ERROR: SUPABASE_URL_{env_suffix.upper()} / "
            f"SUPABASE_SERVICE_ROLE_KEY_{env_suffix.upper()} is missing."
        )
    session = requests.Session()
    session.headers.update(
        {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
        }
    )
    return session, base_url.rstrip("/")


def load_single_event(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and isinstance(data.get("events"), list):
        events = data["events"]
    elif isinstance(data, list):
        events = data
    elif isinstance(data, dict):
        events = [data]
    else:
        raise SystemExit(f"ERROR: invalid draft JSON: {path}")
    if len(events) != 1 or not isinstance(events[0], dict):
        raise SystemExit("ERROR: apply-draft expects exactly one event object.")
    return dict(events[0])


def required_text(event: dict[str, Any], key: str) -> str:
    value = str(event.get(key) or "").strip()
    if not value:
        raise SystemExit(f"ERROR: draft field is required: {key}")
    return value


def string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def nested_string_list(value: Any, length: int) -> list[list[str]]:
    result: list[list[str]] = []
    if isinstance(value, list):
        for item in value[:length]:
            result.append(string_list(item))
    while len(result) < length:
        result.append([])
    return result


def map_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [dict(item) for item in value if isinstance(item, dict)]


def rest_get_single(
    session: requests.Session,
    base_url: str,
    table: str,
    params: dict[str, str],
    label: str,
) -> dict[str, Any]:
    response = session.get(
        f"{base_url}/rest/v1/{table}",
        params=params,
        timeout=60,
    )
    if not response.ok:
        raise SystemExit(
            f"ERROR: lookup failed for {label}: {response.status_code} {response.text}"
        )
    rows = response.json()
    if len(rows) != 1:
        raise SystemExit(f"ERROR: expected one {label}, got {len(rows)}")
    return rows[0]


def rest_get_many(
    session: requests.Session,
    base_url: str,
    table: str,
    params: dict[str, str],
    label: str,
) -> list[dict[str, Any]]:
    response = session.get(
        f"{base_url}/rest/v1/{table}",
        params=params,
        timeout=60,
    )
    if not response.ok:
        raise SystemExit(
            f"ERROR: lookup failed for {label}: {response.status_code} {response.text}"
        )
    rows = response.json()
    if not isinstance(rows, list):
        raise SystemExit(f"ERROR: invalid lookup response for {label}")
    return [dict(row) for row in rows]


def normalized_title(title: str) -> str:
    return " ".join(title.strip().lower().split())


def ensure_title_available(
    session: requests.Session,
    base_url: str,
    title: str,
) -> None:
    """Mirror submit_event_proposal's duplicate title guard for direct inserts."""

    target = normalized_title(title)
    event_rows = rest_get_many(
        session,
        base_url,
        "events",
        {
            "select": "id,title",
            "title": f"ilike.{title}",
            "deleted_at": "is.null",
            "limit": "10",
        },
        f"active event title {title}",
    )
    for row in event_rows:
        if normalized_title(str(row.get("title") or "")) == target:
            raise SystemExit(
                f'ERROR: active event with the same title already exists: "{title}"'
            )

    proposal_rows = rest_get_many(
        session,
        base_url,
        "event_proposals",
        {
            "select": "id,title",
            "title": f"ilike.{title}",
            "proposal_type": "eq.new",
            "status": "eq.pending",
            "limit": "10",
        },
        f"pending proposal title {title}",
    )
    for row in proposal_rows:
        if normalized_title(str(row.get("title") or "")) == target:
            raise SystemExit(
                f'ERROR: pending proposal with the same title already exists: "{title}"'
            )


def resolve_era_id(
    session: requests.Session,
    base_url: str,
    event: dict[str, Any],
) -> str:
    era_id = str(event.get("era_id") or "").strip()
    if era_id:
        return era_id
    era_code = required_text(event, "era")
    row = rest_get_single(
        session,
        base_url,
        "eras",
        {"select": "id", "code": f"eq.{era_code}"},
        f"era code {era_code}",
    )
    return str(row["id"])


def resolve_landmark_id(
    session: requests.Session,
    base_url: str,
    event: dict[str, Any],
) -> str:
    landmark_id = str(event.get("landmark_id") or "").strip()
    if landmark_id:
        return landmark_id
    landmark_code = str(event.get("landmark_code") or "").strip()
    if landmark_code:
        row = rest_get_single(
            session,
            base_url,
            "landmarks",
            {"select": "id", "code": f"eq.{landmark_code}"},
            f"landmark code {landmark_code}",
        )
        return str(row["id"])
    place_name = str(event.get("place_name") or "").strip()
    if place_name:
        row = rest_get_single(
            session,
            base_url,
            "landmarks",
            {"select": "id", "name": f"eq.{place_name}"},
            f"landmark name {place_name}",
        )
        return str(row["id"])
    raise SystemExit(
        "ERROR: one of landmark_id, landmark_code, place_name is required."
    )


def find_scene_image(draft_dir: Path, scene_index: int) -> Path:
    stem = f"scene_{scene_index:02d}"
    for ext in IMAGE_EXTS:
        candidate = draft_dir / f"{stem}{ext}"
        if candidate.exists():
            return candidate
    raise SystemExit(f"ERROR: missing scene image: {draft_dir}/{stem}.*")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def upload_scene(
    session: requests.Session,
    base_url: str,
    local_path: Path,
    *,
    proposer_id: str,
    draft_slug: str,
    scene_index: int,
) -> str:
    ext = local_path.suffix.lower()
    object_path = f"{proposer_id}/{draft_slug}/scene_{scene_index:02d}{ext}"
    mime = mimetypes.guess_type(local_path.name)[0] or "application/octet-stream"
    response = session.post(
        f"{base_url}/storage/v1/object/{BUCKET}/{object_path}",
        data=local_path.read_bytes(),
        headers={
            "Content-Type": mime,
            "x-upsert": "true",
            "cache-control": "3600",
        },
        timeout=120,
    )
    if not response.ok:
        raise SystemExit(
            f"ERROR: upload failed for {local_path}: {response.status_code} "
            f"{response.text}"
        )
    return f"{BUCKET}/{object_path}"


def validate_event(event: dict[str, Any]) -> tuple[list[str], list[str]]:
    required_text(event, "title")
    required_text(event, "summary")
    required_text(event, "background_context")
    scenes = string_list(event.get("story_scenes"))
    captions = string_list(event.get("scene_captions"))
    if not scenes:
        raise SystemExit("ERROR: story_scenes must contain at least one scene.")
    if len(captions) != len(scenes):
        raise SystemExit(
            "ERROR: scene_captions length must match story_scenes length "
            f"({len(captions)} != {len(scenes)})."
        )
    validate_quizzes(event)
    return scenes, captions


def validate_quizzes(event: dict[str, Any]) -> None:
    quizzes = map_list(event.get("quiz_questions"))
    if len(quizzes) < 1 or len(quizzes) > 3:
        raise SystemExit(
            f"ERROR: quiz_questions must contain 1~3 quiz objects (got {len(quizzes)})."
        )
    for index, quiz in enumerate(quizzes, start=1):
        question = str(quiz.get("question") or "").strip()
        if not question:
            raise SystemExit(f"ERROR: quiz_questions[{index}].question is required.")
        raw_choices = quiz.get("choices")
        if not isinstance(raw_choices, list):
            raise SystemExit(f"ERROR: quiz_questions[{index}].choices must be a list.")
        choices = [str(item).strip() for item in raw_choices]
        if len(choices) not in (3, 4):
            raise SystemExit(
                f"ERROR: quiz_questions[{index}].choices must have 3 authored choices "
                f"(or legacy 4 including confused choice), got {len(choices)}."
            )
        if any(not choice for choice in choices[:3]):
            raise SystemExit(
                f"ERROR: quiz_questions[{index}].choices[0..2] must not be empty."
            )
        try:
            answer_index = int(quiz.get("answer_index"))
        except (TypeError, ValueError):
            raise SystemExit(
                f"ERROR: quiz_questions[{index}].answer_index must be 0, 1, or 2."
            ) from None
        if answer_index < 0 or answer_index > 2:
            raise SystemExit(
                f"ERROR: quiz_questions[{index}].answer_index must be 0, 1, or 2 "
                f"(got {answer_index})."
            )
        if not str(quiz.get("explanation") or "").strip():
            raise SystemExit(f"ERROR: quiz_questions[{index}].explanation is required.")


def build_payload(
    event: dict[str, Any],
    *,
    proposer_id: str,
    era_id: str,
    landmark_id: str,
    scenes: list[str],
    captions: list[str],
    scene_image_paths: list[str],
) -> dict[str, Any]:
    return {
        "proposal_type": "new",
        "proposer_user_id": proposer_id,
        "era_id": era_id,
        "title": required_text(event, "title"),
        "summary": required_text(event, "summary"),
        "background_context": required_text(event, "background_context"),
        "character_codes": string_list(
            event.get("characters") or event.get("character_codes")
        ),
        "landmark_id": landmark_id,
        "start_year": event.get("start_year"),
        "end_year": event.get("end_year"),
        "time_precision": str(event.get("time_precision") or "approx"),
        "bible_refs": map_list(event.get("bible_ref") or event.get("bible_refs")),
        "story_scenes": scenes,
        "scene_captions": captions,
        "scene_characters": nested_string_list(
            event.get("scene_characters"), len(scenes)
        ),
        "unit_code": str(event.get("unit_code") or "default").strip() or "default",
        "unit_title": str(event.get("unit_title") or "전체 흐름").strip()
        or "전체 흐름",
        "unit_order": int(event.get("unit_order") or 1),
        "scene_image_paths": scene_image_paths,
        "scene_image_prompts": [
            f"local draft upload: {Path(path).name}" for path in scene_image_paths
        ],
        "proposed_characters": map_list(event.get("proposed_characters")),
        "quiz_questions": map_list(event.get("quiz_questions")),
        "after_story_index": event.get("after_story_index"),
        "status": "pending",
    }


def insert_proposal(
    session: requests.Session,
    base_url: str,
    payload: dict[str, Any],
) -> str:
    response = session.post(
        f"{base_url}/rest/v1/event_proposals",
        json=payload,
        headers={"Prefer": "return=representation"},
        timeout=60,
    )
    if not response.ok:
        raise SystemExit(
            f"ERROR: insert event_proposals failed: {response.status_code} "
            f"{response.text}"
        )
    rows = response.json()
    if not rows:
        raise SystemExit("ERROR: event_proposals insert returned no row.")
    return str(rows[0]["id"])


def apply_one_story(
    *,
    story_path: Path,
    session: requests.Session,
    base_url: str,
    proposer_id: str,
    dry_run: bool,
) -> str | None:
    if not story_path.exists():
        raise SystemExit(f"ERROR: story draft not found: {story_path}")

    event = load_single_event(story_path)
    scenes, captions = validate_event(event)
    draft_dir = story_path.with_suffix("")
    if not draft_dir.exists():
        raise SystemExit(f"ERROR: draft image directory not found: {draft_dir}")

    era_id = resolve_era_id(session, base_url, event)
    landmark_id = resolve_landmark_id(session, base_url, event)
    ensure_title_available(session, base_url, required_text(event, "title"))

    local_images = [
        find_scene_image(draft_dir, idx) for idx in range(1, len(scenes) + 1)
    ]
    if dry_run:
        scene_paths = [
            f"{BUCKET}/{proposer_id}/{story_path.stem}/scene_{idx:02d}{path.suffix.lower()}"
            for idx, path in enumerate(local_images, start=1)
        ]
    else:
        scene_paths = [
            upload_scene(
                session,
                base_url,
                path,
                proposer_id=proposer_id,
                draft_slug=story_path.stem,
                scene_index=idx,
            )
            for idx, path in enumerate(local_images, start=1)
        ]

    payload = build_payload(
        event,
        proposer_id=proposer_id,
        era_id=era_id,
        landmark_id=landmark_id,
        scenes=scenes,
        captions=captions,
        scene_image_paths=scene_paths,
    )
    if dry_run:
        print(f"# draft: {display_path(story_path)}")
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return None

    proposal_id = insert_proposal(session, base_url, payload)
    print(
        f"[OK] {display_path(story_path)} → pending event_proposal: "
        f"{proposal_id} ({len(scene_paths)} scene image(s))"
    )
    return proposal_id


def main() -> int:
    args = parse_args()
    story_paths = resolve_story_paths(args)

    env_suffix = args.env
    session, base_url = service_session(env_suffix)
    proposer_id = proposer_user_id(env_suffix, args.proposer_user_id)

    proposal_ids: list[str] = []
    for story_path in story_paths:
        proposal_id = apply_one_story(
            story_path=story_path,
            session=session,
            base_url=base_url,
            proposer_id=proposer_id,
            dry_run=args.dry_run,
        )
        if proposal_id:
            proposal_ids.append(proposal_id)

    if args.dry_run:
        print(f"[DRY-RUN] validated {len(story_paths)} draft(s)")
    else:
        print(f"[OK] created {len(proposal_ids)} pending proposal(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
