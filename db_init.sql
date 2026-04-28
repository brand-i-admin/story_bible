create extension if not exists pgcrypto;
create extension if not exists vector;

-- Single source of truth for local bootstrap before first production release.
-- Run this file directly to recreate schema + seed data end-to-end.
-- Supabase migration files may lag behind while this mode is enabled.

-- Re-initialize safely when rerunning this script locally or via CI.
-- We keep this as "drop then recreate" for predictable bootstrap.
drop table if exists search_embeddings cascade;
drop table if exists user_daily_study cascade;
drop table if exists user_daily_attendance cascade;
drop table if exists user_intercessory_prayers cascade;
drop table if exists user_saved_verses cascade;
drop table if exists user_notes cascade;
drop table if exists user_profiles cascade;
drop table if exists user_event_progress cascade;
drop table if exists quiz_questions cascade;
drop table if exists event_bible_refs cascade;
drop table if exists bible_verses cascade;
drop table if exists event_persons cascade;
drop table if exists person_eras cascade;
drop table if exists events cascade;
drop table if exists persons cascade;
drop table if exists eras cascade;
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user_profile();
drop function if exists public.generate_profile_share_id();
drop function if exists public.list_intercessory_prayer_requests(integer, integer);
drop function if exists public.add_intercessory_prayer_by_share_id(text);
drop function if exists public.touch_updated_at();

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

create table if not exists user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  share_id text unique,
  nickname text not null,
  photo_url text,
  prayer_request text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.generate_profile_share_id()
returns text
language plpgsql
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := '';
    for i in 1..7 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;

    if not exists (
      select 1
      from public.user_profiles
      where share_id = candidate
    ) then
      return candidate;
    end if;
  end loop;
end;
$$;

alter table user_profiles
  alter column share_id set default public.generate_profile_share_id();

update public.user_profiles
set share_id = public.generate_profile_share_id()
where share_id is null;

alter table user_profiles
  alter column share_id set not null;

create table if not exists user_intercessory_prayers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint user_intercessory_prayers_not_self check (user_id <> target_user_id),
  unique (user_id, target_user_id)
);

create table if not exists user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists user_saved_verses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  translation text not null default 'KRV',
  book_no smallint not null check (book_no between 1 and 66),
  book_name text not null,
  chapter_no smallint not null check (chapter_no > 0),
  verse_no smallint not null check (verse_no > 0),
  verse_text text not null,
  created_at timestamptz not null default now(),
  unique (user_id, translation, book_no, chapter_no, verse_no)
);

create table if not exists user_daily_attendance (
  user_id uuid not null references auth.users(id) on delete cascade,
  attended_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, attended_on)
);

create table if not exists user_daily_study (
  user_id uuid not null references auth.users(id) on delete cascade,
  studied_on date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, studied_on)
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
create index if not exists idx_user_notes_user_created on user_notes (user_id, created_at desc);
create index if not exists idx_user_saved_verses_user_created on user_saved_verses (user_id, created_at desc);
create index if not exists idx_user_intercessory_prayers_user_created on user_intercessory_prayers (user_id, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_user_profiles_updated_at on user_profiles;
create trigger set_user_profiles_updated_at
before update on user_profiles
for each row execute function public.touch_updated_at();

drop trigger if exists set_user_notes_updated_at on user_notes;
create trigger set_user_notes_updated_at
before update on user_notes
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  derived_nickname text;
begin
  derived_nickname := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(trim(split_part(new.email, '@', 1)), ''),
    '사용자'
  );

  insert into public.user_profiles (user_id, nickname)
  values (new.id, derived_nickname)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user_profile();

create or replace function public.list_intercessory_prayer_requests(
  p_limit integer default 13,
  p_offset integer default 0
)
returns table (
  id uuid,
  target_user_id uuid,
  share_id text,
  nickname text,
  photo_url text,
  prayer_request text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    links.id,
    profiles.user_id as target_user_id,
    profiles.share_id,
    profiles.nickname,
    profiles.photo_url,
    profiles.prayer_request,
    links.created_at
  from public.user_intercessory_prayers links
  join public.user_profiles profiles
    on profiles.user_id = links.target_user_id
  where auth.uid() is not null
    and links.user_id = auth.uid()
  order by links.created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

create or replace function public.add_intercessory_prayer_by_share_id(
  p_share_id text
)
returns table (
  id uuid,
  target_user_id uuid,
  share_id text,
  nickname text,
  photo_url text,
  prayer_request text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_share_id text := upper(trim(coalesce(p_share_id, '')));
  target_profile public.user_profiles%rowtype;
  link_row public.user_intercessory_prayers%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if normalized_share_id = '' then
    raise exception '공유 ID를 입력해 주세요.';
  end if;

  select *
  into target_profile
  from public.user_profiles
  where share_id = normalized_share_id;

  if not found then
    raise exception '해당 ID를 찾을 수 없습니다.';
  end if;

  if target_profile.user_id = auth.uid() then
    raise exception '내 기도제목은 추가할 수 없습니다.';
  end if;

  insert into public.user_intercessory_prayers (user_id, target_user_id)
  values (auth.uid(), target_profile.user_id)
  on conflict (user_id, target_user_id)
  do nothing
  returning *
  into link_row;

  if link_row.id is null then
    select *
    into link_row
    from public.user_intercessory_prayers
    where user_id = auth.uid()
      and target_user_id = target_profile.user_id;
  end if;

  return query
  select
    link_row.id,
    target_profile.user_id,
    target_profile.share_id,
    target_profile.nickname,
    target_profile.photo_url,
    target_profile.prayer_request,
    link_row.created_at;
end;
$$;

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
grant select, insert, update on table user_profiles to authenticated;
grant select, insert, delete on table user_intercessory_prayers to authenticated;
grant select, insert, update, delete on table user_notes to authenticated;
grant select, insert, delete on table user_saved_verses to authenticated;
grant select, insert on table user_daily_attendance to authenticated;
grant select, insert on table user_daily_study to authenticated;

alter table eras enable row level security;
alter table persons enable row level security;
alter table person_eras enable row level security;
alter table events enable row level security;
alter table event_persons enable row level security;
alter table event_bible_refs enable row level security;
alter table bible_verses enable row level security;
alter table quiz_questions enable row level security;
alter table user_event_progress enable row level security;
alter table user_profiles enable row level security;
alter table user_intercessory_prayers enable row level security;
alter table user_notes enable row level security;
alter table user_saved_verses enable row level security;
alter table user_daily_attendance enable row level security;
alter table user_daily_study enable row level security;

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

drop policy if exists user_profiles_read_own on user_profiles;
create policy user_profiles_read_own on user_profiles
for select using (auth.uid() = user_id);

drop policy if exists user_profiles_insert_own on user_profiles;
create policy user_profiles_insert_own on user_profiles
for insert with check (auth.uid() = user_id);

drop policy if exists user_profiles_update_own on user_profiles;
create policy user_profiles_update_own on user_profiles
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists user_intercessory_prayers_read_own on user_intercessory_prayers;
create policy user_intercessory_prayers_read_own on user_intercessory_prayers
for select using (auth.uid() = user_id);

drop policy if exists user_intercessory_prayers_insert_own on user_intercessory_prayers;
create policy user_intercessory_prayers_insert_own on user_intercessory_prayers
for insert with check (auth.uid() = user_id);

drop policy if exists user_intercessory_prayers_delete_own on user_intercessory_prayers;
create policy user_intercessory_prayers_delete_own on user_intercessory_prayers
for delete using (auth.uid() = user_id);

drop policy if exists user_notes_read_own on user_notes;
create policy user_notes_read_own on user_notes
for select using (auth.uid() = user_id);

drop policy if exists user_notes_insert_own on user_notes;
create policy user_notes_insert_own on user_notes
for insert with check (auth.uid() = user_id);

drop policy if exists user_notes_update_own on user_notes;
create policy user_notes_update_own on user_notes
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists user_notes_delete_own on user_notes;
create policy user_notes_delete_own on user_notes
for delete using (auth.uid() = user_id);

drop policy if exists user_saved_verses_read_own on user_saved_verses;
create policy user_saved_verses_read_own on user_saved_verses
for select using (auth.uid() = user_id);

drop policy if exists user_saved_verses_insert_own on user_saved_verses;
create policy user_saved_verses_insert_own on user_saved_verses
for insert with check (auth.uid() = user_id);

drop policy if exists user_saved_verses_delete_own on user_saved_verses;
create policy user_saved_verses_delete_own on user_saved_verses
for delete using (auth.uid() = user_id);

drop policy if exists user_daily_attendance_read_own on user_daily_attendance;
create policy user_daily_attendance_read_own on user_daily_attendance
for select using (auth.uid() = user_id);

drop policy if exists user_daily_attendance_insert_own on user_daily_attendance;
create policy user_daily_attendance_insert_own on user_daily_attendance
for insert with check (auth.uid() = user_id);

drop policy if exists user_daily_study_read_own on user_daily_study;
create policy user_daily_study_read_own on user_daily_study
for select using (auth.uid() = user_id);

drop policy if exists user_daily_study_insert_own on user_daily_study;
create policy user_daily_study_insert_own on user_daily_study
for insert with check (auth.uid() = user_id);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-images',
  'profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists profile_images_public_read on storage.objects;
create policy profile_images_public_read on storage.objects
for select using (bucket_id = 'profile-images');

drop policy if exists profile_images_insert_own on storage.objects;
create policy profile_images_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists profile_images_update_own on storage.objects;
create policy profile_images_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists profile_images_delete_own on storage.objects;
create policy profile_images_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

grant execute on function public.list_intercessory_prayer_requests(integer, integer) to authenticated;
grant execute on function public.add_intercessory_prayer_by_share_id(text) to authenticated;

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
