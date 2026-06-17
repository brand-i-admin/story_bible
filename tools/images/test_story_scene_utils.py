#!/usr/bin/env python3
"""Tests for shared story scene image helpers."""

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from story_scene_utils import (  # noqa: E402
    build_prompt_file_header,
    build_prompt_file_line,
    format_bible_refs_for_prompt,
    join_names_for_subject,
    parse_person_name_map_from_seed_sql,
    requests_speech_bubble,
    sanitize_scene_text_for_visual,
)
from generate_event_story_images_vertex import scene_age_art_direction_for  # noqa: E402


class StorySceneUtilsTest(unittest.TestCase):
    def test_parse_person_name_map_reads_all_seed_person_chunks(self) -> None:
        sql = """
delete from characters where code not in ('dan', 'lot_wife');

with seed_persons (code, name) as (
  values
    ('paul', '바울')
)
insert into characters (code, name)
select code, name from seed_persons;

with seed_persons (code, name) as (
  values
    ('john_mark', '마가 요한'),
    ('reuben', '르우벤')
)
insert into characters (code, name)
select code, name from seed_persons;
"""
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "characters_seed.sql"
            path.write_text(sql, encoding="utf-8")

            names = parse_person_name_map_from_seed_sql(path)

        self.assertEqual(names["paul"], "바울")
        self.assertEqual(names["john_mark"], "마가 요한")
        self.assertEqual(names["reuben"], "르우벤")
        self.assertNotIn("dan", names)

    def test_join_names_for_subject_uses_korean_josa_for_three_names(self) -> None:
        subject = join_names_for_subject(
            ["paul", "barnabas", "john_mark"],
            {
                "paul": "바울",
                "barnabas": "바나바",
                "john_mark": "마가 요한",
            },
        )

        self.assertEqual(subject, "바울과 바나바와 마가 요한이")

    def test_format_bible_refs_for_prompt_preserves_all_ranges(self) -> None:
        event = {
            "bible_ref": [
                {"book": "눅", "from": "1:5", "to": "1:80"},
                {"book": "마", "from": "1:18", "to": "1:25"},
                {"book": "눅", "from": "2:1", "to": "2:20"},
            ]
        }

        self.assertEqual(
            format_bible_refs_for_prompt(event),
            "눅 1:5-1:80, 마 1:18-1:25, 눅 2:1-2:20",
        )

    def test_format_bible_refs_for_prompt_accepts_seed_key(self) -> None:
        event = {"bible_refs": [{"book": "계", "from": "22:6", "to": "22:21"}]}

        self.assertEqual(format_bible_refs_for_prompt(event), "계 22:6-22:21")

    def test_build_prompt_file_header_includes_bible_refs(self) -> None:
        line = build_prompt_file_header(bible_ref_text="계 22:6-22:21")

        self.assertEqual(line, "성경: 계 22:6-22:21")

    def test_build_prompt_file_line_uses_scene_only(self) -> None:
        line = build_prompt_file_line(
            file_name="scene_01.png",
            scene_prompt="요한이 두루마리를 품고 선다",
        )

        self.assertEqual(
            line,
            "scene_01.png: 요한이 두루마리를 품고 선다",
        )

    def test_sanitize_scene_text_preserves_speech_bubble_text(self) -> None:
        text = (
            "예수님은 손을 들어 말씀하시며 말풍선 안에 "
            "'나는 하나님의 일을 이루러 왔다'라는 짧은 글이 보인다"
        )

        cleaned = sanitize_scene_text_for_visual(
            text,
            scene_person_codes=["jesus"],
            code_to_name={"jesus": "예수님"},
        )

        self.assertIn("말풍선", cleaned)
        self.assertIn("나는 하나님의 일을 이루러 왔다", cleaned)

    def test_requests_speech_bubble_ignores_negative_instruction(self) -> None:
        self.assertFalse(requests_speech_bubble("글자와 말풍선은 보이지 않는다"))
        self.assertTrue(
            requests_speech_bubble(
                "말풍선 안에 '내 백성을 보내라'라는 짧은 글이 보인다"
            )
        )
        self.assertTrue(
            requests_speech_bubble(
                "글자 없는 말풍선 안에는 열린 길과 돌이키는 사람들이 작은 그림처럼 보인다"
            )
        )

    def test_david_before_enthronement_is_not_royal(self) -> None:
        note = scene_age_art_direction_for(
            {
                "era": "era_monarchy",
                "story_index": 5,
                "title": "다윗과 골리앗: 돌 하나",
            },
            scene_text="18세쯤의 젊은 다윗이 시냇가에서 돌을 고른다",
            scene_person_codes=["david"],
        )

        self.assertIn("Before David's enthronement", note)
        self.assertIn("do not dress him as king yet", note)

    def test_david_after_enthronement_is_royal(self) -> None:
        note = scene_age_art_direction_for(
            {
                "era": "era_monarchy",
                "story_index": 13,
                "title": "다윗 즉위: 한 왕국으로",
            },
            scene_text="장로들이 다윗 앞에 모여 언약을 맺는다",
            scene_person_codes=["david"],
        )

        self.assertIn("From David's enthronement", note)
        self.assertIn("royal blue kingly garments", note)

    def test_solomon_after_enthronement_is_royal(self) -> None:
        note = scene_age_art_direction_for(
            {
                "era": "era_monarchy",
                "story_index": 23,
                "title": "솔로몬 즉위: 왕의 노새",
            },
            scene_text="젊은 솔로몬이 다윗 왕의 노새를 타고 왕으로 세워진다",
            scene_person_codes=["solomon"],
        )

        self.assertIn("From Solomon's enthronement", note)
        self.assertIn("royal sky-blue kingly garments", note)

    def test_solomon_title_does_not_apply_to_scene_without_solomon(self) -> None:
        note = scene_age_art_direction_for(
            {
                "era": "era_monarchy",
                "story_index": 23,
                "title": "솔로몬 즉위: 왕의 노새",
            },
            scene_text="늙은 다윗 왕의 침상 곁에 밧세바가 다가온다",
            scene_person_codes=["david", "bathsheba"],
        )

        self.assertNotIn("From Solomon's enthronement", note)

    def test_solomon_before_enthronement_is_not_reigning_king(self) -> None:
        note = scene_age_art_direction_for(
            {
                "era": "era_monarchy",
                "story_index": 22,
                "title": "인구조사와 제단: 다윗의 선택",
            },
            scene_text="어린 솔로몬이 다윗 곁에 서 있다",
            scene_person_codes=["solomon"],
        )

        self.assertIn("Before Solomon's enthronement", note)
        self.assertIn("not yet dressed as the reigning king", note)


if __name__ == "__main__":
    unittest.main()
