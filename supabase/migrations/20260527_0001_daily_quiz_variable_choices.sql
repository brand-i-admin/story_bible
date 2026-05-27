-- Daily quiz variable choices + idempotent seed key.
--
-- db_init.sql is the source of truth for new environments. This migration is
-- the prod-safe patch for existing databases that still have choice_1..4.

begin;

alter table public.daily_quiz
  add column if not exists slug text;

alter table public.daily_quiz
  add column if not exists quiz_type text not null default 'general';

alter table public.daily_quiz
  add column if not exists choices jsonb;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'daily_quiz'
      and column_name = 'choice_1'
  ) then
    execute $sql$
      update public.daily_quiz
      set choices = jsonb_build_array(choice_1, choice_2, choice_3, choice_4)
      where choices is null
        and choice_1 is not null
        and choice_2 is not null
        and choice_3 is not null
        and choice_4 is not null
    $sql$;
  end if;
end $$;

alter table public.daily_quiz
  alter column choices set not null;

alter table public.daily_quiz
  drop constraint if exists daily_quiz_answer_index_check;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'daily_quiz_slug_key'
      and conrelid = 'public.daily_quiz'::regclass
  ) then
    alter table public.daily_quiz
      add constraint daily_quiz_slug_key unique (slug);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'chk_daily_quiz_type'
      and conrelid = 'public.daily_quiz'::regclass
  ) then
    alter table public.daily_quiz
      add constraint chk_daily_quiz_type check (
        quiz_type in (
          'general',
          'event_region_match',
          'region_event_exclusion',
          'character_region_exclusion',
          'character_event_region_match',
          'region_event_inclusion'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'chk_daily_quiz_choices'
      and conrelid = 'public.daily_quiz'::regclass
  ) then
    alter table public.daily_quiz
      add constraint chk_daily_quiz_choices check (
        jsonb_typeof(choices) = 'array'
        and jsonb_array_length(choices) between 2 and 6
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'chk_daily_quiz_answer_index'
      and conrelid = 'public.daily_quiz'::regclass
  ) then
    alter table public.daily_quiz
      add constraint chk_daily_quiz_answer_index check (
        answer_index between 1 and jsonb_array_length(choices)
      );
  end if;
end $$;

alter table public.daily_quiz
  drop column if exists choice_1,
  drop column if exists choice_2,
  drop column if exists choice_3,
  drop column if exists choice_4;

alter table public.user_daily_quiz_attempts
  drop constraint if exists user_daily_quiz_attempts_selected_index_check;

alter table public.user_daily_quiz_attempts
  add constraint user_daily_quiz_attempts_selected_index_check
  check (selected_index between 1 and 6);

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
    '/weekly',
    'daily_quiz'
  );
end;
$$;

grant execute on function public.dispatch_daily_quiz_push() to authenticated;

commit;
