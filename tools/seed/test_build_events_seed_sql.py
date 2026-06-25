#!/usr/bin/env python3
"""Tests for the events SQL seed builder."""

from __future__ import annotations

import unittest

from build_events_seed_sql import NormalizedEvent, render_delete_stale_events_sql


def _event(era_code: str, story_index: int) -> NormalizedEvent:
    return NormalizedEvent(
        number=story_index,
        era_code=era_code,
        title=f"Story {story_index}",
        summary="summary",
        background_context="background",
        story_scenes=[],
        scene_captions=[],
        scene_characters=[],
        start_year=None,
        end_year=None,
        time_precision="approx",
        story_index=story_index,
        unit_code="default",
        unit_title="전체 흐름",
        unit_order=1,
        landmark_code="lm_test",
        characters=[],
        refs=[],
    )


class BuildEventsSeedSqlTests(unittest.TestCase):
    def test_stale_delete_preserves_soft_deleted_events(self) -> None:
        sql = "\n".join(render_delete_stale_events_sql([_event("era_primeval", 1)]))

        self.assertIn("delete from events e", sql)
        self.assertIn("and e.deleted_at is null", sql)


if __name__ == "__main__":
    unittest.main()
