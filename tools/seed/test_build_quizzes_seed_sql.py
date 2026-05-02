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


class LoadQuizFileTests(unittest.TestCase):
    def _valid_payload(self) -> dict:
        return {
            "era_code": "era_primeval",
            "story_index": 1,
            "story_title": "창조: 7일과 안식",
            "source_version": "2026-04-24",
            "questions": [
                {
                    "type": "fact",
                    "display_order": 0,
                    "question": "첫째 날에 만든 것은?",
                    "choices": ["빛", "궁창", "식물"],
                    "answer_index": 0,
                    "explanation": "창 1:3",
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
        path = self._write_as(self._valid_payload(), "era_primeval_n001.json")
        try:
            quiz = mod.load_quiz_file(path)
            self.assertEqual(quiz.era_code, "era_primeval")
            self.assertEqual(quiz.story_index, 1)
            self.assertEqual(len(quiz.questions), 3)
            self.assertEqual(quiz.seed_key, "era_primeval:n001")
        finally:
            path.unlink()

    def test_filename_must_match_era_code(self) -> None:
        path = self._write_as(self._valid_payload(), "era_exodus_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_filename_must_match_story_index(self) -> None:
        path = self._write_as(self._valid_payload(), "era_primeval_n002.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_missing_era_code_raises(self) -> None:
        payload = self._valid_payload()
        del payload["era_code"]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_wrong_question_count_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"] = payload["questions"][:2]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()


class BuildSqlStatementsTests(unittest.TestCase):
    def _sample_quiz_file(
        self,
        era_code: str = "era_primeval",
        story_index: int = 1,
        title: str = "창조: 7일과 안식",
    ) -> "mod.QuizFile":
        return mod.QuizFile(
            path=Path(f"assets/quizzes/{era_code}_n{story_index:03d}.json"),
            era_code=era_code,
            story_index=story_index,
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

    def test_sql_has_begin_commit_and_lookup_clause(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        self.assertIn("begin;", sql)
        self.assertIn("commit;", sql)
        self.assertIn("er.code = 'era_primeval'", sql)
        self.assertIn("e.story_index = 1", sql)

    def test_sql_emits_three_inserts_per_quiz(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        self.assertEqual(sql.count("insert into quiz_questions"), 3)

    def test_sql_emits_delete_before_inserts(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        self.assertIn("delete from quiz_questions", sql)
        self.assertLess(
            sql.find("delete from quiz_questions"),
            sql.find("insert into quiz_questions"),
        )

    def test_dollar_quoting_handles_single_quotes(self) -> None:
        q = mod.QuizFile(
            path=Path("assets/quizzes/era_primeval_n001.json"),
            era_code="era_primeval",
            story_index=1,
            story_title="창조: 7일과 안식",
            source_version="v",
            questions=[
                mod.QuizQuestionDraft("fact", 0, "A'B", ["x'y", "a", "b"], 0, "e'e"),
                mod.QuizQuestionDraft("attitude", 1, "q2", ["A", "B", "C"], 0, "e2"),
                mod.QuizQuestionDraft(
                    "bible_context", 2, "q3", ["A", "B", "C"], 0, "e3"
                ),
            ],
        )
        sql = mod.build_sql_statements([q])
        self.assertIn("$q$A'B$q$", sql)
        self.assertIn("$q$x'y$q$", sql)


class BuildReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)

    def test_total_counts(self) -> None:
        q = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(quiz_files=[q], events=self.events)
        self.assertEqual(report["total_quiz_files"], 1)
        self.assertEqual(report["total_questions"], 3)

    def test_orphan_quiz_detected(self) -> None:
        bogus = BuildSqlStatementsTests()._sample_quiz_file(
            era_code="era_does_not_exist", story_index=999, title="가짜"
        )
        report = mod.build_report(quiz_files=[bogus], events=self.events)
        self.assertEqual(len(report["orphan_quizzes"]), 1)
        self.assertEqual(report["orphan_quizzes"][0]["era_code"], "era_does_not_exist")

    def test_title_mismatch_detected(self) -> None:
        wrong_title = BuildSqlStatementsTests()._sample_quiz_file(
            era_code="era_primeval", story_index=1, title="옛 제목"
        )
        report = mod.build_report(quiz_files=[wrong_title], events=self.events)
        self.assertEqual(len(report["title_mismatches"]), 1)
        self.assertEqual(report["title_mismatches"][0]["json_title"], "옛 제목")

    def test_events_without_quiz_lists_uncovered(self) -> None:
        q = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(quiz_files=[q], events=self.events)
        # 3 events, 1 covered → 2 uncovered.
        self.assertEqual(len(report["events_without_quiz"]), 2)


class DeterministicShuffleTests(unittest.TestCase):
    def test_same_seed_produces_same_order(self) -> None:
        choices = ["A-correct", "B-wrong", "C-wrong"]
        out1 = mod.deterministic_shuffle("era_primeval:n001", 0, choices)
        out2 = mod.deterministic_shuffle("era_primeval:n001", 0, choices)
        self.assertEqual(out1, out2)

    def test_preserves_all_items(self) -> None:
        choices = ["A", "B", "C"]
        shuffled, _ = mod.deterministic_shuffle("era_patriarch:n042", 1, choices)
        self.assertEqual(sorted(shuffled), sorted(choices))

    def test_answer_index_tracks_original_index_zero(self) -> None:
        choices = ["CORRECT", "wrong1", "wrong2"]
        shuffled, answer_index = mod.deterministic_shuffle(
            "era_judges:n099", 2, choices
        )
        self.assertEqual(shuffled[answer_index], "CORRECT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
