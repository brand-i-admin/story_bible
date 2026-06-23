begin;

drop table if exists public.user_daily_quiz_attempts cascade;
drop table if exists public.daily_quiz cascade;
drop table if exists public.weekly_quiz_progress cascade;
drop function if exists public.dispatch_daily_quiz_push() cascade;

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

  perform public._fire_push_broadcast(
    '이번 주 탐험이 열렸어요',
    '이번 주는 "' || coalesce(v_character_name, v_character_code) ||
      '" 이야기와 함께 걸어요. 주간 탐험을 시작해 보세요.',
    '/weekly',
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
declare
  v_now_kst timestamp;
  v_day_key text;
  v_count int;
  v_seed bigint;
  v_offset int;
  v_event_title text;
begin
  v_now_kst := now() at time zone 'Asia/Seoul';
  v_day_key :=
    extract(year from v_now_kst)::int || '-' ||
    extract(month from v_now_kst)::int || '-' ||
    extract(day from v_now_kst)::int;

  select count(*)
    into v_count
    from events_ordered e
    join eras er on er.id = e.era_id
    where er.code <> 'era_nt_consummation';

  if coalesce(v_count, 0) > 0 then
    v_seed := public._seed_from_week_key('daily-exploration:' || v_day_key);
    v_offset := (v_seed % v_count)::int;

    select e.title
      into v_event_title
      from events_ordered e
      join eras er on er.id = e.era_id
      where er.code <> 'era_nt_consummation'
      order by e.global_rank, e.id
      offset v_offset
      limit 1;
  end if;

  perform public._fire_push_broadcast(
    '오늘의 탐험이 열렸어요',
    '「' || coalesce(v_event_title, '오늘 도착한 성경 사건') ||
      '」 사건을 함께 탐험해봐요.',
    '/daily-exploration',
    'daily_exploration'
  );
end;
$$;
grant execute on function public.dispatch_daily_exploration_push() to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
    from cron.job
    where jobname in (
      'daily-quiz-9am-kst',
      'daily-exploration-wednesday-9am-kst',
      'weekly-character-monday',
      'weekly-exploration-monday-9am-kst',
      'weekly-progress-wed',
      'weekly-progress-fri',
      'weekly-quiz-monday-9am-kst',
      'daily-quiz-wednesday-9am-kst',
      'diary-reflection-friday-9am-kst'
    );

    perform cron.schedule(
      'weekly-exploration-monday-9am-kst',
      '0 0 * * 1',
      $cmd$ select public.pick_weekly_character(); $cmd$
    );
    perform cron.schedule(
      'daily-exploration-wednesday-9am-kst',
      '0 0 * * 3',
      $cmd$ select public.dispatch_daily_exploration_push(); $cmd$
    );
    perform cron.schedule(
      'diary-reflection-friday-9am-kst',
      '0 0 * * 5',
      $cmd$ select public.notify_weekly_diary_reflection(); $cmd$
    );
  end if;
end $$;

commit;
