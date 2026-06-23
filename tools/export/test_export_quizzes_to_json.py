"""Unit tests for tools/export/export_quizzes_to_json.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from export_quizzes_to_json import (  # noqa: E402
    build_quiz_payloads,
    filename_for_quiz,
    quiz_row_to_json,
)


class ExportQuizzesToJsonTests(unittest.TestCase):
    def test_filename_for_quiz_uses_era_and_index(self) -> None:
        self.assertEqual(
            filename_for_quiz("era_primeval", 3),
            "era_primeval_n003.json",
        )

    def test_quiz_row_to_json_maps_db_columns(self) -> None:
        row = {
            "question": "무엇을 하셨습니까?",
            "choice_a": "빛을 만드셨다",
            "choice_b": "성전을 지으셨다",
            "choice_c": "배를 만드셨다",
            "choice_d": "헷갈렸어요",
            "answer_index": 0,
            "explanation": "창 1:3",
            "display_order": 1,
        }

        result = quiz_row_to_json(row)

        self.assertEqual(result["type"], "attitude")
        self.assertEqual(result["display_order"], 1)
        self.assertEqual(
            result["choices"], ["빛을 만드셨다", "성전을 지으셨다", "배를 만드셨다"]
        )
        self.assertEqual(result["answer_index"], 0)

    def test_build_quiz_payloads_preserves_existing_source_version(self) -> None:
        events = [
            {
                "id": "event-1",
                "era_code": "era_primeval",
                "story_index": 1,
                "title": "창조",
            }
        ]
        quizzes = {
            "event-1": [
                {
                    "question": "Q",
                    "choice_a": "A",
                    "choice_b": "B",
                    "choice_c": "C",
                    "answer_index": 2,
                    "explanation": "E",
                    "display_order": 0,
                }
            ]
        }

        payloads = build_quiz_payloads(
            events,
            quizzes,
            source_versions={("era_primeval", 1): "2026-05-25"},
            default_source_version="2026-06-23",
        )

        payload = payloads["era_primeval_n001.json"]
        self.assertEqual(payload["source_version"], "2026-05-25")
        self.assertEqual(len(payload["questions"]), 1)
        self.assertEqual(payload["questions"][0]["type"], "fact")


if __name__ == "__main__":
    unittest.main()
