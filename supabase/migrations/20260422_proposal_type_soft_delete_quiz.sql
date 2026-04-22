-- =========================================================
-- Migration: Proposal type (new/delete) + soft delete events + quiz on proposal
-- Date: 2026-04-22
-- =========================================================
-- 배경:
--   기존 "새 이야기 제안" 외에 "기존 이야기 삭제 제안" 을 추가하고,
--   새 이야기 제안에는 4지선다 퀴즈 1~3개를 강제한다.
--   이야기 삭제는 hard delete 대신 soft delete(events.deleted_at) 로 처리해
--   quiz_questions / user_event_progress 등 FK 연쇄 삭제로 인한 사용자 진도
--   유실을 방지한다. events_ordered view 에 필터를 걸어 앱 전체가 자동으로
--   삭제된 이야기를 제외하도록 한다.
--
-- 체크 제약:
--   - proposal_type in ('new','delete'), 기본 'new'
--   - 'new'    ↔ target_event_id IS NULL, quiz 1~3개
--   - 'delete' ↔ target_event_id NOT NULL, quiz 0개
--   - 동일 target_event_id 에 pending delete 제안은 1건만 허용 (partial unique index)
--
-- 안전 재실행: create if not exists / drop ... if exists / or replace 사용.
-- CHECK 는 NOT VALID 로 추가해 기존 데이터(이전 제안들)를 검증 대상에서
-- 제외한다. 기존 pending 제안들은 지금 시점에 quiz 가 비어있을 수 있으므로
-- 운영에서 별도 정리 후 `ALTER ... VALIDATE CONSTRAINT` 수동 실행 권장.
--
-- 상세 설계: docs/BACKEND.md §(Story proposal workflow) + docs/ADR.md.

begin;

-- 1) event_proposals 확장 -------------------------------------------------
alter table event_proposals
  add column if not exists proposal_type text not null default 'new';

alter table event_proposals
  add column if not exists target_event_id uuid
    references events(id) on delete set null;

alter table event_proposals
  add column if not exists quiz_questions jsonb not null default '[]'::jsonb;

-- proposal_type 값 허용치
alter table event_proposals
  drop constraint if exists event_proposals_proposal_type_check;
alter table event_proposals
  add constraint event_proposals_proposal_type_check
  check (proposal_type in ('new', 'delete')) not valid;

-- new ↔ target 없음 / delete ↔ target 있음
alter table event_proposals
  drop constraint if exists chk_proposal_type_target;
alter table event_proposals
  add constraint chk_proposal_type_target check (
    (proposal_type = 'new' and target_event_id is null) or
    (proposal_type = 'delete' and target_event_id is not null)
  ) not valid;

-- 퀴즈 개수: new 는 1~3, delete 는 0
alter table event_proposals
  drop constraint if exists chk_quiz_count_by_type;
alter table event_proposals
  add constraint chk_quiz_count_by_type check (
    case proposal_type
      when 'new' then jsonb_array_length(quiz_questions) between 1 and 3
      when 'delete' then jsonb_array_length(quiz_questions) = 0
      else false
    end
  ) not valid;

-- 동일 이야기에 pending 삭제 제안 중복 방지 (partial unique index)
drop index if exists uniq_pending_delete_target;
create unique index uniq_pending_delete_target
  on event_proposals (target_event_id)
  where proposal_type = 'delete' and status = 'pending';

-- 2) events soft delete --------------------------------------------------
alter table events
  add column if not exists deleted_at timestamptz;

-- 활성 이벤트만 빠르게 조회
drop index if exists idx_events_active;
create index idx_events_active on events (id) where deleted_at is null;

-- 3) events_ordered view 재정의 ------------------------------------------
-- 기존: status='published' 만 포함. 추가: deleted_at IS NULL.
-- 이 view 를 경유하는 모든 앱 쿼리가 자동으로 삭제된 이야기를 제외한다.
drop view if exists events_ordered cascade;
create view events_ordered as
  select
    e.*,
    row_number() over (partition by e.era_id order by e.story_index) as rank_in_era,
    row_number() over (order by er.display_order, e.story_index) as global_rank
  from events e
  join eras er on er.id = e.era_id
  where e.status = 'published'
    and e.deleted_at is null;

-- 3b) character_eras view / list_characters_by_era RPC — 삭제된 이벤트가
-- "인물의 첫 등장" 후보가 되지 않도록 join 에 deleted_at IS NULL 추가.
drop view if exists character_eras cascade;
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
     and e.deleted_at is null
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
  join public.characters p on p.id = pf.character_id
  where p.is_active = true;
$$;
grant execute on function public.list_characters_by_era(uuid) to authenticated;

-- 4) submit_event_proposal 확장 — p_quiz_questions 파라미터 추가 ---------
-- 기존 signature 를 drop 하고, 새로 jsonb quiz 하나 더 받는 버전으로 교체.
-- `p_quiz_questions` 는 [{question, choices(4), answer_index, explanation}, ...]
-- 개수 1~3 + 4지선다 강제.
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
  if not public.is_pastor() then
    raise exception 'permission denied: pastor role required';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'title is required';
  end if;

  -- 장면 검증
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

  -- 퀴즈 검증 (1~3개, 4지선다, 해설 필수)
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
    place_name, lat, lng, start_year, end_year,
    time_precision, bible_refs, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts,
    proposed_characters,
    quiz_questions,
    after_story_index
  )
  values (
    'new',
    auth.uid(), p_era_id, p_title, p_summary, coalesce(p_character_codes, '{}'),
    p_place_name, p_lat, p_lng, p_start_year, p_end_year,
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
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
) to authenticated;

-- 5) submit_delete_proposal — 신규: 삭제 제안 전용 진입점 -----------------
-- target_event_id 를 받고 사유는 summary 컬럼에 저장 (review_note 와 혼동 피하기).
-- 정상 대상 이벤트만 제안 접수 (이미 soft-deleted 된 것은 거부).
-- 동일 target 에 pending 제안이 이미 있다면 partial unique index 가 위반을 던져
-- 자연스럽게 중복 제출 차단된다.
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
  if not public.is_pastor() then
    raise exception 'permission denied: pastor role required';
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

-- 6) approve_event_proposal — 퀴즈 insert 루프 추가 -----------------------
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
  v_quiz jsonb;
  v_quiz_choices jsonb;
  v_quiz_idx int;
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
  if v_proposal.proposal_type <> 'new' then
    raise exception 'approve_event_proposal is only for proposal_type=new (got %). use approve_delete_proposal for deletions',
      v_proposal.proposal_type;
  end if;

  select code into v_era_code from eras where id = v_proposal.era_id;
  if v_era_code is null then
    raise exception 'era not found for proposal: %', v_proposal.era_id;
  end if;

  v_after := coalesce(p_after_story_index_override, v_proposal.after_story_index, 0);

  -- 1) 새 캐릭터 upsert (기존 로직)
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

  -- 2) events insert
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

  -- 3) 퀴즈 insert — jsonb 배열 → quiz_questions rows
  v_quiz_idx := 0;
  for v_quiz in
    select * from jsonb_array_elements(coalesce(v_proposal.quiz_questions, '[]'::jsonb))
  loop
    v_quiz_choices := v_quiz->'choices';
    if v_quiz_choices is null or jsonb_array_length(v_quiz_choices) <> 4 then
      raise exception 'quiz[%] must have exactly 4 choices', v_quiz_idx;
    end if;
    insert into public.quiz_questions (
      event_id, question,
      choice_a, choice_b, choice_c, choice_d,
      answer_index, explanation, display_order
    )
    values (
      v_event_id,
      coalesce(v_quiz->>'question', ''),
      coalesce(v_quiz_choices->>0, ''),
      coalesce(v_quiz_choices->>1, ''),
      coalesce(v_quiz_choices->>2, ''),
      v_quiz_choices->>3,
      coalesce((v_quiz->>'answer_index')::int, 0),
      coalesce(v_quiz->>'explanation', ''),
      v_quiz_idx
    );
    v_quiz_idx := v_quiz_idx + 1;
  end loop;

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

-- 7) approve_delete_proposal — 신규: 대상 이벤트 soft delete + 제안 승인
drop function if exists public.approve_delete_proposal(uuid) cascade;
create or replace function public.approve_delete_proposal(
  p_proposal_id uuid
)
returns uuid
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

  -- 대상 이벤트 soft delete (idempotent: 이미 삭제된 경우 무시)
  update events
  set deleted_at = now()
  where id = v_proposal.target_event_id
    and deleted_at is null;

  update event_proposals
  set
    status = 'approved',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    approved_event_id = v_proposal.target_event_id
  where id = p_proposal_id;

  return v_proposal.target_event_id;
end;
$$;
grant execute on function public.approve_delete_proposal(uuid) to authenticated;

commit;
