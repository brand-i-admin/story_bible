# Supabase 운영 Patch SQL

real DB 에 보존해야 할 사용자 데이터가 생긴 뒤부터는 `make db-init ENV=real`로
DB를 초기화하지 않는다. schema, RLS, RPC, cron, trigger 변경은 이 디렉토리에
idempotent patch SQL을 추가해서 적용한다.

## 원칙

- `db_init.sql`은 여전히 최종 desired schema 의 단일 진실 소스다.
- real 운영 DB에는 `db_init.sql` 전체 리셋을 적용하지 않는다.
- real 변경용 SQL은 여러 번 실행해도 안전하게 작성한다.
- patch 적용 전에는 dev에서 먼저 검증하고, real 적용 전 백업을 만든다.

## 파일명

```text
YYYYMMDD_HHMM_short_description.sql
```

예:

```text
20260622_1530_add_story_publish_window.sql
```

## 작성 패턴

```sql
alter table if exists public.events
  add column if not exists publish_at timestamptz;

create or replace function public.some_function()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- ...
end;
$$;

drop policy if exists some_policy on public.events;
create policy some_policy
  on public.events
  for select
  using (status = 'published');
```

## 적용

```bash
make apply-patch ENV=dev PATCH=supabase/patches/YYYYMMDD_HHMM_short_description.sql
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_short_description.sql
```

`make db-init ENV=real`은 기본적으로 차단되어 있다. 신규 프로젝트 부트스트랩이나
복구처럼 real DB를 정말 초기화해야 할 때만 아래처럼 명시한다.

```bash
CONFIRM_REAL_DB_INIT=1 make db-init ENV=real
```
