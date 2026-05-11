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
drop table if exists era_boundaries cascade;
drop table if exists landmarks cascade;
drop table if exists map_objects cascade;  -- legacy 이름 (2026-04-29 이전)
drop table if exists audit_log cascade;
drop table if exists search_embeddings cascade;
drop table if exists user_daily_activity cascade;
drop table if exists user_daily_study cascade;
drop table if exists user_daily_quiz_attempts cascade;
drop table if exists daily_quiz cascade;
drop table if exists weekly_quiz_progress cascade;
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

-- ----------------------------------------------------------------------------
-- Storage 파일 purge 는 **SQL 에서 못함**.
-- Supabase 는 storage.objects / storage.buckets 에 protect_delete() 트리거를
-- 걸어서 SQL DELETE 를 차단 ("Direct deletion from storage tables is not
-- allowed. Use the Storage API instead."). 실제 파일이 스토리지 백엔드에
-- 남는 고아를 방지하기 위한 안전장치.
--
-- 따라서 db-init 직전에 REST API (`POST /storage/v1/bucket/<name>/empty`) 로
-- 비우는 별도 Python 스크립트를 돌린다:
--   Makefile `db-init:` → tools/supabase/purge_owned_buckets.py --env $(ENV)
-- 이걸 선행해야 `make upload-character-avatars` 가 clean slate 에서 시작.

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
-- v2 시그니처 (landmark_id) 도 사전 drop.
drop function if exists public.insert_event_at_position(
  text, int, text, text, jsonb, jsonb, text[], jsonb,
  int, int, text, uuid, text[]
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
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
) cascade;
-- v2 시그니처 (landmark_id).
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], uuid,
  int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
) cascade;
drop function if exists public.revise_proposal_position(uuid, int, int, int, uuid) cascade;
drop function if exists public.submit_delete_proposal(uuid, text) cascade;
drop function if exists public.approve_event_proposal(uuid, int) cascade;
drop function if exists public.approve_delete_proposal(uuid) cascade;
drop function if exists public.reject_event_proposal(uuid, text) cascade;
drop function if exists public.add_proposal_comment(uuid, text) cascade;
drop table if exists event_proposal_comments cascade;
drop table if exists event_proposals cascade;

-- Notifications / Push / Weekly selection 관련 객체 (2026-04-22) — 방어적 drop
drop function if exists public.notify_on_new_proposal() cascade;
drop function if exists public.notify_on_proposal_comment() cascade;
drop function if exists public.notify_on_proposal_reviewed() cascade;
drop function if exists public.notify_on_new_event() cascade;
drop function if exists public.notify_quiz_completed(uuid) cascade;
drop function if exists public.mark_notification_read(uuid) cascade;
drop function if exists public.mark_all_notifications_read() cascade;
drop function if exists public.mark_broadcast_read(uuid) cascade;
drop function if exists public.mark_all_broadcasts_read() cascade;
drop function if exists public.list_my_notifications(int, boolean) cascade;
drop function if exists public.unread_notification_count() cascade;
drop function if exists public.register_push_token(text, text, text) cascade;
drop function if exists public.unregister_push_token(text) cascade;
drop function if exists public.pick_weekly_character() cascade;
drop function if exists public.notify_weekly_progress() cascade;
drop function if exists public.dispatch_daily_quiz_push() cascade;
drop function if exists public._fire_push_broadcast(text, text, text, text) cascade;
drop function if exists public._push_after_broadcast() cascade;
drop function if exists public._notify_admins(text, text, text, text, jsonb, uuid) cascade;
drop function if exists public._seed_from_week_key(text) cascade;
drop table if exists broadcast_notification_reads cascade;
drop table if exists broadcast_notifications cascade;
drop table if exists notifications cascade;
drop table if exists user_push_tokens cascade;
drop table if exists weekly_character_selection cascade;

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

  -- 인물이 속한 시대(들). 인물 카드 화면(시대별 필터)이 이 값으로 1차 노출 대상을
  -- 결정한다. events.character_codes 는 "이 사건에 누가 등장했는가"의 사실 데이터를
  -- 그대로 보존하므로 변화산처럼 OT 인물이 NT 사건에 환상으로 나타나도 사건 데이터는
  -- 손상되지 않는다. 한 인물이 두 시대에 걸쳐 활동하면 배열에 여러 era code 를 둔다.
  era_codes text[] not null default '{}',
  created_at timestamptz not null default now()
);

-- events.title 은 GLOBAL UNIQUE — 로컬 번들이 `assets/story_images_thumbs/<title>/`
-- 디렉토리 이름으로 사용되기 때문에 같은 제목 두 개가 있으면 빌드 시 자산이
-- 충돌한다. submit_event_proposal 에서도 동일 검증을 미리 raise 한다.
create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  era_id uuid not null references eras(id),
  title text not null unique,
  summary text,
  story_scenes jsonb not null default '[]'::jsonb,
  scene_characters jsonb not null default '[]'::jsonb,
  character_codes text[] not null default '{}',
  bible_refs jsonb not null default '[]'::jsonb,
  start_year int,
  end_year int,
  time_precision text not null default 'approx',
  story_index int not null,

  -- v2 위치 모델 — landmarks.id (region/anchor/minor) FK. NOT NULL.
  -- FK 제약은 forward reference 를 피하기 위해 landmarks 테이블 정의 뒤
  -- ALTER TABLE 로 추가한다 (이 파일 마지막 부근).
  landmark_id uuid not null,

  -- 장면 이미지 Storage 경로 (proposal 승인 시 proposal-scenes/... 경로가 그대로
  -- 복사됨). 앱은 **로컬 assets/story_images_thumbs/<title>/scene_N.png 를 먼저
  -- 시도** 하고, 번들에 파일이 없을 때만 이 컬럼의 public URL 로 네트워크 로드.
  -- 캐논 이벤트(Makefile 파이프라인으로 만든 것들) 는 이 필드를 빈 배열로 두고
  -- 순수 로컬 로드를 쓴다.
  scene_image_paths text[] not null default '{}',

  video_url text,
  status text not null default 'published'
    check (status in ('draft', 'published')),
  -- Soft delete 마커. 비어있으면 활성(기본), 값이 있으면 사용자에게 숨김.
  -- 사역자의 삭제 제안이 승인되면 여기에 타임스탬프가 기록된다. quiz_questions /
  -- user_event_progress 의 ON DELETE CASCADE 로 인한 진도 유실을 막기 위해
  -- hard delete 대신 soft delete 를 사용한다. 모든 읽기는 events_ordered view
  -- 를 경유해 이 컬럼을 자동 필터한다.
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (era_id, story_index)
);

-- 활성 이벤트(not deleted) 만 빠르게 조회하기 위한 partial index.
create index if not exists idx_events_active on events (id) where deleted_at is null;

-- ----------------------------------------------------------------------------
-- landmarks: 시대별로 지도 위에 표시되는 성경 랜드마크 (정적 카탈로그)
-- ----------------------------------------------------------------------------
-- 예루살렘 성전 · 시내산 · 떨기나무 같은 핵심 장소를 이모지 + 이름으로 노출한다.
-- 시대(era_codes 배열) 단위로 묶여 있어 사용자가 시대를 선택하면 그 시대에 해당
-- 하는 랜드마크만 지도에 떠올라 시대별 무대 감각을 잡아 준다. events 와 별개의
-- 정적 카탈로그 — 시드는 assets/landmarks/landmarks.json →
-- tools/seed/build_landmarks_seed_sql.py → supabase/200_stories/landmarks_seed.sql.
-- v3 — region(영역) + 시각 마크(point 종류) 통합 단일 테이블.
-- alias_group 기능은 v3 에서 제거 (시대별 별개 landmark 로 자연 분리).
create table if not exists landmarks (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  emoji text not null default '📍',
  category text,
  -- v3 — lat/lng nullable. 비지리적 region (요한계시록 환상 등) 은 NULL 가능.
  -- 지리적 region 과 모든 non-region 마커는 채워져야 함 (앱 측에서 검증).
  lat double precision,
  lng double precision,
  -- v3 — 'region' 은 폴리곤 영역. 그 외 모두 시각 마크 (mountain/city/sea/...).
  -- v2 호환을 위해 'anchor', 'minor', 'point' 도 허용 (deprecated).
  kind text not null default 'city'
    check (kind in (
      'region',
      'mountain', 'city', 'sea', 'river', 'island',
      'palace', 'wilderness', 'holy_site', 'campsite',
      'anchor', 'minor', 'point'
    )),
  -- region 일 때만 채워짐. [[lat,lng], [lat,lng], ...] (시계/반시계 무관).
  polygon jsonb,
  -- non-region → 자기가 속한 region 의 landmark id. region 자체는 NULL.
  parent_landmark_id uuid references landmarks(id) on delete set null,
  -- (deprecated) v2 alias_group 기능 잔존 컬럼. v3 에서는 항상 NULL.
  alias_group_id uuid,
  display_priority int not null default 0,
  era_codes text[] not null default '{}',
  related_event_codes text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  -- region 은 polygon 필수 (단 비지리적 region 은 빈 배열도 허용).
  constraint landmarks_polygon_check check (
    (kind = 'region' and polygon is not null)
    or (kind <> 'region')
  ),
  -- region 은 parent_landmark_id NULL, 그 외는 parent 필수 (단 v2 'point' 호환).
  constraint landmarks_parent_check check (
    (kind = 'region' and parent_landmark_id is null)
    or (kind in ('anchor', 'minor', 'point'))
    or (kind not in ('region') and parent_landmark_id is not null)
  )
);
create index if not exists idx_landmarks_active on landmarks (id) where is_active = true;
create index if not exists idx_landmarks_era_codes_gin on landmarks using gin (era_codes);
create index if not exists idx_landmarks_kind on landmarks (kind);
create index if not exists idx_landmarks_parent on landmarks (parent_landmark_id);

-- events.landmark_id 의 FK 를 이제(landmarks 테이블 정의 후) 추가.
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_schema = 'public'
      and table_name = 'events'
      and constraint_name = 'events_landmark_id_fkey'
  ) then
    execute 'alter table events add constraint events_landmark_id_fkey '
            'foreign key (landmark_id) references landmarks(id) on delete restrict';
  end if;
end $$;
create index if not exists idx_events_landmark on events (landmark_id);

-- ----------------------------------------------------------------------------
-- era_boundaries: 시대별 거친 지리 영역 (지도 위 반투명 폴리곤)
-- ----------------------------------------------------------------------------
-- 사용자가 시대를 선택했을 때 그 시대 이야기가 펼쳐진 영역을 색깔 폴리곤으로
-- 보여 준다. 한 시대가 분리된 지역(예: 메소포타미아 + 가나안)을 포함하면
-- 여러 행으로 표현. polygon 은 jsonb 배열 [[lat, lng], [lat, lng], ...].
create table if not exists era_boundaries (
  id uuid primary key default gen_random_uuid(),
  era_id uuid not null references eras(id) on delete cascade,
  polygon_index int not null default 0,
  polygon jsonb not null,
  color text not null default '#FF8800',
  fill_opacity numeric(3,2) not null default 0.18,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (era_id, polygon_index)
);
create index if not exists idx_era_boundaries_era on era_boundaries (era_id);

-- Era 내 story_index 정렬 결과를 1..N rank 로 노출.
-- 어드민/외부 기여로 새 이야기가 끼어들어도 view 가 자동으로 재계산된다.
-- deleted_at IS NULL 필터를 걸어 soft-deleted 이야기는 앱 전체에서 제외된다.
create view events_ordered as
  select
    e.id, e.era_id, e.title, e.summary,
    e.story_scenes, e.scene_characters, e.character_codes,
    e.bible_refs, e.start_year, e.end_year, e.time_precision,
    e.story_index, e.scene_image_paths, e.status, e.deleted_at,
    e.created_at, e.landmark_id,
    -- v2 — 좌표/이름은 landmarks JOIN derived.
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

-- 인물별 첫 등장 era + 첫 등장 story_index 기준으로 era 안의 인물 순서를 동적 계산.
-- is_active = false 인 인물은 노출 대상에서 제외된다.
-- Soft-deleted 이벤트(deleted_at IS NOT NULL)는 인물 첫 등장 계산에서도 제외.
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
                  and e.deleted_at is null
    join eras er on er.id = e.era_id
    where p.is_active = true
      -- p.era_codes 가 비어있으면 후방 호환 통과, 값이 있으면 era code 매칭만 노출
      and (p.era_codes = '{}'::text[] or p.era_codes && array[er.code])
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
  with target_era as (
    select code from eras where id = p_era_id
  ),
  character_first as (
    select
      p.id as character_id,
      p.code as character_code,
      min(e.story_index) as first_story_index
    from characters p
    cross join target_era te
    join events e
      on e.character_codes @> array[p.code]
     and e.status = 'published'
     and e.deleted_at is null
     and e.era_id = p_era_id
    where p.is_active = true
      -- 인물 마스터의 era_codes 가 비어있지 않으면 era 소속 필터를 적용한다.
      -- 비어있으면 (legacy/시드 미반영) 후방 호환을 위해 통과시킨다.
      and (p.era_codes = '{}'::text[] or p.era_codes && array[te.code])
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

-- 주간 퀴즈 진행도 — 사용자/주차/사건 키. 퀴즈 탭의 진행도는 프로필의
-- user_event_progress 와 독립적. 다음 주에 같은 인물이 또 뽑히면 week_key 가
-- 달라져 처음부터 다시 풀어야 한다 (자동 reset).
create table if not exists weekly_quiz_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_key text not null,
  event_id uuid not null references events(id) on delete cascade,
  is_bible_read boolean not null default false,
  is_quiz_completed boolean not null default false,
  last_score_correct smallint,
  last_score_total smallint,
  updated_at timestamptz not null default now(),
  primary key (user_id, week_key, event_id)
);
create index if not exists idx_weekly_quiz_progress_user_week
  on weekly_quiz_progress (user_id, week_key);

-- 매일 퀴즈 — 1 row 가 한 문제. 4지선다 + 정답 + 해설.
create table if not exists daily_quiz (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  choice_1 text not null,
  choice_2 text not null,
  choice_3 text not null,
  choice_4 text not null,
  answer_index smallint not null check (answer_index between 1 and 4),
  explanation text not null,
  created_at timestamptz not null default now()
);

-- 매일 퀴즈 사용자 시도 — 한 사용자가 한 daily_quiz 에 한 번 답을 고른 기록.
-- 같은 daily_quiz 가 active 인 동안엔 같은 row 유지 (수정 불가). daily_quiz 가
-- 새로 등록되면 새 row 가 자연스럽게 생기므로 "초기화" 가 자동.
create table if not exists user_daily_quiz_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_quiz_id uuid not null references daily_quiz(id) on delete cascade,
  selected_index smallint not null check (selected_index between 1 and 4),
  is_correct boolean not null,
  created_at timestamptz not null default now(),
  primary key (user_id, daily_quiz_id)
);
create index if not exists idx_user_daily_quiz_attempts_user
  on user_daily_quiz_attempts (user_id);

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
create index if not exists idx_characters_era_codes_gin on characters using gin (era_codes);
create index if not exists idx_progress_user_completed on user_event_progress (user_id, is_completed);
create unique index if not exists uidx_quiz_event_order on quiz_questions (event_id, display_order);
create index if not exists idx_embed_ivfflat on search_embeddings using ivfflat (embedding vector_cosine_ops);
create index if not exists idx_bible_verses_lookup on bible_verses (translation, book_no, chapter_no, verse_no);
create index if not exists idx_user_notes_user_created on user_notes (user_id, created_at desc);
create index if not exists idx_user_saved_verses_user_created on user_saved_verses (user_id, created_at desc);
create index if not exists idx_user_intercessory_prayers_user_created on user_intercessory_prayers (user_id, created_at desc);
create index if not exists idx_user_intercessory_prayers_target on user_intercessory_prayers (target_user_id);

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
grant select on table landmarks to anon, authenticated;
grant select on table era_boundaries to anon, authenticated;
grant select on table bible_verses to anon, authenticated;
grant select on table quiz_questions to anon, authenticated;
grant select on table daily_quiz to anon, authenticated;
grant select on events_ordered to anon, authenticated;
grant select on character_eras to anon, authenticated;

grant select, insert, update on table user_event_progress to authenticated;
grant select, insert, update on table user_profiles to authenticated;
grant select, insert, delete on table user_intercessory_prayers to authenticated;
grant select, insert, update, delete on table user_notes to authenticated;
grant select, insert, delete on table user_saved_verses to authenticated;
grant select, insert, update, delete on table weekly_quiz_progress to authenticated;
grant select, insert, update on table user_daily_quiz_attempts to authenticated;

alter table eras enable row level security;
alter table characters enable row level security;
alter table events enable row level security;
alter table landmarks enable row level security;
alter table era_boundaries enable row level security;
alter table bible_verses enable row level security;
alter table quiz_questions enable row level security;
alter table daily_quiz enable row level security;
alter table user_event_progress enable row level security;
alter table user_profiles enable row level security;
alter table user_intercessory_prayers enable row level security;
alter table user_notes enable row level security;
alter table user_saved_verses enable row level security;
alter table weekly_quiz_progress enable row level security;
alter table user_daily_quiz_attempts enable row level security;

drop policy if exists eras_read_all on eras;
create policy eras_read_all on eras for select using (true);

drop policy if exists characters_read_active on characters;
create policy characters_read_active on characters for select using (is_active = true);

drop policy if exists events_read_published on events;
create policy events_read_published on events for select using (status = 'published');

drop policy if exists landmarks_read_active on landmarks;
create policy landmarks_read_active on landmarks for select using (is_active = true);

drop policy if exists era_boundaries_read_all on era_boundaries;
create policy era_boundaries_read_all on era_boundaries for select using (true);

drop policy if exists bible_verses_read_all on bible_verses;
create policy bible_verses_read_all on bible_verses for select using (true);

drop policy if exists daily_quiz_read_all on daily_quiz;
create policy daily_quiz_read_all on daily_quiz for select using (true);

drop policy if exists weekly_quiz_progress_read_own on weekly_quiz_progress;
create policy weekly_quiz_progress_read_own on weekly_quiz_progress
for select using (auth.uid() = user_id);

drop policy if exists weekly_quiz_progress_write_own on weekly_quiz_progress;
create policy weekly_quiz_progress_write_own on weekly_quiz_progress
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists user_daily_quiz_attempts_read_own on user_daily_quiz_attempts;
create policy user_daily_quiz_attempts_read_own on user_daily_quiz_attempts
for select using (auth.uid() = user_id);

drop policy if exists user_daily_quiz_attempts_write_own on user_daily_quiz_attempts;
create policy user_daily_quiz_attempts_write_own on user_daily_quiz_attempts
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

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

-- ============================================================================
-- Storage 버킷: 'proposal-general-images' — 일반 제안에 첨부된 이미지 (최대 5장).
--   경로 규칙: proposal-general-images/<user_id>/<draft_id>/<idx>.<ext>
--   쓰기 권한: 본인 폴더 (제출 전 pastor/admin 이 직접 업로드)
--   읽기 권한: public — 다른 사역자/관리자가 상세에서 봄.
-- ============================================================================
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'proposal-general-images', 'proposal-general-images', true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists proposal_general_images_public_read on storage.objects;
create policy proposal_general_images_public_read on storage.objects
for select using (bucket_id = 'proposal-general-images');

drop policy if exists proposal_general_images_insert_own on storage.objects;
create policy proposal_general_images_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'proposal-general-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_general_images_update_own on storage.objects;
create policy proposal_general_images_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'proposal-general-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'proposal-general-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists proposal_general_images_delete_own on storage.objects;
create policy proposal_general_images_delete_own on storage.objects
for delete to authenticated
using (
  bucket_id = 'proposal-general-images'
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
  p_landmark_id uuid,
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

  if p_landmark_id is null then
    raise exception 'p_landmark_id 는 필수입니다 (위치 모델 v2).';
  end if;
  if not exists (select 1 from landmarks where id = p_landmark_id) then
    raise exception '존재하지 않는 landmark_id: %', p_landmark_id;
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
    landmark_id, scene_image_paths, status
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
    p_landmark_id,
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
  int, int, text, uuid, text[]
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
  -- era_id 는 'general' 제안에서는 NULL. 'new' / 'delete' 에서는 NOT NULL
  -- (chk_era_id_required_unless_general 가 강제).
  era_id uuid references eras(id),
  title text not null,
  summary text,
  character_codes text[] not null default '{}',
  -- v2 위치 모델 — 'general' 타입에서는 NULL.
  landmark_id uuid references landmarks(id) on delete restrict,
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

  -- 새 이야기 제안에 포함되는 4지선다 퀴즈(1~3개). 각 요소 구조:
  --   { question, choices[4], answer_index(0~3), explanation }
  -- proposal_type='new' 일 때 1~3개 강제 (CHECK), 그 외 타입은 항상 빈 배열.
  -- 승인 시 approve_event_proposal 이 quiz_questions 테이블에 row 로 insert.
  quiz_questions jsonb not null default '[]'::jsonb,

  -- 제안 종류.
  --   'new'     : 새 이야기 만들기 (era_id, target NULL, scenes/quiz 필수)
  --   'delete'  : 기존 이야기 삭제 (target_event_id 필수). 승인 시 events.deleted_at
  --              이 set 되어 soft delete 된다 (CASCADE 로 인한 진도 유실 방지).
  --   'general' : 앱 전체에 대한 일반 제안 — title + summary(=본문) + image_paths
  --              (최대 5장). era_id/target NULL. 승인/거절은 status 만 갱신.
  proposal_type text not null default 'new',

  -- 'delete' 타입일 때 삭제 대상 이벤트를 가리킴. 'new'/'general' 에서는 NULL.
  target_event_id uuid references events(id) on delete set null,

  -- 'general' 제안에서 첨부 이미지 Storage 경로 (최대 5장).
  -- 'proposal-general-images/<uid>/<draft>/<idx>.<ext>' 형태.
  -- 'new'/'delete' 에서는 항상 빈 배열.
  image_paths text[] not null default '{}',

  after_story_index int,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_by_user_id uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  approved_event_id uuid references events(id) on delete set null,

  -- 승인된 제안의 이미지 자산이 로컬 assets/ 로 내려와 "고정" 된 시점.
  -- null = 아직 내려받지 않음(= Supabase Storage 로만 서빙 중) → sync 대상.
  -- non-null = 이미 로컬 번들에 포함됨(또는 운영자가 동기화 처리 완료).
  -- tools/supabase/sync_approved_proposal_assets.py 가 이 컬럼으로
  -- 처음 sync / 재sync 를 구분해 불필요한 네트워크 트래픽을 제거한다.
  synced_to_local_at timestamptz,

  -- 같은 era + 같은 after_story_index 에 다른 제안이 먼저 승인되어 이 제안의
  -- 위치 의미가 모호해진 시점. set 되면:
  --   - approve/reject RPC 가 거부 (제안자가 revise 할 때까지 락)
  --   - UI 가 빨간색 "수정 필요" 라벨 + 사유 안내
  -- 제안자가 revise_proposal_position RPC 로 새 위치/연도 제출 시 NULL 로 복구.
  position_invalidated_at timestamptz,
  position_invalidation_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- proposal_type 값 허용치
  constraint event_proposals_proposal_type_check
    check (proposal_type in ('new', 'delete', 'general')),

  -- type 별 target_event_id 강제. delete 만 NOT NULL, 나머지는 NULL.
  constraint chk_proposal_type_target check (
    (proposal_type = 'new' and target_event_id is null) or
    (proposal_type = 'delete' and target_event_id is not null) or
    (proposal_type = 'general' and target_event_id is null)
  ),

  -- 퀴즈 개수: new 는 1~3, delete/general 은 0
  constraint chk_quiz_count_by_type check (
    case proposal_type
      when 'new' then jsonb_array_length(quiz_questions) between 1 and 3
      when 'delete' then jsonb_array_length(quiz_questions) = 0
      when 'general' then jsonb_array_length(quiz_questions) = 0
      else false
    end
  ),

  -- era_id 필수 여부: 'general' 만 NULL 허용
  constraint chk_era_id_required_unless_general check (
    proposal_type = 'general' or era_id is not null
  ),

  -- 'general' 의 image_paths 는 최대 5장
  constraint chk_general_image_count check (
    proposal_type <> 'general' or coalesce(array_length(image_paths, 1), 0) <= 5
  )
);

-- 동일 이벤트에 pending 삭제 제안은 최대 1건. 2명이 동시에 같은 이야기를
-- 삭제하자고 낼 수 없도록 partial unique index 로 막는다.
create unique index if not exists uniq_pending_delete_target
  on event_proposals (target_event_id)
  where proposal_type = 'delete' and status = 'pending';

create index if not exists event_proposals_proposer_idx
  on event_proposals(proposer_user_id);
create index if not exists event_proposals_status_idx
  on event_proposals(status);
create index if not exists event_proposals_era_idx
  on event_proposals(era_id);
create index if not exists event_proposals_invalidated_idx
  on event_proposals(position_invalidated_at)
  where position_invalidated_at is not null;

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
  (public.is_pastor() or public.is_admin())
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

-- 제안 DELETE:
--   - admin 은 무조건 허용
--   - proposer 본인은 **승인되지 않은 상태**(pending / rejected) 에서만 삭제 가능.
--     승인된 제안은 이미 events 테이블에 published 로 반영됐으므로 원본
--     삭제는 "이력 보존 + 변경은 별도 프로세스" 원칙으로 막는다.
drop policy if exists event_proposals_delete_admin on event_proposals;
drop policy if exists event_proposals_delete_own_unapproved on event_proposals;
create policy event_proposals_delete_own_unapproved on event_proposals
for delete to authenticated
using (
  public.is_admin()
  or (proposer_user_id = auth.uid() and status <> 'approved')
);

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
  p_landmark_id uuid,
  p_start_year int,
  p_end_year int,
  p_time_precision text,
  p_bible_refs jsonb,
  p_story_scenes jsonb,
  p_scene_characters jsonb,
  p_scene_image_paths text[],
  p_scene_image_prompts text[],
  p_proposed_characters jsonb,
  p_quiz_questions jsonb,
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
  v_quiz_count int;
  v_quiz jsonb;
  v_choices jsonb;
  v_answer_index int;
  v_explanation text;
  v_question text;
begin
  if not (public.is_pastor() or public.is_admin()) then
    raise exception 'permission denied: pastor or admin role required';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'title is required';
  end if;

  -- 제목 충돌 사전 검증. events.title 은 UNIQUE 제약이라 승인 시에도 막히지만
  -- 사역자가 일찍 알도록 제출 단계에서 raise. (1) 활성 events 와 (2) 다른
  -- pending NEW 제안과 비교. 본인이 자기 제안을 수정하는 경우는 제외.
  if exists (
    select 1 from events
    where trim(lower(title)) = trim(lower(p_title))
      and deleted_at is null
  ) then
    raise exception '동일한 제목의 이야기가 이미 등록되어 있습니다: "%"', p_title;
  end if;
  if exists (
    select 1 from event_proposals
    where trim(lower(title)) = trim(lower(p_title))
      and proposal_type = 'new'
      and status = 'pending'
      and proposer_user_id <> auth.uid()
  ) then
    raise exception '동일한 제목의 다른 제안이 검토 대기 중입니다: "%"', p_title;
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

  -- 퀴즈 검증 (1~3개, 4지선다, 해설 필수).
  v_quiz_count := coalesce(jsonb_array_length(p_quiz_questions), 0);
  if v_quiz_count < 1 or v_quiz_count > 3 then
    raise exception 'quiz_questions count must be between 1 and 3 (got %)', v_quiz_count;
  end if;
  for v_quiz in
    select * from jsonb_array_elements(coalesce(p_quiz_questions, '[]'::jsonb))
  loop
    v_question := coalesce(v_quiz->>'question', '');
    v_choices := v_quiz->'choices';
    v_answer_index := coalesce((v_quiz->>'answer_index')::int, -1);
    v_explanation := coalesce(v_quiz->>'explanation', '');
    if trim(v_question) = '' then
      raise exception 'quiz question must not be empty';
    end if;
    if v_choices is null or jsonb_array_length(v_choices) <> 4 then
      raise exception 'quiz choices must be exactly 4 (got %)',
        coalesce(jsonb_array_length(v_choices), 0);
    end if;
    if v_answer_index < 0 or v_answer_index > 3 then
      raise exception 'quiz answer_index must be between 0 and 3 (got %)', v_answer_index;
    end if;
    if trim(v_explanation) = '' then
      raise exception 'quiz explanation must not be empty';
    end if;
  end loop;

  insert into event_proposals (
    proposal_type,
    proposer_user_id, era_id, title, summary, character_codes,
    landmark_id, start_year, end_year,
    time_precision, bible_refs, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts,
    proposed_characters,
    quiz_questions,
    after_story_index
  )
  values (
    'new',
    auth.uid(), p_era_id, p_title, p_summary, coalesce(p_character_codes, '{}'),
    p_landmark_id, p_start_year, p_end_year,
    coalesce(nullif(trim(p_time_precision), ''), 'approx'),
    coalesce(p_bible_refs, '[]'::jsonb),
    coalesce(p_story_scenes, '[]'::jsonb),
    coalesce(p_scene_characters, '[]'::jsonb),
    coalesce(p_scene_image_paths, '{}'),
    coalesce(p_scene_image_prompts, '{}'),
    coalesce(p_proposed_characters, '[]'::jsonb),
    coalesce(p_quiz_questions, '[]'::jsonb),
    p_after_story_index
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.submit_event_proposal(
  uuid, text, text, text[], uuid,
  int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
) to authenticated;

-- 6b) RPC: submit_delete_proposal (pastor 만) — 기존 이야기 삭제 제안 진입점.
-- target_event_id 를 받고 사유는 summary 컬럼에 저장. hard delete 대신
-- events.deleted_at 을 set 하는 soft delete 를 승인 RPC 가 수행한다.
drop function if exists public.submit_delete_proposal(uuid, text) cascade;
create or replace function public.submit_delete_proposal(
  p_target_event_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_era_id uuid;
  v_title text;
begin
  if not (public.is_pastor() or public.is_admin()) then
    raise exception 'permission denied: pastor or admin role required';
  end if;
  if p_target_event_id is null then
    raise exception 'target_event_id is required';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'reason is required';
  end if;

  select era_id, title into v_era_id, v_title
  from events
  where id = p_target_event_id and deleted_at is null;
  if v_era_id is null then
    raise exception 'target event not found or already deleted: %', p_target_event_id;
  end if;

  insert into event_proposals (
    proposal_type, target_event_id,
    proposer_user_id, era_id, title, summary,
    character_codes, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts,
    proposed_characters, quiz_questions, bible_refs
  )
  values (
    'delete', p_target_event_id,
    auth.uid(), v_era_id, v_title, p_reason,
    '{}', '[]'::jsonb, '[]'::jsonb,
    '{}', '{}',
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.submit_delete_proposal(uuid, text) to authenticated;

-- 7) RPC: approve_event_proposal (admin 만) — 제안을 events 에 published 로 반영
--    기존 insert_event_at_position 을 재사용해 era 내 뒤 인덱스 시프트까지 처리.
drop function if exists public.approve_event_proposal(uuid, int) cascade;
drop function if exists public.approve_event_proposal(uuid, int, jsonb) cascade;
create or replace function public.approve_event_proposal(
  p_proposal_id uuid,
  p_after_story_index_override int default null,
  p_character_active_overrides jsonb default '{}'::jsonb
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
  v_active_for_code boolean;
  v_existing_code text;
  v_quiz jsonb;
  v_quiz_choices jsonb;
  v_quiz_idx int;
  v_new_character_names text[] := '{}';
  v_broadcast_body text;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;

  -- events 의 AFTER INSERT 트리거(notify_on_new_event) 가 단순 "새 이야기"
  -- broadcast 를 자동 생성하지 않도록 트랜잭션 범위에서 suppress.
  -- 이 RPC 가 마지막에 신규 인물 정보까지 묶어서 broadcast row 1건을 직접 만든다.
  perform set_config('app.suppress_event_broadcast', 'true', true);

  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;
  if v_proposal.proposal_type <> 'new' then
    raise exception 'approve_event_proposal is only for proposal_type=new (got %). use approve_delete_proposal for deletions',
      v_proposal.proposal_type;
  end if;
  -- 위치가 무효화된(다른 제안이 같은 자리에 먼저 들어가서) 제안은 제안자가
  -- 새 위치를 정하기 전엔 승인할 수 없다. UI 에서도 버튼이 잠기지만 RPC 단에서
  -- 한 번 더 방어.
  if v_proposal.position_invalidated_at is not null then
    raise exception
      'proposal % needs position revision first (invalidated at %)',
      p_proposal_id, v_proposal.position_invalidated_at;
  end if;

  select code into v_era_code from eras where id = v_proposal.era_id;
  if v_era_code is null then
    raise exception 'era not found for proposal: %', v_proposal.era_id;
  end if;

  v_after := coalesce(p_after_story_index_override, v_proposal.after_story_index, 0);

  -- 1) "이 제안에서 새로 만든 캐릭터" 를 characters 에 upsert.
  --    p_character_active_overrides 는 { code: bool } 매핑. 관리자가 승인 다이얼로그
  --    에서 각 인물의 is_active 를 직접 결정한다 (기본은 true — 키 없으면 노출 ON).
  for v_proposed_char in
    select * from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb))
  loop
    v_code := v_proposed_char->>'code';
    v_name := v_proposed_char->>'name';
    v_storage_path := v_proposed_char->>'storage_path';
    -- description 우선순위:
    --   1) 사용자가 별도 입력한 한글 'description' (홈 화면 카드 표시용)
    --   2) 없으면 AI prompt 를 fallback (호환성)
    -- prompt 만 채우면 영문 + COMMON_STYLE 토큰이 사용자에게 노출되므로 비권장.
    v_description := coalesce(
      nullif(trim(v_proposed_char->>'description'), ''),
      v_proposed_char->>'prompt'
    );
    if coalesce(trim(v_code), '') = '' then
      continue;
    end if;
    v_active_for_code := coalesce(
      (p_character_active_overrides->>v_code)::boolean,
      true
    );
    insert into public.characters (
      code, name, description, avatar_storage_path, is_active
    )
    values (
      v_code,
      coalesce(nullif(trim(v_name), ''), v_code),
      v_description,
      v_storage_path,
      v_active_for_code
    )
    on conflict (code) do update set
      name = coalesce(nullif(trim(excluded.name), ''), public.characters.name),
      description = coalesce(excluded.description, public.characters.description),
      avatar_storage_path = coalesce(excluded.avatar_storage_path, public.characters.avatar_storage_path),
      is_active = v_active_for_code;

    -- "신규 활성화된" 인물만 broadcast 본문에 표시. 사용자에게 보일 이름이 없으면 code.
    if v_active_for_code then
      v_new_character_names := v_new_character_names ||
        coalesce(nullif(trim(v_name), ''), v_code);
    end if;
  end loop;

  -- 1b) "기존 캐릭터" 들도 override 가 들어왔으면 적용 — 이번 이야기 등장 인물의
  --     is_active 를 관리자가 새로 지정 가능. override 키 없으면 기존 값 유지.
  for v_existing_code in
    select unnest(v_proposal.character_codes)
  loop
    if v_existing_code is null then continue; end if;
    if not (p_character_active_overrides ? v_existing_code) then continue; end if;
    -- 신규로 위에서 이미 처리한 코드는 건너뛴다 (중복 update 회피).
    if exists (
      select 1
      from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb)) e
      where e->>'code' = v_existing_code
    ) then
      continue;
    end if;
    update public.characters
       set is_active = (p_character_active_overrides->>v_existing_code)::boolean
     where code = v_existing_code;
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
    v_proposal.landmark_id,
    v_proposal.scene_image_paths
  );

  -- 3) 퀴즈 insert — proposal 에 담긴 1~3개를 quiz_questions 로 풀어 넣는다.
  --    승인 시점에 choices 배열을 **랜덤으로 셔플** 하고 정답 인덱스를 다시 계산
  --    한다. 사역자가 제출 시 항상 1번째 자리에 정답을 두는 습관이 있어도
  --    실제 사용자에게는 위치가 분산돼 패턴이 안 잡힌다.
  --    display_order 는 배열 인덱스 (퀴즈 N개 사이 순서) 를 그대로 사용.
  v_quiz_idx := 0;
  declare
    v_shuffled jsonb;
    v_orig_answer int;
    v_new_answer int;
  begin
    for v_quiz in
      select * from jsonb_array_elements(coalesce(v_proposal.quiz_questions, '[]'::jsonb))
    loop
      v_quiz_choices := v_quiz->'choices';
      if v_quiz_choices is null or jsonb_array_length(v_quiz_choices) <> 4 then
        raise exception 'quiz[%] must have exactly 4 choices', v_quiz_idx;
      end if;
      v_orig_answer := coalesce((v_quiz->>'answer_index')::int, 0);
      if v_orig_answer < 0 or v_orig_answer > 3 then
        raise exception 'quiz[%] answer_index out of range (got %)',
          v_quiz_idx, v_orig_answer;
      end if;

      -- 셔플: 0..3 의 무작위 순열을 만들어 choices 를 재배치, 정답이 새로 어느
      -- 인덱스로 갔는지 추적. random() 기반이라 결정적이지 않으나 보안 목적은
      -- 아니라 충분.
      with perm as (
        select g, row_number() over (order by random()) - 1 as new_pos
        from generate_series(0, 3) g
      ),
      remap as (
        select
          jsonb_agg(v_quiz_choices->old.g order by perm.new_pos) as new_choices,
          max(case when old.g = v_orig_answer then perm.new_pos end) as new_answer
        from generate_series(0, 3) old(g)
        join perm on perm.g = old.g
      )
      select new_choices, new_answer into v_shuffled, v_new_answer from remap;

      insert into public.quiz_questions (
        event_id, question,
        choice_a, choice_b, choice_c, choice_d,
        answer_index, explanation, display_order
      )
      values (
        v_event_id,
        coalesce(v_quiz->>'question', ''),
        coalesce(v_shuffled->>0, ''),
        coalesce(v_shuffled->>1, ''),
        coalesce(v_shuffled->>2, ''),
        v_shuffled->>3,
        v_new_answer,
        coalesce(v_quiz->>'explanation', ''),
        v_quiz_idx
      );
      v_quiz_idx := v_quiz_idx + 1;
    end loop;
  end;

  update event_proposals
  set
    status = 'approved',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    approved_event_id = v_event_id
  where id = p_proposal_id;

  -- 4) 충돌 감지 — 같은 era 에서 같은 after_story_index 를 노린 다른 pending
  --    NEW 제안들을 "위치 재선택 필요" 상태로 invalidate.
  --
  --    왜 이게 필요한가: insert_event_at_position 이 v_after 다음 자리를
  --    차지하면서 그 뒤 모든 story_index 가 +1 시프트됐다. 다른 제안자가
  --    같은 v_after 를 골랐다면 그들의 의도(="원래 5번 다음")가 이제 "방금
  --    승인된 새 6번 다음" 이 되어 모호해진다. 또한 그 제안의 start/end_year
  --    이 새 6번 이벤트의 연도 범위와 겹치거나 어긋날 수 있어 위치+연도를
  --    제안자가 다시 결정해야 한다.
  --
  --    invalidate 된 제안은:
  --      - approve/reject RPC 가 거부 (제안자 revise 전엔 잠김)
  --      - UI 가 빨간 라벨로 "수정 필요" 노출
  --      - 알림 트리거가 제안자에게 푸시/인앱 통지
  declare
    v_invalidated_id uuid;
    v_reason text;
  begin
    v_reason := '같은 위치(' ||
      case when v_after = 0 then '맨 앞'
           else 'story_index ' || v_after::text || ' 다음' end ||
      ')에 다른 이야기 "' || coalesce(v_proposal.title, '') ||
      '" 이(가) 먼저 승인되었어요. 이 제안의 위치와 연도를 다시 골라주세요.';

    for v_invalidated_id in
      select id
      from event_proposals
      where era_id = v_proposal.era_id
        and proposal_type = 'new'
        and status = 'pending'
        and id <> p_proposal_id
        and position_invalidated_at is null
        and after_story_index is not distinct from v_proposal.after_story_index
    loop
      update event_proposals
      set
        position_invalidated_at = now(),
        position_invalidation_reason = v_reason
      where id = v_invalidated_id;
      -- 알림은 trg_notify_on_proposal_invalidated 트리거가 이 update 를 보고
      -- 자동 dispatch. 여기서는 row 만 갱신.
    end loop;
  end;

  -- 5) 사건 + 신규 활성화 인물을 한 건의 broadcast 로 합쳐 발송.
  --    suppress 플래그로 events 트리거가 자동 broadcast 를 만들지 않게 했으니
  --    여기서 우리가 정확한 본문을 만들어 INSERT 한다.
  --    이 INSERT 가 trg_push_after_broadcast → _fire_push_broadcast → send-push
  --    경로로 FCM 까지 자동 발송.
  if array_length(v_new_character_names, 1) is null then
    v_broadcast_body := '"' || coalesce(v_proposal.title, '제목 없음') ||
      '" 이야기를 확인해 보세요.';
  elsif array_length(v_new_character_names, 1) = 1 then
    v_broadcast_body := '"' || coalesce(v_proposal.title, '제목 없음') ||
      '" — 새 인물 ' || v_new_character_names[1] || ' 도 함께 만나봐요.';
  else
    v_broadcast_body := '"' || coalesce(v_proposal.title, '제목 없음') ||
      '" — 새 인물 ' || v_new_character_names[1] || ' 외 ' ||
      (array_length(v_new_character_names, 1) - 1)::text || '명도 함께 만나봐요.';
  end if;

  insert into broadcast_notifications (type, target_audience, title, body, deep_link, payload)
  values (
    'new_event', 'all',
    '새 이야기가 등록되었어요',
    v_broadcast_body,
    '/event/' || v_event_id::text,
    jsonb_build_object(
      'event_id', v_event_id,
      'event_title', v_proposal.title,
      'new_character_names', to_jsonb(v_new_character_names)
    )
  );

  return v_event_id;
end;
$$;
grant execute on function public.approve_event_proposal(uuid, int, jsonb) to authenticated;

-- 7b) RPC: approve_delete_proposal (admin 만) — 대상 이벤트 SOFT DELETE.
--
-- HARD DELETE 를 쓰지 않는 이유:
--   (a) target_event_id 의 FK 가 ON DELETE SET NULL 이라, events row 가 사라지면
--       proposal.target_event_id 가 NULL 로 세팅 → 즉시 chk_proposal_type_target
--       (delete ↔ target NOT NULL) CHECK 위반 (PostgrestException 23514).
--   (b) quiz_questions / user_event_progress 가 cascade 로 같이 사라지면
--       사용자 진도가 통째로 유실된다.
--
-- events_ordered 뷰가 deleted_at IS NULL 만 노출하므로 앱에서는 자동으로 숨김.
-- 캐릭터 비활성화 / 고아 이미지 정리는 의도적으로 하지 않는다 (재등록 가능성 보존).
-- 멱등성: 이미 deleted_at 이 set 인 이벤트는 다시 건드리지 않음.
drop function if exists public.approve_delete_proposal(uuid) cascade;
create or replace function public.approve_delete_proposal(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_event events%rowtype;
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
  if v_proposal.proposal_type <> 'delete' then
    raise exception 'approve_delete_proposal is only for proposal_type=delete (got %)',
      v_proposal.proposal_type;
  end if;
  if v_proposal.target_event_id is null then
    raise exception 'target_event_id is null for delete proposal %', p_proposal_id;
  end if;

  -- soft delete: idempotent (이미 deleted_at 인 경우는 noop)
  select * into v_event from events where id = v_proposal.target_event_id;
  if found and v_event.deleted_at is null then
    update events set deleted_at = now() where id = v_event.id;
  end if;

  update event_proposals
  set
    status = 'approved',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    approved_event_id = v_proposal.target_event_id
  where id = p_proposal_id;

  -- 호환성을 위해 키는 남기되, 정리 대상 없음을 의미하는 빈 배열 반환.
  return jsonb_build_object(
    'event_id', v_proposal.target_event_id,
    'scene_image_paths', '{}'::text[],
    'inactive_character_avatar_paths', '{}'::text[],
    'deleted_character_avatar_paths', '{}'::text[]
  );
end;
$$;
grant execute on function public.approve_delete_proposal(uuid) to authenticated;

-- 8) RPC: reject_event_proposal (admin 만) — note 와 함께 status='rejected'.
--
-- position_invalidated_at 가 set 인 제안은 거부할 수 없다 (제안자가 위치를 다시
-- 정한 다음에야 실제로 평가가 가능). UI 도 버튼을 잠그지만 RPC 단에서 한 번 더 방어.
--
-- 거절 시 storage cleanup: row 자체는 history 보존을 위해 남기되, **proposal-***
-- 버킷의 장면 이미지 + 새로 만든 캐릭터 이미지** 는 더 이상 쓰이지 않으므로
-- 클라이언트가 정리할 경로 묶음을 jsonb 로 반환. proposed_characters 의 storage_path
-- 는 같은 code 가 다른 활성 row(events.character_codes 또는 다른 pending 제안)
-- 에서 재사용 중일 때만 보존.
drop function if exists public.reject_event_proposal(uuid, text) cascade;
create or replace function public.reject_event_proposal(
  p_proposal_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_scene_paths text[];
  v_char_paths text[] := '{}';
  v_pc jsonb;
  v_code text;
  v_path text;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;

  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.position_invalidated_at is not null then
    raise exception
      'proposal % needs position revision first (invalidated at %)',
      p_proposal_id, v_proposal.position_invalidated_at;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;

  v_scene_paths := coalesce(v_proposal.scene_image_paths, '{}'::text[]);

  -- proposed_characters 의 storage_path 수집. 단, 같은 code 가 이미 published
  -- characters 테이블에 있거나 (= 다른 이야기에 정착) 다른 pending 제안에서
  -- 재사용 중이면 정리에서 제외.
  for v_pc in
    select * from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb))
  loop
    v_code := v_pc->>'code';
    v_path := v_pc->>'storage_path';
    if coalesce(trim(v_code), '') = '' or coalesce(trim(v_path), '') = '' then
      continue;
    end if;
    if exists (select 1 from characters where code = v_code) then
      continue;
    end if;
    if exists (
      select 1 from event_proposals ep, jsonb_array_elements(coalesce(ep.proposed_characters, '[]'::jsonb)) e
      where ep.id <> p_proposal_id
        and ep.status = 'pending'
        and e->>'code' = v_code
    ) then
      continue;
    end if;
    v_char_paths := array_append(v_char_paths, v_path);
  end loop;

  update event_proposals
  set
    status = 'rejected',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    review_note = p_note
  where id = p_proposal_id;

  return jsonb_build_object(
    'proposal_id', p_proposal_id,
    'scene_image_paths', v_scene_paths,
    'rejected_character_storage_paths', v_char_paths
  );
end;
$$;
grant execute on function public.reject_event_proposal(uuid, text) to authenticated;

-- 8a-1) RPC: submit_general_proposal (pastor + admin) — 앱 일반 제안 등록.
-- title + body(=summary) 필수, image_paths 최대 5장. era_id / target / scenes /
-- quizzes 모두 빈 값으로 들어간다.
drop function if exists public.submit_general_proposal(text, text, text[]) cascade;
create or replace function public.submit_general_proposal(
  p_title text,
  p_body text,
  p_image_paths text[]
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_paths text[];
begin
  if not (public.is_pastor() or public.is_admin()) then
    raise exception 'permission denied: pastor or admin role required';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'title is required';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'body is required';
  end if;
  v_paths := coalesce(p_image_paths, '{}'::text[]);
  if coalesce(array_length(v_paths, 1), 0) > 5 then
    raise exception 'image_paths must have at most 5 entries (got %)',
      array_length(v_paths, 1);
  end if;

  insert into event_proposals (
    proposal_type, proposer_user_id,
    era_id, title, summary,
    character_codes, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts,
    proposed_characters, quiz_questions, bible_refs,
    image_paths
  )
  values (
    'general', auth.uid(),
    null, p_title, p_body,
    '{}', '[]'::jsonb, '[]'::jsonb,
    '{}', '{}',
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
    v_paths
  )
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.submit_general_proposal(text, text, text[]) to authenticated;

-- 8a-2) RPC: approve_general_proposal (admin) — 단순 status 갱신.
drop function if exists public.approve_general_proposal(uuid) cascade;
create or replace function public.approve_general_proposal(p_proposal_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;
  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.proposal_type <> 'general' then
    raise exception 'approve_general_proposal is only for proposal_type=general (got %)',
      v_proposal.proposal_type;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;
  update event_proposals
  set status = 'approved',
      reviewed_by_user_id = auth.uid(),
      reviewed_at = now()
  where id = p_proposal_id;
end;
$$;
grant execute on function public.approve_general_proposal(uuid) to authenticated;

-- 8a-3) RPC: reject_general_proposal (admin) — 단순 status 갱신 + 사유.
drop function if exists public.reject_general_proposal(uuid, text) cascade;
create or replace function public.reject_general_proposal(
  p_proposal_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;
  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.proposal_type <> 'general' then
    raise exception 'reject_general_proposal is only for proposal_type=general (got %)',
      v_proposal.proposal_type;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;
  update event_proposals
  set status = 'rejected',
      reviewed_by_user_id = auth.uid(),
      reviewed_at = now(),
      review_note = p_note
  where id = p_proposal_id;
end;
$$;
grant execute on function public.reject_general_proposal(uuid, text) to authenticated;

-- 8b) RPC: revise_proposal_position — 제안자 본인이 invalidated 된 자기 제안의
--     위치/연도를 다시 결정. 성공 시 position_invalidated_at NULL 로 복구되어
--     관리자가 다시 approve/reject 가능.
--
--   인자:
--     p_proposal_id        — 자기 자신의 pending NEW 제안만 가능
--     p_after_story_index  — 새 위치 (era 안의 0..N — 0 은 맨 앞)
--     p_start_year/end_year — 새 연도 범위 (둘 다 NULL 이면 변경 안 함)
--
--   검증:
--     1) auth.uid() 가 proposer 본인이어야 함
--     2) 제안 상태가 pending + position_invalidated_at IS NOT NULL
--     3) p_after_story_index 가 같은 era 안의 활성 이벤트 카운트(N)를 초과하지 않음
--     4) start_year/end_year 가 새 위치 기준 prev/next 이벤트 연도와 정합
--        (prev.end_year <= start_year <= end_year <= next.start_year)
drop function if exists public.revise_proposal_position(uuid, int, int, int) cascade;
create or replace function public.revise_proposal_position(
  p_proposal_id uuid,
  p_after_story_index int,
  p_start_year int default null,
  p_end_year int default null,
  p_landmark_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_count int;
  v_prev_end int;
  v_next_start int;
  v_start int;
  v_end int;
  v_new_landmark_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then
    raise exception 'proposal not found: %', p_proposal_id;
  end if;
  if v_proposal.proposer_user_id <> auth.uid() then
    raise exception 'permission denied: only the proposer can revise';
  end if;
  if v_proposal.proposal_type <> 'new' then
    raise exception 'revise_proposal_position only applies to new proposals';
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'cannot revise non-pending proposal (status = %)',
      v_proposal.status;
  end if;
  if v_proposal.position_invalidated_at is null then
    raise exception 'proposal is not in revision-required state';
  end if;
  if p_after_story_index < 0 then
    raise exception 'p_after_story_index must be >= 0 (got %)', p_after_story_index;
  end if;

  v_new_landmark_id := coalesce(p_landmark_id, v_proposal.landmark_id);
  if v_new_landmark_id is null then
    raise exception 'landmark_id 는 필수입니다.';
  end if;
  if not exists (select 1 from landmarks where id = v_new_landmark_id) then
    raise exception '존재하지 않는 landmark_id: %', v_new_landmark_id;
  end if;

  -- 같은 era 의 활성 이벤트 개수 — after_story_index 가 그 이상이면 정의 불가.
  select count(*) into v_count
  from events
  where era_id = v_proposal.era_id
    and deleted_at is null
    and status = 'published';
  if p_after_story_index > v_count then
    raise exception
      'p_after_story_index (%) exceeds active event count (%) in era',
      p_after_story_index, v_count;
  end if;

  v_start := coalesce(p_start_year, v_proposal.start_year);
  v_end := coalesce(p_end_year, v_proposal.end_year);

  -- 새 위치 prev/next 의 연도 범위 — story_index 가 정확히 (after_story_index)
  -- 인 이벤트가 prev, story_index 가 그 다음으로 큰 이벤트가 next.
  -- p_after_story_index = 0 → prev 없음 (맨 앞 삽입).
  if p_after_story_index = 0 then
    v_prev_end := null;
  else
    select e.end_year into v_prev_end
    from events e
    where e.era_id = v_proposal.era_id
      and e.deleted_at is null
      and e.status = 'published'
      and e.story_index = p_after_story_index;
  end if;

  select e.start_year into v_next_start
  from events e
  where e.era_id = v_proposal.era_id
    and e.deleted_at is null
    and e.status = 'published'
    and e.story_index > p_after_story_index
  order by e.story_index
  limit 1;

  if v_start is not null and v_end is not null then
    if v_end < v_start then
      raise exception 'end_year (%) must be >= start_year (%)', v_end, v_start;
    end if;
    if v_prev_end is not null and v_start < v_prev_end then
      raise exception
        'start_year (%) must be >= previous event end_year (%)',
        v_start, v_prev_end;
    end if;
    if v_next_start is not null and v_end > v_next_start then
      raise exception
        'end_year (%) must be <= next event start_year (%)',
        v_end, v_next_start;
    end if;
  end if;

  update event_proposals
  set
    after_story_index = p_after_story_index,
    start_year = v_start,
    end_year = v_end,
    landmark_id = v_new_landmark_id,
    position_invalidated_at = null,
    position_invalidation_reason = null,
    updated_at = now()
  where id = p_proposal_id;
end;
$$;
grant execute on function public.revise_proposal_position(uuid, int, int, int, uuid)
  to authenticated;

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

-- =========================================================
-- Notifications / Push / Weekly character selection (2026-04-22)
-- =========================================================
-- 인앱 알림함(bell 아이콘 드롭다운)과 FCM 푸시 알림을 위한 스키마.
-- 상세 설계: docs/BACKEND.md §(Notifications & Push) 참조.

-- 1) notifications — 개인 알림 (Fan-out on Write)
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'proposal_comment',
    'proposal_comment_admin',
    'new_proposal_admin',
    'proposal_approved',
    'proposal_rejected',
    'quiz_completed'
  )),
  title text not null,
  body text,
  deep_link text,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user_created
  on notifications(user_id, created_at desc);
create index if not exists idx_notifications_user_unread
  on notifications(user_id, created_at desc) where read_at is null;
create index if not exists idx_notifications_created_at
  on notifications(created_at desc);

-- 2) broadcast_notifications — 공지 (Fan-out on Read)
-- 주간 인물/진도와 매일 퀴즈는 broadcast 를 거치지 않고 send-push 로 직접
-- 발송한다 (bell drop 에 안 쌓임). broadcast 는 인앱 알림함 + 푸시 둘 다 필요한
-- 케이스(새 이야기/인물 등록 등) 에만 사용.
create table if not exists broadcast_notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in (
    'new_event'
  )),
  target_audience text not null default 'all'
    check (target_audience in ('all', 'pastor_or_admin')),
  title text not null,
  body text,
  deep_link text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_broadcast_created
  on broadcast_notifications(created_at desc);

create table if not exists broadcast_notification_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  broadcast_id uuid not null references broadcast_notifications(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, broadcast_id)
);

create index if not exists idx_broadcast_reads_user
  on broadcast_notification_reads(user_id);

-- 3) user_push_tokens — 디바이스 FCM 토큰
create table if not exists user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('web', 'ios', 'android')),
  token text not null unique,
  device_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_tokens_user on user_push_tokens(user_id);

drop trigger if exists set_user_push_tokens_updated_at on user_push_tokens;
create trigger set_user_push_tokens_updated_at
before update on user_push_tokens
for each row execute function public.touch_updated_at();

-- 4) weekly_character_selection — 금주의 인물 단일 소스
create table if not exists weekly_character_selection (
  week_key text primary key,
  character_code text not null references characters(code),
  picked_at timestamptz not null default now()
);

-- GRANT + RLS
grant select, update on table notifications to authenticated;
grant select on table broadcast_notifications to authenticated;
grant select, insert on table broadcast_notification_reads to authenticated;
grant select, insert, update, delete on table user_push_tokens to authenticated;
grant select on table weekly_character_selection to authenticated;

-- 안전망: drop+create 만으로 비어있어야 정상이지만, 시드/마이그레이션 도중에
-- 트리거가 깨워 broadcast_notifications 가 채워지는 사고를 막기 위해 명시적
-- TRUNCATE 한 번. db_init 종료 시 알림 4종 테이블이 확실히 비어있도록 보장.
truncate table notifications restart identity cascade;
truncate table broadcast_notifications restart identity cascade;
truncate table broadcast_notification_reads restart identity cascade;
truncate table user_push_tokens restart identity cascade;
truncate table weekly_character_selection restart identity cascade;

alter table notifications enable row level security;
alter table broadcast_notifications enable row level security;
alter table broadcast_notification_reads enable row level security;
alter table user_push_tokens enable row level security;
alter table weekly_character_selection enable row level security;

drop policy if exists notifications_select_own on notifications;
create policy notifications_select_own on notifications
for select to authenticated using (auth.uid() = user_id);

drop policy if exists notifications_update_own on notifications;
create policy notifications_update_own on notifications
for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists broadcast_read_all on broadcast_notifications;
create policy broadcast_read_all on broadcast_notifications
for select to authenticated using (true);

drop policy if exists broadcast_reads_select_own on broadcast_notification_reads;
create policy broadcast_reads_select_own on broadcast_notification_reads
for select to authenticated using (auth.uid() = user_id);

drop policy if exists broadcast_reads_insert_own on broadcast_notification_reads;
create policy broadcast_reads_insert_own on broadcast_notification_reads
for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists push_tokens_all_own on user_push_tokens;
create policy push_tokens_all_own on user_push_tokens
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists weekly_char_read_all on weekly_character_selection;
create policy weekly_char_read_all on weekly_character_selection
for select to authenticated using (true);

-- 헬퍼: _notify_admins
create or replace function public._notify_admins(
  p_type text,
  p_title text,
  p_body text,
  p_deep_link text,
  p_payload jsonb,
  p_exclude_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into notifications (user_id, type, title, body, deep_link, payload)
  select u.id, p_type, p_title, p_body, p_deep_link,
         coalesce(p_payload, '{}'::jsonb)
  from auth.users u
  where (u.raw_app_meta_data ->> 'role') = 'admin'
    and (p_exclude_user_id is null or u.id <> p_exclude_user_id);
end;
$$;

-- 트리거: notify_on_new_proposal
create or replace function public.notify_on_new_proposal()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposer_nickname text;
begin
  select coalesce(nickname, '사역자') into v_proposer_nickname
  from user_profiles where user_id = new.proposer_user_id;

  perform public._notify_admins(
    'new_proposal_admin',
    '새 제안이 등록되었어요',
    coalesce(v_proposer_nickname, '사역자') || '님이 "' ||
      coalesce(new.title, '제목 없음') || '" 제안을 등록했어요.',
    '/proposal/' || new.id::text,
    jsonb_build_object(
      'proposal_id', new.id,
      'proposer_user_id', new.proposer_user_id,
      'title', new.title
    ),
    new.proposer_user_id
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_on_new_proposal on event_proposals;
create trigger trg_notify_on_new_proposal
after insert on event_proposals
for each row execute function public.notify_on_new_proposal();

-- 트리거: notify_on_proposal_comment
create or replace function public.notify_on_proposal_comment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_author_nickname text;
  v_author_is_admin boolean;
  v_body_preview text;
begin
  select * into v_proposal from event_proposals where id = new.proposal_id;
  if not found then return new; end if;

  select coalesce(nickname, '사용자') into v_author_nickname
  from user_profiles where user_id = new.author_user_id;

  v_author_is_admin := coalesce(
    (select (raw_app_meta_data ->> 'role') = 'admin'
       from auth.users where id = new.author_user_id),
    false
  );

  v_body_preview := substr(new.body, 1, 40);
  if length(new.body) > 40 then
    v_body_preview := v_body_preview || '…';
  end if;

  if v_proposal.proposer_user_id <> new.author_user_id then
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      v_proposal.proposer_user_id,
      'proposal_comment',
      '"' || coalesce(v_proposal.title, '제안') || '" 제안에 댓글이 달렸어요',
      coalesce(v_author_nickname, '사용자') || ': ' || v_body_preview,
      '/proposal/' || v_proposal.id::text,
      jsonb_build_object(
        'proposal_id', v_proposal.id,
        'comment_id', new.id,
        'author_user_id', new.author_user_id,
        'proposal_title', v_proposal.title
      )
    );
  end if;

  if not v_author_is_admin then
    perform public._notify_admins(
      'proposal_comment_admin',
      '"' || coalesce(v_proposal.title, '제안') || '" 제안에 댓글이 달렸어요',
      coalesce(v_author_nickname, '사용자') || ': ' || v_body_preview,
      '/proposal/' || v_proposal.id::text,
      jsonb_build_object(
        'proposal_id', v_proposal.id,
        'comment_id', new.id,
        'author_user_id', new.author_user_id,
        'proposal_title', v_proposal.title
      ),
      new.author_user_id
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_proposal_comment on event_proposal_comments;
create trigger trg_notify_on_proposal_comment
after insert on event_proposal_comments
for each row execute function public.notify_on_proposal_comment();

-- 트리거: notify_on_proposal_reviewed
create or replace function public.notify_on_proposal_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if old.status = new.status then return new; end if;
  if new.status not in ('approved', 'rejected') then return new; end if;

  if new.status = 'approved' then
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      new.proposer_user_id,
      'proposal_approved',
      '제안이 승인되었어요',
      '"' || coalesce(new.title, '제안') || '" 이(가) 이야기로 등록되었어요.',
      case when new.approved_event_id is not null
           then '/event/' || new.approved_event_id::text
           else '/proposal/' || new.id::text end,
      jsonb_build_object(
        'proposal_id', new.id,
        'event_id', new.approved_event_id,
        'proposal_title', new.title
      )
    );
  else
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      new.proposer_user_id,
      'proposal_rejected',
      '제안이 반려되었어요',
      coalesce(
        nullif(trim(new.review_note), ''),
        '"' || coalesce(new.title, '제안') || '" 이(가) 반려되었어요.'
      ),
      '/proposal/' || new.id::text,
      jsonb_build_object(
        'proposal_id', new.id,
        'proposal_title', new.title,
        'review_note', new.review_note
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_proposal_reviewed on event_proposals;
create trigger trg_notify_on_proposal_reviewed
after update on event_proposals
for each row execute function public.notify_on_proposal_reviewed();

-- 트리거: notify_on_proposal_invalidated — 다른 제안이 같은 위치에 먼저 승인되어
--   이 제안의 position_invalidated_at 이 set 된 순간, 제안자에게 인앱 + 푸시
--   알림을 보낸다. payload 의 deep_link 는 제안 상세로 가서 "위치 다시 선택"
--   버튼이 노출되도록 한다.
drop function if exists public.notify_on_proposal_invalidated() cascade;
create or replace function public.notify_on_proposal_invalidated()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- transition: NULL → non-null (set 된 순간만 알림). 재 invalidate(이미 set 된
  -- row 가 다시 update 되는 경우)는 스킵해 알림 폭탄 방지.
  if old.position_invalidated_at is not null then return new; end if;
  if new.position_invalidated_at is null then return new; end if;

  insert into notifications (user_id, type, title, body, deep_link, payload)
  values (
    new.proposer_user_id,
    'proposal_position_invalidated',
    '제안 위치 재선택이 필요해요',
    coalesce(
      nullif(trim(new.position_invalidation_reason), ''),
      '"' || coalesce(new.title, '제안') ||
      '" 의 위치가 다른 이야기 승인으로 이동했어요. 위치/연도를 다시 골라주세요.'
    ),
    '/proposal/' || new.id::text,
    jsonb_build_object(
      'proposal_id', new.id,
      'proposal_title', new.title,
      'reason', new.position_invalidation_reason
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_on_proposal_invalidated on event_proposals;
create trigger trg_notify_on_proposal_invalidated
after update of position_invalidated_at on event_proposals
for each row execute function public.notify_on_proposal_invalidated();

-- 트리거: notify_on_new_event
--
-- 직접 events 에 INSERT 가 일어나는 경로 (시드/관리자 SQL 등) 에서만 동작.
-- approve_event_proposal RPC 는 인물 정보까지 묶어서 broadcast row 를 직접 만들기
-- 때문에 세션 플래그 app.suppress_event_broadcast='true' 를 set 해 트리거가 자동
-- broadcast 를 만들지 않게 한다.
create or replace function public.notify_on_new_event()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if current_setting('app.suppress_event_broadcast', true) = 'true' then
    return new;
  end if;
  if coalesce(new.status, 'published') <> 'published' then
    return new;
  end if;

  insert into broadcast_notifications (type, target_audience, title, body, deep_link, payload)
  values (
    'new_event', 'all',
    '새 이야기가 등록되었어요',
    '"' || coalesce(new.title, '제목 없음') || '" 이야기를 확인해 보세요.',
    '/event/' || new.id::text,
    jsonb_build_object('event_id', new.id, 'event_title', new.title)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_on_new_event on events;
create trigger trg_notify_on_new_event
after insert on events
for each row execute function public.notify_on_new_event();

-- RPC: notify_quiz_completed
create or replace function public.notify_quiz_completed(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_event_title text;
  v_total_events int;
  v_completed_count int;
  v_percent int;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select title into v_event_title from events where id = p_event_id;
  select count(*) into v_total_events from events where status = 'published';
  select count(*) into v_completed_count
  from user_event_progress
  where user_id = auth.uid() and is_completed = true;

  v_percent := case when v_total_events > 0
    then (v_completed_count * 100 / v_total_events) else 0 end;

  insert into notifications (user_id, type, title, body, deep_link, payload)
  values (
    auth.uid(),
    'quiz_completed',
    '퀴즈를 완주했어요!',
    '"' || coalesce(v_event_title, '이야기') || '" 퀴즈 완료 — 전체 진도 ' ||
      v_percent || '%',
    '/event/' || p_event_id::text,
    jsonb_build_object(
      'event_id', p_event_id,
      'event_title', v_event_title,
      'progress_percent', v_percent,
      'completed_count', v_completed_count,
      'total_count', v_total_events
    )
  );
end;
$$;
grant execute on function public.notify_quiz_completed(uuid) to authenticated;

-- RPC: mark_* / list_* / count
create or replace function public.mark_notification_read(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update notifications set read_at = now()
  where id = p_id and user_id = auth.uid() and read_at is null;
$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void language sql security definer set search_path = public as $$
  update notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
$$;
grant execute on function public.mark_all_notifications_read() to authenticated;

create or replace function public.mark_broadcast_read(p_broadcast_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into broadcast_notification_reads (user_id, broadcast_id)
  values (auth.uid(), p_broadcast_id)
  on conflict (user_id, broadcast_id) do nothing;
$$;
grant execute on function public.mark_broadcast_read(uuid) to authenticated;

create or replace function public.mark_all_broadcasts_read()
returns void language sql security definer set search_path = public as $$
  insert into broadcast_notification_reads (user_id, broadcast_id)
  select auth.uid(), b.id
  from broadcast_notifications b
  where b.created_at > now() - interval '30 days'
    and (b.target_audience = 'all'
         or (b.target_audience = 'pastor_or_admin'
             and (public.is_pastor() or public.is_admin())))
  on conflict (user_id, broadcast_id) do nothing;
$$;
grant execute on function public.mark_all_broadcasts_read() to authenticated;

create or replace function public.list_my_notifications(
  p_limit int default 30,
  p_only_unread boolean default false
)
returns table (
  id uuid, source text, type text, title text, body text,
  deep_link text, payload jsonb, is_read boolean, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with personal as (
    select n.id, 'personal'::text as source, n.type, n.title, n.body,
           n.deep_link, n.payload, (n.read_at is not null) as is_read, n.created_at
    from notifications n
    where n.user_id = auth.uid()
      and n.created_at > now() - interval '30 days'
  ),
  bcast as (
    select b.id, 'broadcast'::text as source, b.type, b.title, b.body,
           b.deep_link, b.payload, (r.broadcast_id is not null) as is_read, b.created_at
    from broadcast_notifications b
    left join broadcast_notification_reads r
      on r.broadcast_id = b.id and r.user_id = auth.uid()
    where b.created_at > now() - interval '30 days'
      and (
        b.target_audience = 'all'
        or (b.target_audience = 'pastor_or_admin'
            and (public.is_pastor() or public.is_admin()))
      )
  ),
  combined as (select * from personal union all select * from bcast)
  select * from combined
  where (not p_only_unread) or (not is_read)
  order by created_at desc
  limit greatest(p_limit, 1);
$$;
grant execute on function public.list_my_notifications(int, boolean) to authenticated;

create or replace function public.unread_notification_count()
returns int language sql stable security definer set search_path = public as $$
  with personal as (
    select count(*) as c from notifications
    where user_id = auth.uid() and read_at is null
      and created_at > now() - interval '30 days'
  ),
  bcast as (
    select count(*) as c from broadcast_notifications b
    where b.created_at > now() - interval '30 days'
      and (
        b.target_audience = 'all'
        or (b.target_audience = 'pastor_or_admin'
            and (public.is_pastor() or public.is_admin()))
      )
      and not exists (
        select 1 from broadcast_notification_reads r
        where r.broadcast_id = b.id and r.user_id = auth.uid()
      )
  )
  select (
    coalesce((select c from personal), 0) + coalesce((select c from bcast), 0)
  )::int;
$$;
grant execute on function public.unread_notification_count() to authenticated;

-- RPC: register_push_token / unregister_push_token
create or replace function public.register_push_token(
  p_token text, p_platform text, p_device_label text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token is required'; end if;
  if p_platform not in ('web', 'ios', 'android') then
    raise exception 'invalid platform: %', p_platform;
  end if;

  insert into user_push_tokens (user_id, platform, token, device_label)
  values (auth.uid(), p_platform, p_token, p_device_label)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        device_label = coalesce(excluded.device_label, user_push_tokens.device_label),
        updated_at = now();
end;
$$;
grant execute on function public.register_push_token(text, text, text) to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from user_push_tokens
  where token = p_token and user_id = auth.uid();
$$;
grant execute on function public.unregister_push_token(text) to authenticated;

-- 금주 인물 — seed 포팅 + pick + 주중 진도 체크
create or replace function public._seed_from_week_key(p_key text)
returns bigint language plpgsql immutable as $$
declare v_acc bigint := 0; v_i int;
begin
  for v_i in 1..length(p_key) loop
    v_acc := ((v_acc * 31) + ascii(substr(p_key, v_i, 1))) & 2147483647;
  end loop;
  return v_acc;
end;
$$;

create or replace function public.pick_weekly_character()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_monday date; v_week_key text;
  v_character_code text; v_character_name text;
  v_active_count int; v_seed bigint; v_index int;
begin
  v_monday := date_trunc('week', now() at time zone 'utc')::date;
  v_week_key := v_monday::text;

  if exists (select 1 from weekly_character_selection where week_key = v_week_key) then
    return;
  end if;

  select count(*) into v_active_count from characters where is_active = true;
  if v_active_count = 0 then return; end if;

  v_seed := public._seed_from_week_key(v_week_key);
  v_index := (v_seed % v_active_count)::int;

  select code, name into v_character_code, v_character_name
  from characters where is_active = true
  order by code offset v_index limit 1;

  if v_character_code is null then return; end if;

  insert into weekly_character_selection (week_key, character_code)
  values (v_week_key, v_character_code);

  -- bell drop 에 쌓이지 않게 broadcast 를 거치지 않고 send-push 로 직접 발송.
  perform public._fire_push_broadcast(
    '이번주 금주의 인물',
    '이번주 인물은 "' || coalesce(v_character_name, v_character_code) ||
      '" 입니다. 함께 공부해봐요!',
    '/weekly',
    'weekly_character'
  );
end;
$$;
grant execute on function public.pick_weekly_character() to authenticated;

create or replace function public.notify_weekly_progress()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_week_key text; v_character_code text; v_character_name text;
  v_total_events int; v_avg_completed numeric; v_percent int;
begin
  v_week_key := date_trunc('week', now() at time zone 'utc')::date::text;

  select w.character_code, c.name into v_character_code, v_character_name
  from weekly_character_selection w
  join characters c on c.code = w.character_code
  where w.week_key = v_week_key;

  if v_character_code is null then return; end if;

  select count(*) into v_total_events
  from events
  where status = 'published' and character_codes @> array[v_character_code];
  if v_total_events = 0 then return; end if;

  select coalesce(avg(completed_per_user), 0) into v_avg_completed
  from (
    select count(*)::numeric / v_total_events * 100 as completed_per_user
    from user_event_progress p
    join events e on e.id = p.event_id
    where p.is_completed = true
      and e.character_codes @> array[v_character_code]
    group by p.user_id
  ) t;

  v_percent := round(v_avg_completed)::int;

  -- push-only — broadcast_notifications 에 row 안 만듦 (bell 안 쌓임).
  perform public._fire_push_broadcast(
    coalesce(v_character_name, v_character_code) || ' 공부 진도 ' || v_percent || '%',
    '금주 인물을 함께 공부해봐요. 남은 이야기를 마저 만나봐요!',
    '/weekly',
    'weekly_progress_check'
  );
end;
$$;
grant execute on function public.notify_weekly_progress() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Push 디스패치 인프라
-- ─────────────────────────────────────────────────────────────────────────
-- DB 트리거/스케줄에서 Edge Function `send-push` 를 호출하기 위한 헬퍼.
-- Vault 에 등록된 두 secret 을 사용:
--   * service_role_key — Edge Function 호출 시 Authorization 헤더
--   * supabase_url     — 프로젝트 URL (예: https://abc.supabase.co)
-- pg_net 확장이 활성화돼 있어야 동작 (Dashboard → Database → Extensions).
create or replace function public._fire_push_broadcast(
  p_title text,
  p_body text,
  p_deep_link text,
  p_type text
)
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_url text;
  v_service_role_key text;
  v_supabase_url text;
begin
  select decrypted_secret into v_service_role_key
    from vault.decrypted_secrets where name = 'service_role_key';
  select decrypted_secret into v_supabase_url
    from vault.decrypted_secrets where name = 'supabase_url';

  -- secret 누락 시 raise warning 후 silent return — 알림 실패가 트리거를 깨우는
  -- 트랜잭션(예: events INSERT) 자체를 막으면 안 되므로.
  if v_service_role_key is null or v_supabase_url is null then
    raise warning '[_fire_push_broadcast] Vault secrets missing (service_role_key/supabase_url) — push skipped';
    return;
  end if;

  v_url := rtrim(v_supabase_url, '/') || '/functions/v1/send-push';

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_role_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'broadcast', true,
      'title', p_title,
      'body', p_body,
      'deep_link', p_deep_link,
      'type', p_type,
      'target', 'all'
    )
  );
exception when others then
  raise warning '[_fire_push_broadcast] http_post failed: %', sqlerrm;
end;
$$;

-- broadcast_notifications row 가 만들어지면 자동으로 send-push 호출 → FCM 발송.
-- (bell drop 에 띄우면서 동시에 푸시도 가야 하는 알림 — 현재는 'new_event' 뿐.)
create or replace function public._push_after_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._fire_push_broadcast(
    new.title,
    new.body,
    new.deep_link,
    new.type
  );
  return new;
end;
$$;

drop trigger if exists trg_push_after_broadcast on broadcast_notifications;
create trigger trg_push_after_broadcast
after insert on broadcast_notifications
for each row execute function public._push_after_broadcast();

-- 매일 퀴즈 푸시 — KST 9시 (= UTC 0시) 에 가장 최신 daily_quiz 1건의 question 을
-- 본문에 담아 전체 사용자에게 push-only 발송. broadcast_notifications 안 거침.
-- 매일 KST 9시 cron 이 호출. daily_quiz 풀에서 random 1건을 뽑아 같은 내용으로
-- **새 row INSERT** → 새 daily_quiz_id 가 발급되므로 user_daily_quiz_attempts
-- (PK: user_id, daily_quiz_id) 가 자연스럽게 새 row 가 되어 사용자 입장에선
-- "어제 푼 결과가 사라지고 오늘 다시 풀 수 있는" 초기화가 자동으로 일어남.
-- 풀이 1건뿐이면 같은 문제가 또 보이지만, 그래도 PK 가 다르니 다시 풀 수 있다.
-- 다양화를 원하면 daily_quiz 시드에 sample 을 더 추가하면 됨.
create or replace function public.dispatch_daily_quiz_push()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_picked record;
  v_new_id uuid;
  v_body text;
begin
  -- 풀에서 random 1건 pick. cron 이 만든 옛 row 와 시드 row 가 섞여 있어도
  -- 모두 동일하게 풀로 취급 — 단순함 우선. 같은 quiz 가 자주 뽑히는 게
  -- 거슬리면 daily_quiz 에 시드 sample 을 추가하라.
  select question, choice_1, choice_2, choice_3, choice_4, answer_index, explanation
    into v_picked
    from daily_quiz
    order by random()
    limit 1;

  if v_picked.question is null then
    raise warning '[dispatch_daily_quiz_push] daily_quiz pool is empty — skipped';
    return;
  end if;

  -- 같은 content 로 새 row INSERT (created_at 자동 = now()). 새 PK 발급으로
  -- 클라이언트의 fetchLatestDailyQuiz 가 이 새 row 를 가져오게 되고
  -- user_daily_quiz_attempts 매핑도 자동 분리된다.
  insert into daily_quiz (
    question, choice_1, choice_2, choice_3, choice_4, answer_index, explanation
  )
  values (
    v_picked.question, v_picked.choice_1, v_picked.choice_2,
    v_picked.choice_3, v_picked.choice_4, v_picked.answer_index, v_picked.explanation
  )
  returning id into v_new_id;

  -- 푸시 본문 길이 제한(iOS ~178자) 고려해 길면 자른다.
  if length(v_picked.question) > 110 then
    v_body := substr(v_picked.question, 1, 107) || '...';
  else
    v_body := v_picked.question;
  end if;

  -- deep_link='/weekly' — 매일 퀴즈는 QuizTabPage 안의 한 섹션이라 weekly 화면을
  -- 그대로 연다. 클라이언트의 NotificationDeepLink.parse 는 weekly 만 인식.
  perform public._fire_push_broadcast(
    '오늘의 퀴즈가 도착했어요',
    v_body,
    '/weekly',
    'daily_quiz'
  );
end;
$$;
grant execute on function public.dispatch_daily_quiz_push() to authenticated;

-- pg_cron 스케줄 — 확장 활성화되어 있으면 등록.
-- 모든 시간은 KST 9시 = UTC 0시 기준.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
    from cron.job
    where jobname in (
      'daily-quiz-9am-kst',
      'weekly-character-monday',
      'weekly-progress-wed',
      'weekly-progress-fri'
    );

    perform cron.schedule(
      'daily-quiz-9am-kst',
      '0 0 * * *',
      $cmd$ select public.dispatch_daily_quiz_push(); $cmd$
    );
    perform cron.schedule(
      'weekly-character-monday',
      '0 0 * * 1',
      $cmd$ select public.pick_weekly_character(); $cmd$
    );
    perform cron.schedule(
      'weekly-progress-wed',
      '0 0 * * 3',
      $cmd$ select public.notify_weekly_progress(); $cmd$
    );
    perform cron.schedule(
      'weekly-progress-fri',
      '0 0 * * 5',
      $cmd$ select public.notify_weekly_progress(); $cmd$
    );
  end if;
end $$;
