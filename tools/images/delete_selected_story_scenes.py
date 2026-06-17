#!/usr/bin/env python3
"""Delete selected generated story scene images so they can be regenerated.

The folder naming logic intentionally mirrors generate_event_story_images_vertex.py.
Default mode is a dry run; pass --delete to unlink PNG/JPG files.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
from typing import Any

from generate_runtime_thumbnails import short_story_thumb_dir

INVALID_FILENAME_CHARS = re.compile(r"[\\/:*?\"<>|]+")
WHITESPACE_REGEX = re.compile(r"\s+")
TITLE_PREFIX_NUMBER_REGEX = re.compile(r"^\s*(\d{1,4})\b")
GOD_VISUAL_REGEX = re.compile(
    r"(하나님의 빛|하늘의 음성|하늘빛|성령이 임|성령의 빛|성령의 권능|"
    r"비둘기 같은 성령|하늘이 열)"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Delete selected story scene images and thumbnails.",
    )
    parser.add_argument(
        "--mode",
        choices=["god-strict", "god-visual", "nt-pictorial-bubbles"],
        required=True,
        help=(
            "god-strict: scene_characters contains god; "
            "god-visual: god-strict plus God/Spirit/voice visual scenes; "
            "nt-pictorial-bubbles: NT scenes whose prompt now asks for pictorial bubbles."
        ),
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing era story JSON files.",
    )
    parser.add_argument(
        "--stories-glob",
        default="era_*.json",
        help="Glob pattern used inside --stories-dir.",
    )
    parser.add_argument(
        "--images-root",
        default="assets/story_images",
        help="Root directory containing generated scene PNGs.",
    )
    parser.add_argument(
        "--thumbs-root",
        default="assets/story_images_thumbs",
        help="Root directory containing generated scene JPG thumbnails.",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Actually delete files. Omit for dry-run preview.",
    )
    return parser.parse_args()


def _title_sort_key(title: str) -> tuple[int, str]:
    match = TITLE_PREFIX_NUMBER_REGEX.match(title)
    if match:
        return int(match.group(1)), title
    return 1_000_000, title


def load_story_events(stories_dir: Path, stories_glob: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for path in sorted(stories_dir.glob(stories_glob)):
        data = json.loads(path.read_text(encoding="utf-8"))
        raw_events = data.get("events", []) if isinstance(data, dict) else data
        if not isinstance(raw_events, list):
            continue
        for index_in_file, item in enumerate(raw_events, start=1):
            if not isinstance(item, dict):
                continue
            event = dict(item)
            event["__source_file"] = path.as_posix()
            event["__source_index"] = index_in_file
            events.append(event)

    events.sort(
        key=lambda event: (
            *_title_sort_key(str(event.get("title") or "").strip()),
            str(event.get("__source_file") or ""),
            int(event.get("__source_index") or 0),
        )
    )
    return events


def sanitize_dirname(raw: str) -> str:
    cleaned = INVALID_FILENAME_CHARS.sub("_", raw).strip()
    cleaned = cleaned.strip(".")
    cleaned = WHITESPACE_REGEX.sub(" ", cleaned).strip()
    return cleaned or "untitled_event"


def unique_dirname(base: str, fallback: str, used: set[str]) -> str:
    candidate = base
    if candidate not in used:
        used.add(candidate)
        return candidate

    suffix = sanitize_dirname(fallback) or "event"
    candidate = f"{base}_{suffix}"
    if candidate not in used:
        used.add(candidate)
        return candidate

    i = 2
    while True:
        numbered = f"{candidate}_{i:02d}"
        if numbered not in used:
            used.add(numbered)
            return numbered
        i += 1


def event_code_for(event: dict[str, Any], fallback_index: int) -> str:
    code = str(event.get("code") or "").strip()
    if code:
        return code
    title = str(event.get("title") or "").strip()
    match = TITLE_PREFIX_NUMBER_REGEX.match(title)
    if match:
        return f"evt_{int(match.group(1)):03d}"
    return f"event_{fallback_index:03d}"


def scene_characters(event: dict[str, Any], scene_index: int) -> list[str]:
    raw = event.get("scene_characters") or []
    if not isinstance(raw, list) or scene_index >= len(raw):
        return []
    scene_raw = raw[scene_index]
    if not isinstance(scene_raw, list):
        return []
    return [str(item).strip().lower() for item in scene_raw if str(item).strip()]


def should_delete_scene(
    *,
    mode: str,
    event: dict[str, Any],
    scene_text: str,
    scene_index: int,
) -> bool:
    chars = scene_characters(event, scene_index)
    has_god_character = "god" in chars
    if mode == "god-strict":
        return has_god_character
    if mode == "god-visual":
        return has_god_character or bool(GOD_VISUAL_REGEX.search(scene_text))
    if mode == "nt-pictorial-bubbles":
        era = str(event.get("era") or "")
        return era.startswith("era_nt_") and "글자 없는 말풍선" in scene_text
    raise ValueError(f"unknown mode: {mode}")


def main() -> int:
    args = parse_args()
    events = load_story_events(Path(args.stories_dir), args.stories_glob)
    used_dirnames: set[str] = set()
    targets: list[Path] = []
    matched_scenes = 0

    for event_position, event in enumerate(events, start=1):
        title = str(event.get("title") or "").strip() or f"event_{event_position:03d}"
        dirname = unique_dirname(
            sanitize_dirname(title),
            event_code_for(event, event_position),
            used_dirnames,
        )
        scenes = event.get("story_scenes") or []
        if not isinstance(scenes, list):
            continue
        for scene_index, scene_text_raw in enumerate(scenes):
            scene_text = str(scene_text_raw or "")
            if not should_delete_scene(
                mode=args.mode,
                event=event,
                scene_text=scene_text,
                scene_index=scene_index,
            ):
                continue
            matched_scenes += 1
            file_stem = f"scene_{scene_index + 1:02d}"
            targets.append(Path(args.images_root) / dirname / f"{file_stem}.png")
            targets.append(
                Path(args.thumbs_root)
                / short_story_thumb_dir(event)
                / f"{file_stem}.jpg"
            )
            # Legacy title-based thumbnail path, kept so old worktrees can be cleaned.
            targets.append(Path(args.thumbs_root) / dirname / f"{file_stem}.jpg")

    existing_targets = [path for path in targets if path.exists()]
    action = "DELETE" if args.delete else "DRY-RUN"
    print(
        f"[{action}] mode={args.mode} matched_scenes={matched_scenes} "
        f"existing_files={len(existing_targets)} target_files={len(targets)}"
    )

    for path in existing_targets:
        if args.delete:
            path.unlink()
            print(f"[DELETED] {path}")
        else:
            print(f"[WOULD DELETE] {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
