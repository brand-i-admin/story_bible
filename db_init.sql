create extension if not exists pgcrypto;
create extension if not exists vector;

-- Single source of truth for local bootstrap before first production release.
-- Run this file directly to recreate schema + seed data end-to-end.
-- Supabase migration files may lag behind while this mode is enabled.

-- Re-initialize safely when rerunning this script locally or via CI.
-- We keep this as "drop then recreate" for predictable bootstrap.
--
-- Legacy tables from earlier prototypes (not part of current schema).
-- Kept here as defensive cleanup so previously-running databases stay clean.
drop table if exists person_generated_assets cascade;
drop table if exists event_scene_generated_assets cascade;
drop table if exists import_jobs cascade;
drop table if exists import_job_artifacts cascade;
drop table if exists books cascade;
drop table if exists study_event_meta cascade;
drop table if exists study_event_points cascade;
drop table if exists study_verse_pages cascade;

-- 2026-04 rename: persons → characters. 기존 DB에 옛 이름 객체가 남아있을 수
-- 있으므로 **옛 이름 + 새 이름 모두** 방어적으로 drop. 이름 간 FK/view 의존성
-- 때문에 CASCADE 필수.
-- character_eras (이전 person_eras) 는 v1/v2 에선 실제 테이블, v3 부터 view.
-- 두 케이스 모두 커버.
do $$
begin
  if exists (
    select 1 from pg_class
    where relnamespace = 'public'::regnamespace
      and relname = 'person_eras'
      and relkind = 'r'
  ) then
    execute 'drop table public.person_eras cascade';
  end if;
  if exists (
    select 1 from pg_class
    where relnamespace = 'public'::regnamespace
      and relname = 'character_eras'
      and relkind = 'r'
  ) then
    execute 'drop table public.character_eras cascade';
  end if;
end $$;

drop view if exists events_ordered cascade;
drop view if exists person_eras cascade;
drop view if exists character_eras cascade;
drop table if exists audit_log cascade;
drop table if exists search_embeddings cascade;
drop table if exists user_daily_activity cascade;
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
-- events 를 먼저 drop 해야 FK (event_persons, event_characters) cascade 안전
drop table if exists events cascade;
drop table if exists event_persons cascade;      -- 옛 이름 (legacy)
drop table if exists event_characters cascade;   -- 새 이름 (legacy)
drop table if exists persons cascade;            -- 옛 이름 — 이번에 drop 안 돼서 남아있음
drop table if exists characters cascade;         -- 새 이름
drop table if exists eras cascade;
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user_profile() cascade;
drop function if exists public.generate_profile_share_id() cascade;
drop function if exists public.list_intercessory_prayer_requests(integer, integer) cascade;
drop function if exists public.add_intercessory_prayer_by_share_id(text) cascade;
drop function if exists public.touch_updated_at() cascade;
drop function if exists public.record_audit() cascade;
drop function if exists public.publish_event(uuid) cascade;
drop function if exists public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, text, double precision, double precision, text
) cascade;
drop function if exists public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, text, double precision, double precision
) cascade;
drop function if exists public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, text, double precision, double precision, text[]
) cascade;
drop function if exists public.is_pastor() cascade;
drop function if exists public.list_persons_by_era(uuid) cascade;       -- 옛 이름 (legacy)
drop function if exists public.list_characters_by_era(uuid) cascade;    -- 새 이름
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, int
) cascade;
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], int
) cascade;
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, int
) cascade;
drop function if exists public.approve_event_proposal(uuid, int) cascade;
drop function if exists public.reject_event_proposal(uuid, text) cascade;
drop function if exists public.add_proposal_comment(uuid, text) cascade;
drop table if exists event_proposal_comments cascade;
drop table if exists event_proposals cascade;

create table if not exists eras (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  display_order int not null,
  start_year int,
  end_year int,
  map_center_lat double precision,
  map_center_lng double precision,
  map_zoom numeric(4,2),
  created_at timestamptz not null default now()
);

create table if not exists characters (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tagline text,
  avatar_url text,

  -- Supabase Storage 경로 — 'characters/<code>.png' 형식.
  -- 로컬 assets/avatars/*.png 를 upload_character_avatars.py 로 업로드하면 채워짐.
  -- 앱과 Edge Function 모두 이 경로로 퍼블릭 URL 을 만들어 쓸 수 있다.
  avatar_storage_path text,

  description text,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  era_id uuid not null references eras(id),
  title text not null,
  summary text,
  story_scenes jsonb not null default '[]'::jsonb,
  scene_characters jsonb not null default '[]'::jsonb,
  character_codes text[] not null default '{}',
  bible_refs jsonb not null default '[]'::jsonb,
  start_year int,
  end_year int,
  time_precision text not null default 'approx',
  story_index int not null,
  place_name text,
  lat double precision,
  lng double precision,

  -- 장면 이미지 Storage 경로 (proposal 승인 시 proposal-scenes/... 경로가 그대로
  -- 복사됨). 앱은 **로컬 assets/story_images_thumbs/<title>/scene_N.png 를 먼저
  -- 시도** 하고, 번들에 파일이 없을 때만 이 컬럼의 public URL 로 네트워크 로드.
  -- 캐논 이벤트(Makefile 파이프라인으로 만든 것들) 는 이 필드를 빈 배열로 두고
  -- 순수 로컬 로드를 쓴다.
  scene_image_paths text[] not null default '{}',

  video_url text,
  status text not null default 'published'
    check (status in ('draft', 'published')),
  created_at timestamptz not null default now(),
  unique (era_id, story_index)
);

-- Era 내 story_index 정렬 결과를 1..N rank 로 노출.
-- 어드민/외부 기여로 새 이야기가 끼어들어도 view 가 자동으로 재계산된다.
create view events_ordered as
  select
    e.*,
    row_number() over (partition by e.era_id order by e.story_index) as rank_in_era,
    row_number() over (order by er.display_order, e.story_index) as global_rank
  from events e
  join eras er on er.id = e.era_id
  where e.status = 'published';

-- 인물별 첫 등장 era + 첫 등장 story_index 기준으로 era 안의 인물 순서를 동적 계산.
-- is_active = false 인 인물은 노출 대상에서 제외된다.
create view character_eras as
  with character_first as (
    select
      p.id as character_id,
      p.code as character_code,
      e.era_id,
      min(e.story_index) as first_story_index
    from characters p
    join events e on e.character_codes @> array[p.code]
                  and e.status = 'published'
    where p.is_active = true
    group by p.id, p.code, e.era_id
  )
  select
    character_id,
    era_id,
    row_number() over (
      partition by era_id
      order by first_story_index, character_code
    ) as display_order
  from character_first;

-- character_eras 는 view 라 WITH + group by + row_number() 탓에 PostgREST 가
-- characters 로의 FK 를 자동 추론하지 못한다 (PGRST200). 클라이언트는 이 RPC 로
-- 호출해 우회한다. characters.is_active = true 조건을 함수 내부에서 유지.
create or replace function public.list_characters_by_era(p_era_id uuid)
returns table (
  id uuid,
  code text,
  name text,
  tagline text,
  description text,
  avatar_url text,
  avatar_storage_path text,
  display_order int
)
language sql
stable
security definer
set search_path = public
as $$
  with character_first as (
    select
      p.id as character_id,
      p.code as character_code,
      min(e.story_index) as first_story_index
    from characters p
    join events e
      on e.character_codes @> array[p.code]
     and e.status = 'published'
     and e.era_id = p_era_id
    where p.is_active = true
    group by p.id, p.code
  )
  select
    p.id,
    p.code,
    p.name,
    p.tagline,
    p.description,
    p.avatar_url,
    p.avatar_storage_path,
    (row_number() over (order by pf.first_story_index, pf.character_code))::int
      as display_order
  from character_first pf
  join characters p on p.id = pf.character_id
  order by display_order;
$$;

grant execute on function public.list_characters_by_era(uuid) to anon, authenticated;

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

-- 하루 한 row 로 출석/학습 플래그를 함께 기록한다. PostgREST upsert 는
-- 요청에 포함된 컬럼만 excluded 로 SET 하므로 두 플래그가 서로 덮어쓰이지 않는다.
create table if not exists user_daily_activity (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  attended boolean not null default false,
  studied boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, activity_date)
);

create table if not exists search_embeddings (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('event', 'character')),
  entity_id uuid not null,
  chunk_text text not null,
  embedding vector(1536) not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_events_era_story_index on events (era_id, story_index);
create index if not exists idx_events_status on events (status);
create index if not exists idx_events_character_codes_gin on events using gin (character_codes);
create index if not exists idx_progress_user_completed on user_event_progress (user_id, is_completed);
create unique index if not exists uidx_quiz_event_order on quiz_questions (event_id, display_order);
create index if not exists idx_embed_ivfflat on search_embeddings using ivfflat (embedding vector_cosine_ops);
create index if not exists idx_bible_verses_lookup on bible_verses (translation, book_no, chapter_no, verse_no);
create index if not exists idx_user_notes_user_created on user_notes (user_id, created_at desc);
create index if not exists idx_user_saved_verses_user_created on user_saved_verses (user_id, created_at desc);
create index if not exists idx_user_intercessory_prayers_user_created on user_intercessory_prayers (user_id, created_at desc);
create index if not exists idx_user_intercessory_prayers_target on user_intercessory_prayers (target_user_id);
create index if not exists idx_user_daily_activity_attended
  on user_daily_activity (user_id, activity_date desc)
  where attended = true;
create index if not exists idx_user_daily_activity_studied
  on user_daily_activity (user_id, activity_date desc)
  where studied = true;

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

drop trigger if exists set_user_daily_activity_updated_at on user_daily_activity;
create trigger set_user_daily_activity_updated_at
before update on user_daily_activity
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
  v_normalized_share_id text := upper(trim(coalesce(p_share_id, '')));
  v_target_user_id uuid;
  v_target_share_id text;
  v_target_nickname text;
  v_target_photo_url text;
  v_target_prayer_request text;
  v_link_id uuid;
  v_link_created_at timestamptz;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if v_normalized_share_id = '' then
    raise exception '공유 ID를 입력해 주세요.';
  end if;

  select
    p.user_id, p.share_id, p.nickname, p.photo_url, p.prayer_request
  into
    v_target_user_id, v_target_share_id, v_target_nickname,
    v_target_photo_url, v_target_prayer_request
  from public.user_profiles p
  where p.share_id = v_normalized_share_id;

  if not found then
    raise exception '해당 ID를 찾을 수 없습니다.';
  end if;

  if v_target_user_id = auth.uid() then
    raise exception '내 기도제목은 추가할 수 없습니다.';
  end if;

  insert into public.user_intercessory_prayers (user_id, target_user_id)
  values (auth.uid(), v_target_user_id)
  on conflict (user_id, target_user_id)
  do nothing
  returning user_intercessory_prayers.id, user_intercessory_prayers.created_at
    into v_link_id, v_link_created_at;

  if v_link_id is null then
    select ip.id, ip.created_at
      into v_link_id, v_link_created_at
    from public.user_intercessory_prayers ip
    where ip.user_id = auth.uid()
      and ip.target_user_id = v_target_user_id;
  end if;

  -- Assign each OUT column directly and emit one row.
  -- RETURN QUERY SELECT with plpgsql variables can fail on some PG/Supabase
  -- builds with "relation <var> does not exist", so we use RETURN NEXT.
  id := v_link_id;
  target_user_id := v_target_user_id;
  share_id := v_target_share_id;
  nickname := v_target_nickname;
  photo_url := v_target_photo_url;
  prayer_request := v_target_prayer_request;
  created_at := v_link_created_at;
  return next;
  return;
end;
$$;

-- -----------------------------------------------------------------------------
-- Public read access + RLS policies
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select on table eras to anon, authenticated;
grant select on table characters to anon, authenticated;
grant select on table events to anon, authenticated;
grant select on table bible_verses to anon, authenticated;
grant select on table quiz_questions to anon, authenticated;
grant select on events_ordered to anon, authenticated;
grant select on character_eras to anon, authenticated;

grant select, insert, update on table user_event_progress to authenticated;
grant select, insert, update on table user_profiles to authenticated;
grant select, insert, delete on table user_intercessory_prayers to authenticated;
grant select, insert, update, delete on table user_notes to authenticated;
grant select, insert, delete on table user_saved_verses to authenticated;
grant select, insert, update on table user_daily_activity to authenticated;

alter table eras enable row level security;
alter table characters enable row level security;
alter table events enable row level security;
alter table bible_verses enable row level security;
alter table quiz_questions enable row level security;
alter table user_event_progress enable row level security;
alter table user_profiles enable row level security;
alter table user_intercessory_prayers enable row level security;
alter table user_notes enable row level security;
alter table user_saved_verses enable row level security;
alter table user_daily_activity enable row level security;

drop policy if exists eras_read_all on eras;
create policy eras_read_all on eras for select using (true);

drop policy if exists characters_read_active on characters;
create policy characters_read_active on characters for select using (is_active = true);

drop policy if exists events_read_published on events;
create policy events_read_published on events for select using (status = 'published');

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

drop policy if exists user_daily_activity_read_own on user_daily_activity;
create policy user_daily_activity_read_own on user_daily_activity
for select using (auth.uid() = user_id);

drop policy if exists user_daily_activity_write_own on user_daily_activity;
create policy user_daily_activity_write_own on user_daily_activity
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

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
-- Admin 워크플로우
-- -----------------------------------------------------------------------------
-- 관리자 식별: auth.users.raw_app_meta_data ->> 'role' = 'admin'
-- (Supabase 대시보드에서 사용자별로 수동 부여)
-- 외부 기여자 제출 기능은 폐기됨 — 이야기 등록 요청은 앱 외부 파이프라인
-- (구글폼/노션/메일 등)을 통해 수집하고, 어드민이 직접 등록한다.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin',
    false
  );
$$;

grant execute on function public.is_admin() to authenticated;

-- events / characters 쓰기 권한: 관리자(is_admin())만 INSERT/UPDATE/DELETE 가능.
-- GRANT 는 authenticated 에 부여하되, RLS 정책이 admin 여부를 체크한다.
grant insert, update, delete on table events to authenticated;
grant insert, update, delete on table characters to authenticated;

drop policy if exists events_read_published on events;
create policy events_read_published on events
for select using (
  status = 'published' or public.is_admin()
);

drop policy if exists events_insert_pending on events;  -- legacy 제거
drop policy if exists events_insert_admin on events;
create policy events_insert_admin on events
for insert to authenticated
with check (public.is_admin());

drop policy if exists events_update_admin on events;
create policy events_update_admin on events
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists events_delete_admin on events;
create policy events_delete_admin on events
for delete to authenticated
using (public.is_admin());

-- characters 는 관리자만 INSERT/UPDATE/DELETE.
drop policy if exists characters_admin_write on characters;
create policy characters_admin_write on characters
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 관리자는 비활성 인물도 볼 수 있어야 토글 가능.
drop policy if exists characters_read_active on characters;
create policy characters_read_active on characters
for select using (is_active = true or public.is_admin());

-- ============================================================================
-- Storage 버킷: 'characters' — 성경 인물 아바타 이미지 (public read)
--   경로 규칙: characters/<character_code>.png   (예: characters/abraham.png)
--   쓰기 권한: admin 만 (관리자가 upload_character_avatars.py 실행)
--   읽기 권한: 누구나 (앱 프론트 + Edge Function 모두 사용)
-- ============================================================================
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'characters', 'characters', true,
  10485760,  -- 10 MB (Imagen PNG 업스케일 여유)
  array['image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists characters_bucket_public_read on storage.objects;
create policy characters_bucket_public_read on storage.objects
for select using (bucket_id = 'characters');

drop policy if exists characters_bucket_admin_write on storage.objects;
create policy characters_bucket_admin_write on storage.objects
for all to authenticated
using (bucket_id = 'characters' and public.is_admin())
with check (bucket_id = 'characters' and public.is_admin());

-- ============================================================================
-- Storage 버킷: 'proposal-scenes' — 제안 장면 AI 생성 이미지
--   경로 규칙: proposal-scenes/<user_id>/<draft_id>/scene_<idx>.png
--     (생성 시점엔 proposal 아직 insert 전이므로 draft_id 는 클라이언트 UUID)
--   쓰기 권한: 본인 폴더만 (pastor 가 제안 등록하기 전 업로드)
--   읽기 권한: public — 제안 상세 페이지에서 다른 pastor / admin 이 봄
--   실제 업로드 주체는 Edge Function (service-role) 이므로 Edge Function 이
--   본인 서명으로 넣고 frontend 에는 path 만 넘긴다.
-- ============================================================================
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'proposal-scenes', 'proposal-scenes', true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists proposal_scenes_public_read on storage.objects;
create policy proposal_scenes_public_read on storage.objects
for select using (bucket_id = 'proposal-scenes');

drop policy if exists proposal_scenes_insert_own on storage.objects;
create policy proposal_scenes_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'proposal-scenes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_scenes_update_own on storage.objects;
create policy proposal_scenes_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'proposal-scenes'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'proposal-scenes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_scenes_delete_own on storage.objects;
create policy proposal_scenes_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'proposal-scenes'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

-- ============================================================================
-- Storage 버킷: 'proposal-characters' — 제안에서 새로 생성한 캐릭터 아바타
--   경로 규칙: proposal-characters/<user_id>/<draft_id>/<character_code>.png
--   쓰기 권한: 본인 폴더 (프로포절 작성 중인 pastor 만)
--   읽기 권한: public — admin / 다른 pastor 가 제안 상세에서 볼 수 있어야.
--   Edge Function (generate-proposal-character) 이 service role 로 업로드한다.
--
--   승인 후 처리:
--     1. approve_event_proposal RPC 가 characters 테이블에
--        avatar_storage_path = 이 경로로 upsert.
--     2. tools/supabase/sync_approved_proposal_assets.py (관리자 수동 실행)
--        가 proposal-characters/ → characters/ 로 파일 복사 + 경로 교체 +
--        assets/avatars/<code>.png 로 로컬 다운로드.
-- ============================================================================
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'proposal-characters', 'proposal-characters', true,
  10485760,
  array['image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists proposal_characters_public_read on storage.objects;
create policy proposal_characters_public_read on storage.objects
for select using (bucket_id = 'proposal-characters');

drop policy if exists proposal_characters_insert_own on storage.objects;
create policy proposal_characters_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'proposal-characters'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_characters_update_own on storage.objects;
create policy proposal_characters_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'proposal-characters'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'proposal-characters'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_characters_delete_own on storage.objects;
create policy proposal_characters_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'proposal-characters'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

-- -----------------------------------------------------------------------------
-- RPC: 새 이야기를 era 안의 특정 위치에 끼워 넣기.
-- (era_id, story_index) UNIQUE 제약이 있으므로 뒤 인덱스를 +1 시프트한 뒤 INSERT.
-- 동시성: era 단위 advisory lock 으로 직렬화.
-- 호출자: **관리자 전용**. status 는 항상 'published' 로 세팅된다.
-- 입력 정책:
--   - p_after_story_index = NULL  → 맨 앞(1)에 삽입
--   - p_after_story_index = N     → N+1 위치에 삽입, N+1.. 이상은 +1 시프트
-- 반환: 새로 만든 events.id
-- 부가 효과: character_codes 중 characters 에 없는 코드는 비활성 placeholder 로 INSERT.
-- -----------------------------------------------------------------------------
create or replace function public.insert_event_at_position(
  p_era_code text,
  p_after_story_index int,
  p_title text,
  p_summary text,
  p_story_scenes jsonb,
  p_scene_characters jsonb,
  p_character_codes text[],
  p_bible_refs jsonb,
  p_start_year int,
  p_end_year int,
  p_time_precision text,
  p_place_name text,
  p_lat double precision,
  p_lng double precision,
  p_scene_image_paths text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_era_id uuid;
  v_target_index int;
  v_new_event_id uuid;
  v_code text;
begin
  if not public.is_admin() then
    raise exception '관리자만 이야기를 등록할 수 있습니다.';
  end if;

  select id into v_era_id from public.eras where code = p_era_code;
  if v_era_id is null then
    raise exception '존재하지 않는 era_code: %', p_era_code;
  end if;

  v_target_index := coalesce(p_after_story_index, 0) + 1;
  if v_target_index < 1 then
    raise exception 'p_after_story_index 가 음수입니다.';
  end if;

  -- era 단위 직렬화. 64bit 키로 hashtext 사용.
  perform pg_advisory_xact_lock(hashtext('events_era_' || v_era_id::text));

  -- 뒤 인덱스를 임시 음수로 옮긴 뒤 +1 정렬 — UNIQUE 제약 충돌 회피.
  update public.events
     set story_index = -(story_index + 1)
   where era_id = v_era_id
     and story_index >= v_target_index;

  update public.events
     set story_index = -story_index
   where era_id = v_era_id
     and story_index < 0;

  insert into public.events (
    era_id, title, summary,
    story_scenes, scene_characters, character_codes, bible_refs,
    start_year, end_year, time_precision, story_index,
    place_name, lat, lng, scene_image_paths, status
  )
  values (
    v_era_id, p_title, p_summary,
    coalesce(p_story_scenes, '[]'::jsonb),
    coalesce(p_scene_characters, '[]'::jsonb),
    coalesce(p_character_codes, '{}'::text[]),
    coalesce(p_bible_refs, '[]'::jsonb),
    p_start_year, p_end_year,
    coalesce(p_time_precision, 'approx'),
    v_target_index,
    p_place_name, p_lat, p_lng,
    coalesce(p_scene_image_paths, '{}'::text[]),
    'published'
  )
  returning id into v_new_event_id;

  -- 누락된 인물 코드는 비활성 placeholder 로 만들어 둠 (관리자가 토글로 활성화).
  if p_character_codes is not null then
    foreach v_code in array p_character_codes loop
      insert into public.characters (code, name, is_active)
      values (v_code, v_code, false)
      on conflict (code) do nothing;
    end loop;
  end if;

  return v_new_event_id;
end;
$$;

grant execute on function public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, text, double precision, double precision, text[]
) to authenticated;

-- -----------------------------------------------------------------------------
-- Seed: eras
-- -----------------------------------------------------------------------------
insert into eras (
  code,
  name,
  display_order,
  start_year,
  end_year,
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_primeval', '원역사', 1, -4000, -2000, 33.00, 44.00, 4.80),
  ('era_patriarch', '족장 시대', 2, -2166, -1805, 31.50, 35.20, 5.40),
  ('era_exodus', '출애굽 시대', 3, -1446, -1406, 29.50, 34.50, 5.20),
  ('era_judges', '사사 시대', 4, -1406, -1050, 31.80, 35.10, 5.40),
  ('era_monarchy', '왕정 시대', 5, -1050, -586, 31.90, 35.20, 5.30),
  ('era_exile_return', '포로 및 포로 후기 시대', 6, -586, -430, 32.20, 38.30, 4.70)
;

-- -----------------------------------------------------------------------------
-- Seed data for characters/character_eras/events/event_characters/event_bible_refs/quiz_questions
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
  map_center_lat,
  map_center_lng,
  map_zoom
)
values
  ('era_nt_public_ministry', 'new', '예수님의 공생애', 1, 27, 33, 31.78, 35.22, 6.10),
  ('era_nt_apostolic', 'new', '사도의 시대', 2, 33, 70, 37.40, 26.90, 4.90),
  ('era_nt_post_apostolic', 'new', '후기 사도의 시대', 3, 70, 100, 37.45, 27.20, 5.20),
  ('era_nt_consummation', 'new', '역사의 종결', 4, null, null, 31.78, 35.22, 4.40)
on conflict (code) do update
set
  testament = excluded.testament,
  name = excluded.name,
  display_order = excluded.display_order,
  start_year = excluded.start_year,
  end_year = excluded.end_year,
  map_center_lat = excluded.map_center_lat,
  map_center_lng = excluded.map_center_lng,
  map_zoom = excluded.map_zoom
;

-- =========================================================
-- Story proposal workflow — pastor 역할 + event_proposals 게시판
-- =========================================================
-- 외부 기여자 제출 기능 폐기(2026-04) 후, "사역자(목회자) 자격을 부여받은
-- 사용자"만 메인 앱 웹 버전에서 이야기를 제안할 수 있다. 관리자가 승인하면
-- 기존 insert_event_at_position 을 통해 events 에 published 로 반영된다.
-- 목회자 인증 절차는 수동: admin@brand-i.net 으로 성함/소속/직책을 보내주면
-- 운영자가 Supabase 대시보드에서 user_profiles.is_pastor = true 로 토글.
--
-- 과거 admin/ 별도 Flutter Web 앱은 폐기됨. UI 는 lib/widgets/proposal/
-- 이주 위젯 + 후속 Phase(2~6) 에서 구축된다.

-- 1) user_profiles 에 is_pastor 컬럼 추가 (기존 row 는 기본 false)
alter table user_profiles
  add column if not exists is_pastor boolean not null default false;

-- 2) is_pastor() 헬퍼 — auth.uid() 의 user_profiles.is_pastor 를 읽는다.
--    is_admin() 와 대칭되는 SECURITY DEFINER 함수.
create or replace function public.is_pastor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_pastor from public.user_profiles where user_id = auth.uid()),
    false
  );
$$;
grant execute on function public.is_pastor() to authenticated;

-- 3) event_proposals: pastor 가 제출하는 이야기 초안 (승인되기 전까지 events 와 격리)
--    (파일 상단 drop 섹션에서 이미 drop 처리됨 — 여기서는 create 만)
create table if not exists event_proposals (
  id uuid primary key default gen_random_uuid(),
  proposer_user_id uuid not null references auth.users(id) on delete cascade,
  era_id uuid not null references eras(id),
  title text not null,
  summary text,
  character_codes text[] not null default '{}',
  place_name text,
  lat double precision,
  lng double precision,
  start_year int,
  end_year int,
  time_precision text not null default 'approx',
  bible_refs jsonb not null default '[]'::jsonb,
  story_scenes jsonb not null default '[]'::jsonb,
  scene_characters jsonb not null default '[]'::jsonb,

  -- 장면 이미지 — Storage 경로 배열. 장면 1..N 과 동일한 길이.
  -- 각 원소는 'proposal-scenes/{user_id}/{draft_id}/scene_{idx}.png' 형태의 Storage path.
  -- 비어있으면 아직 생성 전이라는 뜻. 제안 등록 시 모든 장면이 채워져 있어야 함.
  scene_image_paths text[] not null default '{}',

  -- 각 장면 이미지를 생성할 때 사용한 최종 prompt(참고용 스냅샷).
  -- 재생성 시 이 값이 새로운 prompt 로 덮어씌워진다.
  -- 길이는 scene_image_paths 와 동일해야 한다.
  scene_image_prompts text[] not null default '{}',

  -- 제안 중 "새로 만든 캐릭터" 의 메타데이터 + Storage 경로 리스트.
  -- 기존 characters 에 없는 인물을 사역자가 프롬프트로 생성해 제안에 포함시킬 때
  -- 사용. 각 요소는 { code, name, prompt, storage_path } 객체.
  -- storage_path 는 'proposal-characters/<uid>/<draft>/<code>.png' 형태.
  -- 승인 RPC 가 이 배열을 읽어 characters 테이블에 upsert 한다.
  proposed_characters jsonb not null default '[]'::jsonb,

  after_story_index int,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_by_user_id uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  approved_event_id uuid references events(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists event_proposals_proposer_idx
  on event_proposals(proposer_user_id);
create index if not exists event_proposals_status_idx
  on event_proposals(status);
create index if not exists event_proposals_era_idx
  on event_proposals(era_id);

drop trigger if exists set_event_proposals_updated_at on event_proposals;
create trigger set_event_proposals_updated_at
before update on event_proposals
for each row execute function public.touch_updated_at();

-- 4) event_proposal_comments: 제안에 달리는 댓글 (pastor + admin 작성 가능)
create table if not exists event_proposal_comments (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references event_proposals(id) on delete cascade,
  author_user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists event_proposal_comments_proposal_idx
  on event_proposal_comments(proposal_id);

drop trigger if exists set_event_proposal_comments_updated_at on event_proposal_comments;
create trigger set_event_proposal_comments_updated_at
before update on event_proposal_comments
for each row execute function public.touch_updated_at();

-- 5) GRANT + RLS
grant select, insert, update, delete on table event_proposals to authenticated;
grant select, insert, update, delete on table event_proposal_comments to authenticated;

alter table event_proposals enable row level security;
alter table event_proposal_comments enable row level security;

-- 제안 게시판 SELECT: pastor 또는 admin 이면 전체 공개 (동료 사역자끼리 열람·댓글 가능)
drop policy if exists event_proposals_read on event_proposals;
create policy event_proposals_read on event_proposals
for select to authenticated
using (public.is_pastor() or public.is_admin());

-- 제안 INSERT: pastor 만 가능, proposer_user_id 는 auth.uid() 로 강제, 초기 status='pending'
drop policy if exists event_proposals_insert_pastor on event_proposals;
create policy event_proposals_insert_pastor on event_proposals
for insert to authenticated
with check (
  public.is_pastor()
  and proposer_user_id = auth.uid()
  and status = 'pending'
);

-- 제안 UPDATE:
--   - pastor 는 본인 것 + status='pending' 일 때만 (내용 수정 가능)
--   - admin 은 status/review 필드 변경 목적의 전체 UPDATE 허용
drop policy if exists event_proposals_update on event_proposals;
create policy event_proposals_update on event_proposals
for update to authenticated
using (
  (public.is_pastor() and proposer_user_id = auth.uid() and status = 'pending')
  or public.is_admin()
)
with check (
  (public.is_pastor() and proposer_user_id = auth.uid() and status = 'pending')
  or public.is_admin()
);

-- 제안 DELETE: admin 만
drop policy if exists event_proposals_delete_admin on event_proposals;
create policy event_proposals_delete_admin on event_proposals
for delete to authenticated
using (public.is_admin());

-- 댓글 SELECT: pastor 또는 admin
drop policy if exists event_proposal_comments_read on event_proposal_comments;
create policy event_proposal_comments_read on event_proposal_comments
for select to authenticated
using (public.is_pastor() or public.is_admin());

-- 댓글 INSERT: pastor + admin, author_user_id = auth.uid() 강제
drop policy if exists event_proposal_comments_insert on event_proposal_comments;
create policy event_proposal_comments_insert on event_proposal_comments
for insert to authenticated
with check (
  (public.is_pastor() or public.is_admin())
  and author_user_id = auth.uid()
);

-- 댓글 UPDATE: 본인 author 만
drop policy if exists event_proposal_comments_update_own on event_proposal_comments;
create policy event_proposal_comments_update_own on event_proposal_comments
for update to authenticated
using (author_user_id = auth.uid())
with check (author_user_id = auth.uid());

-- 댓글 DELETE: 본인 또는 admin
drop policy if exists event_proposal_comments_delete on event_proposal_comments;
create policy event_proposal_comments_delete on event_proposal_comments
for delete to authenticated
using (author_user_id = auth.uid() or public.is_admin());

-- 6) RPC: submit_event_proposal (pastor 만) — 제안을 event_proposals 에 INSERT
-- scene_image_paths / scene_image_prompts 는 생성 완료된 장면 이미지를 같이 커밋.
-- proposed_characters 는 "이번 제안에서 새로 만든 캐릭터" 메타데이터 배열.
-- 장면 텍스트 개수와 이미지 개수가 맞아야 한다 (서로 다르면 raise).
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, int
) cascade;
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], int
) cascade;
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, int
) cascade;
create or replace function public.submit_event_proposal(
  p_era_id uuid,
  p_title text,
  p_summary text,
  p_character_codes text[],
  p_place_name text,
  p_lat double precision,
  p_lng double precision,
  p_start_year int,
  p_end_year int,
  p_time_precision text,
  p_bible_refs jsonb,
  p_story_scenes jsonb,
  p_scene_characters jsonb,
  p_scene_image_paths text[],
  p_scene_image_prompts text[],
  p_proposed_characters jsonb,
  p_after_story_index int
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_scene_count int;
begin
  if not public.is_pastor() then
    raise exception 'permission denied: pastor role required';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'title is required';
  end if;

  -- 장면 배열 길이 일치 검증.
  v_scene_count := coalesce(jsonb_array_length(p_story_scenes), 0);
  if v_scene_count = 0 then
    raise exception 'at least one scene is required';
  end if;
  if array_length(coalesce(p_scene_image_paths, '{}'), 1) is distinct from v_scene_count then
    raise exception 'scene_image_paths length (%) must match story_scenes length (%)',
      coalesce(array_length(p_scene_image_paths, 1), 0), v_scene_count;
  end if;
  if array_length(coalesce(p_scene_image_prompts, '{}'), 1) is distinct from v_scene_count then
    raise exception 'scene_image_prompts length (%) must match story_scenes length (%)',
      coalesce(array_length(p_scene_image_prompts, 1), 0), v_scene_count;
  end if;

  insert into event_proposals (
    proposer_user_id, era_id, title, summary, character_codes,
    place_name, lat, lng, start_year, end_year,
    time_precision, bible_refs, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts,
    proposed_characters,
    after_story_index
  )
  values (
    auth.uid(), p_era_id, p_title, p_summary, coalesce(p_character_codes, '{}'),
    p_place_name, p_lat, p_lng, p_start_year, p_end_year,
    coalesce(nullif(trim(p_time_precision), ''), 'approx'),
    coalesce(p_bible_refs, '[]'::jsonb),
    coalesce(p_story_scenes, '[]'::jsonb),
    coalesce(p_scene_characters, '[]'::jsonb),
    coalesce(p_scene_image_paths, '{}'),
    coalesce(p_scene_image_prompts, '{}'),
    coalesce(p_proposed_characters, '[]'::jsonb),
    p_after_story_index
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, int
) to authenticated;

-- 7) RPC: approve_event_proposal (admin 만) — 제안을 events 에 published 로 반영
--    기존 insert_event_at_position 을 재사용해 era 내 뒤 인덱스 시프트까지 처리.
drop function if exists public.approve_event_proposal(uuid, int) cascade;
create or replace function public.approve_event_proposal(
  p_proposal_id uuid,
  p_after_story_index_override int default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_era_code text;
  v_event_id uuid;
  v_after int;
  v_proposed_char jsonb;
  v_code text;
  v_name text;
  v_storage_path text;
  v_description text;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;

  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;

  select code into v_era_code from eras where id = v_proposal.era_id;
  if v_era_code is null then
    raise exception 'era not found for proposal: %', v_proposal.era_id;
  end if;

  v_after := coalesce(p_after_story_index_override, v_proposal.after_story_index, 0);

  -- 1) 먼저 "이 제안에서 새로 만든 캐릭터" 를 characters 에 upsert.
  --    insert_event_at_position 이 placeholder 로 넣어버리기 전에 실제 이름 +
  --    avatar_storage_path 를 반영해 둔다.
  --    avatar_storage_path 는 proposal-characters 버킷 경로 그대로 저장
  --    (후속 make sync-approved-characters 가 characters/ 버킷으로 복사 + 경로 교체).
  --    is_active = true (관리자가 승인했다는 건 노출 OK 라는 뜻).
  for v_proposed_char in
    select * from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb))
  loop
    v_code := v_proposed_char->>'code';
    v_name := v_proposed_char->>'name';
    v_storage_path := v_proposed_char->>'storage_path';
    v_description := v_proposed_char->>'prompt';
    if coalesce(trim(v_code), '') = '' then
      continue;
    end if;
    insert into public.characters (
      code, name, description, avatar_storage_path, is_active
    )
    values (
      v_code,
      coalesce(nullif(trim(v_name), ''), v_code),
      v_description,
      v_storage_path,
      true
    )
    on conflict (code) do update set
      name = coalesce(nullif(trim(excluded.name), ''), public.characters.name),
      description = coalesce(excluded.description, public.characters.description),
      avatar_storage_path = coalesce(excluded.avatar_storage_path, public.characters.avatar_storage_path),
      is_active = true;
  end loop;

  -- 2) insert_event_at_position — 기존 로직. 남은 누락 코드는 비활성 placeholder.
  --    proposal 의 scene_image_paths 를 events 로 그대로 복사해 두면
  --    로컬 assets 가 아직 번들되지 않은 승인 직후 단계에서도 앱이 Supabase
  --    Storage 를 fallback 으로 읽어 이미지를 보여줄 수 있다 (하이브리드 로딩).
  v_event_id := public.insert_event_at_position(
    v_era_code,
    v_after,
    v_proposal.title,
    v_proposal.summary,
    v_proposal.story_scenes,
    v_proposal.scene_characters,
    v_proposal.character_codes,
    v_proposal.bible_refs,
    v_proposal.start_year,
    v_proposal.end_year,
    v_proposal.time_precision,
    v_proposal.place_name,
    v_proposal.lat,
    v_proposal.lng,
    v_proposal.scene_image_paths
  );

  update event_proposals
  set
    status = 'approved',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    approved_event_id = v_event_id
  where id = p_proposal_id;

  return v_event_id;
end;
$$;
grant execute on function public.approve_event_proposal(uuid, int) to authenticated;

-- 8) RPC: reject_event_proposal (admin 만) — note 와 함께 status='rejected'
drop function if exists public.reject_event_proposal(uuid, text) cascade;
create or replace function public.reject_event_proposal(
  p_proposal_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;

  update event_proposals
  set
    status = 'rejected',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    review_note = p_note
  where id = p_proposal_id
    and status = 'pending';
end;
$$;
grant execute on function public.reject_event_proposal(uuid, text) to authenticated;

-- 9) RPC: add_proposal_comment (pastor + admin) — 댓글 한 개 INSERT 편의 함수
drop function if exists public.add_proposal_comment(uuid, text) cascade;
create or replace function public.add_proposal_comment(
  p_proposal_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
begin
  if not (public.is_pastor() or public.is_admin()) then
    raise exception 'permission denied';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'comment body must not be empty';
  end if;

  insert into event_proposal_comments (proposal_id, author_user_id, body)
  values (p_proposal_id, auth.uid(), p_body)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.add_proposal_comment(uuid, text) to authenticated;
