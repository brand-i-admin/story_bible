-- =========================================================
-- Migration: Story proposal workflow (pastor role + event_proposals)
-- Date: 2026-04-21
-- =========================================================
-- 외부 기여자 제출 기능 폐기 후 도입된 "사역자(목회자) → 관리자 승인" 흐름.
-- db_init.sql 의 동일 섹션과 내용 일치. 이미 적용된 dev/prod DB 에는 이
-- 마이그레이션 파일을 돌려 증분 반영한다.
--
-- 안전 재실행: create if not exists / drop policy if exists / drop function if
-- exists 를 사용해 중복 실행해도 상태 수렴.
--
-- 상세 설계: docs/BACKEND.md §(Story proposal workflow) 참조.

begin;

-- 1) user_profiles.is_pastor 컬럼 추가
alter table user_profiles
  add column if not exists is_pastor boolean not null default false;

-- 2) is_pastor() 헬퍼 함수
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

-- 3) event_proposals 테이블
create table if not exists event_proposals (
  id uuid primary key default gen_random_uuid(),
  proposer_user_id uuid not null references auth.users(id) on delete cascade,
  era_id uuid not null references eras(id),
  title text not null,
  summary text,
  person_codes text[] not null default '{}',
  place_name text,
  lat double precision,
  lng double precision,
  start_year int,
  end_year int,
  time_precision text not null default 'approx',
  bible_refs jsonb not null default '[]'::jsonb,
  story_scenes jsonb not null default '[]'::jsonb,
  scene_persons jsonb not null default '[]'::jsonb,
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

-- 4) event_proposal_comments 테이블
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

drop policy if exists event_proposals_read on event_proposals;
create policy event_proposals_read on event_proposals
for select to authenticated
using (public.is_pastor() or public.is_admin());

drop policy if exists event_proposals_insert_pastor on event_proposals;
create policy event_proposals_insert_pastor on event_proposals
for insert to authenticated
with check (
  public.is_pastor()
  and proposer_user_id = auth.uid()
  and status = 'pending'
);

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

drop policy if exists event_proposals_delete_admin on event_proposals;
create policy event_proposals_delete_admin on event_proposals
for delete to authenticated
using (public.is_admin());

drop policy if exists event_proposal_comments_read on event_proposal_comments;
create policy event_proposal_comments_read on event_proposal_comments
for select to authenticated
using (public.is_pastor() or public.is_admin());

drop policy if exists event_proposal_comments_insert on event_proposal_comments;
create policy event_proposal_comments_insert on event_proposal_comments
for insert to authenticated
with check (
  (public.is_pastor() or public.is_admin())
  and author_user_id = auth.uid()
);

drop policy if exists event_proposal_comments_update_own on event_proposal_comments;
create policy event_proposal_comments_update_own on event_proposal_comments
for update to authenticated
using (author_user_id = auth.uid())
with check (author_user_id = auth.uid());

drop policy if exists event_proposal_comments_delete on event_proposal_comments;
create policy event_proposal_comments_delete on event_proposal_comments
for delete to authenticated
using (author_user_id = auth.uid() or public.is_admin());

-- 6) RPC: submit_event_proposal
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, int
) cascade;
create or replace function public.submit_event_proposal(
  p_era_id uuid,
  p_title text,
  p_summary text,
  p_person_codes text[],
  p_place_name text,
  p_lat double precision,
  p_lng double precision,
  p_start_year int,
  p_end_year int,
  p_time_precision text,
  p_bible_refs jsonb,
  p_story_scenes jsonb,
  p_scene_persons jsonb,
  p_after_story_index int
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
begin
  if not public.is_pastor() then
    raise exception 'permission denied: pastor role required';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'title is required';
  end if;

  insert into event_proposals (
    proposer_user_id, era_id, title, summary, person_codes,
    place_name, lat, lng, start_year, end_year,
    time_precision, bible_refs, story_scenes, scene_persons,
    after_story_index
  )
  values (
    auth.uid(), p_era_id, p_title, p_summary, coalesce(p_person_codes, '{}'),
    p_place_name, p_lat, p_lng, p_start_year, p_end_year,
    coalesce(nullif(trim(p_time_precision), ''), 'approx'),
    coalesce(p_bible_refs, '[]'::jsonb),
    coalesce(p_story_scenes, '[]'::jsonb),
    coalesce(p_scene_persons, '[]'::jsonb),
    p_after_story_index
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, int
) to authenticated;

-- 7) RPC: approve_event_proposal
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

  v_event_id := public.insert_event_at_position(
    v_era_code,
    v_after,
    v_proposal.title,
    v_proposal.summary,
    v_proposal.story_scenes,
    v_proposal.scene_persons,
    v_proposal.person_codes,
    v_proposal.bible_refs,
    v_proposal.start_year,
    v_proposal.end_year,
    v_proposal.time_precision,
    v_proposal.place_name,
    v_proposal.lat,
    v_proposal.lng
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

-- 8) RPC: reject_event_proposal
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

-- 9) RPC: add_proposal_comment
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

commit;
