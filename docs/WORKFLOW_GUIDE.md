# 워크플로 가이드 — Story Bible 코드 작업 + 유지보수

> 이 문서는 Claude Code를 사용해 코드를 수정/추가/삭제할 때의 전체 흐름,
> 스킬/에이전트가 어떻게 동작하는지, 그리고 유지보수 규칙을 정리한 가이드이다.
>
> 최종 수정: 2026-04-17

---

## 1. 전체 흐름 한눈에

```
[코드 작성 요청]
    │
    ├─ Claude Code: 작업 분류 + 스킬 호출 + 코드 수정
    ├─ Claude Code: "변경 완료. 커밋할까요?" ← 여기서 멈춤
    │
    ├─ 사용자: "커밋해줘" → 로컬 커밋 (pre-commit hooks 자동)
    ├─ 사용자: "푸시해줘" → GitHub push (pre-push hooks 자동)
    └─ 사용자: "PR 만들어줘" → PR 생성 (GitHub Actions CI 자동)
```

**핵심 원칙**:
- 코드 변경은 Claude Code가 하지만, **커밋/푸시/PR은 항상 사용자가 지시**.
- 자동으로 커밋하거나 push하지 않는다. (CLAUDE.md "룰" 참조)
- 기존 테스트 수정/삭제 시 사용자에게 먼저 확인받는다.

---

## 2. 스킬(Skill)이란?

**한 줄 요약**: "이 도메인 작업할 때 이 참고 문서를 읽어라"라는 지시서.

Claude Code는 평소 `CLAUDE.md`(~120줄)만 가진다. 전체 문서를 항상 읽으면
토큰 낭비이므로, 필요한 도메인의 문서만 **그때그때 로드**한다.

```
평소:
  CLAUDE.md (120줄) ← 빌드/실행/컨벤션/스킬 목록

$frontend 스킬 호출 시:
  CLAUDE.md
  + .claude/skills/frontend/SKILL.md (지시서)
    → docs/FRONTEND.md (파일 표, 위젯 목록, 패턴)
    → docs/UI_GUIDE.md (디자인 가이드)
  = 프론트엔드 컨텍스트 로드됨

$backend 스킬 호출 시:
  CLAUDE.md
  + .claude/skills/backend/SKILL.md
    → docs/BACKEND.md (DB 스키마, RLS, Repository)
  + Supabase 공식 플러그인 (자동 활성화)
  = 백엔드 컨텍스트 로드됨
```

### 현재 등록된 5개 스킬

| 스킬 | 언제 호출 | 로드하는 문서 | 파일 범위 |
|---|---|---|---|
| `$frontend` | UI/위젯/화면/상태 변경 | `docs/FRONTEND.md`, `docs/UI_GUIDE.md` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| `$backend` | DB/쿼리/인증/RLS 변경 | `docs/BACKEND.md` + Supabase 공식 플러그인 2개 | `db_init.sql`, `supabase/`, `lib/data/` |
| `$data-pipeline` | 에셋/시딩/Python 스크립트 | `docs/DATA_PIPELINE.md` | `tools/*.py`, `assets/`, `Makefile` |
| `$testing` | 테스트 작성/실행 | `docs/TESTING.md` | `test/` |
| `$refactor` | 대규모 분해/중복 제거 | 자체 절차 가이드 | 전체 (도메인 횡단) |

### 스킬 호출 방식

- **자동**: Claude Code가 작업 내용을 보고 "이건 프론트엔드다"라고 판단하면 알아서 호출
- **수동**: 사용자가 `$frontend` 또는 `$backend`라고 입력하면 강제 호출

---

## 3. Agent(서브에이전트)란?

**한 줄 요약**: 별도의 Claude를 하나 더 띄워서 병렬로 작업시키는 것.

스킬과 차이: 스킬은 메인 Claude가 문서를 추가 로드, Agent는 **별도 Claude가 독립 작업**.

```
메인 Claude (사용자와 대화 중)
  │
  ├── Agent A: "story_map_panel.dart 구조 분석해줘"
  ├── Agent B: "profile_tab_page.dart 구조 분석해줘"
  └── Agent C: "weekly_tab_page.dart 구조 분석해줘"
  
  (3개 동시 분석 → 각각 요약 반환)
  
메인 Claude: 결과 종합 → 리팩토링 계획 수립
```

### Agent 사용 규칙

| 상황 | 방법 | 이유 |
|---|---|---|
| 여러 큰 파일 분석 | Agent 병렬 | 메인 컨텍스트 절약 + 속도 |
| 영향 범위 조사 | Agent | grep으로 안 잡히는 로직 흐름 추적 |
| 실제 코드 수정 | **메인이 직접** | 여러 Agent가 동시에 같은 파일 수정하면 충돌 |
| 단일 파일 수정 | Agent 안 씀 | 오버헤드만 큼 |

**원칙: 탐색은 병렬, 수정은 직렬.**

---

## 4. 플러그인이란?

**한 줄 요약**: 외부 전문가 도구를 Claude Code에 연결.

현재 설치된 2개:
- `supabase@supabase-agent-skills` — Supabase 공식 가이드 (Auth, Storage, Edge Functions)
- `postgres-best-practices@supabase-agent-skills` — PostgreSQL 쿼리 최적화, 인덱스, RLS

`$backend` 스킬 호출 시 자동 활성화된다. 직접 건드릴 일 없음.

---

## 5. 작업 유형별 흐름

### 5.1 기존 기능 수정

> 예: "연속 출석일 계산 로직을 주말 제외로 바꿔줘"

```
1. Claude Code가 영향 범위 파악 (Grep)
   → computeDailyStreak 사용처 2곳 발견
2. TDD: 테스트 먼저 수정 → flutter test 실패 (Red)
3. 코드 수정 → flutter test 통과 (Green)
4. 문서 동기화 체크 (시그니처 변경 시만)
5. "완료. 커밋할까요?" → 사용자 결정 대기
```

### 5.2 새 기능 추가

> 예: "연속 출석일 누르면 캘린더 팝업 띄워줘"

```
1. 작업 분류: $backend + $frontend + $testing 필요
2. $backend: Repository 메소드 추가
3. $frontend: 위젯 파일 신설 + 기존 화면에 연결
4. $testing: 새 테스트 작성
5. 코드 메트릭 체크 (신규 파일 크기 적정한지)
6. 문서 동기화: FRONTEND.md, BACKEND.md, TESTING.md 갱신
7. "완료. 커밋할까요?" → 사용자 결정 대기
```

### 5.3 기능 삭제

> 예: "연속 출석일 기능 빼줘"

```
1. Agent 파견: 영향 범위 전수 조사 (삭제는 가장 위험)
2. 삭제 계획 + "유지할 것" 제시 → 사용자 승인 필수
3. UI부터 제거 (의존하는 쪽부터) → Repository → 테스트
4. 검증: flutter analyze + test → 죽은 코드 없는지 확인
5. 문서 동기화
6. "완료. 커밋할까요?" → 사용자 결정 대기
```

### 5.4 DB 변경이 필요한 요청

> 예: "사용자끼리 친구 추가 기능 만들어줘"

```
1. $backend 스킬 + Supabase 공식 플러그인 활성화
2. db_init.sql 수정 (스키마 단일 진실 소스)
3. 마이그레이션 SQL 파일 생성 (supabase/migrations/)
4. RLS 정책 설정 (Supabase 플러그인이 검증)
5. Repository Dart 코드 추가
6. Model 클래스 생성
7. $frontend: UI 위젯 추가
8. $testing: 테스트 작성
9. "완료. 커밋할까요?"
   ⚠️ "DB 마이그레이션은 직접 적용해야 합니다:
      Supabase Dashboard > SQL Editor에서 실행"
```

**중요**: Claude Code는 SQL 파일만 만들고, 실제 DB 적용은 사용자가 직접한다.
Claude Code는 Supabase에 직접 접속하지 않는다 (보안).

---

## 6. 유지보수 시스템 — 자동 검증 파이프라인

### 6.1 에디터 (실시간)

`analysis_options.yaml`의 10개 lint 규칙이 에디터에서 코드 치는 순간 경고를 표시.
빨간/노란 밑줄 → Quick Fix로 자동 수정 가능.

### 6.2 Pre-commit (git commit 시 자동)

| Hook | 역할 |
|---|---|
| `dart-format` | Dart 코드 포맷 검증 |
| `forbidden-patterns` | `print()`, JWT 시크릿, Google API key 차단 |
| `dart-import-sort` | import 순서 검증 |
| `black` | Python 코드 포맷 (tools/) |
| `check-large-files` | 2MB 이상 파일 차단 |
| `check-merge-conflict` | 머지 충돌 마커 차단 |

### 6.3 Pre-push (git push 시 자동)

| Hook | 역할 |
|---|---|
| `flutter-analyze` | 0 issues 강제 |
| `flutter-test` | 전체 테스트 통과 강제 |
| `verify-asset-paths` | pubspec.yaml ↔ 실제 파일 일치 검증 (215개) |
| `code-metrics` | 파일/메소드 크기 제한 보고 |

### 6.4 GitHub Actions CI (PR 시 자동)

pre-commit + pre-push의 모든 검사를 원격에서 한 번 더 실행.
`--no-verify`로 로컬 hook을 우회해도 PR 머지 전에 잡힘.

---

## 7. 테스트 변경 정책

테스트 코드 = "이 기능이 이렇게 동작해야 한다"는 명세(spec).

| 작업 | 정책 |
|---|---|
| 새 테스트 **추가** | 자유 (기존 동작 안 바뀜) |
| 기존 테스트 **수정** | 사용자에게 먼저 확인. "이 테스트를 이렇게 바꿔도 될까요?" |
| 기존 테스트 **삭제** | 사용자에게 먼저 확인. 삭제 이유 + 영향 설명. |
| `dart fix`에 의한 문법 변경 | 동작 안 바뀌므로 확인 불필요 |

---

## 8. 커밋/푸시 정책

| 행동 | 정책 |
|---|---|
| 코드 변경 | Claude Code가 알아서 함 (스킬 기반) |
| `git commit` | **사용자가 "커밋해줘"라고 지시할 때만** |
| `git push` | **사용자가 "푸시해줘"라고 지시할 때만** |
| `gh pr create` | **사용자가 "PR 만들어줘"라고 지시할 때만** |
| 자동 push | **절대 하지 않는다** |

---

## 9. 문서 동기화 규칙

코드 변경 후 Claude Code가 스스로 체크:
"이 변경으로 어떤 문서가 오래됐는가?"

| 변경 유형 | 갱신 대상 |
|---|---|
| 새 위젯/화면/모델 추가·이동·삭제 | `docs/FRONTEND.md` |
| DB 스키마/RLS/Repository 변경 | `docs/BACKEND.md`, `db_init.sql` |
| 새 Python 스크립트/Makefile 타겟 | `docs/DATA_PIPELINE.md` |
| 테스트 전략/커버리지 변화 | `docs/TESTING.md` |
| 중요한 아키텍처 결정 | `docs/ADR.md` |
| 스킬/훅/플러그인 변경 | `CLAUDE.md` |
| 빌드/실행 명령 변경 | `CLAUDE.md` |
| 의존성 추가/제거 | `pubspec.yaml` + `docs/FRONTEND.md` §6 |
| PRD 수준의 기능 추가/삭제 | `docs/PRD.md` |

---

## 10. 코드 메트릭 기준

거대 파일 재발 방지용 자동 검사 (`tools/check_code_metrics.py`):

| 항목 | 경고 | 차단 |
|---|---|---|
| 파일 줄 수 | 500줄 | 1,500줄 |
| 메소드/함수 수 | 20개 | 40개 |
| 단일 메소드 줄 수 | 80줄 | 200줄 |

test/ 파일은 기준 2배 완화. part 파일은 부모에 귀속되어 제외.

---

## 11. DB 변경 시 체크리스트

DB를 건드리는 작업 시 반드시:

```
□ db_init.sql 수정 (단일 진실 소스)
□ supabase/migrations/ 마이그레이션 SQL 생성
□ RLS 정책 설정 (공개 읽기 vs 사용자 전용)
□ lib/data/ Repository 메소드 추가/수정
□ lib/models/ Model 클래스 추가/수정 (fromMap)
□ test/ 새 Model의 fromMap 테스트 추가
□ docs/BACKEND.md 테이블·Repository 표 갱신
□ ⚠️ 사용자가 직접 Supabase Dashboard에서 마이그레이션 실행
```

현재 Supabase 접근 권한:
- 앱: `SUPABASE_ANON_KEY` (읽기/쓰기 — RLS 범위 내)
- Claude Code: DB 직접 접근 **없음** (SQL 파일만 생성)
- SERVICE_ROLE_KEY: 코드에 없음 (의도적 보안 설계)

---

## 12. 문서 인덱스

| 문서 | 역할 |
|---|---|
| `CLAUDE.md` | 메인 컨텍스트 — 빌드/실행/스킬/컨벤션/규칙 |
| `docs/PRD.md` | 제품 요구사항 — 뭘 만드는지 |
| `docs/ARCHITECTURE.md` | 기술 아키텍처 — 어떻게 만드는지 + 파일 연결 관계 |
| `docs/ADR.md` | 아키텍처 결정 기록 — 왜 이렇게 만드는지 |
| `docs/UI_GUIDE.md` | UI/UX 가이드 — 어떻게 보여야 하는지 |
| `docs/FRONTEND.md` | 프론트엔드 도메인 상세 |
| `docs/BACKEND.md` | 백엔드 도메인 상세 |
| `docs/DATA_PIPELINE.md` | 데이터 파이프라인 상세 |
| `docs/TESTING.md` | 테스트 전략 상세 |
| **`docs/WORKFLOW_GUIDE.md`** | **이 문서 — 작업 흐름 + 유지보수 규칙** |
