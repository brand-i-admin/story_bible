---
name: backend
description: "백엔드(DB 스키마/쿼리/인증/RLS/Repository) 변경 시 사용하는 스킬. docs/BACKEND.md를 참조하여 db_init.sql, supabase/, lib/data/ 범위에서 작업한다."
---

# Backend

## 개요

Supabase 백엔드(DB 스키마, Repository 쿼리, RLS 정책, 인증, Storage)를 수정할 때 사용한다.

## 작업 순서

1. 먼저 `docs/BACKEND.md`를 읽어 현재 스키마, RLS 정책, Repository 패턴을 파악한다.
2. 수정 대상 파일을 읽고 현재 코드를 확인한다.
3. 변경을 구현한다:
   - 스키마 변경: `db_init.sql` 수정 (단일 진실 소스)
   - 마이그레이션: `supabase/migrations/` 에 날짜 접두사로 파일 생성
   - RLS: 새 테이블에 반드시 RLS 정책 추가
   - Repository: 기존 패턴 (SupabaseClient 주입, 결과를 모델로 변환) 유지
4. 변경 후 검증한다:
   - `flutter analyze`
   - `flutter test`
   - SQL 문법: Supabase SQL Editor에서 dry-run 가능한 경우 확인

## 파일 범위

```
db_init.sql                     # 스키마 정의 (단일 진실 소스)
supabase/
├── migrations/                 # 마이그레이션 SQL
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
- 인증 정보(비밀번호, 토큰)를 코드에 하드코딩하지 않는다.
- Repository 메서드는 적절한 에러 처리를 포함한다.
