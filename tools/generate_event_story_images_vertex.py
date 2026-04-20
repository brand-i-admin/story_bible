#!/usr/bin/env python3
"""Generate per-scene story images from assets/200_stories JSON using Vertex Gemini.

Input JSON format is expected from:
  assets/200_stories/*.json

Usage:
  source .env
  python3 tools/generate_event_story_images_vertex.py --dry-run
"""

from __future__ import annotations

import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any

import google.auth
from google.auth.transport.requests import Request
import requests

from story_scene_utils import (
    dedupe_preserve_order,
    detect_scene_person_codes,
    expand_person_codes,
    normalize_scene_persons_list,
    parse_event_person_codes,
    parse_person_name_map_from_seed_sql,
    sanitize_scene_text_for_visual,
)


CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
MANIFEST_SCHEMA_VERSION = 1
STORY_SCENE_MANIFEST_PATH = Path("supabase/generated_media/story_scenes.json")
INVALID_FILENAME_CHARS = re.compile(r"[\\/:*?\"<>|]+")
WHITESPACE_REGEX = re.compile(r"\s+")
SENTENCE_SPLIT_REGEX = re.compile(r"(?<=[.!?。！？])\s+")
SENTENCE_FALLBACK_REGEX = re.compile(r"[^.!?。！？]+[.!?。！？]?")
TITLE_PREFIX_NUMBER_REGEX = re.compile(r"^\s*(\d{1,4})\b")
SCENE_PREFIX_REGEX = re.compile(r"^\s*장면\s*\d+\s*[:：]\s*")

LATEST_IMAGE_MODEL = "gemini-3-pro-image-preview"
LATEST_STABLE_IMAGE_MODEL = "gemini-2.5-flash-image"
COMMON_SCENE_STYLE = (
    "Create one non-photoreal 2D Bible story illustration in the same visual world as the avatar cast. "
    "Use stylized geometric biblical illustration, blocky low-poly faceted planes, angular but friendly forms, "
    "flat matte vector shading with subtle cut-paper facets, warm parchment-friendly colors, "
    "clean composition, and consistent character design across every scene. "
    "No speech bubbles, no captions, no written letters, no symbols, no watermark, no modern objects."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate scene images per event from assets/200_stories JSON."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing stories JSON files.",
    )
    parser.add_argument(
        "--stories-glob",
        default="*.json",
        help="Glob pattern used inside --stories-dir.",
    )
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT", "").strip().strip('"'),
        help="GCP project id. Defaults to GOOGLE_CLOUD_PROJECT.",
    )
    parser.add_argument(
        "--location",
        default=os.getenv("GOOGLE_CLOUD_LOCATION", "global"),
        help="Vertex AI region. Defaults to GOOGLE_CLOUD_LOCATION or global.",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("VERTEX_IMAGE_MODEL", "latest"),
        help=(
            "Vertex Gemini image model id. Aliases: latest -> "
            f"{LATEST_IMAGE_MODEL}, stable -> {LATEST_STABLE_IMAGE_MODEL}."
        ),
    )
    parser.add_argument(
        "--avatars-dir",
        default="assets/avatars",
        help="Directory containing avatar PNG references.",
    )
    parser.add_argument(
        "--output-root",
        default="assets/story_images",
        help="Root directory where per-title folders are created.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing scene files.",
    )
    parser.add_argument(
        "--limit-events",
        type=int,
        default=0,
        help="Generate only first N events after loading and sorting (0 = all).",
    )
    parser.add_argument(
        "--max-scenes",
        dest="max_scenes",
        type=int,
        default=4,
        help="Maximum scenes per event (1~4 recommended).",
    )
    parser.add_argument(
        "--max-sentences",
        dest="max_scenes",
        type=int,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--max-reference-images",
        type=int,
        default=0,
        help="Maximum avatar reference images attached per scene (0 = all matched refs).",
    )
    parser.add_argument(
        "--sample-count",
        type=int,
        default=1,
        help="Number of candidates to request per scene.",
    )
    parser.add_argument(
        "--sleep-sec",
        type=float,
        default=0.2,
        help="Sleep between API calls.",
    )
    parser.add_argument(
        "--sleep-on-429-sec",
        type=float,
        default=2.0,
        help="Sleep seconds before each retry when status 429 is returned.",
    )
    parser.add_argument(
        "--retry-429-attempts",
        type=int,
        default=3,
        help="Total attempts per request when status 429 occurs.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Create folders and manifest only, without API calls.",
    )
    parser.add_argument(
        "--persons-seed-sql",
        default="supabase/200_stories/persons_seed.sql",
        help="Persons seed SQL used to recover canonical Korean person names.",
    )
    return parser.parse_args()


def _title_sort_key(title: str) -> tuple[int, str]:
    match = TITLE_PREFIX_NUMBER_REGEX.match(title)
    if match:
        return int(match.group(1)), title
    return 1_000_000, title


def load_story_events(stories_dir: Path, stories_glob: str) -> list[dict[str, Any]]:
    files = sorted(stories_dir.glob(stories_glob))
    if not files:
        raise ValueError(
            f"No JSON files found in {stories_dir} matching {stories_glob}."
        )

    events: list[dict[str, Any]] = []
    for path in files:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            raw_events = data.get("events", [])
        else:
            raw_events = data
        if not isinstance(raw_events, list):
            raise ValueError(
                f"Invalid stories JSON format in {path}: expected list or {{'events': [...]}}."
            )
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


def split_sentences(text: str, *, max_sentences: int) -> list[str]:
    normalized = " ".join(text.replace("\n", " ").split()).strip()
    if not normalized:
        return []

    primary = [
        part.strip() for part in SENTENCE_SPLIT_REGEX.split(normalized) if part.strip()
    ]
    sentences = primary
    if len(sentences) <= 1:
        fallback = [
            part.strip()
            for part in SENTENCE_FALLBACK_REGEX.findall(normalized)
            if part.strip()
        ]
        if fallback:
            sentences = fallback
    if not sentences:
        sentences = [normalized]
    return sentences[: max(1, max_sentences)]


def normalize_scene_text(raw: str) -> str:
    text = str(raw).strip()
    if not text:
        return ""
    text = SCENE_PREFIX_REGEX.sub("", text).strip()
    return text


def resolve_model_alias(model: str) -> str:
    normalized = str(model).strip()
    if not normalized or normalized == "latest":
        return LATEST_IMAGE_MODEL
    if normalized == "stable":
        return LATEST_STABLE_IMAGE_MODEL
    return normalized


def resolve_location_for_model(location: str, model: str) -> str:
    requested = str(location).strip() or "global"
    if model.startswith("gemini-3-") and requested != "global":
        return "global"
    return requested


def build_vertex_endpoint(*, project: str, location: str, model: str) -> str:
    host = (
        "aiplatform.googleapis.com"
        if location == "global"
        else f"{location}-aiplatform.googleapis.com"
    )
    return (
        f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/"
        f"{model}:generateContent"
    )


def request_model_candidates(primary_model: str) -> list[str]:
    models = [primary_model]
    if primary_model == LATEST_IMAGE_MODEL:
        models.append(LATEST_STABLE_IMAGE_MODEL)
    return dedupe_preserve_order(models)


def extract_story_scenes(event: dict[str, Any], *, max_scenes: int) -> list[str]:
    normalized_max = min(4, max(1, int(max_scenes)))
    for key in ("story_scenes", "short_story", "sentences"):
        value = event.get(key)
        if isinstance(value, list):
            scenes: list[str] = []
            for item in value:
                if isinstance(item, dict):
                    raw_text = str(
                        item.get("text")
                        or item.get("scene")
                        or item.get("prompt")
                        or item.get("description")
                        or ""
                    )
                else:
                    raw_text = str(item)
                scenes.append(normalize_scene_text(raw_text))
            scenes = [scene for scene in scenes if scene]
            if scenes:
                return scenes[:normalized_max]
        if isinstance(value, str) and value.strip():
            scenes = split_sentences(value, max_sentences=normalized_max)
            scenes = [normalize_scene_text(scene) for scene in scenes]
            scenes = [scene for scene in scenes if scene]
            if scenes:
                return scenes[:normalized_max]

    summary = str(event.get("summary") or "").strip()
    if summary:
        scenes = split_sentences(summary, max_sentences=normalized_max)
        scenes = [normalize_scene_text(scene) for scene in scenes]
        scenes = [scene for scene in scenes if scene]
        if scenes:
            return scenes[:normalized_max]
    return []


def event_code_for(event: dict[str, Any], fallback_index: int) -> str:
    code = str(event.get("code") or "").strip()
    if code:
        return code
    title = str(event.get("title") or "").strip()
    match = TITLE_PREFIX_NUMBER_REGEX.match(title)
    if match:
        return f"evt_{int(match.group(1)):03d}"
    return f"event_{fallback_index:03d}"


def normalize_persons(
    event: dict[str, Any],
    *,
    code_to_name: dict[str, str],
) -> list[dict[str, Any]]:
    codes = parse_event_person_codes(event)
    persons = [
        {
            "code": code,
            "name": code_to_name.get(code, code),
            "role": "",
            "person_sequence": index,
        }
        for index, code in enumerate(codes, start=1)
    ]
    persons.sort(
        key=lambda person: (int(person["person_sequence"]), str(person["code"]))
    )
    return persons


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


def build_avatar_index(avatars_dir: Path) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    for path in sorted(avatars_dir.glob("*.png")):
        mapping[path.stem.lower()] = path
    return mapping


def match_person_codes(sentence: str, persons: list[dict[str, Any]]) -> list[str]:
    lowered = sentence.lower()
    matched: list[str] = []
    for person in persons:
        code = str(person["code"]).strip().lower()
        name = str(person.get("name", "")).strip()
        code_match = bool(code) and code in lowered
        name_match = bool(name) and (
            name in sentence or name.replace(" ", "") in sentence.replace(" ", "")
        )
        if code_match or name_match:
            matched.append(code)
    return dedupe_preserve_order(matched)


def scene_person_codes_for(
    event: dict[str, Any],
    *,
    scene_index: int,
    scene_text: str,
    persons: list[dict[str, Any]],
    code_to_name: dict[str, str],
) -> list[str]:
    scene_persons = event.get("scene_persons")
    event_person_codes = [str(person["code"]).strip().lower() for person in persons]
    explicit_codes: list[str] = []
    if isinstance(scene_persons, list) and scene_index < len(scene_persons):
        explicit_codes = normalize_scene_persons_list(
            scene_persons[scene_index],
            event_person_codes,
        )

    detected_codes = detect_scene_person_codes(
        scene_text,
        event_person_codes,
        code_to_name,
    )
    if explicit_codes or detected_codes:
        return dedupe_preserve_order(explicit_codes + detected_codes)

    return match_person_codes(scene_text, persons)


def scene_reference_codes_for(
    event: dict[str, Any],
    *,
    scene_index: int,
    scene_person_codes: list[str],
    persons: list[dict[str, Any]],
) -> list[str]:
    scene_reference_persons = event.get("scene_reference_persons")
    event_person_codes = [str(person["code"]).strip().lower() for person in persons]
    if isinstance(scene_reference_persons, list) and scene_index < len(
        scene_reference_persons
    ):
        explicit_codes = normalize_scene_persons_list(
            scene_reference_persons[scene_index],
            event_person_codes,
        )
        return explicit_codes
    return dedupe_preserve_order(scene_person_codes)


def choose_reference_avatars(
    scene_person_codes: list[str],
    avatar_index: dict[str, Path],
    *,
    max_reference_images: int,
) -> list[tuple[str, Path]]:
    candidate_codes = expand_person_codes(scene_person_codes)
    if max_reference_images > 0:
        candidate_codes = candidate_codes[:max_reference_images]

    selected: list[tuple[str, Path]] = []
    seen: set[str] = set()
    for code in candidate_codes:
        norm = code.lower()
        if norm in seen:
            continue
        avatar_path = avatar_index.get(norm)
        if avatar_path is None:
            continue
        selected.append((code, avatar_path))
        seen.add(norm)
        if max_reference_images > 0 and len(selected) >= max_reference_images:
            break
    return selected


def missing_reference_avatar_codes(
    scene_person_codes: list[str],
    avatar_index: dict[str, Path],
) -> list[str]:
    missing: list[str] = []
    for code in expand_person_codes(scene_person_codes):
        if code.lower() not in avatar_index:
            missing.append(code)
    return dedupe_preserve_order(missing)


def load_google_credentials():
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    return creds


def credentials_need_refresh(creds) -> bool:
    if not getattr(creds, "valid", False):
        return True
    expiry = getattr(creds, "expiry", None)
    if expiry is None:
        return False
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    return expiry <= datetime.now(timezone.utc) + timedelta(minutes=5)


def ensure_session_auth(
    session: requests.Session, creds, request_adapter: Request, *, force: bool = False
) -> None:
    if force or credentials_need_refresh(creds):
        creds.refresh(request_adapter)
    session.headers.update({"Authorization": f"Bearer {creds.token}"})


def _maybe_decode_base64(raw: str) -> bytes | None:
    value = raw.strip()
    if not value:
        return None
    if value.startswith("data:"):
        parts = value.split(",", 1)
        if len(parts) != 2:
            return None
        value = parts[1]
    value = "".join(value.split())
    if len(value) < 16:
        return None
    try:
        return base64.b64decode(value, validate=True)
    except Exception:  # noqa: BLE001
        return None


def _extract_image_bytes(node: Any) -> bytes | None:
    if isinstance(node, str):
        return _maybe_decode_base64(node)

    if isinstance(node, list):
        for item in node:
            decoded = _extract_image_bytes(item)
            if decoded is not None:
                return decoded
        return None

    if not isinstance(node, dict):
        return None

    for key in (
        "bytesBase64Encoded",
        "b64Json",
        "image",
        "imageBytes",
        "images",
        "generatedImages",
        "inlineData",
        "data",
    ):
        if key not in node:
            continue
        decoded = _extract_image_bytes(node[key])
        if decoded is not None:
            return decoded

    for value in node.values():
        decoded = _extract_image_bytes(value)
        if decoded is not None:
            return decoded

    return None


def decode_image_bytes(candidate: dict[str, Any]) -> bytes:
    image_bytes = _extract_image_bytes(candidate)
    if image_bytes is None:
        keys = sorted(candidate.keys())
        raise ValueError(f"No image bytes found in candidate payload. keys={keys}")
    return image_bytes


def build_parts(
    *,
    event_title: str,
    sentence: str,
    reference_avatars: list[tuple[str, Path]],
    code_to_name: dict[str, str],
    place_name: str = "",
    scene_prompt_note: str = "",
) -> list[dict[str, Any]]:
    reference_labels = [
        f"{code_to_name.get(code, code)} ({code})" for code, _ in reference_avatars
    ]
    char_text = ", ".join(reference_labels) if reference_labels else "none"
    place_clause = f" Place: {place_name}." if place_name else ""
    note_clause = (
        f" Additional art direction: {scene_prompt_note}." if scene_prompt_note else ""
    )
    instruction = (
        f"{COMMON_SCENE_STYLE} "
        f"Event title: {event_title}. "
        f"Scene description: {sentence}.{place_clause}{note_clause} "
        "Keep the composition suitable for mobile storytelling. "
        "Show only visible action, facial expression, body pose, props, weather, light, and environment. "
        "Do not add spoken words, dialogue balloons, captions, written letters, scripture text, or logos. "
        "If reference avatar images are attached, each attached character is canonical and must stay recognizable. "
        "Preserve the attached character's face identity, hair, and recognizable core design. "
        "If the scene description explicitly requests a different age, costume, role, or physical state, keep the same identity but follow that requested change. "
        "Do not redesign, replace, or turn the attached character into a different person. "
        f"Scene reference characters: {char_text}."
    )

    parts: list[dict[str, Any]] = [{"text": instruction}]
    for code, avatar_path in reference_avatars:
        name = code_to_name.get(code, code)
        encoded = base64.b64encode(avatar_path.read_bytes()).decode("ascii")
        parts.append(
            {
                "text": (
                    f"Attached canonical character reference: {name} ({code}). "
                    "Keep this character visually consistent in the generated scene."
                )
            }
        )
        parts.append({"inlineData": {"mimeType": "image/png", "data": encoded}})
    return parts


def build_request_body(
    parts: list[dict[str, Any]], sample_count: int
) -> dict[str, Any]:
    return {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "candidateCount": max(1, int(sample_count)),
        },
    }


def scene_prompt_note_for(event: dict[str, Any], *, scene_index: int) -> str:
    notes = event.get("scene_prompt_notes")
    if isinstance(notes, list) and scene_index < len(notes):
        value = notes[scene_index]
        if isinstance(value, str):
            return value.strip()
    return ""


def natural_key(
    *,
    owner_type: str,
    owner_code: str,
    asset_role: str,
    variant: str,
    scene_index: int | None = None,
) -> str:
    scene_part = str(scene_index) if scene_index is not None else "none"
    return f"{owner_type}:{owner_code}:{asset_role}:{scene_part}:{variant}"


def repo_relative_path(path: Path) -> str:
    if not path.is_absolute():
        return path.as_posix()
    try:
        return path.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return path.as_posix()


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_story_scene_asset(
    *,
    event_code: str,
    event_title: str,
    event_manifest: dict[str, Any],
    entry: dict[str, Any],
    file_path: Path,
) -> dict[str, Any]:
    scene_index = int(entry["scene_index"])
    return {
        "natural_key": natural_key(
            owner_type="event",
            owner_code=event_code,
            asset_role="story_scene",
            scene_index=scene_index,
            variant="original",
        ),
        "owner_type": "event",
        "owner_code": event_code,
        "asset_role": "story_scene",
        "scene_index": scene_index,
        "variant": "original",
        "relative_path": repo_relative_path(file_path),
        "source_relative_path": None,
        "mime_type": "image/png",
        "byte_size": file_path.stat().st_size,
        "content_hash": sha256_for_file(file_path),
        "generator": "tools/generate_event_story_images_vertex.py",
        "generator_model": str(event_manifest.get("model") or "").strip() or None,
        "metadata": {
            "event_title": event_title,
            "scene_prompt": str(entry.get("scene_prompt") or "").strip(),
            "scene_prompt_note": str(entry.get("scene_prompt_note") or "").strip(),
            "scene_person_codes": list(entry.get("scene_person_codes") or []),
            "scene_reference_person_codes": list(
                entry.get("scene_reference_person_codes") or []
            ),
            "reference_avatar_codes": list(entry.get("reference_avatar_codes") or []),
            "missing_reference_avatar_codes": list(
                entry.get("missing_reference_avatar_codes") or []
            ),
            "source_json": str(event_manifest.get("source_json") or "").strip(),
            "source_index": int(event_manifest.get("source_index") or 0),
            "generator_location": str(event_manifest.get("location") or "").strip(),
        },
    }


def write_story_scene_manifest(output_root: Path) -> None:
    assets: list[dict[str, Any]] = []
    for manifest_path in sorted(output_root.rglob("manifest.json")):
        event_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = event_manifest.get("entries", [])
        if not isinstance(entries, list):
            continue

        event_code = str(event_manifest.get("event_code") or "").strip()
        event_title = str(event_manifest.get("title") or "").strip()
        if not event_code:
            continue

        for entry in entries:
            if not isinstance(entry, dict):
                continue
            filename = str(entry.get("file") or "").strip()
            if not filename:
                continue
            file_path = manifest_path.parent / filename
            if not file_path.exists():
                continue
            scene_index = entry.get("scene_index")
            if not isinstance(scene_index, int):
                continue
            assets.append(
                build_story_scene_asset(
                    event_code=event_code,
                    event_title=event_title,
                    event_manifest=event_manifest,
                    entry=entry,
                    file_path=file_path,
                )
            )

    assets.sort(key=lambda item: item["natural_key"])
    STORY_SCENE_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    STORY_SCENE_MANIFEST_PATH.write_text(
        json.dumps(
            {
                "schema_version": MANIFEST_SCHEMA_VERSION,
                "asset_family": "story_scenes",
                "assets": assets,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    resolved_model = resolve_model_alias(args.model)
    resolved_location = resolve_location_for_model(args.location, resolved_model)

    if not resolved_model.lower().startswith("gemini"):
        print(
            "ERROR: this script currently supports Gemini image models only.",
            file=sys.stderr,
        )
        return 2

    stories_dir = Path(args.stories_dir)
    if not stories_dir.exists():
        print(f"ERROR: stories directory not found: {stories_dir}", file=sys.stderr)
        return 2

    avatars_dir = Path(args.avatars_dir)
    if not avatars_dir.exists():
        print(f"ERROR: avatars directory not found: {avatars_dir}", file=sys.stderr)
        return 2

    events = load_story_events(stories_dir, args.stories_glob)
    if args.limit_events > 0:
        events = events[: args.limit_events]
    if not events:
        print("ERROR: no events to process.", file=sys.stderr)
        return 2

    output_root = Path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    avatar_index = build_avatar_index(avatars_dir)
    code_to_name = parse_person_name_map_from_seed_sql(Path(args.persons_seed_sql))
    request_models = request_model_candidates(resolved_model)

    session: requests.Session | None = None
    creds = None
    auth_request: Request | None = None
    if not args.dry_run:
        if not args.project:
            print(
                "ERROR: project id is required. Set --project or GOOGLE_CLOUD_PROJECT.",
                file=sys.stderr,
            )
            return 2
        creds = load_google_credentials()
        auth_request = Request()
        session = requests.Session()
        session.headers.update({"Content-Type": "application/json"})
        ensure_session_auth(session, creds, auth_request)
        print(
            "[INFO] Vertex image generation "
            f"project={args.project} location={resolved_location} "
            f"models={request_models}"
        )

    used_dirnames: set[str] = set()
    success = 0
    failure = 0
    skipped = 0

    for idx, event in enumerate(events, start=1):
        title = str(event.get("title") or "").strip() or f"event_{idx:03d}"
        event_code = event_code_for(event, idx)
        dirname = unique_dirname(sanitize_dirname(title), event_code, used_dirnames)
        event_dir = output_root / dirname
        event_dir.mkdir(parents=True, exist_ok=True)

        persons = normalize_persons(event, code_to_name=code_to_name)
        scenes = extract_story_scenes(event, max_scenes=args.max_scenes)
        if not scenes:
            print(f"[SKIP] {idx:03d} {title} -> no usable story_scenes")
            continue

        manifest_entries: list[dict[str, Any]] = []
        for scene_index, scene_text in enumerate(scenes, start=1):
            out_file = event_dir / f"scene_{scene_index:02d}.png"
            scene_person_codes = scene_person_codes_for(
                event,
                scene_index=scene_index - 1,
                scene_text=scene_text,
                persons=persons,
                code_to_name=code_to_name,
            )
            reference_person_codes = scene_reference_codes_for(
                event,
                scene_index=scene_index - 1,
                scene_person_codes=scene_person_codes,
                persons=persons,
            )
            visual_scene_text = sanitize_scene_text_for_visual(
                scene_text,
                scene_person_codes=scene_person_codes,
                code_to_name=code_to_name,
            )
            scene_prompt_note = scene_prompt_note_for(
                event,
                scene_index=scene_index - 1,
            )
            reference_avatars = choose_reference_avatars(
                reference_person_codes,
                avatar_index,
                max_reference_images=args.max_reference_images,
            )
            reference_codes = [code for code, _ in reference_avatars]
            missing_reference_codes = missing_reference_avatar_codes(
                reference_person_codes,
                avatar_index,
            )

            manifest_entry = {
                "natural_key": natural_key(
                    owner_type="event",
                    owner_code=event_code,
                    asset_role="story_scene",
                    scene_index=scene_index,
                    variant="original",
                ),
                "scene_index": scene_index,
                "scene_prompt": visual_scene_text,
                "scene_prompt_note": scene_prompt_note,
                "scene_person_codes": scene_person_codes,
                "scene_reference_person_codes": reference_person_codes,
                "reference_avatar_codes": reference_codes,
                "missing_reference_avatar_codes": missing_reference_codes,
                "file": out_file.name,
                "relative_path": repo_relative_path(out_file),
                "status": "pending",
            }

            if out_file.exists() and not args.overwrite:
                skipped += 1
                manifest_entry["status"] = "skipped_exists"
                manifest_entries.append(manifest_entry)
                print(f"[SKIP] {idx:03d}.{scene_index:02d} {out_file} (exists)")
                continue

            if args.dry_run:
                skipped += 1
                manifest_entry["status"] = "dry_run"
                manifest_entries.append(manifest_entry)
                print(
                    f"[DRY]  {idx:03d}.{scene_index:02d} {title} -> {out_file.name} "
                    f"(scene_persons={scene_person_codes}, ref_persons={reference_person_codes}, refs={reference_codes}, "
                    f"missing_refs={missing_reference_codes})"
                )
                continue

            assert session is not None
            assert creds is not None
            assert auth_request is not None
            parts = build_parts(
                event_title=title,
                sentence=visual_scene_text,
                reference_avatars=reference_avatars,
                code_to_name=code_to_name,
                place_name=str(event.get("place_name") or "").strip(),
                scene_prompt_note=scene_prompt_note,
            )
            body = build_request_body(parts, sample_count=args.sample_count)

            try:
                label = f"{idx:03d}.{scene_index:02d} {title}"
                max_429_attempts = max(1, int(args.retry_429_attempts))
                response: requests.Response | None = None
                attempts_used = 0
                used_model = request_models[0]
                used_location = resolve_location_for_model(args.location, used_model)

                for model_index, candidate_model in enumerate(request_models):
                    candidate_location = resolve_location_for_model(
                        args.location,
                        candidate_model,
                    )
                    endpoint = build_vertex_endpoint(
                        project=args.project,
                        location=candidate_location,
                        model=candidate_model,
                    )
                    used_model = candidate_model
                    used_location = candidate_location
                    response = None

                    for attempt in range(1, max_429_attempts + 1):
                        attempts_used = attempt
                        ensure_session_auth(session, creds, auth_request)
                        response = session.post(endpoint, json=body, timeout=180)
                        if response.status_code == 401:
                            print(
                                f"[AUTH] {label} model={candidate_model} "
                                "received 401, refreshing access token and retrying once"
                            )
                            ensure_session_auth(
                                session,
                                creds,
                                auth_request,
                                force=True,
                            )
                            response = session.post(endpoint, json=body, timeout=180)
                        if response.status_code != 429:
                            break

                        if attempt < max_429_attempts:
                            print(
                                f"[RETRY] {label} model={candidate_model} status=429 "
                                f"attempt={attempt}/{max_429_attempts} "
                                f"(sleep {args.sleep_on_429_sec:.1f}s)"
                            )
                            if args.sleep_on_429_sec > 0:
                                time.sleep(args.sleep_on_429_sec)

                    assert response is not None
                    if response.status_code != 404:
                        break
                    if model_index + 1 < len(request_models):
                        print(
                            f"[FALLBACK] {label} model={candidate_model} returned 404, "
                            f"retrying with {request_models[model_index + 1]}"
                        )

                assert response is not None
                manifest_entry["retry_429_count"] = max(0, attempts_used - 1)
                manifest_entry["used_model"] = used_model
                manifest_entry["used_location"] = used_location
                if response.status_code == 429:
                    failure += 1
                    manifest_entry["status"] = "failed_http_429"
                    manifest_entry["error"] = response.text[:400]
                    manifest_entries.append(manifest_entry)
                    print(
                        f"[FAIL] {label} status=429 "
                        f"after {attempts_used} attempts, moving to next"
                    )
                    continue

                if response.status_code >= 400:
                    failure += 1
                    manifest_entry["status"] = "failed_http"
                    manifest_entry["error"] = response.text[:400]
                    manifest_entries.append(manifest_entry)
                    print(
                        f"[FAIL] {idx:03d}.{scene_index:02d} {title} "
                        f"status={response.status_code} model={used_model}"
                    )
                    continue

                payload = response.json()
                candidates = payload.get("candidates", [])
                if not candidates:
                    failure += 1
                    manifest_entry["status"] = "failed_no_candidates"
                    manifest_entry["error"] = "No candidates returned."
                    manifest_entries.append(manifest_entry)
                    print(f"[FAIL] {idx:03d}.{scene_index:02d} {title} no candidates")
                    continue

                image_bytes = None
                last_error = ""
                for candidate in candidates:
                    try:
                        image_bytes = decode_image_bytes(candidate)
                        break
                    except ValueError as exc:
                        last_error = str(exc)

                if image_bytes is None:
                    failure += 1
                    manifest_entry["status"] = "failed_no_image"
                    manifest_entry["error"] = last_error or "No decodable image bytes."
                    manifest_entries.append(manifest_entry)
                    print(
                        f"[FAIL] {idx:03d}.{scene_index:02d} {title} "
                        "no decodable image"
                    )
                    continue

                out_file.write_bytes(image_bytes)
                success += 1
                manifest_entry["status"] = "ok"
                manifest_entries.append(manifest_entry)
                print(f"[OK]   {idx:03d}.{scene_index:02d} {title} -> {out_file.name}")
            except Exception as exc:  # noqa: BLE001
                failure += 1
                manifest_entry["status"] = "failed_exception"
                manifest_entry["error"] = str(exc)
                manifest_entries.append(manifest_entry)
                print(f"[FAIL] {idx:03d}.{scene_index:02d} {title} error={exc}")

            if args.sleep_sec > 0:
                time.sleep(args.sleep_sec)

        manifest = {
            "event_id": str(event.get("id") or "").strip(),
            "event_code": event_code,
            "title": title,
            "model": resolved_model,
            "location": resolved_location,
            "source_json": str(event.get("__source_file") or ""),
            "source_index": int(event.get("__source_index") or 0),
            "scenes_count": len(scenes),
            "entries": manifest_entries,
        }
        manifest_path = event_dir / "manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    write_story_scene_manifest(output_root)
    print(f"[OK]   wrote manifest -> {STORY_SCENE_MANIFEST_PATH}")
    print(f"Done. success={success} failure={failure} skipped={skipped}")
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
