-- =========================================================
-- Migration: list_characters_by_era RPC (PGRST200 우회)
-- Date: 2026-04-21
-- Renamed 2026-04-22: persons → characters (domain rename)
-- =========================================================
-- 배경:
--   lib/data/story_repository.dart 의 fetchCharactersByEra 가
--     from('character_eras').select('display_order, characters!inner(...)')
--   형태의 nested select(resource embedding) 로 character_eras → characters 조인을
--   요청하는데, character_eras 는 WITH + group by + row_number() 가 섞인 view 라
--   PostgREST 가 FK 관계를 자동 추론하지 못하고 런타임에 PGRST200
--   ("Could not find a relationship between 'character_eras' and 'characters'") 를 던짐.
--
--   이를 SECURITY DEFINER RPC 로 우회한다. characters 의 RLS(is_active 제한) 를
--   우회하지 않도록 함수 내부에서 c.is_active = true 조건을 유지.
--
-- 안전 재실행: create or replace + drop function if exists 로 증분 반영.
-- 상세 설계: docs/BACKEND.md (character_eras 섹션) 참조.

begin;

drop function if exists public.list_persons_by_era(uuid) cascade;
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
  with character_first as (
    select
      c.id as character_id,
      c.code as character_code,
      min(e.story_index) as first_story_index
    from characters c
    join events e
      on e.character_codes @> array[c.code]
     and e.status = 'published'
     and e.era_id = p_era_id
    where c.is_active = true
    group by c.id, c.code
  )
  select
    c.id,
    c.code,
    c.name,
    c.tagline,
    c.description,
    c.avatar_url,
    c.avatar_storage_path,
    (row_number() over (order by cf.first_story_index, cf.character_code))::int
      as display_order
  from character_first cf
  join characters c on c.id = cf.character_id
  order by display_order;
$$;

grant execute on function public.list_characters_by_era(uuid) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
