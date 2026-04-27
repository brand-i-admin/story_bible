-- 20260427_proposal_lifecycle_overhaul.sql
--
-- 제안/승인 라이프사이클 종합 개편:
--   1) events.title GLOBAL UNIQUE — 로컬 번들이 `assets/story_images_thumbs/<title>/`
--      디렉토리 이름으로 사용
--   2) submit_event_proposal — 제목 충돌 사전 검증 + 모든 기존 검증 유지
--   3) approve_event_proposal — 퀴즈 choices 셔플 (승인 시점 random) + 충돌 감지
--   4) reject_event_proposal  — storage 정리 경로 jsonb 반환 (row 자체는 history 보존)
--   5) approve_delete_proposal — soft delete 폐기, HARD DELETE FROM events +
--      마지막 출연 캐릭터 row HARD DELETE
--
-- events.deleted_at / characters.is_active 컬럼은 backward-compat 위해 유지하되
-- 더 이상 신규 흐름에서 set 되지 않음.

-- 1) events.title UNIQUE
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'events_title_key' and conrelid = 'public.events'::regclass
  ) then
    alter table public.events add constraint events_title_key unique (title);
  end if;
end$$;

-- 2~3) submit + approve (NEW)
drop function if exists public.submit_event_proposal(
  uuid, text, text, text[], text,
  double precision, double precision, int, int, text,
  jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
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
language plpgsql security definer
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
    if trim(v_question) = '' then raise exception 'quiz question must not be empty'; end if;
    if v_choices is null or jsonb_array_length(v_choices) <> 4 then
      raise exception 'quiz choices must be exactly 4';
    end if;
    if v_answer_index < 0 or v_answer_index > 3 then
      raise exception 'quiz answer_index out of range';
    end if;
    if trim(v_explanation) = '' then raise exception 'quiz explanation must not be empty'; end if;
  end loop;

  insert into event_proposals (
    proposer_user_id, era_id, title, summary, character_codes,
    place_name, lat, lng, start_year, end_year, time_precision,
    bible_refs, story_scenes, scene_characters,
    scene_image_paths, scene_image_prompts, proposed_characters, quiz_questions,
    after_story_index
  ) values (
    auth.uid(), p_era_id, p_title, p_summary, coalesce(p_character_codes, '{}'),
    p_place_name, p_lat, p_lng, p_start_year, p_end_year,
    coalesce(p_time_precision, 'approx'),
    coalesce(p_bible_refs, '[]'::jsonb), p_story_scenes, p_scene_characters,
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
  uuid, text, text, text[], text, double precision, double precision,
  int, int, text, jsonb, jsonb, jsonb, text[], text[], jsonb, jsonb, int
) to authenticated;

-- 4) approve_event_proposal — Quiz 셔플 + 충돌 감지 포함 (db_init.sql 본문과 동기)
drop function if exists public.approve_event_proposal(uuid, int, jsonb) cascade;
create or replace function public.approve_event_proposal(
  p_proposal_id uuid,
  p_after_story_index_override int default null,
  p_character_active_overrides jsonb default '{}'::jsonb
)
returns uuid
language plpgsql security definer
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
  if not public.is_admin() then raise exception 'permission denied: admin role required'; end if;
  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found: %', p_proposal_id; end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;
  if v_proposal.proposal_type <> 'new' then
    raise exception 'approve_event_proposal is only for proposal_type=new (got %). use approve_delete_proposal for deletions',
      v_proposal.proposal_type;
  end if;
  if v_proposal.position_invalidated_at is not null then
    raise exception 'proposal % needs position revision first (invalidated at %)',
      p_proposal_id, v_proposal.position_invalidated_at;
  end if;

  select code into v_era_code from eras where id = v_proposal.era_id;
  if v_era_code is null then raise exception 'era not found: %', v_proposal.era_id; end if;

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
      (p_character_active_overrides->>v_code)::boolean, true
    );
    insert into public.characters (code, name, description, avatar_storage_path, is_active)
    values (
      v_code, coalesce(nullif(trim(v_name), ''), v_code),
      v_description, v_storage_path, v_active_for_code
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
      select 1 from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb)) e
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

  -- 퀴즈 INSERT — choices 셔플 + answer_index 재계산
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
        raise exception 'quiz[%] answer_index out of range', v_quiz_idx;
      end if;
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
        event_id, question, choice_a, choice_b, choice_c, choice_d,
        answer_index, explanation, display_order
      ) values (
        v_event_id, coalesce(v_quiz->>'question', ''),
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
  set status='approved', reviewed_by_user_id=auth.uid(), reviewed_at=now(), approved_event_id=v_event_id
  where id = p_proposal_id;

  -- 같은 era + 같은 after_story_index 의 다른 pending NEW 들을 invalidate
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
      select id from event_proposals
      where era_id = v_proposal.era_id
        and proposal_type = 'new' and status = 'pending'
        and id <> p_proposal_id
        and position_invalidated_at is null
        and after_story_index is not distinct from v_proposal.after_story_index
    loop
      update event_proposals
      set position_invalidated_at = now(), position_invalidation_reason = v_reason
      where id = v_invalidated_id;
    end loop;
  end;

  return v_event_id;
end;
$$;
grant execute on function public.approve_event_proposal(uuid, int, jsonb) to authenticated;

-- 5) reject_event_proposal — storage cleanup paths 반환
drop function if exists public.reject_event_proposal(uuid, text) cascade;
create or replace function public.reject_event_proposal(
  p_proposal_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql security definer
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
  if not public.is_admin() then raise exception 'permission denied: admin role required'; end if;
  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found: %', p_proposal_id; end if;
  if v_proposal.position_invalidated_at is not null then
    raise exception 'proposal % needs position revision first (invalidated at %)',
      p_proposal_id, v_proposal.position_invalidated_at;
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal is not pending (status = %)', v_proposal.status;
  end if;

  v_scene_paths := coalesce(v_proposal.scene_image_paths, '{}'::text[]);
  for v_pc in
    select * from jsonb_array_elements(coalesce(v_proposal.proposed_characters, '[]'::jsonb))
  loop
    v_code := v_pc->>'code';
    v_path := v_pc->>'storage_path';
    if coalesce(trim(v_code), '') = '' or coalesce(trim(v_path), '') = '' then continue; end if;
    if exists (select 1 from characters where code = v_code) then continue; end if;
    if exists (
      select 1 from event_proposals ep, jsonb_array_elements(coalesce(ep.proposed_characters, '[]'::jsonb)) e
      where ep.id <> p_proposal_id
        and ep.status = 'pending'
        and e->>'code' = v_code
    ) then continue; end if;
    v_char_paths := array_append(v_char_paths, v_path);
  end loop;

  update event_proposals
  set status='rejected', reviewed_by_user_id=auth.uid(), reviewed_at=now(), review_note=p_note
  where id = p_proposal_id;

  return jsonb_build_object(
    'proposal_id', p_proposal_id,
    'scene_image_paths', v_scene_paths,
    'rejected_character_storage_paths', v_char_paths
  );
end;
$$;
grant execute on function public.reject_event_proposal(uuid, text) to authenticated;

-- 6) approve_delete_proposal — HARD DELETE 모드
drop function if exists public.approve_delete_proposal(uuid) cascade;
create or replace function public.approve_delete_proposal(
  p_proposal_id uuid
)
returns jsonb
language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_event events%rowtype;
  v_deleted_char_paths text[] := '{}';
  v_scene_paths text[] := '{}';
  v_codes text[] := '{}';
  v_code text;
  v_other_count int;
  v_avatar_path text;
begin
  if not public.is_admin() then raise exception 'permission denied: admin role required'; end if;
  select * into v_proposal from event_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found: %', p_proposal_id; end if;
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

  select * into v_event from events where id = v_proposal.target_event_id;
  if found then
    v_scene_paths := coalesce(v_event.scene_image_paths, '{}'::text[]);
    v_codes := coalesce(v_event.character_codes, '{}'::text[]);
    delete from events where id = v_event.id;
  end if;

  foreach v_code in array v_codes
  loop
    select count(*) into v_other_count
    from events e where v_code = any(e.character_codes);
    if v_other_count = 0 then
      delete from characters where code = v_code
      returning avatar_storage_path into v_avatar_path;
      if v_avatar_path is not null and v_avatar_path <> '' then
        v_deleted_char_paths := array_append(v_deleted_char_paths, v_avatar_path);
      end if;
    end if;
  end loop;

  update event_proposals
  set status='approved', reviewed_by_user_id=auth.uid(), reviewed_at=now(), approved_event_id=null
  where id = p_proposal_id;

  return jsonb_build_object(
    'event_id', v_proposal.target_event_id,
    'scene_image_paths', v_scene_paths,
    'deleted_character_avatar_paths', v_deleted_char_paths
  );
end;
$$;
grant execute on function public.approve_delete_proposal(uuid) to authenticated;
