#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "docs" / "build_guides.py"

spec = importlib.util.spec_from_file_location("build_guides", MODULE_PATH)
assert spec and spec.loader
build_guides = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = build_guides
spec.loader.exec_module(build_guides)


class BuildGuidesTest(unittest.TestCase):
    def test_story_stats_match_current_assets(self) -> None:
        stories = build_guides.load_stories_by_era()
        self.assertEqual(sum(len(events) for events in stories.values()), 310)
        self.assertEqual(len(stories["era_divided_kingdom"]), 52)
        self.assertEqual(len(stories["era_nt_consummation"]), 9)

    def test_story_guide_mentions_current_totals_and_hidden_era(self) -> None:
        text = build_guides.build_story_guide_text()
        self.assertIn("**총 사건 수**: 310개", text)
        self.assertIn("**시대 수**: 11개", text)
        self.assertIn("`era_nt_consummation` 9개 사건", text)

    def test_markdown_renderer_rewrites_guide_links_to_html(self) -> None:
        source = (ROOT / "docs" / "guides" / "README.md").resolve()
        guide_map = {
            source: "readme.html",
            (
                ROOT / "docs" / "guides" / "CONTENT_UPDATE.md"
            ).resolve(): "content-update.html",
        }
        renderer = build_guides.MarkdownRenderer(source, guide_map)
        rendered = renderer.render("[콘텐츠](CONTENT_UPDATE.md#section)")
        self.assertIn('href="content-update.html#section"', rendered)


if __name__ == "__main__":
    unittest.main()
