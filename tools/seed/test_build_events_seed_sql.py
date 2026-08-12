#!/usr/bin/env python3
"""Tests for the events SQL seed builder."""

from __future__ import annotations

import unittest

from build_events_seed_sql import (
    BibleRef,
    NormalizedEvent,
    event_publication_status,
    render_delete_stale_events_sql,
    render_events_sql,
)


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

    def test_last_era_and_revelation_refs_are_seeded_as_draft(self) -> None:
        last_era = _event("era_nt_consummation", 1)
        revelation = _event("era_nt_post_apostolic", 2)
        revelation.refs = [
            BibleRef(
                book_abbr="계",
                book_no=66,
                book_name="요한계시록",
                chapter_start=1,
                verse_start=1,
                chapter_end=1,
                verse_end=3,
                display_text="계 1:1-3",
            )
        ]
        visible = _event("era_nt_post_apostolic", 3)

        self.assertEqual(event_publication_status(last_era), "draft")
        self.assertEqual(event_publication_status(revelation), "draft")
        self.assertEqual(event_publication_status(visible), "published")

        sql = "\n".join(render_events_sql([last_era, revelation, visible], 24))
        self.assertEqual(sql.count("'draft'"), 2)
        self.assertEqual(sql.count("'published'"), 1)


if __name__ == "__main__":
    unittest.main()
