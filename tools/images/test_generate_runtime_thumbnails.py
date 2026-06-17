#!/usr/bin/env python3
"""Tests for runtime thumbnail path mapping."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_runtime_thumbnails import (  # noqa: E402
    load_story_thumb_index,
    relative_story_dest,
    short_story_thumb_dir,
    story_dir_name_for_title,
)


class GenerateRuntimeThumbnailsTest(unittest.TestCase):
    def test_story_dir_name_normalizes_decomposed_korean(self) -> None:
        decomposed = "3차 전도 여행: 밀레도"

        self.assertEqual(
            story_dir_name_for_title(decomposed),
            "3차 전도 여행_ 밀레도",
        )

    def test_short_story_thumb_dir_uses_era_and_story_index(self) -> None:
        event = {"era": "era_nt_apostolic", "story_index": 34}

        self.assertEqual(short_story_thumb_dir(event), "nt_apostolic_034")

    def test_load_story_thumb_index_maps_title_and_source_dir(self) -> None:
        event = {
            "era": "era_nt_apostolic",
            "story_index": 34,
            "title": "3차 전도 여행: 밀레도에서 에베소 장로들과 작별",
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            stories_dir = Path(temp_dir)
            (stories_dir / "era_nt_apostolic.json").write_text(
                json.dumps([event], ensure_ascii=False),
                encoding="utf-8",
            )

            source_to_short, payload = load_story_thumb_index(stories_dir)

        self.assertEqual(
            source_to_short["3차 전도 여행_ 밀레도에서 에베소 장로들과 작별"],
            "nt_apostolic_034",
        )
        self.assertEqual(
            payload["by_title"]["3차 전도 여행: 밀레도에서 에베소 장로들과 작별"],
            "nt_apostolic_034",
        )
        self.assertEqual(
            payload["by_source_dir"]["3차 전도 여행_ 밀레도에서 에베소 장로들과 작별"],
            "nt_apostolic_034",
        )

    def test_relative_story_dest_uses_short_dir_when_mapped(self) -> None:
        source_root = Path("/tmp/story_images")
        dest_root = Path("/tmp/story_images_thumbs")
        src = source_root / "긴 한글 제목" / "scene_01.png"

        self.assertEqual(
            relative_story_dest(
                source_root,
                dest_root,
                src,
                {"긴 한글 제목": "nt_apostolic_034"},
            ),
            dest_root / "nt_apostolic_034" / "scene_01.jpg",
        )


if __name__ == "__main__":
    unittest.main()
