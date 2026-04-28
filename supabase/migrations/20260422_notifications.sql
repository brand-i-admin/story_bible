-- =========================================================
-- Migration: Notifications + Push + Weekly character selection
-- Date: 2026-04-22
-- =========================================================
-- 인앱 알림함(bell 아이콘 드롭다운)과 FCM 푸시 알림을 위한 스키마.
--
-- 2 테이블 하이브리드 전략:
--  1. notifications              — 개인용 (Fan-out on Write, user_id 필수)
--     · 제안 댓글, 제안 승인/거절, 퀴즈 완료 등 특정 사용자에게만 가는 알림
--  2. broadcast_notifications    — 공지용 (Fan-out on Read, 전체 공지 1 row)
--  2b. broadcast_notification_reads — 사용자별 읽음 표시
--     · 새 이야기 등록, 금주 인물 선정, 주중 진도 체크 등 전체 대상
--
-- 3 테이블 user_push_tokens      — 디바이스 FCM 토큰 보관.
-- 4 테이블 weekly_character_selection — 금주의 인물 단일 소스
--   (앱 클라이언트와 pg_cron 둘 다 이 테이블을 읽는다 — drift 방지)
--
-- 30일 보관 정책: hard delete 없이 WHERE created_at > now() - 30d 필터로
-- UI 에서만 숨긴다 (DB 용량은 수년 단위까지 여유).
--
-- 상세 설계: docs/BACKEND.md §(Notifications & Push) 참조.

begin;

-- ============================================================================
-- 1) notifications — 개인 알림 (Fan-out on Write)
-- ============================================================================
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'proposal_comment',         -- 본인 제안에 댓글 (작성자에게)
    'proposal_comment_admin',   -- 특정 제안에 댓글 (관리자에게)
    'new_proposal_admin',       -- 새 제안 등록 (관리자에게)
    'proposal_approved',        -- 내 제안 승인됨 (작성자에게)
    'proposal_rejected',        -- 내 제안 거절됨 (작성자에게)
    'quiz_completed'            -- 퀴즈 완료 (본인에게)
  )),
  title text not null,
  body text,
  deep_link text,               -- '/proposal/{id}' | '/event/{id}' 등
  payload jsonb not null default '{}'::jsonb,  -- UI 라우팅/렌더 부가 정보
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user_created
  on notifications(user_id, created_at desc);
create index if not exists idx_notifications_user_unread
  on notifications(user_id, created_at desc) where read_at is null;
create index if not exists idx_notifications_created_at
  on notifications(created_at desc);

-- ============================================================================
-- 2) broadcast_notifications — 공지 (Fan-out on Read)
-- ============================================================================
create table if not exists broadcast_notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in (
    'new_event',                -- 새 이야기 등록 → 전체 유저
    'weekly_character',         -- 금주의 인물 선정 (월) → 전체 유저
    'weekly_progress_check'     -- 주중 진도 체크 (수/금) → 전체 유저
  )),
  -- 'all' = 전체, 'pastor_or_admin' = 소수만 (향후 확장용)
  target_audience text not null default 'all'
    check (target_audience in ('all', 'pastor_or_admin')),
  title text not null,
  body text,
  deep_link text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_broadcast_created
  on broadcast_notifications(created_at desc);

create table if not exists broadcast_notification_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  broadcast_id uuid not null references broadcast_notifications(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, broadcast_id)
);

create index if not exists idx_broadcast_reads_user
  on broadcast_notification_reads(user_id);

-- ============================================================================
-- 3) user_push_tokens — 디바이스 FCM 토큰
-- ============================================================================
create table if not exists user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('web', 'ios', 'android')),
  token text not null unique,
  device_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_tokens_user on user_push_tokens(user_id);

drop trigger if exists set_user_push_tokens_updated_at on user_push_tokens;
create trigger set_user_push_tokens_updated_at
before update on user_push_tokens
for each row execute function public.touch_updated_at();

-- ============================================================================
-- 4) weekly_character_selection — 금주의 인물 단일 소스
-- ============================================================================
create table if not exists weekly_character_selection (
  week_key text primary key,    -- 'YYYY-M-D' (월요일 날짜)
  character_code text not null references characters(code),
  picked_at timestamptz not null default now()
);

-- ============================================================================
-- GRANT + RLS
-- ============================================================================
grant select, update on table notifications to authenticated;
grant select on table broadcast_notifications to authenticated;
grant select, insert on table broadcast_notification_reads to authenticated;
grant select, insert, update, delete on table user_push_tokens to authenticated;
grant select on table weekly_character_selection to authenticated;

alter table notifications enable row level security;
alter table broadcast_notifications enable row level security;
alter table broadcast_notification_reads enable row level security;
alter table user_push_tokens enable row level security;
alter table weekly_character_selection enable row level security;

-- notifications: 본인 것만 SELECT/UPDATE. INSERT 는 SECURITY DEFINER 함수로만.
drop policy if exists notifications_select_own on notifications;
create policy notifications_select_own on notifications
for select to authenticated using (auth.uid() = user_id);

drop policy if exists notifications_update_own on notifications;
create policy notifications_update_own on notifications
for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- broadcast_notifications: 전체 읽기. INSERT 는 admin/SECURITY DEFINER.
drop policy if exists broadcast_read_all on broadcast_notifications;
create policy broadcast_read_all on broadcast_notifications
for select to authenticated using (true);

-- broadcast_notification_reads: 본인 것만.
drop policy if exists broadcast_reads_select_own on broadcast_notification_reads;
create policy broadcast_reads_select_own on broadcast_notification_reads
for select to authenticated using (auth.uid() = user_id);

drop policy if exists broadcast_reads_insert_own on broadcast_notification_reads;
create policy broadcast_reads_insert_own on broadcast_notification_reads
for insert to authenticated with check (auth.uid() = user_id);

-- user_push_tokens: 본인 디바이스만 관리.
drop policy if exists push_tokens_all_own on user_push_tokens;
create policy push_tokens_all_own on user_push_tokens
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- weekly_character_selection: 전체 읽기 공개 (앱이 금주 인물 읽어감).
drop policy if exists weekly_char_read_all on weekly_character_selection;
create policy weekly_char_read_all on weekly_character_selection
for select to authenticated using (true);

-- ============================================================================
-- 헬퍼 함수 1: _notify_admins — 모든 admin 사용자에게 notifications row INSERT
-- ============================================================================
-- admin 여부는 auth.users.raw_app_meta_data ->> 'role' = 'admin' 기준.
-- SECURITY DEFINER 로 auth.users 를 스캔할 수 있게 함.
create or replace function public._notify_admins(
  p_type text,
  p_title text,
  p_body text,
  p_deep_link text,
  p_payload jsonb,
  p_exclude_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into notifications (user_id, type, title, body, deep_link, payload)
  select
    u.id,
    p_type,
    p_title,
    p_body,
    p_deep_link,
    coalesce(p_payload, '{}'::jsonb)
  from auth.users u
  where (u.raw_app_meta_data ->> 'role') = 'admin'
    and (p_exclude_user_id is null or u.id <> p_exclude_user_id);
end;
$$;

-- ============================================================================
-- 트리거 함수 1: notify_on_new_proposal
-- ============================================================================
-- event_proposals 에 새 제안이 INSERT 되면 admin 들에게 알림.
create or replace function public.notify_on_new_proposal()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposer_nickname text;
begin
  select coalesce(nickname, '사역자') into v_proposer_nickname
  from user_profiles
  where user_id = new.proposer_user_id;

  perform public._notify_admins(
    'new_proposal_admin',
    '새 제안이 등록되었어요',
    coalesce(v_proposer_nickname, '사역자') || '님이 "' ||
      coalesce(new.title, '제목 없음') || '" 제안을 등록했어요.',
    '/proposal/' || new.id::text,
    jsonb_build_object(
      'proposal_id', new.id,
      'proposer_user_id', new.proposer_user_id,
      'title', new.title
    ),
    new.proposer_user_id  -- 본인이 admin 이어도 제외
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_new_proposal on event_proposals;
create trigger trg_notify_on_new_proposal
after insert on event_proposals
for each row execute function public.notify_on_new_proposal();

-- ============================================================================
-- 트리거 함수 2: notify_on_proposal_comment
-- ============================================================================
-- 댓글 INSERT 시:
--  - 댓글 작성자가 proposer 아니면 proposer 에게 알림
--  - 댓글 작성자가 admin 아니면 모든 admin 에게도 알림 (본인 제외)
create or replace function public.notify_on_proposal_comment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_proposal event_proposals%rowtype;
  v_author_nickname text;
  v_author_is_admin boolean;
  v_body_preview text;
begin
  select * into v_proposal from event_proposals where id = new.proposal_id;
  if not found then
    return new;
  end if;

  select coalesce(nickname, '사용자') into v_author_nickname
  from user_profiles where user_id = new.author_user_id;

  v_author_is_admin := coalesce(
    (select (raw_app_meta_data ->> 'role') = 'admin'
       from auth.users where id = new.author_user_id),
    false
  );

  -- 본문 미리보기 (40자 컷)
  v_body_preview := substr(new.body, 1, 40);
  if length(new.body) > 40 then
    v_body_preview := v_body_preview || '…';
  end if;

  -- 작성자 != proposer 일 때만 proposer 에게 알림
  if v_proposal.proposer_user_id <> new.author_user_id then
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      v_proposal.proposer_user_id,
      'proposal_comment',
      '"' || coalesce(v_proposal.title, '제안') || '" 제안에 댓글이 달렸어요',
      coalesce(v_author_nickname, '사용자') || ': ' || v_body_preview,
      '/proposal/' || v_proposal.id::text,
      jsonb_build_object(
        'proposal_id', v_proposal.id,
        'comment_id', new.id,
        'author_user_id', new.author_user_id,
        'proposal_title', v_proposal.title
      )
    );
  end if;

  -- 작성자가 admin 이 아니면 모든 admin 에게도 알림
  if not v_author_is_admin then
    perform public._notify_admins(
      'proposal_comment_admin',
      '"' || coalesce(v_proposal.title, '제안') || '" 제안에 댓글이 달렸어요',
      coalesce(v_author_nickname, '사용자') || ': ' || v_body_preview,
      '/proposal/' || v_proposal.id::text,
      jsonb_build_object(
        'proposal_id', v_proposal.id,
        'comment_id', new.id,
        'author_user_id', new.author_user_id,
        'proposal_title', v_proposal.title
      ),
      new.author_user_id  -- 본인이 admin 이면(위 조건에 안 걸림) 어쨌든 본인 제외
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_proposal_comment on event_proposal_comments;
create trigger trg_notify_on_proposal_comment
after insert on event_proposal_comments
for each row execute function public.notify_on_proposal_comment();

-- ============================================================================
-- 트리거 함수 3: notify_on_proposal_reviewed
-- ============================================================================
-- status 가 pending → approved/rejected 로 바뀌면 proposer 에게 알림.
create or replace function public.notify_on_proposal_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if old.status = new.status then
    return new;
  end if;
  if new.status not in ('approved', 'rejected') then
    return new;
  end if;

  if new.status = 'approved' then
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      new.proposer_user_id,
      'proposal_approved',
      '제안이 승인되었어요',
      '"' || coalesce(new.title, '제안') || '" 이(가) 이야기로 등록되었어요.',
      case when new.approved_event_id is not null
           then '/event/' || new.approved_event_id::text
           else '/proposal/' || new.id::text end,
      jsonb_build_object(
        'proposal_id', new.id,
        'event_id', new.approved_event_id,
        'proposal_title', new.title
      )
    );
  else  -- rejected
    insert into notifications (user_id, type, title, body, deep_link, payload)
    values (
      new.proposer_user_id,
      'proposal_rejected',
      '제안이 반려되었어요',
      coalesce(
        nullif(trim(new.review_note), ''),
        '"' || coalesce(new.title, '제안') || '" 이(가) 반려되었어요.'
      ),
      '/proposal/' || new.id::text,
      jsonb_build_object(
        'proposal_id', new.id,
        'proposal_title', new.title,
        'review_note', new.review_note
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_proposal_reviewed on event_proposals;
create trigger trg_notify_on_proposal_reviewed
after update on event_proposals
for each row execute function public.notify_on_proposal_reviewed();

-- ============================================================================
-- 트리거 함수 4: notify_on_new_event (broadcast)
-- ============================================================================
-- events published INSERT 시 전체 유저 대상 broadcast row 1개 만 생성.
-- 승인 경로에서도 insert_event_at_position → events INSERT 가 트리거 됨.
create or replace function public.notify_on_new_event()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if coalesce(new.status, 'published') <> 'published' then
    return new;
  end if;

  insert into broadcast_notifications (type, target_audience, title, body, deep_link, payload)
  values (
    'new_event',
    'all',
    '새 이야기가 등록되었어요',
    '"' || coalesce(new.title, '제목 없음') || '" 이야기를 확인해 보세요.',
    '/event/' || new.id::text,
    jsonb_build_object(
      'event_id', new.id,
      'event_title', new.title
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_new_event on events;
create trigger trg_notify_on_new_event
after insert on events
for each row execute function public.notify_on_new_event();

-- ============================================================================
-- RPC: notify_quiz_completed — 클라이언트가 퀴즈 완료 직후 호출
-- ============================================================================
create or replace function public.notify_quiz_completed(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_event_title text;
  v_total_events int;
  v_completed_count int;
  v_percent int;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select title into v_event_title from events where id = p_event_id;

  select count(*) into v_total_events from events where status = 'published';
  select count(*) into v_completed_count
  from user_event_progress
  where user_id = auth.uid() and is_completed = true;

  v_percent := case when v_total_events > 0
    then (v_completed_count * 100 / v_total_events)
    else 0 end;

  insert into notifications (user_id, type, title, body, deep_link, payload)
  values (
    auth.uid(),
    'quiz_completed',
    '퀴즈를 완주했어요!',
    '"' || coalesce(v_event_title, '이야기') || '" 퀴즈 완료 — 전체 진도 ' ||
      v_percent || '%',
    '/event/' || p_event_id::text,
    jsonb_build_object(
      'event_id', p_event_id,
      'event_title', v_event_title,
      'progress_percent', v_percent,
      'completed_count', v_completed_count,
      'total_count', v_total_events
    )
  );
end;
$$;
grant execute on function public.notify_quiz_completed(uuid) to authenticated;

-- ============================================================================
-- RPC: mark_notification_read / mark_all_notifications_read
-- ============================================================================
create or replace function public.mark_notification_read(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update notifications
    set read_at = now()
  where id = p_id and user_id = auth.uid() and read_at is null;
$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update notifications
    set read_at = now()
  where user_id = auth.uid() and read_at is null;
$$;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- broadcast 읽음 — reads 테이블에 INSERT (ON CONFLICT 무시)
create or replace function public.mark_broadcast_read(p_broadcast_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into broadcast_notification_reads (user_id, broadcast_id)
  values (auth.uid(), p_broadcast_id)
  on conflict (user_id, broadcast_id) do nothing;
$$;
grant execute on function public.mark_broadcast_read(uuid) to authenticated;

create or replace function public.mark_all_broadcasts_read()
returns void
language sql
security definer
set search_path = public
as $$
  insert into broadcast_notification_reads (user_id, broadcast_id)
  select auth.uid(), b.id
  from broadcast_notifications b
  where b.created_at > now() - interval '30 days'
    and (b.target_audience = 'all'
         or (b.target_audience = 'pastor_or_admin'
             and (public.is_pastor() or public.is_admin())))
  on conflict (user_id, broadcast_id) do nothing;
$$;
grant execute on function public.mark_all_broadcasts_read() to authenticated;

-- ============================================================================
-- RPC: list_my_notifications — 개인 + 브로드캐스트 통합 조회
-- ============================================================================
-- 최근 30일 내 알림만 반환. 개인(notifications) + 공지(broadcast_notifications)
-- 를 UNION ALL 로 합쳐 created_at 역순.
-- is_read 플래그를 계산해 돌려줌 (개인은 read_at, 공지는 reads 테이블 존재 여부).
create or replace function public.list_my_notifications(
  p_limit int default 30,
  p_only_unread boolean default false
)
returns table (
  id uuid,
  source text,           -- 'personal' | 'broadcast'
  type text,
  title text,
  body text,
  deep_link text,
  payload jsonb,
  is_read boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with personal as (
    select
      n.id,
      'personal'::text as source,
      n.type,
      n.title,
      n.body,
      n.deep_link,
      n.payload,
      (n.read_at is not null) as is_read,
      n.created_at
    from notifications n
    where n.user_id = auth.uid()
      and n.created_at > now() - interval '30 days'
  ),
  bcast as (
    select
      b.id,
      'broadcast'::text as source,
      b.type,
      b.title,
      b.body,
      b.deep_link,
      b.payload,
      (r.broadcast_id is not null) as is_read,
      b.created_at
    from broadcast_notifications b
    left join broadcast_notification_reads r
      on r.broadcast_id = b.id and r.user_id = auth.uid()
    where b.created_at > now() - interval '30 days'
      and (
        b.target_audience = 'all'
        or (b.target_audience = 'pastor_or_admin'
            and (public.is_pastor() or public.is_admin()))
      )
  ),
  combined as (
    select * from personal
    union all
    select * from bcast
  )
  select *
  from combined
  where (not p_only_unread) or (not is_read)
  order by created_at desc
  limit greatest(p_limit, 1);
$$;
grant execute on function public.list_my_notifications(int, boolean) to authenticated;

-- ============================================================================
-- RPC: unread_notification_count — bell 배지에 쓰는 카운트
-- ============================================================================
create or replace function public.unread_notification_count()
returns int
language sql
stable
security definer
set search_path = public
as $$
  with personal as (
    select count(*) as c
    from notifications
    where user_id = auth.uid()
      and read_at is null
      and created_at > now() - interval '30 days'
  ),
  bcast as (
    select count(*) as c
    from broadcast_notifications b
    where b.created_at > now() - interval '30 days'
      and (
        b.target_audience = 'all'
        or (b.target_audience = 'pastor_or_admin'
            and (public.is_pastor() or public.is_admin()))
      )
      and not exists (
        select 1 from broadcast_notification_reads r
        where r.broadcast_id = b.id and r.user_id = auth.uid()
      )
  )
  select (
    coalesce((select c from personal), 0) + coalesce((select c from bcast), 0)
  )::int;
$$;
grant execute on function public.unread_notification_count() to authenticated;

-- ============================================================================
-- RPC: register_push_token — 디바이스 FCM 토큰 등록(upsert)
-- ============================================================================
create or replace function public.register_push_token(
  p_token text,
  p_platform text,
  p_device_label text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if coalesce(trim(p_token), '') = '' then
    raise exception 'token is required';
  end if;
  if p_platform not in ('web', 'ios', 'android') then
    raise exception 'invalid platform: %', p_platform;
  end if;

  insert into user_push_tokens (user_id, platform, token, device_label)
  values (auth.uid(), p_platform, p_token, p_device_label)
  on conflict (token) do update
    set user_id = excluded.user_id,      -- 같은 토큰이 다른 유저로 넘어간 경우 최신 유저로
        platform = excluded.platform,
        device_label = coalesce(excluded.device_label, user_push_tokens.device_label),
        updated_at = now();
end;
$$;
grant execute on function public.register_push_token(text, text, text) to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from user_push_tokens
  where token = p_token and user_id = auth.uid();
$$;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ============================================================================
-- 금주 인물 선정 — Dart 의 seedFromKey 포팅 (단일 소스 유지용)
-- ============================================================================
-- lib/utils/weekly_selection.dart 의 seedFromKey 와 동일 알고리즘:
--   seed = fold code_units: (acc * 31 + codeUnit) & 0x7FFFFFFF
--   index = seed % length(active_characters)
-- Dart codeUnit 은 UTF-16, 영숫자/숫자 하이픈 범위만 쓰는 week_key('YYYY-M-D')
-- 라 plpgsql ascii() 와 일치. 비-ASCII 가 들어올 일 없음.
create or replace function public._seed_from_week_key(p_key text)
returns bigint
language plpgsql
immutable
as $$
declare
  v_acc bigint := 0;
  v_i int;
begin
  for v_i in 1..length(p_key) loop
    v_acc := ((v_acc * 31) + ascii(substr(p_key, v_i, 1))) & 2147483647;
  end loop;
  return v_acc;
end;
$$;

-- pick_weekly_character — 이번 주 월요일 기준으로 금주의 인물을 선정 + 알림.
-- pg_cron 에서 매주 월요일 00:00 UTC 호출.
-- 선정 기준: is_active = true 인 characters 중 week_key 시드로 선택.
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
  v_character_name text;
  v_active_count int;
  v_seed bigint;
  v_index int;
begin
  -- UTC 기준 월요일 계산.
  v_monday := date_trunc('week', now() at time zone 'utc')::date;
  v_week_key := v_monday::text;

  -- 이미 선정 돼 있으면 재선정 안 함 (idempotent).
  if exists (select 1 from weekly_character_selection where week_key = v_week_key) then
    return;
  end if;

  select count(*) into v_active_count from characters where is_active = true;
  if v_active_count = 0 then
    return;
  end if;

  v_seed := public._seed_from_week_key(v_week_key);
  v_index := (v_seed % v_active_count)::int;

  select code, name into v_character_code, v_character_name
  from characters
  where is_active = true
  order by code
  offset v_index limit 1;

  if v_character_code is null then
    return;
  end if;

  insert into weekly_character_selection (week_key, character_code)
  values (v_week_key, v_character_code);

  insert into broadcast_notifications (type, target_audience, title, body, deep_link, payload)
  values (
    'weekly_character',
    'all',
    '이번주 금주의 인물',
    '이번주 인물은 "' || coalesce(v_character_name, v_character_code) ||
      '" 입니다. 함께 공부해봐요!',
    '/weekly',
    jsonb_build_object(
      'character_code', v_character_code,
      'character_name', v_character_name,
      'week_key', v_week_key
    )
  );
end;
$$;
grant execute on function public.pick_weekly_character() to authenticated;

-- 주중 진도 체크 — 수/금 마다 "금주 인물 X% 달성" 브로드캐스트.
-- 전체 유저의 평균 진도를 body 에 담는다 (개인 세부 진도는 인앱에서 계산).
create or replace function public.notify_weekly_progress()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_key text;
  v_character_code text;
  v_character_name text;
  v_total_events int;
  v_avg_completed numeric;
  v_percent int;
begin
  v_week_key := date_trunc('week', now() at time zone 'utc')::date::text;

  select w.character_code, c.name
    into v_character_code, v_character_name
  from weekly_character_selection w
  join characters c on c.code = w.character_code
  where w.week_key = v_week_key;

  if v_character_code is null then
    return;
  end if;

  -- 이번 주 인물이 등장하는 이벤트 수
  select count(*) into v_total_events
  from events
  where status = 'published'
    and character_codes @> array[v_character_code];

  if v_total_events = 0 then
    return;
  end if;

  -- 유저별 평균 완료율 (로그인한 적 있는 사람 기준)
  select coalesce(avg(completed_per_user), 0) into v_avg_completed
  from (
    select count(*)::numeric / v_total_events * 100 as completed_per_user
    from user_event_progress p
    join events e on e.id = p.event_id
    where p.is_completed = true
      and e.character_codes @> array[v_character_code]
    group by p.user_id
  ) t;

  v_percent := round(v_avg_completed)::int;

  insert into broadcast_notifications (type, target_audience, title, body, deep_link, payload)
  values (
    'weekly_progress_check',
    'all',
    coalesce(v_character_name, v_character_code) || ' 공부 진도 ' || v_percent || '%',
    '금주 인물을 함께 공부해봐요. 남은 이야기를 마저 만나봐요!',
    '/weekly',
    jsonb_build_object(
      'character_code', v_character_code,
      'character_name', v_character_name,
      'week_key', v_week_key,
      'avg_percent', v_percent
    )
  );
end;
$$;
grant execute on function public.notify_weekly_progress() to authenticated;

-- ============================================================================
-- pg_cron 스케줄 (수동 적용 필요 — 아래 블록은 pg_cron 확장이 있을 때만 실행)
-- ============================================================================
-- pg_cron 은 Supabase 프로젝트에서 대시보드 → Database → Extensions 에서
-- 활성화해야 사용 가능. 활성화 되면 이 블록이 자동으로 스케줄을 등록한다.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- 기존 스케줄 제거 (idempotent)
    perform cron.unschedule(jobname)
    from cron.job
    where jobname in (
      'weekly-character-monday',
      'weekly-progress-wed',
      'weekly-progress-fri'
    );

    -- 월요일 00:00 UTC = 한국시간 월요일 09:00
    perform cron.schedule(
      'weekly-character-monday',
      '0 0 * * 1',
      $cmd$ select public.pick_weekly_character(); $cmd$
    );
    -- 수요일 00:00 UTC = 한국시간 수요일 09:00
    perform cron.schedule(
      'weekly-progress-wed',
      '0 0 * * 3',
      $cmd$ select public.notify_weekly_progress(); $cmd$
    );
    -- 금요일 00:00 UTC = 한국시간 금요일 09:00
    perform cron.schedule(
      'weekly-progress-fri',
      '0 0 * * 5',
      $cmd$ select public.notify_weekly_progress(); $cmd$
    );
  end if;
end $$;

commit;
