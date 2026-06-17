"""Unit tests for tools/app/verify_asset_paths.py."""

from __future__ import annotations

import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verify_asset_paths as mod  # noqa: E402


class VerifyAssetPathsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._old_root = mod.REPO_ROOT
        self._old_pubspec = mod.PUBSPEC
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        mod.REPO_ROOT = self.root
        mod.PUBSPEC = self.root / "pubspec.yaml"

    def tearDown(self) -> None:
        mod.REPO_ROOT = self._old_root
        mod.PUBSPEC = self._old_pubspec
        self.tmp.cleanup()

    def write_pubspec(self, body: str) -> None:
        mod.PUBSPEC.write_text(body, encoding="utf-8")

    def test_parse_assets_reads_flutter_assets_block(self) -> None:
        self.write_pubspec(
            """
name: sample
flutter:
  uses-material-design: true
  assets:
    - .env
    - assets/images/
"""
        )

        self.assertEqual(mod.parse_assets(), [".env", "assets/images/"])

    def test_main_fails_when_assets_block_is_missing(self) -> None:
        self.write_pubspec("name: sample\nflutter:\n  uses-material-design: true\n")

        with redirect_stdout(StringIO()):
            self.assertEqual(mod.main(), 1)

    def test_verify_accepts_existing_non_empty_directory(self) -> None:
        image_dir = self.root / "assets" / "images"
        image_dir.mkdir(parents=True)
        (image_dir / "probe.png").write_bytes(b"png")

        self.assertEqual(mod.verify("assets/images/"), (True, "ok"))

    def test_verify_rejects_empty_directory(self) -> None:
        image_dir = self.root / "assets" / "images"
        image_dir.mkdir(parents=True)

        ok, reason = mod.verify("assets/images/")

        self.assertFalse(ok)
        self.assertEqual(reason, "디렉토리가 비어있음")

    def test_verify_rejects_url_encoded_component_that_is_too_long(self) -> None:
        long_korean_name = "3차 전도 여행: 밀레도에서 에베소 장로들과 작별" * 4

        ok, reason = mod.verify(f"assets/story_images_thumbs/{long_korean_name}/")

        self.assertFalse(ok)
        self.assertIn("URL 인코딩 후 파일명 너무 김", reason)


if __name__ == "__main__":
    unittest.main()
