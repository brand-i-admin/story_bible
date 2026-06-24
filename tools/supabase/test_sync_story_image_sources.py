#!/usr/bin/env python3
"""Unit tests for sync_story_image_sources.py.

Run:
    python3 tools/supabase/test_sync_story_image_sources.py -v
"""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
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
        self.assertEqual(plan.delete_stale, [])

    def test_plan_push_deletes_remote_entries_missing_from_active_manifest(
        self,
    ) -> None:
        local = mod.SourceEntry(
            object_path="story_images/a/scene_01.png",
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="same",
            local_path="assets/story_images/a/scene_01.png",
        )
        remote_same = mod.SourceEntry(
            object_path=local.object_path,
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="same",
        )
        remote_stale = mod.SourceEntry(
            object_path="story_images/deleted/scene_01.png",
            source_dir="deleted",
            filename="scene_01.png",
            title="Deleted",
            era="era_primeval",
            story_index=2,
            size=10,
            sha256="old",
        )

        plan = mod.plan_push(
            local_entries=[local],
            remote_entries={
                remote_same.object_path: remote_same,
                remote_stale.object_path: remote_stale,
            },
        )

        self.assertEqual(plan.upload, [])
        self.assertEqual(plan.skip, [local])
        self.assertEqual(plan.delete_stale, [remote_stale])

    def test_command_push_deletes_stale_before_uploading_manifest(self) -> None:
        item = mod.StoryItem(
            title="A",
            era="era_primeval",
            story_index=1,
            source_dir="a",
        )
        local = mod.SourceEntry(
            object_path="story_images/a/scene_01.png",
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="same",
            local_path="/tmp/not-read-for-skip.png",
        )
        remote_same = mod.SourceEntry(
            object_path=local.object_path,
            source_dir="a",
            filename="scene_01.png",
            title="A",
            era="era_primeval",
            story_index=1,
            size=10,
            sha256="same",
        )
        remote_stale = mod.SourceEntry(
            object_path="story_images/deleted/scene_01.png",
            source_dir="deleted",
            filename="scene_01.png",
            title="Deleted",
            era="era_primeval",
            story_index=2,
            size=10,
            sha256="old",
        )
        remote_payload = mod.build_manifest(
            entries=[remote_same, remote_stale],
            bucket="story-image-sources",
            object_prefix="story_images",
        )
        calls: list[tuple[str, str]] = []

        originals = {
            "load_story_items": mod.load_story_items,
            "collect_local_entries": mod.collect_local_entries,
            "has_any_local_scene": mod.has_any_local_scene,
            "make_session": mod.make_session,
            "ensure_bucket": mod.ensure_bucket,
            "load_remote_manifest": mod.load_remote_manifest,
            "delete_object": mod.delete_object,
            "upload_object": mod.upload_object,
        }
        try:
            mod.load_story_items = lambda stories_dir: [item]
            mod.collect_local_entries = lambda **kwargs: [local]
            mod.has_any_local_scene = lambda source_root, source_dir: True
            mod.make_session = lambda args: object()
            mod.ensure_bucket = lambda **kwargs: None
            mod.load_remote_manifest = lambda **kwargs: remote_payload
            mod.delete_object = lambda **kwargs: calls.append(
                ("delete", kwargs["object_path"])
            )
            mod.upload_object = lambda **kwargs: calls.append(
                ("upload", kwargs["object_path"])
            )

            with contextlib.redirect_stdout(io.StringIO()):
                result = mod.command_push(
                    SimpleNamespace(
                        stories_dir=Path("/unused/stories"),
                        source_dir=Path("/unused/story_images"),
                        object_prefix="story_images",
                        bucket="story-image-sources",
                        dry_run=False,
                        base_url="https://example.supabase.co",
                        manifest_path="_manifests/story_images_manifest.json",
                        timeout_sec=30,
                        retry_attempts=1,
                        retry_wait_sec=0,
                    )
                )
        finally:
            for name, value in originals.items():
                setattr(mod, name, value)

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [
                ("delete", remote_stale.object_path),
                ("upload", "_manifests/story_images_manifest.json"),
            ],
        )

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
