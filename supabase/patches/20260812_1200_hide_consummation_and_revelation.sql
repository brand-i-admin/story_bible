-- 마지막 시대와 요한계시록 기반 사건은 콘텐츠 검수 완료 전까지 공개하지 않는다.
-- row를 삭제하지 않고 draft로 전환해 사용자 진행도/제안 FK를 보존한다.

update public.events as event
set status = 'draft'
where event.status <> 'draft'
  and (
    exists (
      select 1
      from public.eras as era
      where era.id = event.era_id
        and era.code = 'era_nt_consummation'
    )
    or exists (
      select 1
      from jsonb_array_elements(coalesce(event.bible_refs, '[]'::jsonb)) as ref
      where ref ->> 'book' in ('계', '요한계시록')
    )
  );
