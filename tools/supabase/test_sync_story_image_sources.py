#!/usr/bin/env python3
"""Unit tests for sync_story_image_sources.py.

Run:
    python3 tools/supabase/test_sync_story_image_sources.py -v
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_story_image_sources as mod  # noqa: E402


class SyncStoryImageSourcesTest(unittest.TestCase):
    def test_collect_local_entries_uses_current_story_index_and_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            stories_dir = root / "stories"
            source_root = root / "story_images"
            stories_dir.mkdir()
            source_root.mkdir()
            (stories_dir / "era_primeval.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "가인과 아벨: 들판의 비극",
                            "era": "era_primeval",
                            "story_index": 2,
                        }
                    ],
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            story_dir = source_root / "가인과 아벨_ 들판의 비극"
            story_dir.mkdir()
            (story_dir / "scene_01.png").write_bytes(b"image")

            items = mod.load_story_items(stories_dir)
            entries = mod.collect_local_entries(
                story_items=items,
                source_root=source_root,
                object_prefix="story_images",
            )

        self.assertEqual(len(entries), 1)
        self.assertEqual(
            entries[0].object_path,
            "story_images/d2d59abfd625db91/scene_01.png",
        )
        self.assertEqual(entries[0].size, 5)
        self.assertEqual(
            entries[0].sha256,
            "6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d",
        )

    def test_plan_push_uploads_missing_or_changed_remote_entries(self) -> None:
        local = mod.SourceEntry(
            object_path="story_images/a/scene_01.png",
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="new",
            local_path="assets/story_images/a/scene_01.png",
        )
        same = mod.SourceEntry(
            object_path="story_images/b/scene_01.png",
            source_dir="b",
            filename="scene_01.png",
            title="B",
            era="era_primeval",
            story_index=2,
            size=10,
            sha256="same",
            local_path="assets/story_images/b/scene_01.png",
        )
        remote_same = mod.SourceEntry(
            object_path=same.object_path,
            source_dir="b",
            filename="scene_01.png",
            title="B",
            era="era_primeval",
            story_index=2,
            size=10,
            sha256="same",
        )
        remote_changed = mod.SourceEntry(
            object_path=local.object_path,
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=9,
            sha256="old",
        )

        plan = mod.plan_push(
            local_entries=[local, same],
            remote_entries={
                remote_same.object_path: remote_same,
                remote_changed.object_path: remote_changed,
            },
        )

        self.assertEqual(plan.upload, [local])
        self.assertEqual(plan.skip, [same])

    def test_plan_pull_downloads_remote_when_local_missing(self) -> None:
        item = mod.StoryItem(
            title="A",
            era="era_primeval",
            story_index=1,
            source_dir="a",
        )
        remote = mod.SourceEntry(
            object_path="story_images/a/scene_01.png",
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="abc",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            plan = mod.plan_pull(
                story_items=[item],
                local_entries={},
                remote_entries={remote.object_path: remote},
                source_root=Path(temp_dir),
            )

        self.assertEqual(plan.download, [remote])
        self.assertEqual(plan.missing_remote, [])

    def test_plan_pull_reports_missing_when_no_local_or_remote_source(self) -> None:
        item = mod.StoryItem(
            title="A",
            era="era_primeval",
            story_index=1,
            source_dir="a",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            plan = mod.plan_pull(
                story_items=[item],
                local_entries={},
                remote_entries={},
                source_root=Path(temp_dir),
            )

        self.assertEqual(plan.download, [])
        self.assertEqual(plan.missing_remote, [item])

    def test_entries_from_manifest_round_trips_manifest_entries(self) -> None:
        entry = mod.SourceEntry(
            object_path="story_images/a/scene_01.png",
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="abc",
            local_path="assets/story_images/a/scene_01.png",
        )

        manifest = mod.build_manifest(
            entries=[entry],
            bucket="story-image-sources",
            object_prefix="story_images",
        )
        parsed = mod.entries_from_manifest(manifest)

        self.assertEqual(parsed[entry.object_path].sha256, "abc")
        self.assertIsNone(parsed[entry.object_path].local_path)


if __name__ == "__main__":
    unittest.main()
