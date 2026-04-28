-- 20260427_proposal_position_invalidation.sql
--
-- 같은 era + 같은 after_story_index 에 두 개 이상의 NEW 제안이 pending 상태로
-- 들어와 있을 때, 한 쪽이 승인되면 나머지의 위치 의미가 모호해진다 (story_index
-- 시프트로 prev/next 이벤트가 달라지고 연도 정합성도 깨질 수 있음).
--
-- 해결: 충돌하는 다른 제안들을 "위치 재선택 필요" 상태로 잠그고, 제안자가
-- 새 위치/연도를 제출(revise_proposal_position RPC)하기 전엔 admin 의 approve/
-- reject 가 RPC 단에서 거부되도록 한다.
--
-- Schema:
--   alter event_proposals add columns:
--     position_invalidated_at timestamptz
--     position_invalidation_reason text
--   + partial index on position_invalidated_at IS NOT NULL
--
-- RPCs:
--   approve_event_proposal — 위치 invalidate 된 제안 거부 + 같은 era/after_idx
--                            를 노린 다른 pending 제안 invalidate 처리
--   reject_event_proposal  — 위치 invalidate 된 제안 거부
--   revise_proposal_position — 신규: 제안자 본인이 새 위치/연도 제출
--
-- Trigger:
--   notify_on_proposal_invalidated — invalidate 된 순간 제안자에게 인앱 알림.

-- 1) Schema
alter table event_proposals
  add column if not exists position_invalidated_at timestamptz,
  add column if not exists position_invalidation_reason text;

create index if not exists event_proposals_invalidated_idx
  on event_proposals(position_invalidated_at)
  where position_invalidated_at is not null;

-- 2) approve_event_proposal — 충돌 감지 추가 (반드시 db_init.sql 의 본문과 동기 유지).
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

  for v_proposed_char in
    select * from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb))
  loop
    v_code := v_proposed_char->>'code';
    v_name := v_proposed_char->>'name';
    v_storage_path := v_proposed_char->>'storage_path';
    v_description := coalesce(
      nullif(trim(v_proposed_char->>'description'), ''),
      v_proposed_char->>'prompt'
    );
    if coalesce(trim(v_code), '') = '' then continue; end if;
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
  end loop;

  for v_existing_code in
    select unnest(v_proposal.character_codes)
  loop
    if v_existing_code is null then continue; end if;
    if not (p_character_active_overrides ? v_existing_code) then continue; end if;
    if exists (
      select 1
      from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb)) e
      where e->>'code' = v_existing_code
    ) then continue; end if;
    update public.characters
       set is_active = (p_character_active_overrides->>v_existing_code)::boolean
     where code = v_existing_code;
  end loop;

  v_event_id := public.insert_event_at_position(
    v_era_code, v_after,
    v_proposal.title, v_proposal.summary, v_proposal.story_scenes,
    v_proposal.scene_characters, v_proposal.character_codes,
    v_proposal.bible_refs, v_proposal.start_year, v_proposal.end_year,
    v_proposal.time_precision, v_proposal.place_name, v_proposal.lat, v_proposal.lng,
    v_proposal.scene_image_paths
  );

  v_quiz_idx := 0;
  for v_quiz in
    select * from jsonb_array_elements(coalesce(v_proposal.quiz_questions, '[]'::jsonb))
  loop
    v_quiz_choices := v_quiz->'choices';
    if v_quiz_choices is null or jsonb_array_length(v_quiz_choices) <> 4 then
      raise exception 'quiz[%] must have exactly 4 choices', v_quiz_idx;
    end if;
    insert into public.quiz_questions (
      event_id, question, choice_a, choice_b, choice_c, choice_d,
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

  -- 충돌 감지 + invalidate (alias로 변수명 충돌 방지: v_invalidated_id, v_reason).
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
    end loop;
  end;

  return v_event_id;
end;
$$;
grant execute on function public.approve_event_proposal(uuid, int, jsonb) to authenticated;

-- 3) reject_event_proposal — invalidate 된 제안 거부 추가
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
declare
  v_invalidated_at timestamptz;
begin
  if not public.is_admin() then
    raise exception 'permission denied: admin role required';
  end if;

  select position_invalidated_at into v_invalidated_at
  from event_proposals where id = p_proposal_id;
  if v_invalidated_at is not null then
    raise exception
      'proposal % needs position revision first (invalidated at %)',
      p_proposal_id, v_invalidated_at;
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

-- 4) revise_proposal_position — 신규
drop function if exists public.revise_proposal_position(uuid, int, int, int) cascade;
create or replace function public.revise_proposal_position(
  p_proposal_id uuid,
  p_after_story_index int,
  p_start_year int default null,
  p_end_year int default null
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
    position_invalidated_at = null,
    position_invalidation_reason = null,
    updated_at = now()
  where id = p_proposal_id;
end;
$$;
grant execute on function public.revise_proposal_position(uuid, int, int, int)
  to authenticated;

-- 5) Trigger — invalidate 된 순간 제안자에게 알림
drop function if exists public.notify_on_proposal_invalidated() cascade;
create or replace function public.notify_on_proposal_invalidated()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
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
