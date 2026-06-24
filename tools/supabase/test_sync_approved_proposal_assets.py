#!/usr/bin/env python3
"""Tests for approved proposal asset sync cleanup behavior."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_approved_proposal_assets as sync  # noqa: E402


class SyncApprovedProposalAssetsTest(unittest.TestCase):
    def test_story_dir_names_match_generator_and_legacy_sync_names(self) -> None:
        title = "가인과 아벨: 들판의 비극"

        self.assertEqual(sync.safe_dirname(title), "가인과 아벨_ 들판의 비극")
        self.assertEqual(
            sync.legacy_underscore_dirname(title),
            "가인과_아벨_들판의_비극",
        )

    def test_migrate_legacy_story_dirs_moves_old_underscore_folder(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            story_images = root / "assets" / "story_images"
            story_images.mkdir(parents=True)
            legacy_dir = story_images / "가인과_아벨_들판의_비극"
            legacy_dir.mkdir()
            (legacy_dir / "scene_1.png").write_bytes(b"png")

            with (
                patch.object(sync, "REPO_ROOT", root),
                patch.object(sync, "STORIES_IMG_DIR", story_images),
            ):
                moved = sync.migrate_legacy_story_dirs(
                    [{"title": "가인과 아벨: 들판의 비극"}],
                    dry_run=False,
                )

            self.assertEqual(moved, 1)
            self.assertFalse(legacy_dir.exists())
            self.assertTrue(
                (story_images / "가인과 아벨_ 들판의 비극" / "scene_1.png").exists()
            )

    def test_sync_deletions_removes_soft_deleted_story_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            story_images = root / "assets" / "story_images"
            avatars = root / "assets" / "avatars"
            avatar_thumbs = root / "assets" / "avatars_thumbs"
            story_images.mkdir(parents=True)
            avatars.mkdir(parents=True)
            avatar_thumbs.mkdir(parents=True)

            active_dir = story_images / "Active Story"
            deleted_dir = story_images / "Deleted Story"
            active_dir.mkdir()
            deleted_dir.mkdir()
            (active_dir / "scene_1.png").write_bytes(b"active")
            (deleted_dir / "scene_1.png").write_bytes(b"deleted")
            (avatars / "alive.png").write_bytes(b"alive")
            (avatars / "ghost.png").write_bytes(b"ghost")
            (avatars / "guide.png").write_bytes(b"guide")
            (avatar_thumbs / "alive.png").write_bytes(b"alive")
            (avatar_thumbs / "ghost.png").write_bytes(b"ghost")
            (avatar_thumbs / "guide.png").write_bytes(b"guide")

            cleanup_storage = Mock()
            with (
                patch.object(sync, "REPO_ROOT", root),
                patch.object(sync, "STORIES_IMG_DIR", story_images),
                patch.object(sync, "AVATARS_DIR", avatars),
                patch.object(sync, "AVATARS_THUMBS_DIR", avatar_thumbs),
                patch.object(
                    sync,
                    "fetch_active_events",
                    return_value=[{"title": "Active Story"}],
                ),
                patch.object(
                    sync,
                    "fetch_deleted_events",
                    return_value=[
                        {
                            "title": "Deleted Story",
                            "scene_image_paths": [
                                "proposal-scenes/story/scene_1.png",
                            ],
                        }
                    ],
                ),
                patch.object(
                    sync,
                    "fetch_all_characters",
                    return_value=[{"code": "alive"}],
                ),
                patch.object(sync, "cleanup_storage_paths", cleanup_storage),
            ):
                totals = sync.sync_deletions(
                    session=Mock(),
                    base_url="http://example.test",
                    dry_run=False,
                )

            self.assertEqual(totals["event_dirs"], 1)
            self.assertEqual(totals["avatars"], 1)
            self.assertEqual(totals["thumbs"], 1)
            self.assertTrue(active_dir.exists())
            self.assertFalse(deleted_dir.exists())
            self.assertTrue((avatars / "alive.png").exists())
            self.assertFalse((avatars / "ghost.png").exists())
            self.assertTrue((avatars / "guide.png").exists())
            self.assertTrue((avatar_thumbs / "alive.png").exists())
            self.assertFalse((avatar_thumbs / "ghost.png").exists())
            self.assertTrue((avatar_thumbs / "guide.png").exists())
            cleanup_storage.assert_called_once()
            self.assertEqual(
                cleanup_storage.call_args.args[2],
                ["proposal-scenes/story/scene_1.png"],
            )


if __name__ == "__main__":
    unittest.main()
