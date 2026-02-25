create extension if not exists pgcrypto;
create extension if not exists vector;

-- Single source of truth for local bootstrap before first production release.
-- Run this file directly to recreate schema + seed data end-to-end.
-- Supabase migration files may lag behind while this mode is enabled.

-- Re-initialize safely when rerunning this script locally or via CI.
-- We keep this as "drop then recreate" for predictable bootstrap.
drop table if exists search_embeddings cascade;
drop table if exists user_event_progress cascade;
drop table if exists quiz_questions cascade;
drop table if exists event_bible_refs cascade;
drop table if exists bible_verses cascade;
drop table if exists event_persons cascade;
drop table if exists person_eras cascade;
drop table if exists events cascade;
drop table if exists persons cascade;
drop table if exists eras cascade;

create table if not exists eras (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  display_order int not null,
  start_year int,
  end_year int,
  theme_color text,
  map_center_lat double precision,
  map_center_lng double precision,
  map_zoom numeric(4,2),
  created_at timestamptz not null default now()
);

create table if not exists persons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tagline text,
  avatar_url text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists person_eras (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references persons(id) on delete cascade,
  era_id uuid not null references eras(id) on delete cascade,
  display_order int not null default 0,
  unique (person_id, era_id)
);

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  era_id uuid not null references eras(id),
  title text not null,
  summary text,
  story text,
  short_story text,
  story_scenes text,
  start_year int,
  end_year int,
  time_sort_key bigint not null,
  time_precision text not null default 'approx',
  place_name text,
  lat double precision,
  lng double precision,
  video_url text,
  thumb_url text,
  created_at timestamptz not null default now()
);

create table if not exists event_persons (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  person_id uuid not null references persons(id) on delete cascade,
  role text,
  person_sequence int,
  unique (event_id, person_id)
);

create table if not exists event_bible_refs (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  book text not null,
  chapter_start int not null,
  verse_start int not null,
  chapter_end int,
  verse_end int,
  display_text text not null
);

create table if not exists bible_verses (
  translation text not null default 'KRV',
  testament text not null check (testament in ('old', 'new')),
  book_no smallint not null check (book_no between 1 and 66),
  book_name text not null,
  chapter_no smallint not null check (chapter_no > 0),
  verse_no smallint not null check (verse_no > 0),
  verse_text text not null,
  primary key (translation, book_no, chapter_no, verse_no)
);

create table if not exists quiz_questions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  question text not null,
  choice_a text not null,
  choice_b text not null,
  choice_c text not null,
  choice_d text,
  answer_index int not null check (answer_index between 0 and 3),
  explanation text,
  display_order int not null default 0
);

create table if not exists user_event_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event_id uuid not null references events(id) on delete cascade,
  is_completed boolean not null default false,
  score int not null default 0,
  xp_earned int not null default 0,
  completed_at timestamptz,
  unique (user_id, event_id)
);

create table if not exists search_embeddings (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('event', 'person')),
  entity_id uuid not null,
  chunk_text text not null,
  embedding vector(1536) not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_events_era_time on events (era_id, time_sort_key);
create index if not exists idx_event_persons_person_seq on event_persons (person_id, person_sequence);
create index if not exists idx_event_persons_person_event on event_persons (person_id, event_id);
create index if not exists idx_progress_user_completed on user_event_progress (user_id, is_completed);
create unique index if not exists uidx_quiz_event_order on quiz_questions (event_id, display_order);
create index if not exists idx_embed_ivfflat on search_embeddings using ivfflat (embedding vector_cosine_ops);
create unique index if not exists idx_event_bible_refs_unique on event_bible_refs (event_id, display_text);
create index if not exists idx_bible_verses_lookup on bible_verses (translation, book_no, chapter_no, verse_no);
create index if not exists idx_bible_verses_book_name on bible_verses (translation, book_name, chapter_no, verse_no);

-- -----------------------------------------------------------------------------
-- Public read access + RLS policies
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select on table eras to anon, authenticated;
grant select on table persons to anon, authenticated;
grant select on table person_eras to anon, authenticated;
grant select on table events to anon, authenticated;
grant select on table event_persons to anon, authenticated;
grant select on table event_bible_refs to anon, authenticated;
grant select on table bible_verses to anon, authenticated;
grant select on table quiz_questions to anon, authenticated;

grant select, insert, update on table user_event_progress to authenticated;

alter table eras enable row level security;
alter table persons enable row level security;
alter table person_eras enable row level security;
alter table events enable row level security;
alter table event_persons enable row level security;
alter table event_bible_refs enable row level security;
alter table bible_verses enable row level security;
alter table quiz_questions enable row level security;
alter table user_event_progress enable row level security;

drop policy if exists eras_read_all on eras;
create policy eras_read_all on eras for select using (true);

drop policy if exists persons_read_all on persons;
create policy persons_read_all on persons for select using (true);

drop policy if exists person_eras_read_all on person_eras;
create policy person_eras_read_all on person_eras for select using (true);

drop policy if exists events_read_all on events;
create policy events_read_all on events for select using (true);

drop policy if exists event_persons_read_all on event_persons;
create policy event_persons_read_all on event_persons for select using (true);

drop policy if exists event_bible_refs_read_all on event_bible_refs;
create policy event_bible_refs_read_all on event_bible_refs for select using (true);

drop policy if exists bible_verses_read_all on bible_verses;
create policy bible_verses_read_all on bible_verses for select using (true);

drop policy if exists quiz_questions_read_all on quiz_questions;
create policy quiz_questions_read_all on quiz_questions for select using (true);

drop policy if exists user_event_progress_read_own on user_event_progress;
create policy user_event_progress_read_own on user_event_progress
for select using (auth.uid() = user_id);

drop policy if exists user_event_progress_write_own on user_event_progress;
create policy user_event_progress_write_own on user_event_progress
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- Seed: eras
-- -----------------------------------------------------------------------------
insert into eras (
  code,
  name,
  display_order,
  start_year,
  end_year,
  theme_color,
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_primeval', '원역사', 1, -4000, -2000, '#6E4A2B', 33.00, 44.00, 4.80),
  ('era_patriarch', '족장 시대', 2, -2166, -1805, '#8B5A2B', 31.50, 35.20, 5.40),
  ('era_exodus', '출애굽 시대', 3, -1446, -1406, '#A66A2C', 29.50, 34.50, 5.20),
  ('era_judges', '사사 시대', 4, -1406, -1050, '#7A5C3A', 31.80, 35.10, 5.40),
  ('era_monarchy', '왕정 시대', 5, -1050, -586, '#73533D', 31.90, 35.20, 5.30),
  ('era_exile_return', '포로 및 포로 후기 시대', 6, -586, -430, '#5D4B3F', 32.20, 38.30, 4.70)
;

-- -----------------------------------------------------------------------------
-- Seed data for persons/person_eras/events/event_persons/event_bible_refs/quiz_questions
-- is intentionally omitted here.
-- Use generated SQL files under supabase/200_stories instead.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Seed: New Testament (구약/신약 분리 + 예수/바울)
-- -----------------------------------------------------------------------------
alter table eras
  add column if not exists testament text not null default 'old';

update eras
set testament = 'old'
where coalesce(testament, '') <> 'new';

insert into eras (
  code,
  testament,
  name,
  display_order,
  start_year,
  end_year,
  theme_color,
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_nt_public_ministry', 'new', '예수님의 공생애', 1, 27, 33, '#9F642A', 31.78, 35.22, 6.10),
  ('era_nt_apostolic', 'new', '사도의 시대', 2, 33, 70, '#7D5A3A', 37.40, 26.90, 4.90),
  ('era_nt_post_apostolic', 'new', '후기 사도의 시대', 3, 70, 100, '#6C5646', 37.45, 27.20, 5.20),
  ('era_nt_consummation', 'new', '역사의 종결', 4, null, null, '#8B6B4A', 31.78, 35.22, 4.40)
on conflict (code) do update
set
  testament = excluded.testament,
  name = excluded.name,
  display_order = excluded.display_order,
  start_year = excluded.start_year,
  end_year = excluded.end_year,
  theme_color = excluded.theme_color,
  map_center_lat = excluded.map_center_lat,
  map_center_lng = excluded.map_center_lng,
  map_zoom = excluded.map_zoom
;
