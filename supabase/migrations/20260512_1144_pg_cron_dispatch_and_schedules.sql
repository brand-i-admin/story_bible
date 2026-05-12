-- 20260512_1144_pg_cron_dispatch_and_schedules.sql
--
-- 매일 퀴즈 자동 발급 함수 + pg_cron 4개 스케줄 등록.
--
-- 배경 (ADR-022, ADR-023):
--   ADR-022 에서 dispatch_daily_quiz_push() 함수 + pg_cron 스케줄을
--   db_init.sql 에 추가했으나, 옛 정책상 prod 에 자동 반영되지 않아 KST 9시
--   매일 새 quiz row 발급이 누락됐다. 사용자가 어제 답한 quiz/답안이 그대로
--   유지되어 "오늘의 퀴즈가 갱신되지 않는다" 사고 발생.
--
--   ADR-023 에서 supabase/migrations/ 부활 — 모든 schema/function/cron 변경은
--   db_init.sql 과 supabase/migrations/<timestamp>_<slug>.sql 두 곳에 동시 작성.
--   `make db-init` 은 신규 환경 부트스트랩 (db_init.sql 전체 + 그 직후 자동
--   db-migrate), `make db-migrate ENV=prod` 는 기존 prod 의 증분 적용.
--
-- 동작:
--   - daily-quiz-9am-kst (매일 KST 9시 = UTC 0시):
--       daily_quiz 풀에서 random 1건 → 같은 내용으로 새 row INSERT (새 PK)
--       → fetchLatestDailyQuiz 가 새 row 반환, user_daily_quiz_attempts 자동 분리
--       → 클라이언트 입장에서 "오늘 퀴즈 초기화 + 답안 입력 가능" + push 발송
--   - weekly-character-monday (월 KST 9시): 금주 인물 선정
--   - weekly-progress-wed/fri (수·금 KST 9시): 주중·주말 진도 알림
--
-- Idempotent — 여러 번 실행해도 동일 결과:
--   * create or replace function — 함수는 항상 최신
--   * if exists pg_extension — pg_cron 미설치면 cron.schedule 통째 skip
--   * cron.unschedule + cron.schedule — 같은 jobname 재등록 안전
--
-- 의존:
--   - public.daily_quiz, public._fire_push_broadcast(text,text,text,text)
--   - public.pick_weekly_character(), public.notify_weekly_progress()
--   모두 db_init.sql 에 정의되어 있어야 함.

-- ─── 함수 ────────────────────────────────────────────────────────────────
-- db_init.sql §"매일 퀴즈 푸시" 와 동일.

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
  -- 모두 동일하게 풀로 취급 — 단순함 우선.
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

-- ─── pg_cron 스케줄 ──────────────────────────────────────────────────────
-- 모든 시간은 KST 9시 = UTC 0시 기준.
-- pg_cron 미활성화면 통째 skip — Supabase Dashboard → Database → Extensions
-- → pg_cron Enable 후 이 마이그레이션을 다시 적용해야 한다.

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
  else
    raise warning '[migration] pg_cron not installed — cron schedules skipped. '
                  'Enable pg_cron in Supabase Dashboard then re-apply this migration.';
  end if;
end $$;
