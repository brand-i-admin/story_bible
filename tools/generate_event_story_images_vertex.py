#!/usr/bin/env python3
"""Generate sentence-level story images for sampled events using Vertex Gemini.

Input JSON format is expected from:
  tools/export_event_short_story_examples.py

Usage:
  source .env
  python3 tools/generate_event_story_images_vertex.py --dry-run
"""

from __future__ import annotations

import argparse
import base64
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


CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
INVALID_FILENAME_CHARS = re.compile(r"[\\/:*?\"<>|]+")
WHITESPACE_REGEX = re.compile(r"\s+")
SENTENCE_SPLIT_REGEX = re.compile(r"(?<=[.!?。！？])\s+")
SENTENCE_FALLBACK_REGEX = re.compile(r"[^.!?。！？]+[.!?。！？]?")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate scene images per short_story sentence with Vertex Gemini."
    )
    parser.add_argument(
        "--examples-json",
        default="assets/story_images/events_short_story_examples.json",
        help="Path to sampled events JSON.",
    )
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT", "").strip().strip("\""),
        help="GCP project id. Defaults to GOOGLE_CLOUD_PROJECT.",
    )
    parser.add_argument(
        "--location",
        default=os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1"),
        help="Vertex AI region. Defaults to GOOGLE_CLOUD_LOCATION or us-central1.",
    )
    parser.add_argument(
        "--model",
        default="gemini-2.5-flash-image",
        help="Vertex Gemini image model id.",
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
        help="Generate only first N events from JSON (0 = all).",
    )
    parser.add_argument(
        "--max-sentences",
        type=int,
        default=5,
        help="Maximum sentences to generate per event.",
    )
    parser.add_argument(
        "--max-reference-images",
        type=int,
        default=2,
        help="Maximum avatar reference images attached per sentence.",
    )
    parser.add_argument(
        "--sample-count",
        type=int,
        default=1,
        help="Number of candidates to request per sentence.",
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
    return parser.parse_args()


def load_examples(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if isinstance(data, dict):
        events = data.get("events", [])
    else:
        events = data

    if not isinstance(events, list):
        raise ValueError("Invalid examples JSON: expected top-level list or {'events': [...]} format.")
    return [item for item in events if isinstance(item, dict)]


def split_sentences(text: str, *, max_sentences: int) -> list[str]:
    normalized = " ".join(text.replace("\n", " ").split()).strip()
    if not normalized:
        return []

    primary = [part.strip() for part in SENTENCE_SPLIT_REGEX.split(normalized) if part.strip()]
    sentences = primary
    if len(sentences) <= 1:
        fallback = [part.strip() for part in SENTENCE_FALLBACK_REGEX.findall(normalized) if part.strip()]
        if fallback:
            sentences = fallback
    if not sentences:
        sentences = [normalized]
    return sentences[: max(1, max_sentences)]


def normalize_persons(event: dict[str, Any]) -> list[dict[str, Any]]:
    persons_data = event.get("persons")
    persons: list[dict[str, Any]] = []

    if isinstance(persons_data, list):
        for item in persons_data:
            if not isinstance(item, dict):
                continue
            code = str(item.get("code") or "").strip()
            if not code:
                continue
            persons.append(
                {
                    "code": code,
                    "name": str(item.get("name") or "").strip(),
                    "role": str(item.get("role") or "").strip(),
                    "person_sequence": int(item.get("person_sequence") or 0),
                }
            )
    else:
        event_persons = event.get("event_persons")
        if isinstance(event_persons, list):
            for item in event_persons:
                if not isinstance(item, dict):
                    continue
                person = item.get("persons")
                if not isinstance(person, dict):
                    continue
                code = str(person.get("code") or "").strip()
                if not code:
                    continue
                persons.append(
                    {
                        "code": code,
                        "name": str(person.get("name") or "").strip(),
                        "role": str(item.get("role") or "").strip(),
                        "person_sequence": int(item.get("person_sequence") or 0),
                    }
                )

    persons.sort(key=lambda p: (p["person_sequence"], p["code"]))
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
        code = person["code"]
        name = person.get("name", "")
        code_match = code.lower() in lowered
        name_match = bool(name) and (name in sentence)
        if code_match or name_match:
            matched.append(code)
    return matched


def choose_reference_avatars(
    sentence: str,
    persons: list[dict[str, Any]],
    avatar_index: dict[str, Path],
    *,
    max_reference_images: int,
) -> list[tuple[str, Path]]:
    matched_codes = match_person_codes(sentence, persons)
    candidate_codes = matched_codes if matched_codes else [person["code"] for person in persons]

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
        if len(selected) >= max(1, max_reference_images):
            break
    return selected


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


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
) -> list[dict[str, Any]]:
    char_text = ", ".join(code for code, _ in reference_avatars) if reference_avatars else "none"
    instruction = (
        "Create one non-photoreal 2D illustration scene for a Bible story app. "
        f"Event title: {event_title}. "
        f"Scene sentence: {sentence} "
        "Keep the composition suitable for mobile storytelling. "
        "No text, no watermark, no modern objects. "
        "If reference avatar images are attached, preserve each character's face identity and style. "
        f"Prioritize these character codes when applicable: {char_text}."
    )

    parts: list[dict[str, Any]] = [{"text": instruction}]
    for code, avatar_path in reference_avatars:
        encoded = base64.b64encode(avatar_path.read_bytes()).decode("ascii")
        parts.append({"text": f"Character reference image for code {code}."})
        parts.append({"inlineData": {"mimeType": "image/png", "data": encoded}})
    return parts


def build_request_body(parts: list[dict[str, Any]], sample_count: int) -> dict[str, Any]:
    return {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "candidateCount": max(1, int(sample_count)),
        },
    }


def main() -> int:
    args = parse_args()

    if not args.model.lower().startswith("gemini"):
        print("ERROR: this script currently supports Gemini image models only.", file=sys.stderr)
        return 2

    examples_path = Path(args.examples_json)
    if not examples_path.exists():
        print(f"ERROR: examples JSON not found: {examples_path}", file=sys.stderr)
        return 2

    avatars_dir = Path(args.avatars_dir)
    if not avatars_dir.exists():
        print(f"ERROR: avatars directory not found: {avatars_dir}", file=sys.stderr)
        return 2

    events = load_examples(examples_path)
    if args.limit_events > 0:
        events = events[: args.limit_events]
    if not events:
        print("ERROR: no events to process.", file=sys.stderr)
        return 2

    output_root = Path(args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    avatar_index = build_avatar_index(avatars_dir)

    endpoint = (
        f"https://{args.location}-aiplatform.googleapis.com/v1/projects/"
        f"{args.project}/locations/{args.location}/publishers/google/models/"
        f"{args.model}:generateContent"
    )

    session: requests.Session | None = None
    if not args.dry_run:
        if not args.project:
            print(
                "ERROR: project id is required. Set --project or GOOGLE_CLOUD_PROJECT.",
                file=sys.stderr,
            )
            return 2
        token = get_access_token()
        session = requests.Session()
        session.headers.update(
            {
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            }
        )

    used_dirnames: set[str] = set()
    success = 0
    failure = 0
    skipped = 0

    for idx, event in enumerate(events, start=1):
        title = str(event.get("title") or "").strip() or f"event_{idx:02d}"
        event_code = str(event.get("code") or "").strip() or f"event_{idx:02d}"
        dirname = unique_dirname(sanitize_dirname(title), event_code, used_dirnames)
        event_dir = output_root / dirname
        event_dir.mkdir(parents=True, exist_ok=True)

        persons = normalize_persons(event)
        short_story = str(event.get("short_story") or "").strip()
        raw_sentences = event.get("sentences")
        if isinstance(raw_sentences, list):
            sentences = [str(sentence).strip() for sentence in raw_sentences if str(sentence).strip()]
        else:
            sentences = split_sentences(short_story, max_sentences=args.max_sentences)
        sentences = sentences[: max(1, args.max_sentences)]

        if not sentences:
            print(f"[SKIP] {idx:02d} {title} -> no usable sentences")
            continue

        manifest_entries: list[dict[str, Any]] = []
        for sentence_index, sentence in enumerate(sentences, start=1):
            out_file = event_dir / f"scene_{sentence_index:02d}.png"
            reference_avatars = choose_reference_avatars(
                sentence,
                persons,
                avatar_index,
                max_reference_images=args.max_reference_images,
            )
            reference_codes = [code for code, _ in reference_avatars]

            manifest_entry = {
                "sentence_index": sentence_index,
                "sentence": sentence,
                "reference_avatar_codes": reference_codes,
                "file": out_file.name,
                "status": "pending",
            }

            if out_file.exists() and not args.overwrite:
                skipped += 1
                manifest_entry["status"] = "skipped_exists"
                manifest_entries.append(manifest_entry)
                print(f"[SKIP] {idx:02d}.{sentence_index:02d} {out_file} (exists)")
                continue

            if args.dry_run:
                skipped += 1
                manifest_entry["status"] = "dry_run"
                manifest_entries.append(manifest_entry)
                print(
                    f"[DRY]  {idx:02d}.{sentence_index:02d} {title} -> {out_file.name} "
                    f"(refs={reference_codes})"
                )
                continue

            assert session is not None
            parts = build_parts(
                event_title=title,
                sentence=sentence,
                reference_avatars=reference_avatars,
            )
            body = build_request_body(parts, sample_count=args.sample_count)

            try:
                label = f"{idx:02d}.{sentence_index:02d} {title}"
                max_429_attempts = max(1, int(args.retry_429_attempts))
                response: requests.Response | None = None
                attempts_used = 0

                for attempt in range(1, max_429_attempts + 1):
                    attempts_used = attempt
                    response = session.post(endpoint, json=body, timeout=180)
                    if response.status_code != 429:
                        break

                    if attempt < max_429_attempts:
                        print(
                            f"[RETRY] {label} status=429 "
                            f"attempt={attempt}/{max_429_attempts} "
                            f"(sleep {args.sleep_on_429_sec:.1f}s)"
                        )
                        if args.sleep_on_429_sec > 0:
                            time.sleep(args.sleep_on_429_sec)

                assert response is not None
                manifest_entry["retry_429_count"] = max(0, attempts_used - 1)
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
                        f"[FAIL] {idx:02d}.{sentence_index:02d} {title} "
                        f"status={response.status_code}"
                    )
                    continue

                payload = response.json()
                candidates = payload.get("candidates", [])
                if not candidates:
                    failure += 1
                    manifest_entry["status"] = "failed_no_candidates"
                    manifest_entry["error"] = "No candidates returned."
                    manifest_entries.append(manifest_entry)
                    print(f"[FAIL] {idx:02d}.{sentence_index:02d} {title} no candidates")
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
                        f"[FAIL] {idx:02d}.{sentence_index:02d} {title} "
                        "no decodable image"
                    )
                    continue

                out_file.write_bytes(image_bytes)
                success += 1
                manifest_entry["status"] = "ok"
                manifest_entries.append(manifest_entry)
                print(f"[OK]   {idx:02d}.{sentence_index:02d} {title} -> {out_file.name}")
            except Exception as exc:  # noqa: BLE001
                failure += 1
                manifest_entry["status"] = "failed_exception"
                manifest_entry["error"] = str(exc)
                manifest_entries.append(manifest_entry)
                print(f"[FAIL] {idx:02d}.{sentence_index:02d} {title} error={exc}")

            if args.sleep_sec > 0:
                time.sleep(args.sleep_sec)

        manifest = {
            "event_id": str(event.get("id") or "").strip(),
            "event_code": event_code,
            "title": title,
            "short_story": short_story,
            "sentences_count": len(sentences),
            "entries": manifest_entries,
        }
        manifest_path = event_dir / "manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print(f"Done. success={success} failure={failure} skipped={skipped}")
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
