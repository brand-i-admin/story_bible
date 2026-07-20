-- 월요일의 주간 미션 푸시와 수요일의 일일 미션 푸시 문구를
-- 동행 격려 및 이야기 탐험 안내로 교체한다.

create or replace function public.pick_weekly_character()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_monday date;
  v_week_key text;
  v_character_code text;
  v_active_count int;
  v_seed bigint;
  v_index int;
begin
  v_monday := date_trunc('week', now() at time zone 'utc')::date;
  v_week_key := v_monday::text;

  if exists (
    select 1 from weekly_character_selection where week_key = v_week_key
  ) then
    return;
  end if;

  select count(*)
    into v_active_count
    from characters
    where is_active = true;
  if v_active_count = 0 then return; end if;

  v_seed := public._seed_from_week_key(v_week_key);
  v_index := (v_seed % v_active_count)::int;

  select code
    into v_character_code
    from characters
    where is_active = true
    order by code
    offset v_index
    limit 1;

  if v_character_code is null then return; end if;

  insert into weekly_character_selection (week_key, character_code)
  values (v_week_key, v_character_code);

  -- push-only: bell 알림함에는 쌓지 않는다.
  perform public._fire_push_broadcast(
    '좋은 한주의 시작입니다!',
    '이번주도 하나님과 친밀한 동행하는 한주 되세요!',
    null,
    'weekly_exploration'
  );
end;
$$;

grant execute on function public.pick_weekly_character() to authenticated;

create or replace function public.dispatch_daily_exploration_push()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- push-only: bell 알림함에는 쌓지 않는다.
  perform public._fire_push_broadcast(
    '한주도 잘 보내고 계신가요!?',
    '이야기 탐험으로 하나님의 이야기를 탐험해보세요!',
    '/daily-exploration',
    'daily_exploration'
  );
end;
$$;

grant execute on function public.dispatch_daily_exploration_push()
  to authenticated;
