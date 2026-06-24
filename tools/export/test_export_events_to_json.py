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
    event_row_to_json,
    filename_for_era,
    group_events_by_era_file,
    published_events_query_params,
    write_grouped_events,
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
            "background_context": "창조 이야기의 배경 지식.",
            "start_year": -4000,
            "end_year": -4000,
            "time_precision": "approx",
            "story_index": 1,
            "unit_code": "primeval_creation",
            "unit_title": "창조와 타락",
            "unit_order": 1,
            "story_scenes": ["장면 1", "장면 2"],
            "scene_captions": ["캡션 1", "캡션 2"],
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
        self.assertEqual(result["background_context"], "창조 이야기의 배경 지식.")
        self.assertEqual(result["unit_code"], "primeval_creation")
        self.assertEqual(result["unit_title"], "창조와 타락")
        self.assertEqual(result["unit_order"], 1)
        self.assertEqual(result["story_scenes"], ["장면 1", "장면 2"])
        self.assertEqual(result["scene_captions"], ["캡션 1", "캡션 2"])
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
                "background_context",
                "bible_ref",
                "start_year",
                "end_year",
                "time_precision",
                "story_index",
                "unit_code",
                "unit_title",
                "unit_order",
                "story_scenes",
                "scene_captions",
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
            "background_context": None,
            "start_year": None,
            "end_year": None,
            "time_precision": None,
            "story_index": 5,
            "unit_code": None,
            "unit_title": None,
            "unit_order": None,
            "story_scenes": None,
            "scene_captions": None,
            "scene_characters": None,
        }

        result = event_row_to_json(row)

        self.assertEqual(result["characters"], [])
        self.assertEqual(result["bible_ref"], [])
        self.assertEqual(result["story_scenes"], [])
        self.assertEqual(result["scene_captions"], [])
        self.assertEqual(result["scene_characters"], [])
        self.assertEqual(result["time_precision"], "approx")
        self.assertEqual(result["background_context"], "")
        self.assertEqual(result["unit_code"], "default")
        self.assertEqual(result["unit_title"], "전체 흐름")
        self.assertEqual(result["unit_order"], 1)
        self.assertIsNone(result["lat"])
        self.assertEqual(result["summary"], "")

    def test_filename_for_era_uses_era_scoped_files(self) -> None:
        self.assertEqual(filename_for_era("era_primeval"), "era_primeval.json")
        self.assertEqual(
            filename_for_era("era_divided_kingdom"),
            "era_divided_kingdom.json",
        )
        self.assertEqual(filename_for_era(""), "unknown_era.json")

    def test_group_events_by_era_file_groups_and_sorts_within_each_file(self) -> None:
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
                "background_context": "",
                "start_year": None,
                "end_year": None,
                "time_precision": "approx",
                "unit_code": "default",
                "unit_title": "전체 흐름",
                "unit_order": 1,
                "story_scenes": [],
                "scene_captions": [],
                "scene_characters": [],
            }
            for row in rows
        ]

        grouped = group_events_by_era_file(rows_full)

        self.assertEqual(set(grouped.keys()), {"era_primeval.json", "era_exodus.json"})
        self.assertEqual(
            [item["title"] for item in grouped["era_primeval.json"]],
            ["001 b", "002 a"],
        )
        self.assertEqual(grouped["era_exodus.json"][0]["title"], "060 c")

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
            "background_context": "bg",
            "start_year": -4000,
            "end_year": -4000,
            "time_precision": "approx",
            "story_index": 1,
            "unit_code": "default",
            "unit_title": "전체 흐름",
            "unit_order": 1,
            "story_scenes": ["scene"],
            "scene_captions": ["caption"],
            "scene_characters": [["god"]],
        }

        out = event_row_to_json(row)
        decoded = json.loads(json.dumps(out, ensure_ascii=False))

        self.assertEqual(decoded["title"], "001 X")

    def test_published_events_query_params_excludes_soft_deleted_rows(self) -> None:
        params = published_events_query_params(limit=1000, offset=0)

        self.assertEqual(params["status"], "eq.published")
        self.assertEqual(params["deleted_at"], "is.null")

    def test_write_grouped_events_prunes_stale_era_files(self) -> None:
        temp_dir = Path(self._temp_dir.name)
        stale = temp_dir / "era_exodus.json"
        stale.write_text("[]\n", encoding="utf-8")

        write_grouped_events(
            temp_dir,
            {
                "era_primeval.json": [
                    {
                        "title": "창조",
                        "era": "era_primeval",
                        "story_index": 1,
                    }
                ]
            },
        )

        self.assertTrue((temp_dir / "era_primeval.json").exists())
        self.assertFalse(stale.exists())

    def setUp(self) -> None:
        import tempfile

        self._temp_dir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self._temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
