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

> **모든 코드 변경은 TDD 순서를 따른다.** "TDD는 새 기능에만 쓰는 것"이 아니라
> **요구사항 해석 → 테스트 정렬 → 구현 변경**이라는 **작업 순서 원칙**이다.
>
> 요청이 들어오면 코드를 고치기 전에 **반드시**:
> 1. 관련 테스트가 이미 있는지 확인 (`test/` grep)
> 2. 요구사항과 기존 테스트를 **비교** — 기존 테스트가 요구사항과 충돌하면 이 테스트를
>    수정/삭제해야 하는데, 그건 사용자 확인 대상(§7)임
> 3. 테스트부터 먼저 갱신/추가 → `flutter test` 실패(Red) 확인
> 4. 구현 변경 → `flutter test` 통과(Green) 확인
> 5. 리팩토링 (테스트는 그대로 두고 구현만 정리)
>
> 이 순서를 지키면 "요구사항이 뭐였는지"가 항상 테스트 코드에 기록으로 남는다.

### 5.1 기존 기능 수정

> 예: "연속 출석일 계산 로직을 주말 제외로 바꿔줘"

```
1. Grep: computeDailyStreak 사용처 + 기존 테스트 위치 파악
   → lib/state/story_controller.dart 2곳 + test/state/streak_test.dart 발견
2. 요구사항 ↔ 기존 테스트 비교
   → 기존 테스트는 "주말 포함"으로 검증 중 → 테스트 수정 필요 →
     ⚠️ 사용자 확인 (§7 "기존 테스트 수정은 승인 필요")
3. 사용자 승인 후: 테스트 먼저 수정 → flutter test 실패 (Red)
4. 코드 수정 → flutter test 통과 (Green)
5. 리팩토링 (필요 시)
6. 문서 동기화 체크 (시그니처 변경 시만)
7. "완료. 커밋할까요?" → 사용자 결정 대기
```

### 5.2 새 기능 추가

> 예: "연속 출석일 누르면 캘린더 팝업 띄워줘"

```
1. 작업 분류: $backend + $frontend + $testing 필요
2. $testing: 요구사항을 테스트로 먼저 표현 (Red)
   - Repository 메소드 시그니처 테스트 (mocktail)
   - Controller 상태 전환 테스트
   - 위젯 렌더링 테스트
   → 모두 실패 확인
3. $backend: Repository 메소드 추가 → 해당 테스트 Green
4. $frontend: 위젯 파일 신설 + 화면 연결 → 위젯 테스트 Green
5. 전체 flutter test 통과 확인
6. 코드 메트릭 체크 (신규 파일 크기 적정한지)
7. 문서 동기화: FRONTEND.md, BACKEND.md, TESTING.md 갱신
8. "완료. 커밋할까요?" → 사용자 결정 대기
```

### 5.2.1 버그 수정

> 예: "지도 핀이 겹칠 때 앞 핀이 뒤 핀을 가린다"

```
1. Grep: 관련 렌더링 코드 + 기존 테스트 위치
2. 버그를 재현하는 실패 테스트 먼저 작성 (Red)
   → 현재 코드에서 테스트가 실패해야 "버그가 실제로 있음"이 증명됨
3. 코드 수정 → 테스트 통과 (Green)
4. 회귀 방지용으로 테스트는 영구 보존
5. "완료. 커밋할까요?"
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

거대 파일 재발 방지용 자동 검사 (`tools/lint/check_code_metrics.py`):

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

---

## 13. 린트/훅은 어떻게 선정되었는가 (중요)

> 이 프로젝트는 **코드가 먼저, 규칙이 나중에** 쌓인 구조다. 이상적 흐름과 실제 흐름이
> 다르다는 걸 인지하고 앞으로 어떻게 확장할지 이해해야 한다.

### 13.1 이상 vs 실제

```
이상:  프로젝트 시작 → 팀 코딩 스타일 합의 → 린트 규칙 확정 → 코드 작성
실제:  코드 먼저 쌓임 → 리팩토링 중 문제 발견 → 재발 방지용 린트/훅을 역으로 추가
```

현재의 `analysis_options.yaml` 10개 규칙은 `story_home_screen.dart`가 7,172줄까지
비대해진 걸 복구하면서 **역으로** 골라낸 것이다. `pre-commit`/`pre-push` hook도
같은 경로로 쌓였다. 앞으로의 신규 코드는 **규칙 → 코드** 방향(정방향)으로 작동한다.

### 13.2 `analysis_options.yaml` 규칙 선정 근거

| 카테고리 | 규칙 | 근거 |
|---|---|---|
| 안전성 | `cancel_subscriptions`, `close_sinks`, `unawaited_futures` | StreamSubscription/Sink 누수, Future 누락이 실제로 디버깅 난이도 높음 |
| 성능 | `prefer_const_*` 3종 | Flutter rebuild 폭발 방지 — 거대 화면에서 특히 중요 |
| 위젯 품질 | `sized_box_for_whitespace`, `use_key_in_widget_constructors`, `use_build_context_synchronously` | Flutter 공식 권장 + 비동기 이후 context 사용 버그 방지 |
| 코드 품질 | `prefer_final_locals`, `prefer_final_fields` | 불변성 기본값 → 상태 추적 용이 |

선정 원칙:
1. `dart fix --apply`로 자동 수정 가능한 것 우선 (기존 코드 일괄 수정 용이)
2. 큰 diff를 만드는 규칙(`require_trailing_commas`, `prefer_single_quotes`)은 보류
3. 프로젝트 위험도가 실제로 높았던 것 (`use_build_context_synchronously`)을 포함

### 13.3 앞으로 추가 검토할 규칙

| 규칙 | 효과 | 적용 시점 |
|---|---|---|
| `require_trailing_commas` | 포맷 diff 최소화 | `dart fix`로 일괄 적용 — 가까운 시일 |
| `prefer_single_quotes` | 따옴표 통일 | `dart fix`로 일괄 — 가까운 시일 |
| `always_declare_return_types` | 함수 시그니처 명시 | 수동 수정 필요 — 중기 |
| `avoid_dynamic_calls` | 타입 안전성 | 수동 수정 — 중기 |

### 13.4 pre-commit / pre-push 선정 근거

```
pre-commit  (가벼움, 매 커밋)     pre-push     (무거움, 푸시 전)
├ dart format                    ├ flutter analyze (0 issues 강제)
├ black (Python tools/)          ├ flutter test
├ import 정렬 (import_sorter)    ├ verify-asset-paths
├ forbidden patterns             └ code-metrics (현재 보고만)
├ check-large-files (2MB)
├ check-merge-conflict
├ check-yaml
├ end-of-file-fixer
└ trailing-whitespace
```

**분리 원칙**: 커밋은 자주 일어나므로 빠른 것만, 푸시는 원격 공유 전 마지막 게이트이므로
무거운 analyze/test도 감당한다.

### 13.5 현재 훅의 한계 — 앞으로 보강할 것

| 항목 | 현상 | 권장 |
|---|---|---|
| `code-metrics` 차단 모드 | `--ci` 없이 보고만 — 새 거대 파일 생성 못 막음 | 기존 FAIL 해소 후 `--ci` 추가 |
| 커버리지 회귀 체크 | 없음 | `lcov` 기준 최소 커버리지 설정 (중기) |
| 의존성 취약점 스캔 | 없음 | GitHub Dependabot 활성화 (즉시 가능) |
| 커밋 메시지 규칙 | 없음 | 팀 크기 작으므로 선택 사항 |
| Supabase 마이그레이션 순서 검증 | 없음 | 스크립트로 migrations/ 파일명 순서 + db_init.sql 대조 |

---

## 14. 프로젝트 구성 전체 요약 — 무엇이 어디에 어떻게 놓였는가

> "지금 이 프로젝트에 어떤 규칙/문서/스킬/훅이 구성되어 있고, 유지보수 시 어떻게
> 협력하는가"를 한눈에 볼 수 있도록 정리한 종합 지도이다.

### 14.1 Flutter 패턴 — 어떤 아키텍처를 따르는가

이 프로젝트는 Flutter 커뮤니티에서 흔한 **Repository + Riverpod Notifier** 계층형
아키텍처를 따른다.

```
┌─────────────────────────────────────────┐
│ UI 계층 (screens/, widgets/)            │  ← ConsumerWidget
│   ref.watch(storyControllerProvider)    │
├─────────────────────────────────────────┤
│ 상태 계층 (state/)                       │  ← Riverpod Notifier
│   StoryController → StoryState          │
│   (비즈니스 로직 + 불변 상태 copyWith)  │
├─────────────────────────────────────────┤
│ 데이터 계층 (data/)                      │  ← Repository
│   StoryRepository, UserRepository       │
│   (Supabase 쿼리 캡슐화)                 │
├─────────────────────────────────────────┤
│ 모델 계층 (models/)                      │  ← 순수 데이터 클래스
│   fromMap() 팩토리, 비즈니스 로직 없음  │
└─────────────────────────────────────────┘
             ↓
      supabase_flutter SDK → Supabase
```

**이 패턴의 특징과 파생 규칙**:

| 특징 | 그래서 어떤 하네스가 필요한가 |
|---|---|
| Riverpod `Notifier` + 불변 `State` 패턴 | `prefer_final_fields`, `prefer_final_locals` 린트로 불변성 강제 |
| `ConsumerWidget` 다수 리빌드 | `prefer_const_*` 3종으로 rebuild 최소화 |
| 비동기 많음 (Supabase I/O) | `unawaited_futures`, `use_build_context_synchronously` 린트 |
| 3단계 Provider 그래프 (Client→Repository→Controller) | `ProviderContainer + overrides`로 테스트 격리 (`test/state/`) |
| `fromMap()` 팩토리 패턴 | `test/models/`에서 JSON 경계 조건 테스트 |
| Repository가 Supabase SDK 직접 호출 | `mocktail`로 `SupabaseClient` mock (`test/data/`) |
| `part`/`part of` + `extension on State` (ADR-009) | `code-metrics`로 파일/메소드 크기 감시, part 파일은 부모에 귀속 |

### 14.2 문서 구조 — 무엇이 어디에 적혀 있는가

```
CLAUDE.md                      ← 메인 컨텍스트 (항상 로드, 120줄)
├── 빌드/실행 명령
├── 도메인 스킬 인덱스
├── 문서 동기화 규칙
├── 코딩 컨벤션 / TDD / 테스트 변경 정책
└── 커밋/푸시 정책

docs/
├── PRD.md                     ← 제품 요구사항 (뭘 만드는지)
├── ARCHITECTURE.md            ← 기술 아키텍처 (어떻게 만드는지)
│   └── §3 데이터 흐름 + 파일 간 연결 관계
├── ADR.md                     ← 아키텍처 결정 기록 (왜 이렇게)
├── UI_GUIDE.md                ← UI/UX 가이드 (어떻게 보여야 하는지)
├── FRONTEND.md                ← 프론트엔드 도메인 상세 ($frontend 스킬이 로드)
├── BACKEND.md                 ← 백엔드 도메인 상세 ($backend 스킬이 로드)
├── DATA_PIPELINE.md           ← 에셋/시딩 파이프라인 ($data-pipeline 스킬이 로드)
├── TESTING.md                 ← 테스트 전략 ($testing 스킬이 로드)
└── WORKFLOW_GUIDE.md          ← 본 문서 — 모든 것의 흐름 설명
```

**역할 분담 원칙**:
- `CLAUDE.md`: **인덱스 역할** — 뭐가 어디 있는지만 가리키고 상세는 docs/에 맡김
- `docs/*.md`: **도메인 레퍼런스** — 스킬이 그때그때 로드해서 컨텍스트로 사용
- 이 분리 덕분에 메인 Claude는 항상 가벼운 `CLAUDE.md`만 보고 필요할 때만 도메인 문서 로드

### 14.3 `CLAUDE.md` 세팅 — 에이전트에게 강제한 규칙

현재 `CLAUDE.md`에 명시된 에이전트 동작 규칙:

| 항목 | 규칙 |
|---|---|
| 스킬 인덱스 | 5개 도메인 스킬 + 참조 문서 + 파일 범위 표 |
| 병렬 탐색 | 큰 파일 분석은 Agent 병렬, 수정은 메인 직렬 |
| 문서 동기화 | 9가지 변경 유형별로 갱신해야 할 문서 지정 |
| TDD | 새 기능·버그 수정 시 테스트 먼저 |
| **테스트 변경 정책** | 기존 테스트 수정/삭제는 **사용자 확인 필수** |
| **커밋 정책** | 사용자가 "커밋해줘"라고 지시할 때만 |
| **푸시 정책** | 사용자가 "푸시해줘"라고 지시할 때만, 자동 push 절대 금지 |
| `print()` 금지 | `debugPrint` 사용 |
| 시크릿 금지 | forbidden-patterns hook으로 자동 차단 |

### 14.4 스킬 / 에이전트 / 플러그인 구성

| 구분 | 항목 | 역할 | 트리거 |
|---|---|---|---|
| **도메인 스킬** | `$frontend` | UI/위젯/상태 변경 | 자동 감지 or `$frontend` 명시 |
| | `$backend` | DB/Repository/RLS | 자동 감지 or `$backend` 명시 |
| | `$data-pipeline` | 에셋/시딩 | 자동 감지 or 명시 |
| | `$testing` | 테스트 작성 | 자동 감지 or 명시 |
| | `$refactor` | 대규모 분해/중복 제거 | 명시 |
| **Supabase 공식** | `supabase` | Auth, Storage, Edge Functions, RLS 가이드 | `$backend` 시 자동 |
| | `supabase-postgres-best-practices` | 쿼리 최적화, 인덱스 | `$backend` 시 자동 |
| **Agent (서브에이전트)** | `general-purpose` | 큰 파일 병렬 분석 | 메인이 호출 |
| | `Explore` / `Plan` / `code-reviewer` | 탐색/계획/리뷰 | 메인이 호출 |

### 14.5 유지보수 파이프라인 — 3단 방어선

```
┌─ 1단: 에디터 (실시간) ─────────────────────┐
│ analysis_options.yaml 11개 규칙             │
│ IDE 빨간/노란 밑줄 → Quick Fix              │
└───────────────────────────────────────────┘
              ↓ 커밋 시도
┌─ 2단: 로컬 git hook ──────────────────────┐
│ pre-commit: 포맷, import, 패턴, YAML       │
│ pre-push:   analyze + test + 에셋 + 메트릭 │
└───────────────────────────────────────────┘
              ↓ 원격 push
┌─ 3단: GitHub Actions CI ──────────────────┐
│ .github/workflows/flutter_ci.yml           │
│ 4 jobs: analyze+test / forbidden /         │
│         asset-paths / code-metrics         │
│ --no-verify로 로컬 우회해도 여기서 잡힘    │
└───────────────────────────────────────────┘
              ↓ PR 머지
            main 브랜치
```

### 14.6 커밋/푸시 세팅 — 경로별 방어

| 경로 | 검증 지점 | 내용 |
|---|---|---|
| **IDE 저장** | analyzer (실시간) | 11개 린트 규칙 즉시 경고 |
| **`git commit`** | pre-commit hooks | dart format, black, import sort, forbidden patterns, large files, merge conflicts, YAML 검증 |
| **`git push`** | pre-push hooks | `flutter analyze` (0 issues), `flutter test`, 에셋 경로 검증, code metrics 보고 |
| **PR 생성** | GitHub Actions | 로컬 검증 전체 재실행 (로컬 우회 방지) + 별도 job으로 forbidden/asset/metrics |
| **Claude 자동 행동** | CLAUDE.md 규칙 | 사용자 지시 없으면 커밋/푸시 **절대 안 함** |

**Claude 규칙 (CLAUDE.md + WORKFLOW_GUIDE.md 중복 명시)**:
```
코드 변경  → 스킬이 자동 수행
git add   → 스킬이 자동 수행 가능
git commit → 사용자가 "커밋해줘" 할 때만
git push  → 사용자가 "푸시해줘" 할 때만
gh pr create → 사용자가 "PR 만들어줘" 할 때만
```

### 14.7 유지보수 세팅 — 도구별 매핑

| 도구 | 위치 | 역할 | 언제 동작 |
|---|---|---|---|
| `analysis_options.yaml` | 루트 | 11개 린트 규칙 | IDE + `flutter analyze` |
| `.pre-commit-config.yaml` | 루트 | git hook 정의 | 커밋/푸시 시 |
| `tools/lint/check_forbidden_patterns.py` | tools/ | print/시크릿 차단 | pre-commit |
| `tools/lint/check_code_metrics.py` | tools/ | 파일/메소드 크기 감시 (500/1500줄, 80/200줄) | pre-push (보고) + CI |
| `tools/app/verify_asset_paths.py` | tools/ | pubspec ↔ 실제 파일 정합성 | pre-push + CI |
| `.github/workflows/flutter_ci.yml` | .github/ | 원격 CI (4 jobs) | push/PR |
| `pubspec.yaml` | 루트 | 의존성 + 에셋 목록 | `flutter pub get` |
| `db_init.sql` | 루트 | DB 스키마 단일 진실 소스 | 수동 (Supabase SQL Editor) |
| `supabase/migrations/` | supabase/ | 마이그레이션 보조 | 수동 |
| `Makefile` | 루트 | 에셋/시딩 파이프라인 | `make <target>` |

### 14.8 "요구사항 → 머지"까지 전체 흐름

```
[사용자 요청]
   │
   ├─ 1. 메인 Claude가 작업 분류 + 도메인 스킬 호출
   │      → 해당 docs/*.md 로드 (컨텍스트 확장)
   │
   ├─ 2. TDD 순서로 작업
   │      a. 기존 테스트 탐색 (grep)
   │      b. 요구사항 ↔ 기존 테스트 비교
   │      c. 테스트 수정/추가 (사용자 확인 필요 시 대기)
   │      d. Red 확인 → 구현 변경 → Green 확인
   │
   ├─ 3. 에디터 실시간 린트 (11개 규칙)
   │
   ├─ 4. "완료. 커밋할까요?" ← Claude 멈춤
   │
   ├─ 5. 사용자: "커밋해줘"
   │      → pre-commit hooks 통과해야 커밋 생성
   │
   ├─ 6. 사용자: "푸시해줘"
   │      → pre-push hooks 통과해야 원격 전송
   │
   ├─ 7. 사용자: "PR 만들어줘"
   │      → GitHub Actions CI 4 jobs 자동 실행
   │
   └─ 8. PR 머지 → main 브랜치 업데이트
```

**이 흐름의 설계 목표**:
1. **에이전트 자율성 제한**: 커밋/푸시는 사용자 결정으로 고정
2. **3단 방어**: 에디터/로컬/원격 어느 하나를 뚫어도 다음 단에서 잡힘
3. **컨텍스트 효율**: 도메인 스킬로 필요한 문서만 로드
4. **문서 일관성**: 코드 변경과 같은 커밋에서 관련 docs/*.md 동시 갱신
5. **테스트 = 명세**: 기존 테스트 변경은 사용자 승인 게이트로 보호

---

## 15. 알려진 이슈 / Gotchas

### 15.1 git worktree에서 pre-push 훅이 Flutter SDK 캐시를 오염시키는 문제

**증상**: `git push` 시 pre-push 훅의 `flutter analyze`/`flutter test`가
`The current Flutter SDK version is 0.0.0-unknown` 로 실패. `sign_in_with_apple`
등 SDK 버전 요구 패키지의 version solving이 깨진다.

**근본 원인**: pre-commit framework가 훅 실행 시 `GIT_DIR`/`GIT_WORK_TREE`
환경변수를 주입한다. Flutter tool이 자기 SDK 캐시를 갱신할 때 내부적으로
`git` 명령을 실행하는데, 이 환경변수 때문에 Flutter SDK가 아닌 **story_bible
프로젝트의 git에 대고 명령을 실행** → `flutter.version.json`이 story_bible의
repository URL/commit hash로 덮어씌워진다.

**대응**: `.pre-commit-config.yaml`의 `flutter-analyze`/`flutter-test` 엔트리에서
`GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`를 `unset` 한 뒤 `FLUTTER_ROOT` 명시,
오염된 캐시를 선제거하고 SDK 디렉토리에서 `flutter --version`을 먼저 실행해
정상 캐시를 확보한 다음 프로젝트 명령을 수행한다 (이미 적용됨). 캐시가 이미
오염된 경우 수동 복구:

```bash
rm $FLUTTER_ROOT/bin/cache/flutter.version.json
rm $FLUTTER_ROOT/bin/cache/flutter_tools.stamp
flutter --version  # 재생성
```

---

## 16. 이 문서의 유지보수 규칙

- 새 스킬/훅/CI job 추가 시 → §2, §13, §14 갱신
- 새 도메인 문서 추가 시 → §14.2 갱신
- TDD/테스트 정책 변경 시 → §5, §7 갱신
- 커밋/푸시 정책 변경 시 → §8, §14.6 갱신
- 알려진 이슈 발견 시 → §15에 증상/원인/대응 추가
- 의문점/오해를 사용자가 지적할 때마다 → 해당 섹션에 Q&A 형태로 추가 고려

---

## 17. 승인 후 작동 반영 프로세스 (제안 → 공개 이야기)

2026-04 도입된 **사역자 제안 → 관리자 승인 → 배포** 플로우의 end-to-end 순서.
이 섹션은 "관리자 / 운영자 관점" 기준. 사역자가 폼에 입력하는 UX 는
`lib/screens/proposal_submit_screen.dart` 참조.

### 17.1 한 장 요약

```
[사역자] 웹에서 제안 작성                    [관리자] 제안 상세에서 승인        [운영자] 로컬에서 freeze & publish
─────────────────────────                 ─────────────────────────         ────────────────────────────
Step 1 시대 → 2 인물 → 3 사건 → 4 세부      '승인' 버튼                        git pull
  - 기존 characters 선택                     ↓ approve_event_proposal RPC     make sync-approved-proposal-assets
  - 없는 인물 → [새 인물 만들기] 다이얼로그     1. proposed_characters 를        make thumbnails
    · AI 가 Vertex Imagen 으로 아바타 생성       characters 테이블에 upsert     make build-character-meta
    · proposal-characters/<uid>/<draft>/       (is_active=true)                 (새 인물이 있을 때만)
      <code>.png 에 업로드                     avatar_storage_path =           make seed-stories-characters
  - [이미지 생성] 버튼으로 각 장면 AI 생성       'proposal-characters/...'       make apply-seeds-stories-characters
    proposal-scenes/<uid>/<draft>/scene_N.png 2. insert_event_at_position     (선택) sync-approved-proposal-assets-clean
[제안 등록] → event_proposals row 생성        으로 events 행 생성                으로 원본 버킷 정리
                                              3. status='approved'            git commit + 앱 재빌드 → Store 배포
```

### 17.2 단계별 상세

#### 17.2.1 사역자: 제안 작성
- 웹에서 **이야기 등록** 진입 (pastor 역할 필요, §17.3 참조).
- Step 2 에서 등장인물을 고를 때 **[새 인물 만들기]** 버튼으로 기존 characters
  에 없는 인물도 추가 가능:
  - 다이얼로그에 이름(한글) + 영문 code + 설명(프롬프트) 입력
  - [이미지 생성] → Supabase Edge Function `generate-proposal-character` 가
    Vertex Imagen 4.0 으로 PNG 생성 → `proposal-characters/<uid>/<draft>/<code>.png`
  - 마음에 들 때까지 [다시 생성]. 확정 시 자동으로 선택 상태로 들어감.
- Step 4 에서 각 장면에 **[이미지 생성]** 버튼 — Edge Function
  `generate-proposal-scene` 가 Vertex Gemini 로 장면 PNG 생성 →
  `proposal-scenes/<uid>/<draft>/scene_N.png`
- 모든 장면 이미지가 준비되면 [제안 등록] 활성화 → `event_proposals` row 생성
  (status='pending', scene_image_paths + proposed_characters 포함).

#### 17.2.2 관리자: 승인 / 거절 — 내부 동작 상세

**승인** 버튼 → `approve_event_proposal(proposal_id)` RPC 한 번의 트랜잭션.
단계별:

1. **admin 권한 확인** — `is_admin()` 아니면 exception
2. **`proposed_characters` 순회** → 각각 `characters` 테이블에 **upsert**
   ```sql
   insert into characters (code, name, description,
                           avatar_storage_path, is_active)
   values (code, name, prompt, 'proposal-characters/{uid}/{draft}/{code}.png', true)
   on conflict (code) do update set
     name = coalesce(...), description = coalesce(...),
     avatar_storage_path = coalesce(...), is_active = true;
   ```
   - `avatar_storage_path` 는 **proposal-characters/... 경로 그대로** — 아직
     canonical `characters/` 버킷으로 옮기지 않음 (그건 `make
     sync-approved-proposal-assets` 시점에 일어남)
   - `is_active = true` 하드코딩 — admin 이 승인한 것 = 공개 OK 로 간주
     (수동 토글 원하면 Dashboard 에서 UPDATE)
3. **`insert_event_at_position` RPC** 로 `events` 테이블에 새 행 삽입
   - `scene_image_paths` 는 proposal 의 것을 그대로 복사
     (`proposal-scenes/{uid}/{draft}/scene_N.png`)
   - era 내 `story_index` 시프트 (+1) 로 자리 확보
   - `character_codes` 중 characters 테이블에 없는 건 `is_active=false`
     placeholder 로 INSERT (관리자가 나중에 토글 가능)
4. **`event_proposals` 상태 업데이트**
   ```sql
   update event_proposals set
     status = 'approved',
     reviewed_by_user_id = auth.uid(),
     reviewed_at = now(),
     approved_event_id = <events.id>
   where id = proposal_id;
   ```

**즉각적인 효과** — 승인 직후 모든 사용자가 새 이야기를 본다:
- 앱 홈 시대 재선택 / 리로드 시 events 테이블을 다시 읽어 새 이벤트 포함
- 이미지는 **하이브리드 로딩** 으로 로컬 번들에 없는 파일이라 Supabase
  Storage 에서 받음 (`proposal-scenes/...`, `proposal-characters/...`)
- `user_event_progress` 는 UUID 기반이라 기존 사용자 자동으로 "미완료"

**거절** 시엔 `status='rejected' + review_note`. 제안자가 상세 페이지에서
사유 확인 가능. 작성자 본인은 그 상태에서도 제안 삭제 가능 (RLS
`event_proposals_delete_own_unapproved`).

#### 17.2.3 운영자: 로컬 freeze & publish — **이게 이 섹션의 핵심**

승인된 제안의 AI 이미지는 일단 proposal-* 버킷에만 존재. **로컬 번들에
포함시키려면** 운영자가 로컬에서 pull 해서 assets/ 로 복사한 뒤 썸네일 생성 +
DB 재반영 + 앱 재빌드 + 스토어 배포 ([ADR-006] 이미지 번들 원칙).

##### Idempotency 모델 (중요)

`event_proposals.synced_to_local_at timestamptz` 컬럼이 "이 제안이 이미
로컬로 내려와 번들에 포함된 상태" 를 기록한다.

- 승인 직후: `synced_to_local_at IS NULL` → 다음 sync 대상
- 스크립트가 성공적으로 내려받으면 `synced_to_local_at = now()` PATCH
- 다시 `make sync-approved-proposal-assets` 를 돌리면 이 제안은 **자동으로
  스킵** — 불필요한 트래픽 없음
- 승인이 10개 쌓인 뒤 한 번에 sync 해도, 이미 7개가 sync 됐었다면 나머지
  3개만 처리

→ **admin 용 "동기화 상태 리스트 UI" 는 필요 없음.** SQL 로 한 줄:
```sql
select title, status, reviewed_at, synced_to_local_at
from event_proposals
where status = 'approved'
order by reviewed_at desc;
```

##### 표준 운영 레시피

```bash
# 0) pull
git checkout main && git pull

# 1) [dry-run] 어떤 제안이 sync 대상인지 먼저 확인
make sync-approved-proposal-assets-dry
#   출력 예:
#   approved & unsynced: 3 proposal(s)
#   == [uuid1] 엘리야와 까마귀   → scene[0] proposal-scenes/.../scene_1.png → assets/story_images/엘리야와_까마귀/scene_1.png
#   ...

# 2) 실제 실행 (synced_to_local_at NULL 인 것만)
make sync-approved-proposal-assets
#
#   결과:
#   - assets/story_images/<title>/scene_1..N.png
#   - assets/avatars/<new_code>.png
#   - characters 버킷에 <code>.png 업로드 (canonical)
#   - characters.avatar_storage_path = '<code>.png' 로 PATCH
#   - **event_proposals.synced_to_local_at = now()** (마커)

# 3) 런타임 썸네일 (avatars + story_images 양쪽 둘 다 처리)
make thumbnails

# 4) (새 캐릭터가 생긴 경우) character_meta.json 업데이트 후 재빌드
make build-character-meta

# 5) SQL 재생성 + DB 반영 (UPSERT, 재실행 안전)
make seed-stories-characters
make apply-seeds-stories-characters

# 6) 커밋 + 앱 빌드 + 스토어 배포
git add assets/avatars/ assets/story_images/ tools/seed/character_meta.json
git commit -m "content: 승인된 제안 반영 (<사건 제목>)"
git push
# → flutter build apk/ipa → 스토어

# 7) (배포 확정 후) proposal-* 버킷 원본 정리
#    ⚠️ 배포 전엔 절대 사용 금지 — 앱 업데이트 전 사용자는 하이브리드 fallback
#    으로 proposal-* URL 을 요청하는데 그 파일이 사라지면 이미지 깨짐.
make sync-approved-proposal-assets-clean
```

##### 특수 상황

**로컬 assets 를 통째로 날렸다 / 다른 머신에서 작업하다 돌아옴**
```bash
# synced_to_local_at 마커를 무시하고 전체 재동기화
make sync-approved-proposal-assets-all
```

**부분 실패 복구**
- sync 중 한 파일이라도 실패하면 그 proposal 은 `synced_to_local_at` 세팅이
  **안 됨** → 다음 run 에서 자동 재시도
- 에러 로그는 `[ERROR]` 로 출력됨

**승인 후 운영자가 캐릭터 `is_active` 를 끄고 싶을 때**
```sql
update characters set is_active = false where code = '<code>';
```

### 17.3 권한 요약

| 역할 | 검증 방법 | 허용 동작 |
|------|----------|----------|
| 일반 사용자 | auth.users 존재만 | 앱 사용, 제안 게시판 진입 시 pastor gate 팝업 |
| 사역자 (pastor) | `user_profiles.is_pastor = true` | 제안 작성/수정(본인 pending), 댓글, AI 이미지 생성 |
| 관리자 (admin) | `auth.users.raw_app_meta_data->>'role' = 'admin'` | 위 모든 권한 + 제안 승인/거절, characters 테이블 쓰기, Storage `characters` 버킷 쓰기 |

- pastor 부여: 운영자가 수동으로
  `update user_profiles set is_pastor=true where user_id=...`
  — 사역자가 `admin@brand-i.net` 으로 성함/사역 단체/직책을 보내면 처리.
- admin 부여: Supabase Dashboard SQL Editor 에서
  `update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{"role":"admin"}'::jsonb where id='<uuid>';`
  — 해당 사용자 **재로그인 필요** (JWT 갱신).

### 17.4 Storage 버킷

| 버킷 | public read | 쓰기 권한 | 경로 |
|------|:-----------:|----------|------|
| `profile-images` | ✅ | 본인 폴더 | `{uid}/profile_{ts}.{ext}` |
| `characters` | ✅ | admin 만 | `{code}.png` (정규 아바타) |
| `proposal-scenes` | ✅ | 본인 폴더 | `{uid}/{draft}/scene_{n}.png` |
| `proposal-characters` | ✅ | 본인 폴더 | `{uid}/{draft}/{code}.png` |

실제 업로드는 Edge Function 이 service role 키로 수행. RLS 는 방어선 역할.

### 17.6 하이브리드 에셋 로딩 (로컬 먼저 → Supabase fallback)

**왜**: 앱 번들 이미지는 Store 재심사 없이 바뀔 수 없지만, 제안 승인은 즉시
이뤄져야 한다. 반대로 모든 이미지를 항상 Supabase 에서 내려받으면 트래픽
과금이 폭증한다. 절충안은 "로컬 있으면 로컬, 없으면 Supabase":

- **캐릭터 아바타** (`CharacterAvatar` 위젯, `lib/widgets/character_avatar.dart`)
  - 1순위: `Image.asset('assets/avatars_thumbs/<code>.png')`
  - 2순위 (errorBuilder): `Image.network(publicUrl(character.avatarStoragePath))`
  - 3순위: 이름 첫 글자 이니셜 배경
- **장면 이미지** (`SceneAssetLoader`, `lib/utils/scene_asset_loader.dart`)
  - 1순위: `assets/story_images_thumbs/<safe_title>/scene_N.png` (AssetManifest 조회)
  - 2순위: `events.scene_image_paths` → Supabase Storage public URL
  - 3순위: 빈 리스트 (이미지 row 숨김)

**DB 측 양쪽 경로 저장**:
- `characters.avatar_url` — 로컬 번들 경로 (`assets/avatars/<code>.png`)
- `characters.avatar_storage_path` — Supabase 경로 (`characters/<code>.png`
  또는 `proposal-characters/...`)
- `events.scene_image_paths text[]` — proposal 승인 시 `proposal-scenes/...` 로
  채워지고, 운영자가 `sync-approved-proposal-assets` 로 로컬에 내린 뒤에도 그대로
  남아있음 (로컬 assets 가 1순위로 뜨므로 네트워크 호출 안 됨)

**비용 수렴 모델**:
1. 승인 직후: 로컬 번들에 없음 → Supabase 호출 발생
2. 운영자가 `sync-approved-proposal-assets` 실행 + 앱 재빌드 배포
3. 사용자가 업데이트 받음 → 로컬 번들에 포함 → 그 시점부터 Supabase 비용 0

### 17.7 Edge Function Secrets 셋업 (최초 1회)

Edge Function 이 Vertex AI 를 호출하려면 3개 secret 이 필요.

#### A. GCP service account 키 발급

1. [GCP Console](https://console.cloud.google.com) → 프로젝트 선택
2. **APIs & Services → Library** → "Vertex AI API" 검색 → Enable
3. **IAM & Admin → Service Accounts → + CREATE SERVICE ACCOUNT**
   - Name: `story-bible-vertex`
   - Role: `Vertex AI User` (`roles/aiplatform.user`)
4. 생성된 SA 클릭 → **Keys** → **ADD KEY → JSON → CREATE** → JSON 파일 자동 다운로드

#### B. JSON 을 한 줄 문자열로 변환

```bash
# 다운받은 JSON 경로로 바꿔서 실행
python3 -c "import json, sys; print(json.dumps(json.load(open(sys.argv[1]))))" \
  ~/Downloads/story-bible-vertex-abc123.json > /tmp/sa.oneline.json
```

#### C. Supabase secrets 등록

**CLI 경로** (추천):

```bash
# .env.supabase.secrets (repo 루트, .gitignore 됨)
cat > .env.supabase.secrets <<EOF
GOOGLE_CLOUD_PROJECT=<your GCP project id>
GOOGLE_CLOUD_LOCATION=us-central1
GCP_SERVICE_ACCOUNT_JSON=$(cat /tmp/sa.oneline.json)
EOF

supabase login                           # 최초 1회
supabase link --project-ref <ref>        # Dashboard URL 의 /project/<ref>
supabase secrets set --env-file .env.supabase.secrets
supabase secrets list                    # 3개 다 들어갔는지 확인
```

**Dashboard 경로** (GUI):
1. Supabase Dashboard → 프로젝트 선택
2. 좌측 **Edge Functions** → 우상단 **Manage secrets**
3. **Add new secret** 로 3개 항목 각각 등록
   - Name: `GOOGLE_CLOUD_PROJECT`, Value: `<your GCP project id>`
   - Name: `GOOGLE_CLOUD_LOCATION`, Value: `us-central1`
   - Name: `GCP_SERVICE_ACCOUNT_JSON`, Value: `<한 줄 JSON 전체>`
4. 저장 후 CLI 로 함수 배포:
   ```bash
   supabase functions deploy generate-proposal-scene
   supabase functions deploy generate-proposal-character
   ```

#### D. 동작 스모크 테스트

```bash
curl -i -X POST \
  "https://<ref>.supabase.co/functions/v1/generate-proposal-character" \
  -H "Authorization: Bearer <사용자 JWT>" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"test","characterCode":"_smoketest","characterName":"테스트","draftId":"smoke1"}'
```

기대 응답 스펙:
| HTTP | 의미 |
|------|------|
| 200 `{"storage_path":...}` | 정상 |
| 401 | Authorization 헤더 누락/만료 |
| 409 | 이미 active 인 canonical character code — 다른 code 사용 |
| 500 `secret not set` | CLI/Dashboard 에서 secrets 등록 안 됨 |
| 502 `Imagen ...` | SA 권한 부족 or Vertex API 미활성 |

### 17.8 고아 이미지 정리 (`cleanup-orphan-proposal-assets`)

**문제**: 사역자가 폼에서 **[이미지 생성]** 버튼을 누르는 순간 이미지는 즉시
`proposal-scenes` / `proposal-characters` 버킷에 업로드된다. 하지만
`event_proposals` 행은 **[제안 등록]** 을 눌러야 INSERT 된다. 그 사이에 창을
닫거나 재생성을 많이 하면 **DB에 참조 없는 고아 파일** 이 Storage 에 남는다.
GCP 생성 비용은 이미 지출됐지만 Storage 용량은 계속 과금 대상.

**해결**: `make cleanup-orphan-proposal-assets` 주기 실행 (주 1회 권장).

동작 규칙:
1. 두 버킷(`proposal-scenes`, `proposal-characters`) 의 **모든 파일**을 재귀 열거.
2. **세 테이블 전부** 에서 참조 경로를 union 해 "참조 중" 집합 생성:
   - `event_proposals.scene_image_paths` + `proposed_characters[*].storage_path`
   - `events.scene_image_paths` (승인된 이벤트의 하이브리드 fallback 보호)
   - `characters.avatar_storage_path` (proposal-characters 경로도 포함 가능)

   `events` 를 같이 봐야 하는 이유: admin 이 승인 후 원본 proposal row 를
   삭제해도 `events.scene_image_paths` 는 여전히 `proposal-scenes/...` 를
   가리킨다. 그 파일을 지우면 아직 앱 업데이트 안 받은 사용자의 하이브리드
   fallback 이 깨짐.
3. 파일 중 (a) 24h 이상 지났고 (b) 참조되지 않은 것만 삭제. 신규 업로드
   (= "진행 중인 드래프트") 는 24h grace window 로 보호.

```bash
# 먼저 dry-run 으로 삭제 후보 확인 (삭제 안 함)
make cleanup-orphan-proposal-assets-dry

# 실제 삭제 실행
make cleanup-orphan-proposal-assets
```

출력 예:
```
Cutoff: files older than 24h (created_at < 2026-04-21T00:00+00:00) considered
Referenced paths in event_proposals: 12

== proposal-scenes
  total files: 18
  [orphan] proposal-scenes/<uid>/draft_abcde/scene_0.png  age=2 days, 4:13:22  (deleting)
  ...

== proposal-characters
  total files: 5
  [orphan] proposal-characters/<uid>/draft_abcde/caleb.png  age=2 days, 4:10:01  (deleting)

=== Summary ===
  deleted:         6
  kept_referenced: 11
  kept_too_young:  5
  skipped:         1
  dry_run:         False
```

**주의**:
- 거절된 제안(status='rejected') 의 이미지는 참조가 남아있으니 **자동 정리 대상 아님**.
  원한다면 그 제안을 DB 에서 삭제하거나 스크립트를 확장할 수 있음 (현재 미구현).
- `.env` 에 `SUPABASE_SERVICE_ROLE_KEY_<ENV>` 필요 (service_role 로 실행).
- cron 등록 예:
  ```
  # 매주 일요일 03:00 KST 에 dev 환경 정리
  0 3 * * 0 cd /path/to/story_bible && make cleanup-orphan-proposal-assets ENV=dev
  ```

### 17.9 진행도 트래킹 — 새 이벤트/캐릭터 추가 시 자동 반영

- `user_event_progress(user_id, event_id)` 는 UUID 기반이라, 승인으로 새 event
  가 생기면 **누구의 user_event_progress 에도 그 UUID 가 없음** → 자동으로
  "아직 완료 안 함" 상태
- `CharacterStudyProgress.fetchCharacterStudyProgress` 는 `events_ordered` view
  를 매번 쿼리 → 새 event 가 포함되면 totalCount 자동 증가
- `insert_event_at_position` 은 story_index 만 시프트 — UUID 건드리지 않음 →
  기존 user_event_progress 행 그대로 유효
- 주의: 홈 화면이 열려있는 상태에서 다른 기기/관리자가 승인하면 — 시대
  바꾸거나 앱 재시작 전까진 새 이벤트가 안 보임 (pull-to-refresh 추가 여부는
  향후 과제)

### 17.5 관련 파일

- **Edge Functions** (장면 + 캐릭터 AI 생성):
  - `supabase/functions/generate-proposal-scene/` (Gemini multimodal)
  - `supabase/functions/generate-proposal-character/` (Imagen 4.0 text-to-image)
  - `supabase/functions/_shared/{gcp_auth,character_style,cors}.ts`
- **DB**: `db_init.sql` (테이블 / 버킷 / RPC / RLS)
- **Repository**: `lib/data/proposal_repository.dart` (RPC + functions.invoke 래퍼)
- **UI**:
  - `lib/screens/proposal_submit_screen.dart` (wizard)
  - `lib/widgets/proposal/new_character_dialog.dart` (새 인물 만들기)
  - `lib/widgets/proposal/proposal_scenes_editor.dart` (장면 + 이미지)
  - `lib/widgets/proposal/proposal_character_row.dart` (Step 4 상단 아바타 row)
  - `lib/screens/proposal_detail_screen.dart` (상세 — EventDetailPage 스타일)
- **Sync 스크립트**: `tools/supabase/sync_approved_proposal_assets.py`
- **Makefile 타겟**:
  - `make upload-character-avatars` (초기 아바타 일괄 업로드)
  - `make sync-approved-proposal-assets` / `...-clean` (승인 자산 로컬 동기화)
