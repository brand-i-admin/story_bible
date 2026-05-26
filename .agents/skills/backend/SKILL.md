---
name: backend
description: "Story Bible Supabase 백엔드 작업 스킬. DB 스키마, RLS 정책, RPC, Edge Functions, 인증, Storage, 알림 배관, Flutter Repository 쿼리를 수정할 때 사용한다."
---

# Backend

## 작업 순서

1. 스키마, RLS, RPC, Edge Function, Repository 작업 전 `docs/BACKEND.md`를 읽는다.
2. 현재 Supabase 동작에 의존하는 작업이면 기억에만 의존하지 말고 공식 문서나 사용 가능한 Supabase 도구로 확인한다.
3. 관련 테스트를 `test/data/`, `test/models/`, `tools/**/test_*.py`에서 찾는다.
4. 기존 Repository 패턴을 따른다: 주입된 `SupabaseClient`, row-to-model 변환, 명시적 에러 처리.
5. Schema/RLS/RPC 변경은 `db_init.sql`과 문서를 함께 갱신한다.
6. `flutter analyze`, `flutter test`, 관련 Python 테스트, SQL dry-run 또는 수동 Supabase 검증으로 확인한다.

## 기본 원칙

- `db_init.sql`이 스키마 단일 진실 소스다.
- `supabase/migrations/`는 필요한 경우 prod-safe 보조 migration을 담는다. 새 migration을 추가하면 문서화한다.
- 공개 성경 이야기 데이터는 읽기 가능하고, 사용자 데이터는 RLS로 사용자 범위에 묶는다.
- Story event hard delete는 학습 진행도/제안 이력 때문에 위험하다. 삭제 의미를 바꾸기 전 ADR과 backend 문서를 읽는다.
- Edge Functions는 TypeScript/Deno Supabase 함수이며 service key를 노출하면 안 된다.

## PDCA 적용

- Plan: 변경할 table/RPC/function/repository와 RLS 영향을 먼저 적는다.
- Do: `db_init.sql`, migration, repository, model/test를 한 흐름으로 수정한다.
- Check: `git diff`에서 schema와 docs가 같이 움직였는지, secret이 섞이지 않았는지 확인하고 검증 명령을 실행한다.
- Act: 실패 원인을 반영해 다시 수정하거나, 통과 결과와 남은 운영 리스크를 보고한다.

## 가드레일

- migration만 추가하고 `db_init.sql`/문서를 빼먹지 않는다.
- 새 테이블에는 RLS 정책, grant, 필요한 index, 문서가 필요하다.
- secret, token, DB URL, service-role key, private JSON을 로그나 코드에 남기지 않는다.
- Repository 단위 테스트는 mock을 우선한다. live Supabase에 의존하는 unit test를 만들지 않는다.

## 함께 갱신할 문서

- `docs/BACKEND.md`: schema, RLS, RPC, Edge Functions, Repository.
- `docs/ARCHITECTURE.md`: 시스템 흐름이나 관계 변화.
- `docs/ADR.md`: 새 아키텍처 결정.
- `AGENTS.md`: 검증 명령이나 backend 작업 흐름 변경.
