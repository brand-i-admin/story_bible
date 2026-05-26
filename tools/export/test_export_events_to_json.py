"""Unit tests for tools/export/export_events_to_json.py.

DB calls are mocked away; these tests cover events row -> JSON conversion.
Run: python3 -m unittest tools/export/test_export_events_to_json.py -v
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from export_events_to_json import (  # noqa: E402
    bucket_for_story_index,
    event_row_to_json,
    group_events_by_bucket,
)


class ExportEventsToJsonTests(unittest.TestCase):
    def test_event_row_to_json_basic_published_row(self) -> None:
        row = {
            "title": "001 창조: 7일과 안식",
            "era_code": "era_primeval",
            "summary": "하나님이 말씀으로 세상을 창조하신다.",
            "character_codes": ["god"],
            "place_name": "메소포타미아(추정)",
            "lat": 31.018,
            "lng": 47.423,
            "bible_refs": [{"book": "창", "from": "1:1", "to": "2:3"}],
            "start_year": -4000,
            "end_year": -4000,
            "time_precision": "approx",
            "story_index": 1,
            "story_scenes": ["장면 1", "장면 2"],
            "scene_characters": [["god"], []],
        }

        result = event_row_to_json(row)

        self.assertEqual(result["title"], "001 창조: 7일과 안식")
        self.assertEqual(result["era"], "era_primeval")
        self.assertEqual(result["characters"], ["god"])
        self.assertEqual(result["lat"], 31.018)
        self.assertEqual(result["lng"], 47.423)
        self.assertEqual(
            result["bible_ref"],
            [{"book": "창", "from": "1:1", "to": "2:3"}],
        )
        self.assertEqual(result["story_index"], 1)
        self.assertEqual(result["story_scenes"], ["장면 1", "장면 2"])
        self.assertEqual(result["scene_characters"], [["god"], []])
        self.assertEqual(
            list(result.keys()),
            [
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
            ],
        )

    def test_event_row_to_json_handles_nulls_and_missing_fields(self) -> None:
        row = {
            "title": "999 빈 이야기",
            "era_code": "era_judges",
            "summary": None,
            "character_codes": None,
            "place_name": None,
            "lat": None,
            "lng": None,
            "bible_refs": None,
            "start_year": None,
            "end_year": None,
            "time_precision": None,
            "story_index": 5,
            "story_scenes": None,
            "scene_characters": None,
        }

        result = event_row_to_json(row)

        self.assertEqual(result["characters"], [])
        self.assertEqual(result["bible_ref"], [])
        self.assertEqual(result["story_scenes"], [])
        self.assertEqual(result["scene_characters"], [])
        self.assertEqual(result["time_precision"], "approx")
        self.assertIsNone(result["lat"])
        self.assertEqual(result["summary"], "")

    def test_bucket_for_story_index_uses_50_step_buckets(self) -> None:
        self.assertEqual(bucket_for_story_index(1), "1_50.json")
        self.assertEqual(bucket_for_story_index(50), "1_50.json")
        self.assertEqual(bucket_for_story_index(51), "51_100.json")
        self.assertEqual(bucket_for_story_index(100), "51_100.json")
        self.assertEqual(bucket_for_story_index(101), "101_150.json")
        self.assertEqual(bucket_for_story_index(184), "151_200.json")
        self.assertEqual(bucket_for_story_index(215), "201_250.json")

    def test_group_events_by_bucket_groups_and_sorts_within_each_file(self) -> None:
        rows = [
            {"title": "002 a", "era_code": "era_primeval", "story_index": 2},
            {"title": "001 b", "era_code": "era_primeval", "story_index": 1},
            {"title": "060 c", "era_code": "era_exodus", "story_index": 60},
        ]
        rows_full = [
            {
                **row,
                "summary": "",
                "character_codes": [],
                "place_name": "",
                "lat": None,
                "lng": None,
                "bible_refs": [],
                "start_year": None,
                "end_year": None,
                "time_precision": "approx",
                "story_scenes": [],
                "scene_characters": [],
            }
            for row in rows
        ]

        grouped = group_events_by_bucket(rows_full)

        self.assertEqual(set(grouped.keys()), {"1_50.json", "51_100.json"})
        self.assertEqual(
            [item["title"] for item in grouped["1_50.json"]],
            ["001 b", "002 a"],
        )
        self.assertEqual(grouped["51_100.json"][0]["title"], "060 c")

    def test_round_trip_json_serializable(self) -> None:
        row = {
            "title": "001 X",
            "era_code": "era_primeval",
            "summary": "s",
            "character_codes": ["god"],
            "place_name": "p",
            "lat": 1.0,
            "lng": 2.0,
            "bible_refs": [{"book": "창", "from": "1:1", "to": "1:1"}],
            "start_year": -4000,
            "end_year": -4000,
            "time_precision": "approx",
            "story_index": 1,
            "story_scenes": ["scene"],
            "scene_characters": [["god"]],
        }

        out = event_row_to_json(row)
        decoded = json.loads(json.dumps(out, ensure_ascii=False))

        self.assertEqual(decoded["title"], "001 X")


if __name__ == "__main__":
    unittest.main()
