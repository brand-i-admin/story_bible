-- =========================================================
-- Migration: list_persons_by_era RPC (PGRST200 우회)
-- Date: 2026-04-21
-- =========================================================
-- 배경:
--   lib/data/story_repository.dart 의 fetchPersonsByEra 가
--     from('person_eras').select('display_order, persons!inner(...)')
--   형태의 nested select(resource embedding) 로 person_eras → persons 조인을
--   요청하는데, person_eras 는 WITH + group by + row_number() 가 섞인 view 라
--   PostgREST 가 FK 관계를 자동 추론하지 못하고 런타임에 PGRST200
--   ("Could not find a relationship between 'person_eras' and 'persons'") 를 던짐.
--
--   이를 SECURITY DEFINER RPC 로 우회한다. persons 의 RLS(is_active 제한) 를
--   우회하지 않도록 함수 내부에서 p.is_active = true 조건을 유지.
--
-- 안전 재실행: create or replace + drop function if exists 로 증분 반영.
-- 상세 설계: docs/BACKEND.md (person_eras 섹션) 참조.

begin;

drop function if exists public.list_persons_by_era(uuid) cascade;

create or replace function public.list_persons_by_era(p_era_id uuid)
returns table (
  id uuid,
  code text,
  name text,
  tagline text,
  description text,
  avatar_url text,
  display_order int
)
language sql
stable
security definer
set search_path = public
as $$
  with person_first as (
    select
      p.id as person_id,
      p.code as person_code,
      min(e.story_index) as first_story_index
    from persons p
    join events e
      on e.person_codes @> array[p.code]
     and e.status = 'published'
     and e.era_id = p_era_id
    where p.is_active = true
    group by p.id, p.code
  )
  select
    p.id,
    p.code,
    p.name,
    p.tagline,
    p.description,
    p.avatar_url,
    (row_number() over (order by pf.first_story_index, pf.person_code))::int
      as display_order
  from person_first pf
  join persons p on p.id = pf.person_id
  order by display_order;
$$;

grant execute on function public.list_persons_by_era(uuid) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
