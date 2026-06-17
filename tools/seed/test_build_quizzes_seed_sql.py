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

_EVENTS_SEED_WITH_UNIT_SAMPLE = """\
with seed_events (era_code, title, summary, story_scenes, scene_characters, character_codes, bible_refs, start_year, end_year, time_precision, story_index, unit_code, unit_title, unit_order, landmark_code, status) as (
  values
    ('era_nt_consummation', '미혹과 환난 속에서도 끝까지 견딤', '...', '[]'::jsonb, '[]'::jsonb, ARRAY['jesus']::text[], '[]'::jsonb, 33, 33, 'approx', 1, 'jesus_last_days_watchfulness', '예수님이 가르치신 마지막 때의 자세', 1, 'lm_nt_con_mount_olives', 'published'),
    ('era_nt_post_apostolic', '믿음으로 의롭다 하심', '...', '[]'::jsonb, '[]'::jsonb, ARRAY['paul']::text[], '[]'::jsonb, 57, 57, 'approx', 17, 'pauline_churches', '바울이 세운 교회들의 문제와 소망', 2, 'lm_nt_post_rome', 'published')
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

    def test_parses_unit_event_rows(self) -> None:
        events = mod.extract_events_from_seed_sql(_EVENTS_SEED_WITH_UNIT_SAMPLE)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0].era_code, "era_nt_consummation")
        self.assertEqual(events[0].title, "미혹과 환난 속에서도 끝까지 견딤")
        self.assertEqual(events[0].story_index, 1)
        self.assertEqual(events[1].era_code, "era_nt_post_apostolic")
        self.assertEqual(events[1].story_index, 17)


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
                    "type": "story_context",
                    "display_order": 2,
                    "question": "하나님이 무엇을 했습니까?",
                    "choices": [
                        "말씀으로 세상을 창조하셨다",
                        "빛과 어두움을 나누셨다",
                        "일곱째 날에 안식하셨다",
                    ],
                    "answer_index": 0,
                    "explanation": "창 1:1 — '하나님이 말씀으로 세상을 창조하시니라'",
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

    def test_story_context_rejects_source_location_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2]["question"] = "이 사건이 기록된 성경 책은?"
        payload["questions"][2]["choices"] = ["창세기", "출애굽기", "레위기"]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "source location"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_verse_location_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2]["question"] = "이 사건은 어느 구절에 나옵니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "source location"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_story_title_matching_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = "이 설명에 맞는 이야기는 무엇입니까? 하나님이 세상을 창조하신다."
        payload["questions"][2]["choices"] = [
            "창조: 7일과 안식",
            "홍해: 길이 열리다",
            "가나의 혼인잔치",
        ]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "story title"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_title_wrapped_summary_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = "「창조: 7일과 안식」에서 실제로 일어난 일은 무엇입니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "story title"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_rejects_quoted_story_title_question_prefix(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0][
            "question"
        ] = "'창조: 7일과 안식'에서 하나님은 무엇을 하셨습니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "story title"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_story_title_choice(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2]["choices"][0] = "창조: 7일과 안식"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "story title"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_rejects_generic_filler_distractor(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["choices"][1] = "그 일을 숨기고 물러났다"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "generic filler"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_core_summary_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = "본문을 읽고 알 수 있는 핵심 내용으로 알맞은 것은 무엇입니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "summary"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_blank_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = '본문의 빈칸에 들어갈 말은 무엇입니까? "하나님이 ____ 하시니라"'
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "blank"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_generic_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = "본문에 따르면 다음 중 맞는 내용은 무엇입니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "generic"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_rejects_contextless_generic_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["question"] = "왕은 어떻게 했습니까?"
        payload["questions"][0]["choices"] = [
            "조서를 내리고 잔치에 앉았다",
            "백성을 다시 불러 모았다",
            "성문 밖으로 나가 기다렸다",
        ]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "ambiguous"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_rejects_choice_that_cannot_answer_speech_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0][
            "question"
        ] = "모세 앞에서 아론은 무엇이라고 말했습니까?"
        payload["questions"][0]["choices"] = [
            "백성의 악함을 당신도 알고 있다고 답했다",
            "여호수아",
            "전쟁의 함성이라고 대답했다",
        ]
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "grammatically"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_expression_lookup_question(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "question"
        ] = "다음 중 이 이야기 본문에서 확인되는 표현은 무엇입니까?"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "generic"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_rejects_full_verse_choice(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2]["choices"][0] = (
            "하나님이 말씀으로 세상을 창조하시니라 그리고 빛과 어두움을 나누셨으며 "
            "하늘과 땅과 바다와 모든 생물을 차례로 만드시고 일곱째 날에는 안식하셨다"
        )
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(
                mod.QuizValidationError, "too long|verse fragment"
            ):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_rejects_verse_fragment_choice_wording(self) -> None:
        payload = self._valid_payload()
        payload["questions"][0]["choices"][0] = "빛이 있으라 하시니라"
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "verse fragment"):
                mod.load_quiz_file(path)
        finally:
            path.unlink()

    def test_story_context_requires_verse_evidence(self) -> None:
        payload = self._valid_payload()
        payload["questions"][2][
            "explanation"
        ] = "이 이야기에서는 하나님이 세상을 창조하신다."
        path = self._write_as(payload, "era_primeval_n001.json")
        try:
            with self.assertRaisesRegex(mod.QuizValidationError, "verse"):
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
                    type="story_context",
                    display_order=2,
                    question="하나님이 무엇을 했습니까?",
                    choices=[
                        "말씀으로 세상을 창조하셨다",
                        "빛과 어두움을 나누셨다",
                        "일곱째 날에 안식하셨다",
                    ],
                    answer_index=0,
                    explanation="창 1:1 — '하나님이 말씀으로 세상을 창조하시니라'",
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

    def test_sql_adds_confused_choice_as_fourth_choice(self) -> None:
        sql = mod.build_sql_statements([self._sample_quiz_file()])
        self.assertEqual(sql.count("$q$헷갈렸어요$q$"), 3)

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
                    "story_context", 2, "q3", ["A", "B", "C"], 0, "e3"
                ),
            ],
        )
        sql = mod.build_sql_statements([q])
        self.assertIn("$q$A'B$q$", sql)
        self.assertIn("$q$x'y$q$", sql)


class BuildReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.events = mod.extract_events_from_seed_sql(_EVENTS_SEED_SAMPLE)
        self.story_scopes = {
            ("era_primeval", 1): mod.StoryVerseScope(
                title="창조: 7일과 안식",
                refs=(mod.BibleRefRange(book="창", start=(1, 1), end=(2, 3)),),
            )
        }

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

    def test_story_context_uses_longer_length_limits(self) -> None:
        q = mod.QuizFile(
            path=Path("assets/quizzes/era_primeval_n001.json"),
            era_code="era_primeval",
            story_index=1,
            story_title="창조: 7일과 안식",
            source_version="v",
            questions=[
                mod.QuizQuestionDraft("fact", 0, "짧은 질문?", ["A", "B", "C"], 0, ""),
                mod.QuizQuestionDraft(
                    "attitude", 1, "또 짧은 질문?", ["A", "B", "C"], 0, ""
                ),
                mod.QuizQuestionDraft(
                    "story_context",
                    2,
                    "하나님이 무엇을 했습니까?",
                    [
                        "말씀으로 세상을 창조하셨다",
                        "빛과 어두움을 나누셨다",
                        "일곱째 날에 안식하셨다",
                    ],
                    0,
                    "창 1:1 — '하나님이 말씀으로 세상을 창조하시니라'",
                ),
            ],
        )
        report = mod.build_report(quiz_files=[q], events=self.events)
        self.assertEqual(report["length_warnings"], [])

    def test_verse_scope_accepts_evidence_inside_story_ref(self) -> None:
        q = BuildSqlStatementsTests()._sample_quiz_file()
        report = mod.build_report(
            quiz_files=[q],
            events=self.events,
            story_scopes=self.story_scopes,
        )
        self.assertEqual(report["verse_scope_violations"], [])

    def test_verse_scope_detects_evidence_outside_story_ref(self) -> None:
        q = BuildSqlStatementsTests()._sample_quiz_file()
        bad = mod.QuizFile(
            path=q.path,
            era_code=q.era_code,
            story_index=q.story_index,
            story_title=q.story_title,
            source_version=q.source_version,
            questions=[
                mod.QuizQuestionDraft(
                    "fact",
                    0,
                    "첫째 날에 만든 것은?",
                    ["빛", "궁창", "식물"],
                    0,
                    "출 21:6 — '그가 영영히 그 상전을 섬기리라'",
                ),
                *q.questions[1:],
            ],
        )
        report = mod.build_report(
            quiz_files=[bad],
            events=self.events,
            story_scopes=self.story_scopes,
        )
        self.assertEqual(len(report["verse_scope_violations"]), 1)
        self.assertEqual(
            report["verse_scope_violations"][0]["reason"],
            "outside_story_bible_ref",
        )
        self.assertEqual(
            report["verse_scope_violations"][0]["evidence_ref"],
            "출 21:6",
        )


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
