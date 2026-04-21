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

-- person_eras was a real table in v1/v2 schema; v3 promotes it to a view.
-- Detect what kind of object exists right now and drop it accordingly so
-- both first-time migrations and idempotent reruns succeed.
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
end $$;

drop view if exists events_ordered cascade;
drop view if exists person_eras cascade;
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
drop table if exists event_persons cascade;
drop table if exists person_eras cascade;
drop table if exists events cascade;
drop table if exists persons cascade;
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

create table if not exists persons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tagline text,
  avatar_url text,
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
  scene_persons jsonb not null default '[]'::jsonb,
  person_codes text[] not null default '{}',
  bible_refs jsonb not null default '[]'::jsonb,
  start_year int,
  end_year int,
  time_precision text not null default 'approx',
  story_index int not null,
  place_name text,
  lat double precision,
  lng double precision,
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
create view person_eras as
  with person_first as (
    select
      p.id as person_id,
      p.code as person_code,
      e.era_id,
      min(e.story_index) as first_story_index
    from persons p
    join events e on e.person_codes @> array[p.code]
                  and e.status = 'published'
    where p.is_active = true
    group by p.id, p.code, e.era_id
  )
  select
    person_id,
    era_id,
    row_number() over (
      partition by era_id
      order by first_story_index, person_code
    ) as display_order
  from person_first;

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
  entity_type text not null check (entity_type in ('event', 'person')),
  entity_id uuid not null,
  chunk_text text not null,
  embedding vector(1536) not null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_events_era_story_index on events (era_id, story_index);
create index if not exists idx_events_status on events (status);
create index if not exists idx_events_person_codes_gin on events using gin (person_codes);
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
grant select on table persons to anon, authenticated;
grant select on table events to anon, authenticated;
grant select on table bible_verses to anon, authenticated;
grant select on table quiz_questions to anon, authenticated;
grant select on events_ordered to anon, authenticated;
grant select on person_eras to anon, authenticated;

grant select, insert, update on table user_event_progress to authenticated;
grant select, insert, update on table user_profiles to authenticated;
grant select, insert, delete on table user_intercessory_prayers to authenticated;
grant select, insert, update, delete on table user_notes to authenticated;
grant select, insert, delete on table user_saved_verses to authenticated;
grant select, insert, update on table user_daily_activity to authenticated;

alter table eras enable row level security;
alter table persons enable row level security;
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

drop policy if exists persons_read_active on persons;
create policy persons_read_active on persons for select using (is_active = true);

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

-- events / persons 쓰기 권한: 관리자(is_admin())만 INSERT/UPDATE/DELETE 가능.
-- GRANT 는 authenticated 에 부여하되, RLS 정책이 admin 여부를 체크한다.
grant insert, update, delete on table events to authenticated;
grant insert, update, delete on table persons to authenticated;

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

-- persons 는 관리자만 INSERT/UPDATE/DELETE.
drop policy if exists persons_admin_write on persons;
create policy persons_admin_write on persons
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 관리자는 비활성 인물도 볼 수 있어야 토글 가능.
drop policy if exists persons_read_active on persons;
create policy persons_read_active on persons
for select using (is_active = true or public.is_admin());

-- -----------------------------------------------------------------------------
-- RPC: 새 이야기를 era 안의 특정 위치에 끼워 넣기.
-- (era_id, story_index) UNIQUE 제약이 있으므로 뒤 인덱스를 +1 시프트한 뒤 INSERT.
-- 동시성: era 단위 advisory lock 으로 직렬화.
-- 호출자: **관리자 전용**. status 는 항상 'published' 로 세팅된다.
-- 입력 정책:
--   - p_after_story_index = NULL  → 맨 앞(1)에 삽입
--   - p_after_story_index = N     → N+1 위치에 삽입, N+1.. 이상은 +1 시프트
-- 반환: 새로 만든 events.id
-- 부가 효과: person_codes 중 persons 에 없는 코드는 비활성 placeholder 로 INSERT.
-- -----------------------------------------------------------------------------
create or replace function public.insert_event_at_position(
  p_era_code text,
  p_after_story_index int,
  p_title text,
  p_summary text,
  p_story_scenes jsonb,
  p_scene_persons jsonb,
  p_person_codes text[],
  p_bible_refs jsonb,
  p_start_year int,
  p_end_year int,
  p_time_precision text,
  p_place_name text,
  p_lat double precision,
  p_lng double precision
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
    story_scenes, scene_persons, person_codes, bible_refs,
    start_year, end_year, time_precision, story_index,
    place_name, lat, lng, status
  )
  values (
    v_era_id, p_title, p_summary,
    coalesce(p_story_scenes, '[]'::jsonb),
    coalesce(p_scene_persons, '[]'::jsonb),
    coalesce(p_person_codes, '{}'::text[]),
    coalesce(p_bible_refs, '[]'::jsonb),
    p_start_year, p_end_year,
    coalesce(p_time_precision, 'approx'),
    v_target_index,
    p_place_name, p_lat, p_lng,
    'published'
  )
  returning id into v_new_event_id;

  -- 누락된 인물 코드는 비활성 placeholder 로 만들어 둠 (관리자가 토글로 활성화).
  if p_person_codes is not null then
    foreach v_code in array p_person_codes loop
      insert into public.persons (code, name, is_active)
      values (v_code, v_code, false)
      on conflict (code) do nothing;
    end loop;
  end if;

  return v_new_event_id;
end;
$$;

grant execute on function public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, text, double precision, double precision
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
