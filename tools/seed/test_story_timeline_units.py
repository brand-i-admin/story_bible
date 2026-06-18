#!/usr/bin/env python3
"""Tests for curated time-order units in story source JSON."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STORY_DIR = ROOT / "assets" / "200_stories"

EXPECTED_OLD_TESTAMENT_UNITS = {
    "era_primeval.json": [
        "창조와 사람의 사명",
        "에덴 밖 세상",
    ],
    "era_patriarch.json": [
        "아브라함과 이삭의 약속",
        "야곱: 이스라엘이 되다",
        "요셉: 애굽으로 이어진 구원",
    ],
    "era_exodus.json": [
        "애굽의 압제와 홍해 구원",
        "광야의 삶과 언약 훈련",
        "가나안 입성과 여호수아",
    ],
    "era_judges.json": [
        "사사들의 구원과 반복되는 위기",
        "룻과 보아스의 기업 무름",
        "사무엘과 왕정의 문턱",
    ],
    "era_monarchy.json": [
        "사울 시대: 왕의 시작과 몰락",
        "다윗 왕국: 언약과 집안의 균열",
        "솔로몬 시대: 지혜와 성전, 타락",
    ],
    "era_divided_kingdom.json": [
        "왕국 분열과 초기 왕조의 악",
        "엘리야 시대: 아합 집과 참 말씀",
        "엘리사와 예후: 표징과 심판",
        "두 왕국의 흔들림과 북이스라엘의 몰락",
        "남유다의 마지막 회복과 멸망",
    ],
    "era_exile_return.json": [
        "포로지의 소망과 성전 회복",
        "에스더와 뒤집힌 위기",
        "에스라와 느헤미야의 공동체 회복",
    ],
}


def _load_story_file(filename: str) -> list[dict[str, object]]:
    return json.loads((STORY_DIR / filename).read_text(encoding="utf-8"))


class StoryTimelineUnitsTests(unittest.TestCase):
    def test_old_testament_eras_are_split_into_curated_units(self) -> None:
        for filename, expected_titles in EXPECTED_OLD_TESTAMENT_UNITS.items():
            with self.subTest(filename=filename):
                events = _load_story_file(filename)
                units = {str(event.get("unit_code", "")).strip() for event in events}
                metadata_by_code = {
                    str(event.get("unit_code", "")).strip(): (
                        str(event.get("unit_title", "")).strip(),
                        int(event.get("unit_order", 0)),
                    )
                    for event in events
                }
                ordered_titles = [
                    title
                    for title, _ in sorted(
                        metadata_by_code.values(),
                        key=lambda metadata: metadata[1],
                    )
                ]

                self.assertEqual(len(units), len(expected_titles))
                self.assertEqual(ordered_titles, expected_titles)
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
