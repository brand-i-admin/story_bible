-- Non-destructive patch for per-scene captions.
-- Apply before 200_stories_seed_part_*.sql so events_ordered exposes
-- scene_captions to Flutter clients.

alter table events
  add column if not exists background_context text,
  add column if not exists scene_captions jsonb not null default '[]'::jsonb;

drop view if exists events_ordered cascade;

create view events_ordered as
  select
    e.id, e.era_id, e.title, e.summary, e.background_context,
    e.story_scenes, e.scene_captions, e.scene_characters, e.character_codes,
    e.bible_refs, e.start_year, e.end_year, e.time_precision,
    e.story_index, e.unit_code, e.unit_title, e.unit_order,
    e.scene_image_paths, e.status, e.deleted_at,
    e.created_at, e.landmark_id,
    lm.lat as lat,
    lm.lng as lng,
    lm.name as place_name,
    lm.kind as landmark_kind,
    lm.parent_landmark_id as landmark_parent_id,
    lm.alias_group_id as landmark_alias_group_id,
    row_number() over (partition by e.era_id order by e.story_index) as rank_in_era,
    row_number() over (order by er.display_order, e.story_index) as global_rank
  from events e
  join eras er on er.id = e.era_id
  join landmarks lm on lm.id = e.landmark_id
  where e.status = 'published'
    and e.deleted_at is null;

grant select on events_ordered to anon, authenticated;
