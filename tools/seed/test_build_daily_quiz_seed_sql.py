"""Unit tests for tools/seed/build_daily_quiz_seed_sql.py.

Run: python3 tools/seed/test_build_daily_quiz_seed_sql.py -v
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_daily_quiz_seed_sql as mod  # noqa: E402


class DailyQuizEraNameTests(unittest.TestCase):
    def test_daily_quiz_keeps_readable_era_names_for_short_ui_labels(self) -> None:
        events = [
            mod.EventSeed(
                era="era_patriarch",
                story_index=1,
                title="아브라함: 부르심을 따라가다",
                place_name="세겜",
                region_code="canaan",
                landmark_code="lm_canaan",
                characters=("abraham",),
            ),
            mod.EventSeed(
                era="era_patriarch",
                story_index=2,
                title="요셉: 애굽으로 팔려가다",
                place_name="고센",
                region_code="egypt",
                landmark_code="lm_egypt",
                characters=("joseph",),
            ),
        ]
        builder = mod.DailyQuizBuilder(
            events=events,
            era_names={"era_patriarch": "족장"},
            region_names={"canaan": "가나안", "egypt": "애굽"},
            character_names={"abraham": "아브라함", "joseph": "요셉"},
        )

        questions = builder.build(1)

        self.assertEqual(len(questions), 1)
        self.assertIn("'족장 시대'", questions[0].question)
        self.assertNotIn("'족장'에서", questions[0].question)

    def test_event_region_questions_are_balanced_across_eras(self) -> None:
        events = [
            mod.EventSeed(
                era="era_patriarch",
                story_index=1,
                title="아브라함: 부르심을 따라가다",
                place_name="세겜",
                region_code="canaan",
                landmark_code="lm_canaan",
                characters=("abraham",),
            ),
            mod.EventSeed(
                era="era_patriarch",
                story_index=2,
                title="요셉: 애굽으로 팔려가다",
                place_name="고센",
                region_code="egypt",
                landmark_code="lm_egypt",
                characters=("joseph",),
            ),
            mod.EventSeed(
                era="era_exodus",
                story_index=1,
                title="모세의 탄생과 갈대상자",
                place_name="나일강",
                region_code="egypt",
                landmark_code="lm_egypt",
                characters=("moses",),
            ),
            mod.EventSeed(
                era="era_exodus",
                story_index=2,
                title="홍해: 길이 열리다",
                place_name="홍해",
                region_code="red_sea",
                landmark_code="lm_red_sea",
                characters=("moses",),
            ),
        ]
        builder = mod.DailyQuizBuilder(
            events=events,
            era_names={"era_patriarch": "족장", "era_exodus": "출애굽"},
            region_names={
                "canaan": "가나안",
                "egypt": "애굽",
                "red_sea": "홍해",
            },
            character_names={
                "abraham": "아브라함",
                "joseph": "요셉",
                "moses": "모세",
            },
        )

        questions = builder.build(2)

        self.assertEqual(
            [mod._source_era(q.source) for q in questions],
            [
                "era_patriarch",
                "era_exodus",
            ],
        )

    def test_hidden_consummation_era_is_excluded(self) -> None:
        events = [
            mod.EventSeed(
                era="era_nt_consummation",
                story_index=1,
                title="새 하늘과 새 땅",
                place_name="새 예루살렘",
                region_code="vision",
                landmark_code="lm_vision",
                characters=("john",),
            ),
            mod.EventSeed(
                era="era_nt_consummation",
                story_index=2,
                title="생명수 강",
                place_name="새 예루살렘",
                region_code="new_creation",
                landmark_code="lm_new_creation",
                characters=("john",),
            ),
        ]
        builder = mod.DailyQuizBuilder(
            events=events,
            era_names={"era_nt_consummation": "역사의 종결"},
            region_names={"vision": "환상", "new_creation": "새 창조"},
            character_names={"john": "요한"},
        )

        self.assertEqual(builder.build(10), [])


if __name__ == "__main__":
    unittest.main()
