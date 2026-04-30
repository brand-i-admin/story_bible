"""Unit tests for tools/seed/build_quizzes_seed_sql.py.

Run: python3 tools/seed/test_build_quizzes_seed_sql.py -v
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_quizzes_seed_sql as mod  # noqa: E402


_EVENTS_SEED_SAMPLE = """\
with seed_events (era_code, title, summary, story_scenes, scene_characters, character_codes, bible_refs, start_year, end_year, time_precision, story_index, place_name, lat, lng, status) as (
  values
    ('era_primeval', '창조: 7일과 안식', '...', '[]'::jsonb, '[]'::jsonb, ARRAY[]::text[], '[]'::jsonb, -4000, -4000, 'approx', 1, '메소포타미아', 31.018, 47.423, 'published'),
    ('era_primeval', '에덴: 사람의 창조와 사명', '...', '[]'::jsonb, '[]'::jsonb, ARRAY[]::text[], '[]'::jsonb, -4000, -4000, 'approx', 2, '에덴', 31.018, 47.423, 'published'),
    ('era_exodus', '시내산 도착: 십계명과 하나님 기준', '...', '[]'::jsonb, '[]'::jsonb, ARRAY[]::text[], '[]'::jsonb, -1446, -1446, 'exact', 14, '시내산', 28.5, 33.9, 'published')
)
"""


class ExtractEventsFromSeedSqlTests(unittest.TestCase):
    def test_parses_three_event_rows(self) -> None:
        events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)
        self.assertEqual(len(events), 3)
        self.assertEqual(events[0].era_code, "era_primeval")
        self.assertEqual(events[0].title, "창조: 7일과 안식")
        self.assertEqual(events[0].story_index, 1)
        self.assertEqual(events[2].era_code, "era_exodus")
        self.assertEqual(events[2].story_index, 14)

    def test_returns_empty_for_unrelated_sql(self) -> None:
        self.assertEqual(
            mod.extract_events_from_seed_sql(
                "insert into characters values ('paul'), ('john');"
            ),
            [],
        )


class ResolveEventForQuizTests(unittest.TestCase):
    def setUp(self) -> None:
        self.events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)
        self.lookup = {e.title: e for e in self.events}

    def test_direct_title_match(self) -> None:
        ek = mod.resolve_event_for_quiz("창조: 7일과 안식", self.lookup)
        self.assertIsNotNone(ek)
        assert ek is not None
        self.assertEqual(ek.story_index, 1)

    def test_alias_match(self) -> None:
        ek = mod.resolve_event_for_quiz(
            "십계명: 하나님 나라의 기준", self.lookup
        )
        self.assertIsNotNone(ek)
        assert ek is not None
        self.assertEqual(ek.title, "시내산 도착: 십계명과 하나님 기준")

    def test_unmatched_returns_none(self) -> None:
        self.assertIsNone(
            mod.resolve_event_for_quiz("가상의 사라진 이야기", self.lookup)
        )


class LoadQuizFileTests(unittest.TestCase):
    def _valid_payload(self) -> dict:
        return {
            "story_code": "evt_n001",
            "story_title": "창조: 7일과 안식",
            "source_version": "2026-04-24",
            "questions": [
                {
                    "type": "fact",
                    "display_order": 0,
                    "question": "첫째 날에 만든 것은?",
                    "choices": ["빛", "궁창", "식물"],
                    "answer_index": 0,
                    "explanation": "창 1:3 — '빛이 있으라'",
                },
                {
                    "type": "attitude",
                    "display_order": 1,
                    "question": "안식일에 하나님은 무엇을 하셨습니까?",
                    "choices": ["쉬셨다", "더 만드셨다", "심판하셨다"],
                    "answer_index": 0,
                    "explanation": "창 2:2",
                },
                {
                    "type": "bible_context",
                    "display_order": 2,
                    "question": "이 사건이 기록된 성경 책은?",
                    "choices": ["창세기", "출애굽기", "레위기"],
                    "answer_index": 0,
                    "explanation": "창세기 1장",
                },
            ],
        }

    def _write_as(self, payload: dict, filename: str) -> Path:
        tmp_dir = tempfile.mkdtemp()
        path = Path(tmp_dir) / filename
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_valid_payload_loads_clean(self) -> None:
        path = self._write_as(self._valid_payload(), "evt_n001.json")
        try:
            quiz = mod.load_quiz_file(path)
            self.assertEqual(quiz.story_code, "evt_n001")
            self.assertEqual(len(quiz.questions), 3)
            self.assertEqual(
                [q.type for q in quiz.questions],
                ["fact", "attitude", "bible_context"],
            )
        finally:
            path.unlink()

    def test_wrong_question_count_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"] = payload["questions"][:2]
        path = self._write_as(payload, "evt_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_filename_must_match_story_code(self) -> None:
        path = self._write_as(self._valid_payload(), "evt_wrong.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()


class BuildSqlStatementsTests(unittest.TestCase):
    def _sample_quiz_file(
        self,
        story_code: str = "evt_n001",
        title: str = "창조: 7일과 안식",
    ) -> "mod.QuizFile":
        return mod.QuizFile(
            path=Path(f"assets/quizzes/{story_code}.json"),
            story_code=story_code,
            story_title=title,
            source_version="2026-04-24",
            questions=[
                mod.QuizQuestionDraft(
                    type="fact",
                    display_order=0,
                    question="첫째 날에 만든 것은?",
                    choices=["빛", "궁창", "식물"],
                    answer_index=0,
                    explanation="창 1:3",
                ),
                mod.QuizQuestionDraft(
                    type="attitude",
                    display_order=1,
                    question="안식일에 하나님은 무엇을 하셨습니까?",
                    choices=["쉬셨다", "더 만드셨다", "심판하셨다"],
                    answer_index=0,
                    explanation="창 2:2",
                ),
                mod.QuizQuestionDraft(
                    type="bible_context",
                    display_order=2,
                    question="이 사건이 기록된 성경 책은?",
                    choices=["창세기", "출애굽기", "레위기"],
                    answer_index=0,
                    explanation="창세기 1장",
                ),
            ],
        )

    def setUp(self) -> None:
        self.events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)
        self.lookup = {e.title: e for e in self.events}

    def test_sql_has_begin_commit_and_lookup_clause(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()], self.lookup)
        self.assertIn("begin;", sql)
        self.assertIn("commit;", sql)
        self.assertIn("er.code = 'era_primeval'", sql)
        self.assertIn("e.story_index = 1", sql)

    def test_sql_emits_three_inserts_per_resolved_quiz(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()], self.lookup)
        self.assertEqual(sql.count("insert into quiz_questions"), 3)

    def test_sql_emits_delete_before_inserts(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()], self.lookup)
        self.assertIn("delete from quiz_questions", sql)
        self.assertLess(
            sql.find("delete from quiz_questions"),
            sql.find("insert into quiz_questions"),
        )

    def test_unresolved_quiz_is_skipped_with_marker(self) -> None:
        unresolved = self._sample_quiz_file(
            story_code="evt_ghost", title="존재하지 않는 이야기"
        )
        sql = mod.build_sql_statements([unresolved], self.lookup)
        self.assertIn("-- SKIPPED evt_ghost", sql)
        self.assertNotIn("insert into quiz_questions", sql)

    def test_alias_redirects_to_current_event_title(self) -> None:
        quiz = self._sample_quiz_file(
            story_code="evt_n064", title="십계명: 하나님 나라의 기준"
        )
        sql = mod.build_sql_statements([quiz], self.lookup)
        self.assertIn("er.code = 'era_exodus'", sql)
        self.assertIn("e.story_index = 14", sql)

    def test_dollar_quoting_handles_single_quotes(self) -> None:
        q = mod.QuizFile(
            path=Path("assets/quizzes/evt_n001.json"),
            story_code="evt_n001",
            story_title="창조: 7일과 안식",
            source_version="v",
            questions=[
                mod.QuizQuestionDraft(
                    "fact", 0, "A'B", ["x'y", "a", "b"], 0, "e'e"
                ),
                mod.QuizQuestionDraft(
                    "attitude", 1, "q2", ["A", "B", "C"], 0, "e2"
                ),
                mod.QuizQuestionDraft(
                    "bible_context", 2, "q3", ["A", "B", "C"], 0, "e3"
                ),
            ],
        )
        sql = mod.build_sql_statements([q], self.lookup)
        self.assertIn("$q$A'B$q$", sql)
        self.assertIn("$q$x'y$q$", sql)


class BuildReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)

    def test_resolved_and_unresolved_counts(self) -> None:
        resolved = BuildSqlStatementsTests()._sample_quiz_file()
        unresolved = BuildSqlStatementsTests()._sample_quiz_file(
            story_code="evt_ghost", title="존재하지 않는 이야기"
        )
        report = mod.build_report(
            quiz_files=[resolved, unresolved], events=self.events
        )
        self.assertEqual(report["total_quiz_files"], 2)
        self.assertEqual(report["resolved_quiz_count"], 1)
        self.assertEqual(len(report["unresolved_quizzes"]), 1)
        self.assertEqual(
            report["unresolved_quizzes"][0]["story_code"], "evt_ghost"
        )

    def test_events_without_quiz_lists_unmapped_events(self) -> None:
        resolved = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(quiz_files=[resolved], events=self.events)
        self.assertEqual(len(report["events_without_quiz"]), 2)


class DeterministicShuffleTests(unittest.TestCase):
    def test_same_seed_produces_same_order(self) -> None:
        choices = ["A-correct", "B-wrong", "C-wrong"]
        out1 = mod.deterministic_shuffle("evt_n001", 0, choices)
        out2 = mod.deterministic_shuffle("evt_n001", 0, choices)
        self.assertEqual(out1, out2)

    def test_preserves_all_items(self) -> None:
        choices = ["A", "B", "C"]
        shuffled, _ = mod.deterministic_shuffle("evt_n042", 1, choices)
        self.assertEqual(sorted(shuffled), sorted(choices))

    def test_answer_index_tracks_original_index_zero(self) -> None:
        choices = ["CORRECT", "wrong1", "wrong2"]
        shuffled, answer_index = mod.deterministic_shuffle(
            "evt_n099", 2, choices
        )
        self.assertEqual(shuffled[answer_index], "CORRECT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
