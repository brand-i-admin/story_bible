import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).with_name("apply_story_draft.py")
SPEC = importlib.util.spec_from_file_location("apply_story_draft", MODULE_PATH)
apply_story_draft = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(apply_story_draft)


def valid_event() -> dict:
    return {
        "title": "까마귀가 먹인 엘리야",
        "summary": "하나님이 엘리야를 시냇가에서 돌보신 이야기",
        "background_context": "아합 시대의 영적 혼란 속에서 하나님이 선지자를 지키신다.",
        "story_scenes": ["엘리야가 말씀을 받는다.", "까마귀가 음식을 가져온다."],
        "scene_captions": ["말씀을 듣는 엘리야", "시냇가의 공급"],
        "quiz_questions": [
            {
                "question": "누가 엘리야에게 음식을 가져왔나요?",
                "choices": ["까마귀", "상인", "군인"],
                "answer_index": 0,
                "explanation": "하나님은 까마귀를 통해 엘리야를 먹이셨습니다.",
            }
        ],
    }


class ApplyStoryDraftValidationTest(unittest.TestCase):
    def test_validate_event_accepts_current_story_shape(self):
        scenes, captions = apply_story_draft.validate_event(valid_event())

        self.assertEqual(scenes, valid_event()["story_scenes"])
        self.assertEqual(captions, valid_event()["scene_captions"])

    def test_validate_event_requires_background_context(self):
        event = valid_event()
        event["background_context"] = ""

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

    def test_validate_event_requires_matching_scene_captions(self):
        event = valid_event()
        event["scene_captions"] = ["하나만 있음"]

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

    def test_validate_event_requires_one_to_three_quizzes(self):
        event = valid_event()
        event["quiz_questions"] = []

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

        event = valid_event()
        event["quiz_questions"] = valid_event()["quiz_questions"] * 4

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

    def test_validate_event_rejects_invalid_quiz_choices(self):
        event = valid_event()
        event["quiz_questions"][0]["choices"] = ["까마귀", ""]

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

    def test_validate_event_rejects_invalid_quiz_answer_index(self):
        event = valid_event()
        event["quiz_questions"][0]["answer_index"] = 3

        with self.assertRaises(SystemExit):
            apply_story_draft.validate_event(event)

    def test_normalized_title_collapses_case_and_spaces(self):
        self.assertEqual(
            apply_story_draft.normalized_title("  새   이야기  "),
            apply_story_draft.normalized_title("새 이야기"),
        )


if __name__ == "__main__":
    unittest.main()
