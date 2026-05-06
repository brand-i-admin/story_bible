---
name: backend
description: "백엔드(DB 스키마/쿼리/인증/RLS/Repository) 변경 시 사용하는 스킬. docs/BACKEND.md를 참조하여 db_init.sql, supabase/, lib/data/ 범위에서 작업한다. Supabase 공식 agent-skills와 함께 사용하면 최신 가이드라인을 활용할 수 있다."
---

# Backend

## 개요

Supabase 백엔드(DB 스키마, Repository 쿼리, RLS 정책, 인증, Storage)를 수정할 때 사용한다.

## Supabase 공식 Agent Skills 통합

Supabase가 공식으로 제공하는 [agent-skills](https://github.com/supabase/agent-skills)가 Claude Code 플러그인으로 설치되어 있으면 자동으로 함께 활성화된다. 이 스킬들은 다음을 커버한다:

- **`supabase`**: Database, Auth, Edge Functions, Realtime, Storage, RLS, JWT, supabase-js/ssr 등 전체 제품
- **`supabase-postgres-best-practices`**: 쿼리 최적화, 인덱싱, RLS 안티패턴, 스키마 설계 등 Postgres 성능 가이드 (8개 카테고리)

### 설치 (최초 1회)

```bash
# Claude Code 플러그인 설치
claude plugin install supabase@supabase-agent-skills

# 또는 특정 스킬만
npx skills add supabase/agent-skills --skill supabase
npx skills add supabase/agent-skills --skill supabase-postgres-best-practices
```

### 언제 공식 스킬을 활용하는가

- **쿼리 최적화** → `supabase-postgres-best-practices`가 EXPLAIN 분석과 수정안을 제시
- **RLS 정책 작성** → `supabase`의 RLS 안티패턴 체크리스트 활용
- **Auth 이슈** (세션/쿠키/JWT) → `supabase`의 최신 auth 가이드 참조
- **Edge Functions / Storage** → `supabase`의 클라이언트/서버 패턴 참조
- **신규 기능 API** → `supabase`는 "훈련 데이터가 금방 낡는다"는 전제로 최신 문서를 재확인하도록 안내

본 프로젝트 고유 규칙(예: `db_init.sql` 단일 진실 소스, 한국어 UI, Riverpod Repository 패턴)은 여전히 `docs/BACKEND.md`를 기준으로 한다.

## 작업 순서

1. 먼저 `docs/BACKEND.md`를 읽어 현재 스키마, RLS 정책, Repository 패턴을 파악한다.
2. Supabase 공식 스킬이 활성화되어 있으면, 작업 맥락(쿼리 최적화/RLS/Auth 등)에 맞는 가이드도 함께 참조한다.
3. 수정 대상 파일을 읽고 현재 코드를 확인한다.
4. 변경을 구현한다:
   - 스키마 변경: `db_init.sql` 만 수정 (단일 진실 소스 — 별도 증분 마이그레이션
     파일은 만들지 않는다, `supabase/migrations/` 폐기됨)
   - RLS: 새 테이블에 반드시 RLS 정책 추가 (공식 스킬의 RLS 체크리스트 준수)
   - Repository: 기존 패턴 (SupabaseClient 주입, 결과를 모델로 변환) 유지
   - 쿼리: 성능 best-practices 준수 (N+1 방지, 인덱스 활용, RLS 함수 인라인화 등)
5. 변경 후 검증한다:
   - `flutter analyze`
   - `flutter test`
   - SQL 문법: Supabase SQL Editor에서 dry-run 또는 `EXPLAIN ANALYZE`

## 파일 범위

```
db_init.sql                     # 스키마 정의 (단일 진실 소스 — DROP & CREATE 전체)
supabase/
├── 200_stories/                # 이야기 시드 SQL
└── seeds/                      # 성경 구절 시드 SQL
lib/data/
├── auth_repository.dart        # 인증 (77줄)
├── story_repository.dart       # 이야기 쿼리 (382줄)
└── user_repository.dart        # 사용자 데이터 (485줄)
```

## 이 저장소 기본값

- `db_init.sql`은 DROP + CREATE로 로컬 재현 가능하게 작성
- RLS: 이야기 데이터는 공개 읽기, 사용자 데이터는 본인만
- Repository: `SupabaseClient`를 생성자 주입, Riverpod Provider로 제공
- 쿼리 결과를 `models/` 클래스로 변환 (fromMap 패턴)
- Supabase RPC 함수는 PostgreSQL 함수로 정의

## 가드레일

- `docs/BACKEND.md`를 읽지 않고 스키마를 수정하지 않는다.
- `db_init.sql` 수정 없이 마이그레이션만 만들지 않는다 (동기화 필수).
- 새 테이블에 RLS 정책을 빠뜨리지 않는다.
- 인증 정보(비밀번호, 토큰, API 키)를 코드/로그/URL 파라미터에 노출하지 않는다 (공식 skill 체크리스트 준수).
- Repository 메서드는 적절한 에러 처리를 포함한다.
- 성능 최적화 시 `supabase-postgres-best-practices`의 CRITICAL 규칙(query/connection/security)을 우선 확인한다.
- **TDD**: Repository 메소드를 추가/수정하기 전에 `test/data/`의 해당 테스트를 먼저
  작성/수정한다. mocktail로 `SupabaseClient` mock → 기대 호출 검증 → 구현.
  기존 테스트와 요구사항이 충돌하면 **사용자 확인 후** 테스트부터 변경.

## 문서 동기화

백엔드(`db_init.sql`, `supabase/`, `lib/data/`) 변경 시 **같은 커밋에서** 아래도 갱신한다. (CLAUDE.md 「문서 동기화 규칙」 참조)

- `docs/BACKEND.md` — 스키마 테이블, RLS 정책 표, PostgreSQL 함수/트리거, Repository 메소드 목록
- `docs/ARCHITECTURE.md` §3 (DB 스키마 개요) — 테이블 관계도 변경 시
- `docs/ADR.md` — 새로운 아키텍처 결정이 생기면 새 ADR 추가
- `db_init.sql` — 스키마 변경의 단일 진실 소스, 반드시 동기화
