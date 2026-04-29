-- =========================================================
-- Migration: characters.era_codes 도입 + 인물 카드 노출 era 필터
-- Date: 2026-04-29
-- =========================================================
-- 배경:
--   인물 카드 화면(시대별 필터)이 events.character_codes 에 등장한 모든 인물을
--   동등하게 노출하다 보니, 변화산처럼 OT 인물(모세/엘리야)이 NT 사건에 환상으로
--   언급되어도 NT 시대 카드에 함께 떠 사용자에게 혼란을 줬다. 또한 동명이인
--   (왕 사울 vs 청년 사울=바울, 야곱의 아들 요셉 vs 예수 양아버지 요셉) 이 한
--   코드로 섞여 있어 era 분리도 불가능했다.
--
--   해결 방향:
--     1) characters 에 era_codes text[] 컬럼 도입 — 인물 단위 노출 era 정책
--     2) character_eras view + list_characters_by_era RPC 가 era_codes 매칭 시에만
--        노출되도록 필터 추가 (era_codes 가 비어있으면 후방 호환 통과)
--     3) events.character_codes 는 사실 데이터로 손대지 않음 — 변화산에 모세/엘리야가
--        등장했다는 사건 정보는 이벤트 상세/검색에서 그대로 보존됨
--     4) 동명이인은 별도 코드로 분리 (saul/paul, joseph/joseph_nazareth) — 시드 데이터
--        재생성으로 처리되며 본 마이그레이션은 스키마/뷰만 다룬다
--
-- 안전 재실행: ADD COLUMN IF NOT EXISTS + create or replace + drop view/function
--             if exists 로 증분 반영. 시드 적용은 별개 (characters_seed.sql).
-- 상세 설계: docs/BACKEND.md (characters.era_codes / character_eras 섹션) 참조.

begin;

-- 1) characters.era_codes 컬럼
alter table public.characters
  add column if not exists era_codes text[] not null default '{}';

create index if not exists idx_characters_era_codes_gin
  on public.characters using gin (era_codes);

-- 2) character_eras view 재정의 — era_codes 필터 추가
drop view if exists public.character_eras cascade;

create view public.character_eras as
  with character_first as (
    select
      p.id as character_id,
      p.code as character_code,
      e.era_id,
      min(e.story_index) as first_story_index
    from public.characters p
    join public.events e on e.character_codes @> array[p.code]
                        and e.status = 'published'
                        and e.deleted_at is null
    join public.eras er on er.id = e.era_id
    where p.is_active = true
      and (p.era_codes = '{}'::text[] or p.era_codes && array[er.code])
    group by p.id, p.code, e.era_id
  )
  select
    character_id,
    era_id,
    row_number() over (
      partition by era_id
      order by first_story_index, character_code
    ) as display_order
  from character_first;

grant select on public.character_eras to anon, authenticated;

-- 3) list_characters_by_era RPC 재정의 — era_codes 필터 + soft delete 필터 유지
drop function if exists public.list_characters_by_era(uuid) cascade;

create or replace function public.list_characters_by_era(p_era_id uuid)
returns table (
  id uuid,
  code text,
  name text,
  tagline text,
  description text,
  avatar_url text,
  avatar_storage_path text,
  display_order int
)
language sql
stable
security definer
set search_path = public
as $$
  with target_era as (
    select code from public.eras where id = p_era_id
  ),
  character_first as (
    select
      p.id as character_id,
      p.code as character_code,
      min(e.story_index) as first_story_index
    from public.characters p
    cross join target_era te
    join public.events e
      on e.character_codes @> array[p.code]
     and e.status = 'published'
     and e.deleted_at is null
     and e.era_id = p_era_id
    where p.is_active = true
      and (p.era_codes = '{}'::text[] or p.era_codes && array[te.code])
    group by p.id, p.code
  )
  select
    p.id,
    p.code,
    p.name,
    p.tagline,
    p.description,
    p.avatar_url,
    p.avatar_storage_path,
    (row_number() over (order by pf.first_story_index, pf.character_code))::int
      as display_order
  from character_first pf
  join public.characters p on p.id = pf.character_id
  order by display_order;
$$;

grant execute on function public.list_characters_by_era(uuid) to anon, authenticated;

commit;
