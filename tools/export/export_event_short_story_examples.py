#!/usr/bin/env python3
"""Export random event short-story examples from Supabase into JSON.

Usage:
  source .env
  python3 tools/export/export_event_short_story_examples.py
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import random
import re
import sys
from typing import Any

import requests

SENTENCE_SPLIT_REGEX = re.compile(r"(?<=[.!?。！？])\s+")
SENTENCE_FALLBACK_REGEX = re.compile(r"[^.!?。！？]+[.!?。！？]?")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export random events.short_story examples from Supabase."
    )
    parser.add_argument(
        "--supabase-url",
        default=os.getenv("SUPABASE_URL_DEV", ""),
        help="Supabase project URL. Defaults to SUPABASE_URL_DEV.",
    )
    parser.add_argument(
        "--supabase-key",
        default=os.getenv("SUPABASE_ANON_KEY_DEV", ""),
        help="Supabase anon/service key. Defaults to SUPABASE_ANON_KEY_DEV.",
    )
    parser.add_argument(
        "--output",
        default="assets/story_images/events_short_story_examples.json",
        help="Output JSON path.",
    )
    parser.add_argument(
        "--sample-size",
        type=int,
        default=10,
        help="Number of random events to export.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Optional random seed for reproducible sampling.",
    )
    parser.add_argument(
        "--max-sentences",
        type=int,
        default=5,
        help="Maximum number of sentences to keep per short_story.",
    )
    return parser.parse_args()


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
        return [normalized]
    return sentences[: max(1, max_sentences)]


def fetch_events(supabase_url: str, supabase_key: str) -> list[dict[str, Any]]:
    endpoint = f"{supabase_url.rstrip('/')}/rest/v1/events"
    params = {
        "select": "id,code,title,short_story,event_persons(person_sequence,role,characters(code,name))",
        "short_story": "not.is.null",
        "limit": "1000",
    }
    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
    }

    response = requests.get(endpoint, params=params, headers=headers, timeout=60)
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, list):
        raise ValueError("Unexpected Supabase response: expected a JSON array.")
    return payload


def normalize_event(
    raw: dict[str, Any], *, max_sentences: int
) -> dict[str, Any] | None:
    short_story = str(raw.get("short_story") or "").strip()
    if not short_story:
        return None

    raw_event_persons = raw.get("event_persons")
    characters: list[dict[str, Any]] = []
    if isinstance(raw_event_persons, list):
        for item in raw_event_persons:
            if not isinstance(item, dict):
                continue
            character = item.get("characters")
            if not isinstance(character, dict):
                continue
            code = str(character.get("code") or "").strip()
            name = str(character.get("name") or "").strip()
            if not code:
                continue
            characters.append(
                {
                    "code": code,
                    "name": name,
                    "role": str(item.get("role") or "").strip(),
                    "person_sequence": int(item.get("person_sequence") or 0),
                }
            )

    characters.sort(key=lambda p: (p["person_sequence"], p["code"]))
    sentences = split_sentences(short_story, max_sentences=max_sentences)

    return {
        "id": str(raw.get("id") or "").strip(),
        "code": str(raw.get("code") or "").strip(),
        "title": str(raw.get("title") or "").strip(),
        "short_story": short_story,
        "sentences": sentences,
        "characters": characters,
    }


def main() -> int:
    args = parse_args()

    if not args.supabase_url:
        print("ERROR: --supabase-url or SUPABASE_URL_DEV is required.", file=sys.stderr)
        return 2
    if not args.supabase_key:
        print(
            "ERROR: --supabase-key or SUPABASE_ANON_KEY_DEV is required.",
            file=sys.stderr,
        )
        return 2
    if args.sample_size <= 0:
        print("ERROR: --sample-size must be > 0.", file=sys.stderr)
        return 2

    try:
        raw_events = fetch_events(args.supabase_url, args.supabase_key)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: failed to fetch events from Supabase: {exc}", file=sys.stderr)
        return 1

    normalized: list[dict[str, Any]] = []
    for item in raw_events:
        if not isinstance(item, dict):
            continue
        event = normalize_event(item, max_sentences=args.max_sentences)
        if event is not None:
            normalized.append(event)

    if not normalized:
        print(
            "ERROR: no events with non-empty short_story were found.", file=sys.stderr
        )
        return 1

    rng = random.Random(args.seed)
    count = min(args.sample_size, len(normalized))
    sampled = rng.sample(normalized, count)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = {
        "meta": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "source": "supabase.events.short_story",
            "supabase_url": args.supabase_url,
            "sample_size_requested": args.sample_size,
            "sample_size_actual": count,
            "seed": args.seed,
        },
        "events": sampled,
    }
    output_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Saved {count} events -> {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
