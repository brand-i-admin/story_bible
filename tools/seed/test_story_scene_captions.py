#!/usr/bin/env python3
"""Tests for user-facing scene captions in story source JSON."""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STORY_DIR = ROOT / "assets" / "200_stories"
MAX_CAPTION_CHARS = 58

FORBIDDEN_CAPTION_MARKERS = (
    "글자 없는",
    "글자 없는 말풍선",
    "말풍선",
    "작은 그림처럼",
    "보이지 않는다",
    "글자는",
    "글자가",
    "읽을 수 있는",
    "직접적인",
    "잔혹한",
    "선정적",
    "노골적",
    "위 칸",
    "가운데 칸",
    "아래 칸",
)

OPEN_ENDING_RE = re.compile(r"(고|며|하고|되고|지고|오고|가고|하시|하였고|지만)$")
AWKWARD_ENDING_RE = re.compile(r"(으다|가다|오다|우다|기다|하는)$")


def _load_story_file(path: Path) -> list[dict[str, object]]:
    return json.loads(path.read_text(encoding="utf-8"))


class StorySceneCaptionTests(unittest.TestCase):
    def test_every_story_scene_has_matching_editable_caption(self) -> None:
        for path in STORY_DIR.glob("era_*.json"):
            events = _load_story_file(path)
            for event in events:
                title = str(event.get("title", ""))
                with self.subTest(filename=path.name, title=title):
                    scenes = event.get("story_scenes")
                    captions = event.get("scene_captions")

                    self.assertIsInstance(scenes, list)
                    self.assertIsInstance(captions, list)
                    self.assertEqual(len(captions), len(scenes))

                    for caption in captions:
                        self.assertIsInstance(caption, str)
                        self.assertTrue(caption.strip())
                        self.assertLessEqual(len(caption), MAX_CAPTION_CHARS)
                        self.assertTrue(caption.endswith("다"))

    def test_scene_captions_do_not_expose_prompt_artifacts(self) -> None:
        for path in STORY_DIR.glob("era_*.json"):
            events = _load_story_file(path)
            for event in events:
                title = str(event.get("title", ""))
                captions = event.get("scene_captions") or []
                for index, caption in enumerate(captions):
                    with self.subTest(filename=path.name, title=title, index=index):
                        for marker in FORBIDDEN_CAPTION_MARKERS:
                            self.assertNotIn(marker, caption)

    def test_scene_captions_end_as_complete_phrases(self) -> None:
        for path in STORY_DIR.glob("era_*.json"):
            events = _load_story_file(path)
            for event in events:
                title = str(event.get("title", ""))
                captions = event.get("scene_captions") or []
                for index, caption in enumerate(captions):
                    with self.subTest(filename=path.name, title=title, index=index):
                        self.assertIsNone(OPEN_ENDING_RE.search(caption))
                        self.assertIsNone(AWKWARD_ENDING_RE.search(caption))


if __name__ == "__main__":
    unittest.main()
