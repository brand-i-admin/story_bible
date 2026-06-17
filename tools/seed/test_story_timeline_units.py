#!/usr/bin/env python3
"""Tests for curated time-order units in story source JSON."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STORY_DIR = ROOT / "assets" / "200_stories"

EXPECTED_OLD_TESTAMENT_UNIT_COUNTS = {
    "era_primeval.json": 3,
    "era_patriarch.json": 5,
    "era_exodus.json": 5,
    "era_judges.json": 3,
    "era_monarchy.json": 4,
    "era_divided_kingdom.json": 6,
    "era_exile_return.json": 4,
}


def _load_story_file(filename: str) -> list[dict[str, object]]:
    return json.loads((STORY_DIR / filename).read_text(encoding="utf-8"))


class StoryTimelineUnitsTests(unittest.TestCase):
    def test_old_testament_eras_are_split_into_curated_units(self) -> None:
        for filename, expected_count in EXPECTED_OLD_TESTAMENT_UNIT_COUNTS.items():
            with self.subTest(filename=filename):
                events = _load_story_file(filename)
                units = {str(event.get("unit_code", "")).strip() for event in events}

                self.assertEqual(len(units), expected_count)
                self.assertNotIn("default", units)

    def test_unit_metadata_is_consistent_within_each_story_file(self) -> None:
        for path in STORY_DIR.glob("era_*.json"):
            with self.subTest(filename=path.name):
                events = _load_story_file(path.name)
                metadata_by_code: dict[str, tuple[str, int]] = {}
                for event in events:
                    code = str(event.get("unit_code", "")).strip()
                    title = str(event.get("unit_title", "")).strip()
                    order = event.get("unit_order")

                    self.assertTrue(code)
                    self.assertTrue(title)
                    self.assertIsInstance(order, int)

                    metadata = (title, int(order))
                    previous = metadata_by_code.setdefault(code, metadata)
                    self.assertEqual(previous, metadata)


if __name__ == "__main__":
    unittest.main()
