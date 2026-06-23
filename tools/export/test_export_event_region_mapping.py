"""Unit tests for tools/export/export_event_region_mapping.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from export_event_region_mapping import (  # noqa: E402
    build_mapping_payload,
    event_row_to_mapping,
)


class ExportEventRegionMappingTests(unittest.TestCase):
    def test_event_row_to_mapping_uses_parent_region_for_landmark(self) -> None:
        landmarks = {
            "r1": {
                "id": "r1",
                "code": "rgn_judea",
                "name": "유다",
                "kind": "region",
                "parent_landmark_id": None,
            },
            "l1": {
                "id": "l1",
                "code": "lm_jerusalem",
                "name": "예루살렘",
                "kind": "landmark",
                "parent_landmark_id": "r1",
            },
        }
        event = {
            "era_code": "era_monarchy",
            "story_index": 4,
            "title": "다윗",
            "landmark_id": "l1",
        }

        result = event_row_to_mapping(event, landmarks)

        self.assertEqual(result["region_code"], "rgn_judea")
        self.assertEqual(result["landmark_code"], "lm_jerusalem")
        self.assertEqual(result["place_name"], "예루살렘")

    def test_region_landmark_maps_to_itself(self) -> None:
        landmarks = {
            "r1": {
                "id": "r1",
                "code": "rgn_sinai",
                "name": "시내 광야",
                "kind": "region",
            },
        }

        result = event_row_to_mapping(
            {
                "era_code": "era_exodus",
                "story_index": 1,
                "title": "출애굽",
                "landmark_id": "r1",
            },
            landmarks,
        )

        self.assertEqual(result["region_code"], "rgn_sinai")
        self.assertEqual(result["landmark_code"], "rgn_sinai")

    def test_build_mapping_payload_sorts_by_era_and_index(self) -> None:
        landmarks = {
            "r1": {"id": "r1", "code": "rgn_a", "name": "A", "kind": "region"},
        }
        payload = build_mapping_payload(
            [
                {
                    "era_code": "era_b",
                    "story_index": 2,
                    "title": "B2",
                    "landmark_id": "r1",
                },
                {
                    "era_code": "era_a",
                    "story_index": 1,
                    "title": "A1",
                    "landmark_id": "r1",
                },
            ],
            landmarks,
        )

        self.assertEqual(
            [(row["era"], row["story_index"]) for row in payload["rows"]],
            [("era_a", 1), ("era_b", 2)],
        )


if __name__ == "__main__":
    unittest.main()
