#!/usr/bin/env python3
"""Rewrite story_scenes for image generation and add per-scene person metadata.

Goals:
- remove direct speech / narration wording that often causes text in images
- keep scene descriptions visual and concise
- add scene_persons metadata aligned to each scene
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from story_scene_utils import (
    detect_scene_person_codes,
    normalize_scene_persons_list,
    parse_event_person_codes,
    parse_person_name_map_from_seed_sql,
    sanitize_scene_text_for_visual,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rewrite assets/200_stories story scenes for image generation.",
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing story JSON files.",
    )
    parser.add_argument(
        "--stories-glob",
        default="*.json",
        help="Glob pattern used inside --stories-dir.",
    )
    parser.add_argument(
        "--persons-seed-sql",
        default="supabase/200_stories/persons_seed.sql",
        help="Persons seed SQL used to recover canonical Korean person names.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing files.",
    )
    return parser.parse_args()


def _scene_text_and_existing_codes(
    scene: object, event_person_codes: list[str]
) -> tuple[str, list[str]]:
    if isinstance(scene, dict):
        text = str(
            scene.get("text")
            or scene.get("scene")
            or scene.get("prompt")
            or scene.get("description")
            or ""
        ).strip()
        explicit = normalize_scene_persons_list(
            scene.get("persons") or scene.get("person_codes"),
            event_person_codes,
        )
        return text, explicit
    return str(scene).strip(), []


def rewrite_event(event: dict, code_to_name: dict[str, str]) -> bool:
    event_person_codes = parse_event_person_codes(event)
    story_scenes = event.get("story_scenes")
    if not isinstance(story_scenes, list) or not story_scenes:
        return False

    existing_scene_persons = event.get("scene_persons")
    changed = False
    rewritten_scenes: list[str] = []
    rewritten_scene_persons: list[list[str]] = []

    for index, scene in enumerate(story_scenes):
        raw_text, explicit_codes = _scene_text_and_existing_codes(
            scene, event_person_codes
        )
        if not raw_text:
            continue

        inherited_codes = []
        if isinstance(existing_scene_persons, list) and index < len(
            existing_scene_persons
        ):
            inherited_codes = normalize_scene_persons_list(
                existing_scene_persons[index],
                event_person_codes,
            )

        detected_codes = detect_scene_person_codes(
            raw_text,
            event_person_codes,
            code_to_name,
        )
        scene_person_codes = explicit_codes + inherited_codes + detected_codes
        scene_person_codes = normalize_scene_persons_list(
            scene_person_codes,
            event_person_codes,
        )
        rewritten_text = sanitize_scene_text_for_visual(
            raw_text,
            scene_person_codes=scene_person_codes,
            code_to_name=code_to_name,
        )

        rewritten_scenes.append(rewritten_text)
        rewritten_scene_persons.append(scene_person_codes)

        if rewritten_text != raw_text or explicit_codes != scene_person_codes:
            changed = True

    if not rewritten_scenes:
        return False

    if event.get("story_scenes") != rewritten_scenes:
        event["story_scenes"] = rewritten_scenes
        changed = True
    if event.get("scene_persons") != rewritten_scene_persons:
        event["scene_persons"] = rewritten_scene_persons
        changed = True
    return changed


def main() -> int:
    args = parse_args()
    stories_dir = Path(args.stories_dir)
    if not stories_dir.exists():
        raise FileNotFoundError(f"stories directory not found: {stories_dir}")

    code_to_name = parse_person_name_map_from_seed_sql(Path(args.persons_seed_sql))
    files = sorted(stories_dir.glob(args.stories_glob))
    if not files:
        raise FileNotFoundError(
            f"no story files found in {stories_dir} matching {args.stories_glob}"
        )

    changed_files = 0
    changed_events = 0

    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        events = data.get("events") if isinstance(data, dict) else data
        if not isinstance(events, list):
            continue

        file_changed = False
        for event in events:
            if not isinstance(event, dict):
                continue
            if rewrite_event(event, code_to_name):
                changed_events += 1
                file_changed = True

        if file_changed:
            changed_files += 1
            if not args.dry_run:
                path.write_text(
                    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )

    mode = "DRY" if args.dry_run else "WROTE"
    print(f"{mode}: changed_files={changed_files} changed_events={changed_events}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
