-- 20260427_delete_proposal_storage_cleanup.sql
--
-- 목적: 이야기 삭제 제안이 승인될 때
--   1) events soft delete (기존)
--   2) 그 이벤트가 마지막 출연이었던 캐릭터를 is_active=false 로 비활성화 (신규)
--   3) 클라이언트가 정리할 storage 경로 묶음을 jsonb 로 반환 (신규: 반환 타입
--      uuid → jsonb 로 확장)
--
-- 클라이언트(`lib/data/proposal_repository.dart::approveDelete`)는 반환된
--   - scene_image_paths
--   - inactive_character_avatar_paths
-- 두 배열을 받아 best-effort 로 Supabase Storage 에서 제거한다 (이미 삭제되어
-- 있으면 무시).
--
-- 멱등성: 이미 deleted_at 이 set 인 이벤트나 is_active=false 인 캐릭터는 다시
-- 건드리지 않고 진행. 같은 RPC 가 재호출돼도 안전.

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
  v_inactive_paths text[] := '{}';
  v_scene_paths text[] := '{}';
  v_code text;
  v_other_count int;
  v_avatar_path text;
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

  select * into v_event from events where id = v_proposal.target_event_id;
  if not found then
    raise exception 'target event % not found', v_proposal.target_event_id;
  end if;
  v_scene_paths := coalesce(v_event.scene_image_paths, '{}'::text[]);

  update events
  set deleted_at = now()
  where id = v_event.id
    and deleted_at is null;

  foreach v_code in array coalesce(v_event.character_codes, '{}'::text[])
  loop
    select count(*) into v_other_count
    from events e
    where v_code = any(e.character_codes)
      and e.id <> v_event.id
      and e.deleted_at is null
      and e.status = 'published';

    if v_other_count = 0 then
      update characters
      set is_active = false
      where code = v_code
      returning avatar_storage_path into v_avatar_path;
      if v_avatar_path is not null and v_avatar_path <> '' then
        v_inactive_paths := array_append(v_inactive_paths, v_avatar_path);
      end if;
    end if;
  end loop;

  update event_proposals
  set
    status = 'approved',
    reviewed_by_user_id = auth.uid(),
    reviewed_at = now(),
    approved_event_id = v_event.id
  where id = p_proposal_id;

  return jsonb_build_object(
    'event_id', v_event.id,
    'scene_image_paths', v_scene_paths,
    'inactive_character_avatar_paths', v_inactive_paths
  );
end;
$$;
grant execute on function public.approve_delete_proposal(uuid) to authenticated;
