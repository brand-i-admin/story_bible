"""Unit tests for tools/build_quizzes_seed_sql.py.

Run: python3 tools/test_build_quizzes_seed_sql.py -v
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

# Make sibling import work regardless of CWD.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_quizzes_seed_sql as mod  # noqa: E402


class ExtractEventCodesTests(unittest.TestCase):
    def test_extracts_unique_evt_codes_sorted(self) -> None:
        sql_sample = """
        insert into seed_events (code, title) values
            ('evt_n001', 'a'),
            ('evt_n002', 'b'),
            ('evt_nt_paul_j1_n185', 'c'),
            ('evt_n001', 'a-dup');
        """
        codes = mod.extract_event_codes_from_seed_sql(sql_sample)
        self.assertEqual(
            codes,
            ["evt_n001", "evt_n002", "evt_nt_paul_j1_n185"],
        )

    def test_ignores_non_evt_string_literals(self) -> None:
        sql_sample = "insert into persons values ('paul_apostle'), ('john_baptist');"
        codes = mod.extract_event_codes_from_seed_sql(sql_sample)
        self.assertEqual(codes, [])


import json
import tempfile
from pathlib import Path as _P


class LoadQuizFileTests(unittest.TestCase):
    def _write(self, payload: dict) -> _P:
        tmp = tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=".json", delete=False
        )
        json.dump(payload, tmp)
        tmp.close()
        return _P(tmp.name)

    def _valid_payload(self) -> dict:
        return {
            "story_code": "evt_n001",
            "story_title": "창조",
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
                    "explanation": "창 2:2 — 제 칠일에 안식하셨다",
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

    def test_valid_payload_loads_clean(self) -> None:
        path = self._write(self._valid_payload())
        # Rename the temp file so its stem equals "evt_n001".
        target = path.with_name("evt_n001.json")
        path.rename(target)
        try:
            quiz = mod.load_quiz_file(target)
            self.assertEqual(quiz.story_code, "evt_n001")
            self.assertEqual(len(quiz.questions), 3)
            self.assertEqual(
                [q.type for q in quiz.questions],
                ["fact", "attitude", "bible_context"],
            )
        finally:
            target.unlink()

    def _write_as(self, payload: dict, filename: str) -> _P:
        """Write payload to a temp directory with a specific filename (stem matters)."""
        tmp_dir = tempfile.mkdtemp()
        path = _P(tmp_dir) / filename
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_wrong_question_count_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"] = payload["questions"][:2]
        path = self._write_as(payload, "evt_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError) as cm:
                mod.load_quiz_file(path)
            self.assertIn("questions length", str(cm.exception))
        finally:
            path.unlink()

    def test_wrong_type_order_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["type"] = "attitude"
        payload["questions"][1]["type"] = "fact"
        path = self._write_as(payload, "evt_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_wrong_choices_length_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["choices"] = ["A", "B"]
        path = self._write_as(payload, "evt_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_empty_choice_raises(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["choices"] = ["빛", "", "식물"]
        path = self._write_as(payload, "evt_n001.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_filename_must_match_story_code(self) -> None:
        payload = self._valid_payload()
        path = self._write_as(payload, "evt_wrong.json")
        try:
            with self.assertRaises(mod.QuizValidationError):
                mod.load_quiz_file(path)
        finally:
            path.unlink()


class BuildReportTests(unittest.TestCase):
    def test_report_counts_and_distribution(self) -> None:
        quiz_file = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(
            quiz_files=[quiz_file],
            expected_codes=["evt_n001"],
        )
        self.assertEqual(report["total_files"], 1)
        self.assertEqual(report["total_questions"], 3)
        self.assertEqual(report["missing_story_codes"], [])
        self.assertEqual(report["unknown_story_codes"], [])
        dist = report["answer_index_distribution"]
        self.assertEqual(sum(dist.values()), 3)

    def test_report_detects_missing_and_unknown(self) -> None:
        quiz_file = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(
            quiz_files=[quiz_file],
            expected_codes=["evt_n001", "evt_n002"],
        )
        self.assertEqual(report["missing_story_codes"], ["evt_n002"])

        quiz_file2 = mod.QuizFile(
            path=_P("assets/quizzes/evt_bogus.json"),
            story_code="evt_bogus",
            story_title="",
            source_version="",
            questions=quiz_file.questions,
        )
        report2 = mod.build_report(
            quiz_files=[quiz_file2], expected_codes=["evt_n001"]
        )
        self.assertEqual(report2["unknown_story_codes"], ["evt_bogus"])
        self.assertEqual(report2["missing_story_codes"], ["evt_n001"])


class BuildSqlStatementsTests(unittest.TestCase):
    def _sample_quiz_file(self) -> "mod.QuizFile":
        return mod.QuizFile(
            path=_P("assets/quizzes/evt_n001.json"),
            story_code="evt_n001",
            story_title="창조",
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

    def test_sql_contains_expected_clauses(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        self.assertIn("begin;", sql)
        self.assertIn("commit;", sql)
        self.assertIn("on conflict (event_id, display_order)", sql)
        self.assertIn("where e.story_index = 1", sql)
        self.assertIn("null,", sql)  # choice_d NULL

    def test_sql_emits_three_inserts_per_file(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        insert_count = sql.count("insert into quiz_questions")
        self.assertEqual(insert_count, 3)

    def test_shuffling_repositions_correct_answer(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        # The deterministic shuffle places the original choices[0] ("빛") at
        # some index in {0,1,2}; whichever slot it lands in, "빛" must appear
        # somewhere in the first INSERT statement. Values are dollar-quoted so
        # we look for the bare substring, not a single-quoted literal.
        statements = sql.split(";")
        # statements[0] = preamble+'begin', statements[1] = first INSERT.
        first_insert = statements[1]
        self.assertIn("빛", first_insert)

    def test_escapes_single_quotes_via_dollar_quoting(self) -> None:
        q = mod.QuizFile(
            path=_P("assets/quizzes/evt_n042.json"),
            story_code="evt_n042",
            story_title="t",
            source_version="v",
            questions=[
                mod.QuizQuestionDraft("fact", 0, "A'B", ["x'y", "a", "b"], 0, "e'e"),
                mod.QuizQuestionDraft("attitude", 1, "q2", ["A", "B", "C"], 0, "e2"),
                mod.QuizQuestionDraft("bible_context", 2, "q3", ["A", "B", "C"], 0, "e3"),
            ],
        )
        sql = mod.build_sql_statements([q])
        self.assertIn("$q$A'B$q$", sql)
        self.assertIn("$q$x'y$q$", sql)


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

    def test_answer_index_tracks_item_at_original_index_0(self) -> None:
        choices = ["CORRECT", "wrong1", "wrong2"]
        shuffled, answer_index = mod.deterministic_shuffle("evt_n099", 2, choices)
        self.assertEqual(shuffled[answer_index], "CORRECT")

    def test_different_display_orders_can_produce_different_orderings(self) -> None:
        # Not a strict property of the hash, but we at least exercise multiple seeds
        # and ensure they don't all collapse to the identity permutation.
        choices = ["A", "B", "C"]
        permutations = {
            tuple(mod.deterministic_shuffle(f"evt_n{i:03d}", j, choices)[0])
            for i in range(1, 50)
            for j in range(3)
        }
        self.assertGreater(len(permutations), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
