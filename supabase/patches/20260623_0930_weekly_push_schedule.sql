begin;

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
    '이번 주 퀴즈가 열렸어요',
    '이번 주는 "' || coalesce(v_character_name, v_character_code) ||
      '" 이야기와 함께 걸어요. 주간 퀴즈를 시작해 보세요.',
    '/weekly',
    'weekly_quiz'
  );
end;
$$;
grant execute on function public.pick_weekly_character() to authenticated;

create or replace function public.notify_weekly_diary_reflection()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._fire_push_broadcast(
    '이번 주 다이어리 묵상 시간',
    '이번 주 나의 다이어리를 다시 묵상하면서 신앙을 정리해보는 건 어떨까요?',
    '/profile',
    'weekly_diary_reflection'
  );
end;
$$;
grant execute on function public.notify_weekly_diary_reflection() to authenticated;

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
  select quiz_type, question, choices, answer_index, explanation
    into v_picked
    from daily_quiz
    order by random()
    limit 1;

  if v_picked.question is null then
    raise warning '[dispatch_daily_quiz_push] daily_quiz pool is empty — skipped';
    return;
  end if;

  insert into daily_quiz (quiz_type, question, choices, answer_index, explanation)
  values (
    v_picked.quiz_type,
    v_picked.question,
    v_picked.choices,
    v_picked.answer_index,
    v_picked.explanation
  )
  returning id into v_new_id;

  if length(v_picked.question) > 110 then
    v_body := substr(v_picked.question, 1, 107) || '...';
  else
    v_body := v_picked.question;
  end if;

  perform public._fire_push_broadcast(
    '오늘의 퀴즈가 도착했어요',
    v_body,
    '/daily-quiz',
    'daily_quiz'
  );
end;
$$;
grant execute on function public.dispatch_daily_quiz_push() to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
    from cron.job
    where jobname in (
      'daily-quiz-9am-kst',
      'weekly-character-monday',
      'weekly-progress-wed',
      'weekly-progress-fri',
      'weekly-quiz-monday-9am-kst',
      'daily-quiz-wednesday-9am-kst',
      'diary-reflection-friday-9am-kst'
    );

    perform cron.schedule(
      'weekly-quiz-monday-9am-kst',
      '0 0 * * 1',
      $cmd$ select public.pick_weekly_character(); $cmd$
    );
    perform cron.schedule(
      'daily-quiz-wednesday-9am-kst',
      '0 0 * * 3',
      $cmd$ select public.dispatch_daily_quiz_push(); $cmd$
    );
    perform cron.schedule(
      'diary-reflection-friday-9am-kst',
      '0 0 * * 5',
      $cmd$ select public.notify_weekly_diary_reflection(); $cmd$
    );
  end if;
end $$;

drop function if exists public.notify_weekly_progress() cascade;

commit;
