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
    filter_story_files_to_indexed_dirs,
    find_missing_story_sources,
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

    def test_filter_story_files_to_indexed_dirs_skips_deleted_story_sources(
        self,
    ) -> None:
        source_root = Path("/tmp/story_images")
        active = source_root / "살아있는 이야기" / "scene_1.png"
        deleted = source_root / "삭제된 이야기" / "scene_1.png"

        indexed, orphaned = filter_story_files_to_indexed_dirs(
            [active, deleted],
            source_root,
            {"살아있는 이야기": "primeval_001"},
        )

        self.assertEqual(indexed, [active])
        self.assertEqual(orphaned, [deleted])

    def test_find_missing_story_sources_reports_current_story_without_png(
        self,
    ) -> None:
        event = {
            "era": "era_primeval",
            "story_index": 1,
            "title": "가인과 아벨: 들판의 비극",
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stories_dir = root / "stories"
            source_dir = root / "story_images"
            stories_dir.mkdir()
            source_dir.mkdir()
            (stories_dir / "era_primeval.json").write_text(
                json.dumps([event], ensure_ascii=False),
                encoding="utf-8",
            )

            _, payload = load_story_thumb_index(stories_dir)

            missing = find_missing_story_sources(source_dir, payload)

        self.assertEqual(len(missing), 1)
        self.assertEqual(missing[0]["title"], "가인과 아벨: 들판의 비극")

    def test_find_missing_story_sources_accepts_existing_scene_png(self) -> None:
        event = {
            "era": "era_primeval",
            "story_index": 1,
            "title": "가인과 아벨: 들판의 비극",
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stories_dir = root / "stories"
            source_root = root / "story_images"
            stories_dir.mkdir()
            source_root.mkdir()
            (stories_dir / "era_primeval.json").write_text(
                json.dumps([event], ensure_ascii=False),
                encoding="utf-8",
            )
            story_dir = source_root / "가인과 아벨_ 들판의 비극"
            story_dir.mkdir()
            (story_dir / "scene_01.png").write_bytes(b"png")

            _, payload = load_story_thumb_index(stories_dir)

            missing = find_missing_story_sources(source_root, payload)

        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
