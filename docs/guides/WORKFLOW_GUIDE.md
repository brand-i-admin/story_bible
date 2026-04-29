# 워크플로 가이드 — Story Bible 코드 작업 + 유지보수

> 이 문서는 Claude Code를 사용해 코드를 수정/추가/삭제할 때의 전체 흐름,
> 스킬/에이전트가 어떻게 동작하는지, 그리고 유지보수 규칙을 정리한 가이드이다.
>
> 최종 수정: 2026-04-28

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
    → ../FRONTEND.md (파일 표, 위젯 목록, 패턴)
    → ../UI_GUIDE.md (디자인 가이드)
  = 프론트엔드 컨텍스트 로드됨

$backend 스킬 호출 시:
  CLAUDE.md
  + .claude/skills/backend/SKILL.md
    → ../BACKEND.md (DB 스키마, RLS, Repository)
  + Supabase 공식 플러그인 (자동 활성화)
  = 백엔드 컨텍스트 로드됨
```

### 현재 등록된 5개 스킬

| 스킬 | 언제 호출 | 로드하는 문서 | 파일 범위 |
|---|---|---|---|
| `$frontend` | UI/위젯/화면/상태 변경 | `../FRONTEND.md`, `../UI_GUIDE.md` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| `$backend` | DB/쿼리/인증/RLS 변경 | `../BACKEND.md` + Supabase 공식 플러그인 2개 | `db_init.sql`, `supabase/`, `lib/data/` |
| `$data-pipeline` | 에셋/시딩/Python 스크립트 | `../DATA_PIPELINE.md` | `tools/*.py`, `assets/`, `Makefile` |
| `$testing` | 테스트 작성/실행 | `../TESTING.md` | `test/` |
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

`analysis_options.yaml`의 11개 lint 규칙이 에디터에서 코드 치는 순간 경고를 표시.
빨간/노란 밑줄 → Quick Fix로 자동 수정 가능. (선정 근거 + 카테고리는 §13.2 참조)

### 6.2 Pre-commit (git commit 시 자동)

| Hook | 역할 |
|---|---|
| `dart-format` | Dart 코드 포맷 검증 |
| `forbidden-patterns` | `print()`, JWT 시크릿, Google API key 차단 |
| `dart-import-sort` | import 순서 검증 (`import_sorter`) |
| `black` | Python 코드 포맷 (tools/) |
| `check-added-large-files` | 2MB 이상 파일 차단 |
| `check-merge-conflict` | 머지 충돌 마커 차단 |
| `check-yaml` | YAML 문법 검증 |
| `end-of-file-fixer` | 파일 끝 개행 보장 |
| `trailing-whitespace` | 행 끝 공백 제거 |

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
| 새 위젯/화면/모델 추가·이동·삭제 | `../FRONTEND.md` |
| DB 스키마/RLS/Repository 변경 | `../BACKEND.md`, `db_init.sql` |
| 새 Python 스크립트/Makefile 타겟 | `../DATA_PIPELINE.md` |
| 테스트 전략/커버리지 변화 | `../TESTING.md` |
| 중요한 아키텍처 결정 | `../ADR.md` |
| 스킬/훅/플러그인 변경 | `CLAUDE.md` |
| 빌드/실행 명령 변경 | `CLAUDE.md` |
| 의존성 추가/제거 | `pubspec.yaml` + `../FRONTEND.md` §6 |
| PRD 수준의 기능 추가/삭제 | `../PRD.md` |

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
□ ../BACKEND.md 테이블·Repository 표 갱신
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
| `../PRD.md` | 제품 요구사항 — 뭘 만드는지 |
| `../ARCHITECTURE.md` | 기술 아키텍처 — 어떻게 만드는지 + 파일 연결 관계 |
| `../ADR.md` | 아키텍처 결정 기록 — 왜 이렇게 만드는지 |
| `../UI_GUIDE.md` | UI/UX 가이드 — 어떻게 보여야 하는지 |
| `../FRONTEND.md` | 프론트엔드 도메인 상세 |
| `../BACKEND.md` | 백엔드 도메인 상세 |
| `../DATA_PIPELINE.md` | 데이터 파이프라인 상세 |
| `../TESTING.md` | 테스트 전략 상세 |
| **`../WORKFLOW_GUIDE.md`** | **이 문서 — 작업 흐름 + 유지보수 규칙** |

---

## 13. 린트/훅은 어떻게 선정되었는가 (중요)

> 이 프로젝트는 **코드가 먼저, 규칙이 나중에** 쌓인 구조다. 이상적 흐름과 실제 흐름이
> 다르다는 걸 인지하고 앞으로 어떻게 확장할지 이해해야 한다.

### 13.1 이상 vs 실제

```
이상:  프로젝트 시작 → 팀 코딩 스타일 합의 → 린트 규칙 확정 → 코드 작성
실제:  코드 먼저 쌓임 → 리팩토링 중 문제 발견 → 재발 방지용 린트/훅을 역으로 추가
```

현재의 `analysis_options.yaml` 11개 규칙은 `story_home_screen.dart`가 7,172줄까지
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

## 17. 운영 셋업 — 권한 / 버킷 / Secrets / 정리 작업

> §18~§21 이 제안 라이프사이클(추가/삭제/위치 충돌/종합)을 시점별로 풀어 쓴
> 본체라면, 이 섹션은 그 흐름이 동작하기 위한 **상수 셋업** 과 **주변 정리
> 작업** 만 모은다. 단계별 데이터/스토리지 변화 자체는 §18~§21 을 참고.

### 17.1 권한 요약

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

### 17.2 Storage 버킷

| 버킷 | public read | 쓰기 권한 | 경로 |
|------|:-----------:|----------|------|
| `profile-images` | ✅ | 본인 폴더 | `{uid}/profile_{ts}.{ext}` |
| `characters` | ✅ | admin 만 | `{code}.png` (정규 아바타) |
| `proposal-scenes` | ✅ | 본인 폴더 | `{uid}/{draft}/scene_{n}.png` |
| `proposal-characters` | ✅ | 본인 폴더 | `{uid}/{draft}/{code}.png` |

실제 업로드는 Edge Function 이 service role 키로 수행. RLS 는 방어선 역할.

### 17.3 Edge Function Secrets 셋업 (최초 1회)

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

### 17.4 고아 이미지 정리 (`cleanup-orphan-proposal-assets`)

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

### 17.5 진행도 트래킹 — 새 이벤트/캐릭터 추가 시 자동 반영

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

### 17.6 관련 파일

- **Edge Functions** (장면 + 캐릭터 AI 생성):
  - `supabase/functions/generate-proposal-scene/` (Gemini multimodal)
  - `supabase/functions/generate-proposal-character/` (Imagen 4.0 text-to-image)
  - `supabase/functions/_shared/{gcp_auth,character_style,cors}.ts`
- **DB**: `db_init.sql` (테이블 / 버킷 / RPC / RLS)
- **고아 정리 스크립트**: `tools/supabase/cleanup_orphan_proposal_assets.py` (§17.4)
- **Makefile 타겟**:
  - `make upload-character-avatars` (초기 아바타 일괄 업로드, 1회)
  - `make cleanup-orphan-proposal-assets[-dry]` (§17.4)
  - `make sync-approved-proposal-assets[-dry|-all|-clean]` — 라이프사이클은 §18~§19 참조

> 라이프사이클 (제안 → 승인 → sync → 재배포) 본체와 관련 UI/Repository 파일은
> §18.6, §19.5, §20.6, §21.5 의 "관련 파일" 섹션에 정리되어 있다.

---

## 18. 자산/DB 라이프사이클 — 제안 → 승인 → 재배포 단계별 어디에 어떻게 저장되나

> "이야기가 제안되었을 때 / 승인되었지만 앱 재배포 안 됐을 때 / 앱 재배포가
> 끝났을 때" 세 시점에 각각 어떤 DB row 와 Storage 버킷이 쓰이는지, 그리고
> 앱 화면이 어느 경로로 이미지를 가져오는지를 한 자리에 정리한 섹션이다.
> 여기서 다루는 하이브리드 로딩 정책 (로컬 1순위 → Storage fallback) 의 동작
> 원리는 §18.2 "사용자가 이미지를 어떻게 보나" / §18.3 "사용자가 이미지를
> 어떻게 보나 (시점 C)" 절에서 함께 풀어 쓴다. 권한·버킷·Secrets 셋업은 §17 참조.

### 18.0 시점별 한 장 요약

```
┌─────────────────┬────────────────────┬────────────────────┬─────────────────────┐
│      시점        │    DB (Postgres)    │     Storage         │     앱 (사용자)      │
├─────────────────┼────────────────────┼────────────────────┼─────────────────────┤
│ A. 제안 작성     │ event_proposals    │ proposal-scenes/    │ 사용자 안 보임       │
│    (status=     │ (대기열)            │   <uid>/<draft>/    │ — 작성자/관리자만   │
│    'pending')   │                    │   scene_N.png       │   제안 게시판에서   │
│                 │ (proposed_chars   │ proposal-characters/│   본다              │
│                 │  if 있음 — JSON   │   <uid>/<draft>/    │                     │
│                 │  안에)            │   <code>.png        │                     │
├─────────────────┼────────────────────┼────────────────────┼─────────────────────┤
│ B. 승인됨,      │ events 행 추가     │ proposal-* 그대로   │ 모든 사용자 즉시 봄 │
│    재배포 전    │ characters         │ (아직 canonical로   │ — 이미지는          │
│    (즉시 노출)   │ upsert (신규 인물) │  복사 안 됨)        │   Storage fallback  │
│                 │ event_proposals.   │                    │   으로 매번 받음    │
│                 │   status='approved'│                    │   (트래픽 발생)     │
├─────────────────┼────────────────────┼────────────────────┼─────────────────────┤
│ C. sync 후      │ characters.        │ characters/        │ 로컬 1순위로 표시    │
│    재배포 완료   │   avatar_url=     │   <code>.png       │ — Storage 호출 0    │
│                 │   assets/avatars/. │ (canonical 복사)   │                     │
│                 │ event_proposals.   │ assets/ 번들에      │                     │
│                 │  synced_to_local_at│   동일 PNG          │                     │
└─────────────────┴────────────────────┴────────────────────┴─────────────────────┘
```

### 18.1 시점 A — 제안 작성 중 (status='pending')

#### 데이터 흐름

```
사역자가 폼 작성 (proposal_submit_screen.dart)
   │
   ├─ Step 4: [이미지 생성] 버튼
   │    │
   │    └─► supabase.functions.invoke('generate-proposal-scene')
   │           │
   │           ├─ Vertex Gemini 가 PNG 생성
   │           └─ Storage 'proposal-scenes/<uid>/<draft>/scene_N.png' 에 upsert
   │                  │
   │                  └─► 클라이언트가 path 받음 → _sceneImages[N] 에 보관
   │
   ├─ Step 2/3: [새 인물 만들기] 다이얼로그 (있을 때만)
   │    │
   │    └─► supabase.functions.invoke('generate-proposal-character')
   │           │
   │           ├─ Vertex Imagen 이 PNG 생성
   │           └─ Storage 'proposal-characters/<uid>/<draft>/<code>.png' 에 upsert
   │                  │
   │                  └─► 클라이언트가 ProposedCharacter 객체로 보관
   │                        (_newCharactersByCode)
   │
   └─ [제안 등록] 버튼
        │
        └─► RPC submit_event_proposal(...)
               │
               └─ event_proposals 테이블에 row INSERT
                  · status = 'pending'
                  · scene_image_paths = ['proposal-scenes/...', ...]
                  · proposed_characters = [{code, name, prompt, storage_path}, ...]
                  · quiz_questions = [...]  (이 시점에 인물은 characters
                    테이블에 아직 없음 — 승인 시점까지 보류)
```

#### 캐릭터 유무에 따른 차이

| 케이스 | DB | Storage |
|--------|----|---------|
| **기존 캐릭터만 사용** (예: 아담, 노아) | `event_proposals.character_codes = ['adam','noah']` 만 채움. `proposed_characters = []` | `proposal-scenes/...` 만 새로 업로드. 인물 아바타는 이미 `characters/<code>.png` 로 존재 |
| **새 캐릭터 1명 이상** (예: 테스터) | `character_codes = ['adam','tester']`, `proposed_characters = [{code:'tester', name:'테스터', prompt:'...', storage_path:'proposal-characters/...'}]` | `proposal-characters/<uid>/<draft>/tester.png` 추가 업로드. **`characters` 테이블에는 아직 row 없음** — 승인 전까지 placeholder 도 없음 |

#### 이 시점에 누가 무엇을 보나

| 누구 | 화면 | 어디서 이미지 로드 |
|------|------|------------------|
| 일반 사용자 | 영향 없음 — 기존 events/characters 만 보임 | 로컬 번들 |
| 작성자 본인 (사역자) | 제안 게시판 → 내 제안 → 상세 | `proposal-scenes/...`, `proposal-characters/...` (Image.network) |
| 관리자 | 제안 게시판 → 대기중 탭 → 상세 | 같음 |

이 단계의 자산은 **사용자 지도에 영향 없음** — `events` 테이블에 INSERT 되지 않았으므로.

### 18.2 시점 B — 승인됨, 앱 재배포 전 (status='approved' AND synced_to_local_at IS NULL)

#### 승인 트랜잭션 (`approve_event_proposal` RPC)

```
[관리자 — 제안 상세 → "승인" 버튼]
        │
        └─► ApproveProposalDialog (등장 인물 is_active 결정)
                │
                └─► supabase.rpc('approve_event_proposal',
                                  proposal_id, after_idx, char_active_overrides)
                       │
                       │ 한 트랜잭션 안에서:
                       │
                       ├─ 1. proposed_characters 순회 → characters UPSERT
                       │     · code, name(한글), description, avatar_storage_path
                       │       = 'proposal-characters/<uid>/<draft>/<code>.png'
                       │     · is_active = override 결과 (기본 true)
                       │     ⚠️ avatar_url 은 비워둠 — 아직 로컬 sync 전이라
                       │        canonical 'assets/avatars/...' 경로 부여 못함
                       │
                       ├─ 2. character_codes 중 characters 에 없는 코드는
                       │     placeholder row INSERT (is_active=false)
                       │
                       ├─ 3. insert_event_at_position(...) 호출
                       │     → events 테이블에 row 1개 추가
                       │     · scene_image_paths = proposal 의 것 그대로 복사
                       │       (즉 'proposal-scenes/<uid>/<draft>/scene_N.png')
                       │     · 같은 era 내 뒷 story_index 시프트
                       │     · status='published', deleted_at=null
                       │
                       ├─ 4. quiz_questions 테이블에 1~3개 row 풀어넣기
                       │
                       └─ 5. event_proposals UPDATE
                             · status='approved'
                             · approved_event_id = <events.id>
                             · synced_to_local_at IS NULL  ← 아직 로컬 미반영
```

#### 데이터 위치 (시점 B)

```
DB (Postgres)
├── events                            ← NEW row
│   · id = uuid
│   · scene_image_paths = [
│       'proposal-scenes/<uid>/<draft>/scene_1.png',  ← 아직 proposal-* 가리킴
│       'proposal-scenes/<uid>/<draft>/scene_2.png',
│       ...
│     ]
├── characters                        ← 신규 인물 추가됨 (있을 때)
│   · code = 'tester'
│   · name = '테스터'
│   · is_active = true  (관리자가 다이얼로그에서 결정)
│   · avatar_url = ''                  ← 비어있음 (로컬 번들 경로 미부여)
│   · avatar_storage_path = 'proposal-characters/<uid>/<draft>/tester.png'
├── quiz_questions                    ← row 1~3개
└── event_proposals
    · status = 'approved'
    · synced_to_local_at = NULL       ← 시점 B 마커

Storage
├── proposal-scenes/<uid>/<draft>/scene_N.png   (그대로 — 사용 중)
└── proposal-characters/<uid>/<draft>/<code>.png (그대로 — 사용 중)
```

#### 모든 사용자가 이미지를 어떻게 보나 (하이브리드 로딩 1차/2차/3차)

##### (1) 캐릭터 아바타 — `CharacterAvatar` 위젯

```
character.avatarUrl ('') + character.avatarStoragePath ('proposal-characters/...')
   │
   ├─ hasLocalAvatar?
   │   = avatar_url 이 'assets/avatars/...' 로 시작하는가?
   │   → false  (비어있음)
   │
   └─ Case 3 진입 — Storage 1차 사용
        │
        └─ Image.network(
             storage.from('proposal-characters')
                    .getPublicUrl('<uid>/<draft>/<code>.png')
           )
           실패 시 → 이름 첫 글자 fallback
```

##### (2) 장면 이미지 — `SceneAssetLoader.loadForEvent`

```
1순위: AssetManifest 에서 'assets/story_images_thumbs/<safe_title>/scene_N.png' 검색
       → 번들에 없음 (이 이야기는 새로 추가됐으므로)

2순위: event.sceneImagePaths 가 비어있지 않음 → 각 path 를 publicUrl 로 변환
       → 'https://<ref>.supabase.co/storage/v1/object/public/proposal-scenes/...'
       → Image.network 가 받아 표시
```

#### 이 시점의 트래픽 특성

- 신규 이야기를 보는 **모든 사용자**가 이미지 4장 + 신규 캐릭터 1+장씩 Storage 에서 다운로드
- Supabase Storage 는 public 버킷이라 CDN 캐시 발동 (같은 사용자가 두 번째 보면 로컬 브라우저/CDN 캐시 hit)
- 비용: 사용자 수 × 이미지 수 × 첫 view 1회 분량. 1000명 × 5장 × ~200KB ≈ **1GB/대유행 한 이야기당** 정도 — 운영자가 시점 C 까지 빨리 완료하면 부담 적음

### 18.3 시점 C — 운영자가 sync 실행 + 앱 재배포 완료

#### 재배포는 어떻게 이루어지는가 (운영자 표준 레시피)

> 핵심은 단 하나의 명령 — `make sync-approved-proposal-assets` 가 Phase A
> (다운로드) + Phase B (DB↔로컬 diff 정리) + Step C (썸네일) + Step D (pubspec
> 갱신) **네 단계를 자동으로 실행**한다. 운영자가 따로 `make thumbnails`,
> `make update-pubspec-assets` 를 부를 필요 없음. 다만 신규 인물이 추가된 경우
> seed 갱신만 별도로 한 번 더 돌려야 한다 (아래 5번).

##### 사전 준비 (한 번만)

```bash
# Python 가상환경 활성 — sync 스크립트가 requests 등 의존
source .venv/bin/activate

# .env 에 두 키가 있는지 확인 (없으면 sync 가 즉시 ERROR 종료)
grep -E "SUPABASE_URL_DEV|SUPABASE_SERVICE_ROLE_KEY_DEV" .env
#   → 둘 다 값이 있어야 함. service_role 키는 Storage 쓰기/PATCH 권한 필요.
#   → ENV=prod 로 운영 환경에 적용할 거면 SUPABASE_*_PROD 도 필요.
```

##### 1) 어떤 제안이 sync 대상인지 먼저 확인 (dry-run)

```bash
make sync-approved-proposal-assets-dry
```

내부 동작:
- `event_proposals` 에서 `status='approved' AND synced_to_local_at IS NULL`
  인 행을 모두 읽어 list 출력 (실제 다운로드/DB 변경 없음).
- 각 제안마다 어떤 파일이 어디로 갈지 미리 보여 줌.

기대 출력:
```
approved & unsynced: 3 proposal(s)
== [uuid1] 엘리야와 까마귀
   scene[0] proposal-scenes/<uid>/<draft>/scene_1.png
     → assets/story_images/엘리야와_까마귀/scene_1.png
   scene[1] proposal-scenes/<uid>/<draft>/scene_2.png
     → assets/story_images/엘리야와_까마귀/scene_2.png
   character[새] proposal-characters/<uid>/<draft>/elijah.png
     → assets/avatars/elijah.png + characters 버킷 업로드
...
Phase B (예상): event_dirs=2 (deleted_at), avatars=1 (is_active=false)
```

→ 결과를 보고 의도와 일치하는지 확인. 어긋나면 DB 상태 점검 후 재실행.

##### 2) 실제 sync 실행 — 4-phase 자동

```bash
make sync-approved-proposal-assets
```

`tools/supabase/sync_approved_proposal_assets.py --env dev` 가 다음 순서로
실행된다. 각 단계는 멱등 (재실행 안전).

**Phase A — 신규 승인 제안 다운로드**
1. `event_proposals` 에서 `status='approved' AND synced_to_local_at IS NULL`
   조회.
2. 각 제안마다:
   - `scene_image_paths` 의 PNG 다운로드 (`proposal-scenes/...` public URL)
     → `assets/story_images/<safe_title>/scene_N.png` 저장.
   - `proposed_characters[]` 의 PNG 다운로드
     → `assets/avatars/<code>.png` 저장.
   - 같은 PNG 바이트를 `characters` 버킷의 canonical `{code}.png` 로
     **service_role 키로 업로드**. 이걸로 `proposal-characters/...` →
     `characters/...` 로 자산 이동 완료.
   - DB PATCH: `characters` 의 `avatar_url='assets/avatars/<code>.png'`,
     `avatar_storage_path='<code>.png'` 로 갱신 (canonical 두 경로 동시 부여).
3. 모든 파일이 성공한 제안에만 `event_proposals.synced_to_local_at=now()`
   PATCH. **한 파일이라도 실패하면 마커 미세팅 → 다음 run 에서 자동 재시도**.

**Phase B — DB↔로컬 diff 정리** (소프트 삭제 / 비활성 캐릭터 흔적 제거)
1. `events` 중 `deleted_at IS NOT NULL` 행 조회.
2. 각 행마다:
   - `assets/story_images/<safe_title>/`, `assets/story_images_thumbs/<safe_title>/`
     디렉토리 제거 (이미 없으면 skip).
   - `events.scene_image_paths` 의 storage 파일 best-effort 삭제 (404 무시).
3. `characters` 중 `is_active=false` 행 조회.
4. 각 행마다:
   - `assets/avatars/<code>.png`, `assets/avatars_thumbs/<code>.png` 제거.
   - `characters.avatar_storage_path` 의 storage 파일 best-effort 삭제.

→ Phase B 만 끄고 싶으면 `--skip-deletions` (별도 워크플로우에서 정리할 때).

**Step C — 썸네일 자동 재생성** (Phase A 또는 B 에서 변경이 있을 때만)
- 내부적으로 `python tools/images/generate_runtime_thumbnails.py` 호출.
- `assets/avatars/` → `assets/avatars_thumbs/` (모든 PNG 압축 사본)
- `assets/story_images/<title>/` → `assets/story_images_thumbs/<title>/`
- 이미 있는 썸네일은 mtime 비교로 skip → 재실행 빠름.

**Step D — pubspec.yaml 자동 갱신** (Phase A 또는 B 에서 변경이 있을 때만)
- 내부적으로 `python tools/app/update_pubspec_assets.py` 호출.
- `pubspec.yaml` 의 `flutter.assets:` 아래 `story_images_thumbs/<title>/`
  엔트리를 실제 디렉토리 목록에 맞춰 추가/제거.
- `avatars_thumbs/` 는 이미 글롭 패턴 (`assets/avatars_thumbs/`) 으로
  등록돼 있어 손대지 않음.

→ Step C, D 둘 다 끄고 싶으면 `--skip-post-processing`.

기대 출력 (요약):
```
approved & unsynced: 3 proposal(s)
== [uuid1] 엘리야와 까마귀  (downloading 4 scene + 1 character)
   ✓ assets/story_images/엘리야와_까마귀/scene_1.png
   ✓ assets/avatars/elijah.png + characters bucket upload
   ✓ PATCH characters.avatar_url, avatar_storage_path
   ✓ PATCH event_proposals.synced_to_local_at
...
=== Phase B ===
   ✗ events deleted_at: 2 events → 2 dirs removed
   ✗ characters inactive: 1 → 1 avatar+thumb removed

[thumbnails] generated: 8, skipped: 215
[pubspec] added: 2 entries, removed: 1

=== Summary ===
  Phase A — synced (마커 갱신): 3
  Phase A — failed: 0
  Phase B — local 정리: event_dirs=2, avatars=1, thumbs=3

Next steps: 앱 재빌드 + 배포.
```

##### 3) 빌드 사전 검증

```bash
# (a) pubspec.yaml 이 실제 파일과 일치하는지 한 번 더 확인 (Step D 가 이미 처리했지만 안전 검증)
make check-pubspec-assets

# (b) Flutter 정적 분석 — 새 자산 경로 / SafeTitle 충돌 없는지
flutter analyze

# (c) 테스트 — 하이브리드 로딩 분기 깨지지 않았는지
flutter test
```

세 단계 다 0 issues / 0 failure 여야 다음으로 넘어감. 실패 시 sync 결과
(asset 경로, pubspec 엔트리) 를 점검하고 필요 시 `make
sync-approved-proposal-assets-all` 로 재동기화.

##### 4) 신규 캐릭터가 있을 때만 — character_meta.json 재생성

신규 인물이 한 명도 없으면 이 단계는 **건너뛴다**.

```bash
make build-character-meta
```

내부 동작:
- `assets/200_stories/*.json` 전체를 스캔 → 등장하는 모든 character code 수집.
- `tools/seed/character_meta.json` 갱신 (이름/설명/아바타 프롬프트 카탈로그).
- 이 파일은 다음 빌더 (`seed-characters`, `generate-avatars`) 의 입력.

##### 5) (선택) DB seed 파일을 현재 상태로 재생성

`approve_event_proposal` RPC 가 이미 `events` / `characters` 행을 INSERT 했
으므로 **운영 DB 자체에는 sync 가 필요 없다**. 다만 `db_init.sql + seed`
로 클린 부트스트랩하는 시나리오를 지원하려면 seed SQL 도 최신 상태로 유지
하는 게 좋다.

```bash
# (a) DB 현재 events 를 로컬 JSON 으로 역추출 (description 등 보존)
make export-stories-json ENV=dev

# (b) 그 JSON 을 입력으로 events + characters seed SQL 재생성
make seed-stories-characters

# (c) 생성된 SQL 을 운영 DB 에 UPSERT 로 재적용 (멱등 — 안전)
make apply-seeds-stories-characters ENV=dev
```

→ **신규 콘텐츠를 추가한 라운드면 5(c) 까지 모두 실행하는 게 안전**.
순수 삭제만 처리한 라운드면 5 단계 전체 생략 가능 (DB 가 이미 정답).

##### 6) 커밋 + 푸시

```bash
# 무엇이 변경됐는지 먼저 확인 — 의도하지 않은 파일이 들어가지 않는지 체크
git status
git diff --stat

# 변경 대상은 보통 다음 4가지뿐
git add \
  assets/avatars/ \
  assets/avatars_thumbs/ \
  assets/story_images/ \
  assets/story_images_thumbs/ \
  pubspec.yaml \
  tools/seed/character_meta.json \
  supabase/200_stories/  # 5번까지 돌렸을 때만

git commit -m "content: 승인된 제안 반영 — <사건 제목>"
git push origin <branch>   # 사용자 지시 후 실행
```

> ⚠️ **secrets 확인**: `.env`, `.env.supabase.secrets`, `*.json` 키 파일이
> 우연히 staging 에 들어가지 않았는지 `git status` 로 한 번 더 본다. forbidden
> patterns hook 이 자동 차단하지만 수동 확인이 안전.

##### 7) PR + 머지 + 앱 빌드

```bash
gh pr create   # 사용자 지시 후 실행

# 머지된 main 브랜치에서:
git checkout main && git pull

# Android (Play Console internal track 권장)
flutter build appbundle --release --dart-define=ENV=prod

# iOS (TestFlight)
flutter build ipa --release --dart-define=ENV=prod
```

이 빌드를 Play Console / App Store Connect 에 업로드 → 심사 통과 → 사용자
디바이스가 새 번들을 받으면 시점 C 진입 (로컬 1순위 로딩 → Storage 호출 0).

##### 8) 배포 확정 후 — proposal-* 버킷 원본 정리

```bash
make sync-approved-proposal-assets-clean
```

내부 동작 (Phase A 와 동일하지만 `--delete-source` 플래그):
- 이번 라운드에서 sync 한 제안의 `proposal-scenes/...`, `proposal-characters/...`
  원본을 **service_role 키로 삭제**.
- DB 의 `events.scene_image_paths` 는 그대로 (path 값은 더 이상 읽히지
  않으므로 무해).

> ⚠️ **이걸 8번 *전에* 돌리면 안 된다.** 구버전 앱을 쓰는 사용자는 아직
> 시점 B 동작 — `events.scene_image_paths` 의 `proposal-scenes/...` 를
> Storage 에서 가져온다. 그 파일이 사라지면 broken_image 로 보임.
> 권장 대기 기간: 강제 업데이트 안 걸리는 한 **앱 빌드 출시 후 1~2주**.

##### 트러블슈팅 / 특수 상황

| 상황 | 대응 |
|------|------|
| 로컬 `assets/` 를 통째로 날렸다 / 다른 머신에서 작업하다 돌아옴 | `make sync-approved-proposal-assets-all` — `synced_to_local_at` 마커 무시하고 처음부터 재동기화. Phase B 의 정리도 같이 다시 돌림 |
| Phase A 에서 한 파일이 실패해 마커 미세팅 | 다음 `make sync-approved-proposal-assets` 에 자동 재시도. 영구 실패면 로그의 `[ERROR]` 메시지로 원인 파악 (네트워크 / Storage 권한 / DB 경합) |
| 승인 후 운영자가 캐릭터 `is_active` 만 끄고 싶을 때 | `update characters set is_active=false where code='<code>';` → 다음 sync 의 Phase B 가 로컬 PNG + storage 파일 정리 |
| 사용자가 시점 C 도달 전 앱 업데이트를 안 받음 | 구버전 앱은 시점 B 동작 — `events.scene_image_paths` 의 Supabase URL 로 fallback. 8번을 미루면 양쪽 다 정상 동작 (§18.4 참고) |
| 빌드 파이프라인이 `flutter test` 에서 위젯 골든 차이 fail | 새 PNG 추가가 골든을 깰 가능성 → 의도한 변경이면 골든 갱신 후 별도 PR. sync 와 분리해 처리 |

#### 데이터 위치 (시점 C 완료 후)

```
앱 번들 (사용자 디바이스)
├── assets/avatars/<code>.png           ← canonical 위치
├── assets/avatars_thumbs/<code>.png    ← 런타임 썸네일
├── assets/story_images/<title>/scene_N.png
├── assets/story_images_thumbs/<title>/scene_N.png  ← 런타임 썸네일
└── pubspec.yaml 에 위 디렉토리들 등록

DB (Postgres)
├── events.scene_image_paths = [
│     'proposal-scenes/<uid>/<draft>/scene_1.png',  ← 그대로
│     ...
│   ]
│   ⚠️ DB 의 path 는 변경되지 않음 — 로컬 번들이 1순위라 안 읽힘
├── characters
│   · avatar_url = 'assets/avatars/<code>.png'      ← 이제 로컬 경로 부여됨
│   · avatar_storage_path = 'characters/<code>.png' ← canonical 위치
└── event_proposals.synced_to_local_at = <timestamp>

Storage
├── characters/<code>.png                ← canonical (sync 가 service_role 로 복사)
├── proposal-scenes/...                  ← 아직 남아있음 (정리 전)
└── proposal-characters/...              ← 아직 남아있음 (정리 전)
```

#### 사용자가 이미지를 어떻게 보나 (시점 C)

##### (1) 캐릭터 아바타

```
character.avatarUrl = 'assets/avatars/<code>.png'  ← 이제 로컬 경로
   │
   ├─ hasLocalAvatar = true
   │
   └─ Case 2 진입 — 로컬 1차
        │
        ├─ Image.asset('assets/avatars_thumbs/<code>.png')  (avatarAssetPath getter
        │   가 thumbs 로 매핑) → 즉시 표시
        └─ 만약 번들에 없으면 errorBuilder → storage URL fallback (≈ 일어날 일 없음)
```

##### (2) 장면 이미지

```
SceneAssetLoader.loadForEvent
   │
   ├─ 1순위: assets/story_images_thumbs/<safe_title>/scene_N.png
   │         AssetManifest 에 등록되어 있음 → 즉시 표시
   │
   └─ 2순위로 갈 일 없음 — Storage 호출 0
```

#### 비용 수렴 모델

```
Storage 트래픽
   │
   ▲
   │ ┌─ 시점 B 시작 (승인 즉시)
   │ │
   │ │ ▒▒▒▒▒▒▒▒▒▒▒▒▒  사용자가 신규 이야기를 처음 볼 때마다 다운로드
   │ │ ▒▒▒▒▒▒▒▒▒▒▒▒▒
   │ │
   │ └─ 시점 C 시작 (재배포 + 사용자 업데이트 받음)
   │
   │   ▁▁▁▁▁▁  로컬 번들로 흡수 — Storage 호출 0 수렴
   │
   └────────────────────► 시간
```

운영자가 시점 B 를 짧게 유지(승인 후 며칠 안에 sync + 재배포)하는 게 비용
관리의 핵심.

### 18.4 사용자가 시점 C 도달 전에 앱 업데이트를 안 받았다면?

```
사용자 A 디바이스 (구버전 앱 — 시점 B 동작)
  → 새 이야기 보기 시도
  → assets/ 번들에 없음 → events.scene_image_paths 의 proposal-scenes/...
  → Storage public URL 호출 → 정상 표시 ✅

사용자 B 디바이스 (신버전 앱 — 시점 C 동작)
  → 새 이야기 보기
  → assets/ 번들에 있음 (재배포 받음) → 즉시 로컬 표시 ✅
```

같은 DB 에서 두 종류 클라이언트가 공존해도 둘 다 정상 동작.

운영자가 `make sync-approved-proposal-assets-clean` 으로 proposal-* 정리
하기 전까지 **양쪽 fallback 모두 살아있음**. 정리는 모든 사용자가 새 앱
업데이트를 받았다고 확신할 때만 (보통 배포 후 1~2주).

### 18.5 한 줄로 요약하는 판별 규칙

| 어떤 이미지를 보고 있는지 알고 싶으면 | 확인 방법 |
|--------------------------------------|----------|
| 이 캐릭터의 아바타가 로컬에서 왔나, Storage 에서 왔나? | `character.avatar_url` 이 `assets/...` 면 로컬, 비어있으면 Storage |
| 이 장면 이미지가 로컬에서 왔나? | `assets/story_images_thumbs/<safe_title>/scene_N.png` 가 AssetManifest 에 있으면 로컬, 없으면 `events.scene_image_paths` 의 Storage URL |
| 이 제안이 sync 됐나? | `event_proposals.synced_to_local_at IS NOT NULL` |
| 다음 sync 가 필요한가? | `select count(*) from event_proposals where status='approved' and synced_to_local_at is null` |

### 18.6 관련 파일

- DB / RPC: `db_init.sql` 의 `approve_event_proposal`, `insert_event_at_position`,
  `event_proposals.synced_to_local_at` 컬럼
- 하이브리드 로딩:
  - `lib/widgets/character_avatar.dart` (3-tier: 로컬 → Storage → 이니셜)
  - `lib/utils/scene_asset_loader.dart` (3-tier: 로컬 → Storage → 빈 배열)
  - `lib/models/character.dart` (`hasLocalAvatar` getter)
- Sync 스크립트: `tools/supabase/sync_approved_proposal_assets.py`
- 정리 스크립트: `tools/supabase/cleanup_orphan_proposal_assets.py`
- Makefile 타겟: `sync-approved-proposal-assets[-dry|-all|-clean]`,
  `cleanup-orphan-proposal-assets[-dry]`,
  `apply-seeds-stories-characters`, `thumbnails`

---

## 19. 삭제 라이프사이클 — 제안 → 승인 → sync → 재배포

§18 이 "추가" 라이프사이클이라면, 이 섹션은 **삭제** 라이프사이클이다. 사역자가
이야기를 삭제 제안하고 관리자가 승인하면 이야기 + 그에 종속된 자산이 어디에서
어떻게 사라지는지 시점별로 정리한다.

### 19.1 한 장 요약

| 시점 | events.deleted_at | characters.is_active | local PNG | Storage PNG | 사용자에게 보임? |
|------|-------------------|----------------------|-----------|-------------|------------------|
| 제안 제출 직후 (`status='pending'`) | NULL | true | 그대로 | 그대로 | **보임** (아직 결정 전) |
| 관리자 승인 직후 (RPC 완료) | now() | 마지막 출연이면 false, 아니면 true | 그대로 | 1차 정리됨 | 안 보임 |
| 운영자 `make sync-approved-proposal-assets` 실행 후 | now() | 동일 | 정리됨 | 2차 정리됨 (잔존만) | 안 보임 |
| 앱 재배포 후 | now() | 동일 | 정리됨 | 정리됨 | 안 보임 (로컬 번들 자체에 없음) |

**핵심 invariant**: `events.deleted_at IS NOT NULL` 이 set 된 그 순간부터 사용자
는 이미 그 이야기를 못 본다. `events_ordered` view 가 `deleted_at IS NULL` 필터
를 걸기 때문. 후속 sync/재배포는 디스크/스토리지 비용 정리 + 캐릭터 일관성 보강
일 뿐 사용자 경험에 영향 없다.

### 19.2 시점별 상세

#### 19.2.1 시점 A — 사역자 삭제 제안 (`submit_delete_proposal` RPC)

`event_proposals` 에 `proposal_type='delete'`, `target_event_id` set, `status='pending'`
인 row 가 만들어진다. 이 단계에서는:

- `events.deleted_at` 은 그대로 NULL → 일반 사용자에게 그대로 보임 (관리자
  검토 중).
- 같은 target 에 또 다른 pending 삭제 제안이 들어오면 partial unique index
  (`event_proposals_unique_pending_delete`) 가 거부 — 중복 제안 방지.
- 사유 텍스트(`summary`) 는 관리자 검토 화면에 표시.

#### 19.2.2 시점 B — 관리자 승인 (`approve_delete_proposal` RPC)

이 RPC 한 번이 다음 4가지를 atomically 수행:

1. `events.deleted_at = now()` (idempotent: 이미 set 이면 no-op).
   → `events_ordered` 가 즉시 숨김 → 모든 사용자 화면에서 사라짐.
2. 이벤트의 `character_codes` 각 코드에 대해 다른 활성 이벤트(deleted_at IS NULL
   AND status='published') 가 그 코드를 참조하는지 카운트:
   - **0건** → 이 이벤트가 그 캐릭터의 마지막 출연 → `characters.is_active = false`
     로 비활성화. `characters_read_active` RLS 가 anon 에 대해 `is_active=true` 만
     노출하므로 **로컬 번들에 PNG 가 남아있어도 캐릭터 목록 fetch 결과에 안 들어옴**.
   - **1건 이상** → 그 캐릭터는 다른 이야기에서 살아있음 → 건드리지 않음.
3. `event_proposals` 를 `status='approved'`, `reviewed_by_user_id=auth.uid()`,
   `reviewed_at=now()`, `approved_event_id=target_event_id` 로 업데이트.
4. 클라이언트가 정리할 storage 경로 묶음을 jsonb 로 반환:
   - `scene_image_paths`: 이 이벤트의 장면 이미지 경로 (예: `proposal-scenes/<uid>/<draft>/scene_1.png`)
   - `inactive_character_avatar_paths`: 방금 비활성화된 캐릭터 아바타 경로

클라이언트 `lib/data/proposal_repository.dart::approveDelete` 가 이 두 묶음을
받아 **best-effort** 로 Supabase Storage 에서 제거 (`storage.from(bucket).remove([path])`).
이미 다른 경로에서 정리됐거나 권한 문제로 실패해도 무시 — 앱 동작에 영향 없음.

**왜 best-effort 인가**: storage 파일은 아래 시나리오들에서 이미 사라졌을 수 있다:
- `make sync-approved-proposal-assets-clean` (`--delete-source`) 가 돌아 proposal-* 원본 제거
- 같은 캐릭터의 다른 이야기 삭제 시 한 번 비활성화됐다가 재활성화 후 다시 비활성화
- 외부 운영자가 수동으로 정리

각 경우 remove() 가 404 에 가깝게 실패해도 클라이언트는 정상으로 간주한다.

#### 19.2.3 시점 C — 운영자 sync 실행 (`make sync-approved-proposal-assets`)

이 Makefile 타겟은 두 phase 를 실행한다:

**Phase A — 추가** (§18 에서 이미 다룬 내용): 새로 승인된 제안의 PNG 를 로컬로
다운로드 + characters/ 버킷으로 이동 + `synced_to_local_at` 마커 세팅.

**Phase B — 삭제** (NEW):

1. `events` 중 `deleted_at IS NOT NULL` 인 모든 row 조회 (service-role 키로 직접
   events 쿼리; `events_ordered` view 는 이걸 안 보여줌).
2. 각 이벤트마다:
   - 로컬 `assets/story_images/<safe_title>/` 디렉토리 제거 (이미 없으면 skip)
   - 로컬 `assets/story_images_thumbs/<safe_title>/` 디렉토리 제거
   - `scene_image_paths` 의 storage 파일 best-effort 삭제 (404 무시)
3. `characters` 중 `is_active = false` 인 모든 row 조회.
4. 각 캐릭터마다:
   - 로컬 `assets/avatars/<code>.png` 제거
   - 로컬 `assets/avatars_thumbs/<code>.png` 제거
   - `avatar_storage_path` 의 storage 파일 best-effort 삭제

**멱등성**: 별도 sync marker 없이 **파일 존재 여부**로만 판단. 이미 정리된
파일은 자연스럽게 skip → 같은 sync 를 N번 돌려도 안전.

**스킵 옵션**: Phase B 가 불필요하면 `--skip-deletions` 플래그 (예: 운영자가
local 정리를 별도 워크플로우로 하고 싶을 때).

#### 19.2.4 시점 D — 앱 재배포

운영자가 sync 후 `flutter build` + 앱 스토어 배포를 돌리면:

- 로컬 번들에서 삭제된 캐릭터/장면 PNG 가 빠진 새 빌드가 나간다.
- 이미 `events.deleted_at` / `is_active=false` 로 사용자에게는 안 보이고 있던 상태
  였으니, 이 단계는 **번들 크기 절감** + 신규 사용자가 받는 빌드의 정합성 확보
  목적.

### 19.3 비활성화된 캐릭터의 흔적

- `events.character_codes` 에는 inactive 코드가 그대로 남는다 (배열 컬럼이라
  무결성 검증 없음). `character_eras` view 가 `p.is_active = true` 로 join 하기
  때문에 그 캐릭터는 era 목록에서 자동 제외 → 시각적으로 영향 없음.
- 같은 코드로 다시 캐릭터가 등록되면 (예: 새 제안 승인) `approve_event_proposal`
  의 ON CONFLICT (code) 분기가 그 row 를 재활용해 `is_active = true` (또는 관리자
  override) 로 되살린다. 이 경우 **이전에 사용자에게 노출되던 동일 코드의 인물**
  로 자연스럽게 복구.

### 19.4 사용자가 시점 C 도달 전에 앱 업데이트를 안 받았다면?

- `events.deleted_at` 은 서버에 즉시 반영 → `events_ordered` 가 자동 필터.
- 사용자 앱이 events 목록을 다시 fetch 하는 순간 이야기가 사라짐 (홈 화면
  pull-to-refresh 또는 앱 재실행).
- 사용자가 그 이야기 상세 화면을 **이미 열어둔 상태** 라면? 그 화면은 캐시된
  StoryEvent 객체를 들고 있어 그대로 보일 수 있다. 다음 새로고침 시점에 자연
  소거. 이 경우의 사용자 진도(`user_event_progress`) 는 보존 — soft delete 의
  핵심 가치.

### 19.5 관련 파일

- DB / RPC: `db_init.sql` 의 `approve_delete_proposal`, `submit_delete_proposal`,
  `events.deleted_at`, `characters.is_active`
- Migration: `supabase/migrations/20260427_delete_proposal_storage_cleanup.sql`
- Client: `lib/data/proposal_repository.dart::approveDelete`,
  `lib/widgets/proposal/delete_event_proposal_sheet.dart`,
  `lib/screens/proposal_detail_screen.dart`
- Sync 스크립트: `tools/supabase/sync_approved_proposal_assets.py` Phase B
  (`fetch_soft_deleted_events`, `fetch_inactive_characters`, `sync_deletions`,
  `cleanup_storage_paths`)
- Makefile 타겟: `sync-approved-proposal-assets` (Phase A + B 자동),
  `--skip-deletions` 으로 Phase B 스킵 가능

---

## 20. 위치 충돌 → 재제출 라이프사이클 (NEW 제안 동시 승인 시나리오)

§18~§19 가 "한 제안의 라이프사이클" 이라면, 이 섹션은 **여러 NEW 제안이 같은
위치를 노릴 때** 의 충돌 해소 메커니즘을 설명한다.

### 20.1 시나리오

사역자 A 와 B 가 같은 era 에서 동일한 `after_story_index = 5` 로 새 이야기를 제안:
- A: 제목 "노아의 비둘기", 연도 [1500, 1510]
- B: 제목 "노아의 까마귀", 연도 [1505, 1515]

둘 다 `pending` 상태. 관리자가 A 를 먼저 승인한다고 가정.

`insert_event_at_position` 이 동작하면:
- A 는 `story_index = 6` 으로 INSERT (era 내 6번 자리)
- 기존 6, 7, 8 ... 은 7, 8, 9 ... 로 +1 시프트
- A 의 연도 [1500, 1510] 가 새 6번 자리에 자리 잡음

이제 B 의 제안을 보자:
- B 의 `after_story_index = 5` 는 그대로지만, 실제 의미는 모호해짐. "5번 다음"
  을 골랐을 때는 6번이 비어있었는데, 이제 6번에 A 가 있다.
- B 가 그대로 승인되면 새 6번에 들어가 A 가 7번으로 밀린다 — 하지만 그게 B 가
  원래 의도한 위치인지 확실치 않다. 게다가 A 의 연도(1500-1510)와 B 의 연도
  (1505-1515)가 겹쳐 시간 흐름이 부자연스러워질 수 있다.

→ 결론: **B 는 자동 통과시키지 않고 제안자에게 다시 결정하게** 해야 한다.

### 20.2 충돌 감지 + 잠금

`approve_event_proposal` RPC 가 A 의 events INSERT 를 마친 직후, 같은 era 에서
같은 `after_story_index` 를 노린 다른 pending NEW 제안들을 찾아 잠근다:

```sql
update event_proposals
set
  position_invalidated_at = now(),
  position_invalidation_reason = '같은 위치(...)에 다른 이야기 "..." 이(가) 먼저 승인되었어요. ...'
where era_id = :era
  and proposal_type = 'new'
  and status = 'pending'
  and id <> :approved_proposal_id
  and position_invalidated_at is null
  and after_story_index is not distinct from :approved_after_story_index;
```

`position_invalidated_at` 이 set 된 동안:
- `approve_event_proposal` / `reject_event_proposal` RPC 가 raise 로 거부.
  관리자 UI 도 **"승인" / "거절" 버튼이 비활성화** 되고 툴팁으로 안내.
- 제안 리스트/상세에 **빨간색 "수정 필요" 라벨** + 사유 배너가 노출 (제안자
  본인뿐 아니라 다른 사용자에게도 보임 — 투명성).
- 트리거 `notify_on_proposal_invalidated` 가 제안자에게 인앱 + 푸시 알림 발송.
  딥링크 = `/proposal/{id}` → 제안 상세로 진입하면 "위치 재선택" 버튼이 보임.

### 20.3 제안자 재제출 (`revise_proposal_position` RPC)

제안자 본인이 상세 화면의 빨간 **"위치 재선택"** 버튼을 누르면 다이얼로그가 뜬다:

1. 같은 era 의 **현재 활성 events 목록** 을 시간순으로 표시 (이미 A 가 들어있어
   사용자 시점에서 정확함).
2. "맨 앞 / 1번 다음 / 2번 다음 / ..." 라디오 선택.
3. 선택 즉시 **prev/next 이벤트의 연도 범위** 를 미리 보여준다 (예: "허용 연도
   범위: 1485 ≤ 시작 ≤ 끝 ≤ 1500").
4. 시작 연도 / 끝 연도 입력 — 클라이언트가 사전 검증 (`prev.endYear ≤ start ≤
   end ≤ next.startYear`), RPC 가 동일 규칙으로 한 번 더 검증.
5. **"재제출"** 클릭 → `revise_proposal_position(p_proposal_id,
   p_after_story_index, p_start_year, p_end_year)` 호출.

RPC 처리:
- `auth.uid() = proposer_user_id` 검증 (제안자 본인만 가능)
- `proposal_type = 'new' AND status = 'pending' AND position_invalidated_at IS
  NOT NULL` 검증
- `p_after_story_index` 가 era 안의 활성 이벤트 개수를 초과하지 않는지 검증
- 연도 검증 (위 4 와 동일 규칙)
- 통과 시:
  - `after_story_index`, `start_year`, `end_year` 갱신
  - `position_invalidated_at = NULL`, `position_invalidation_reason = NULL`
  - `updated_at = now()`

→ 잠금 해제. 관리자가 다시 approve/reject 가능.

### 20.4 한 장 요약

```
A 제출 (after=5)        B 제출 (after=5)            관리자 A 승인
       │                        │                          │
       ▼                        ▼                          ▼
   pending                  pending              ┌─ A → events INSERT
                                                 ├─ 충돌 감지: B 같은 era+after
                                                 │
                                                 ▼
                                          B.position_invalidated_at = now()
                                          + 알림 발송 (in-app + push)
                                                 │
                                B 의 상세 화면:    │
                                ┌── 빨간 "수정 필요" 라벨/배너  ◄────┘
                                ├── admin 의 "승인"/"거절" 버튼 잠김 (RPC 도 거부)
                                └── B 본인의 "위치 재선택" 버튼 활성
                                                 │
                                 B 가 다이얼로그 열고 새 위치/연도 선택
                                 → revise_proposal_position RPC
                                                 │
                                                 ▼
                                position_invalidated_at = NULL
                                                 │
                                                 ▼
                                관리자가 다시 approve/reject 가능
```

### 20.5 엣지 케이스

- **B 가 위치 재선택을 안 하고 방치**: 영구히 `pending + invalidated` 상태로
  남는다. 관리자는 어떤 액션도 못 하지만, RLS `event_proposals_delete_own_unapproved`
  정책상 **B 본인 또는 admin 이 제안 row 자체를 삭제** 할 수 있어 청소 가능.
- **세 명 이상 같은 위치**: 첫 번째 승인 시점에 나머지 모두가 한꺼번에 invalidate
  됨. 각자 따로 revise → 그 사이에 또 다른 승인이 일어나면 다시 invalidate 가능
  (멱등 — 이미 invalidate 된 row 는 트리거가 알림 중복 발송 안 함, `old.position_invalidated_at IS NULL → new IS NOT NULL` 전이일 때만 알림).
- **관리자 override 위치 사용**: `approve_event_proposal` 의
  `p_after_story_index_override` 로 admin 이 제안자가 고른 위치와 다른 자리에
  넣을 수도 있다. 이 경우 충돌 감지는 여전히 **제안의 원래 `after_story_index`**
  기준 (즉 admin override 가 같은 자리이면 다른 제안도 invalidate 되지만,
  override 가 다른 자리면 같은 제안끼리는 충돌 안 함).
- **연도 검증 회피 시도**: revise RPC 가 prev/next 검증을 강제 — 사용자가 클라이
  언트 검증을 우회해도 RPC 단에서 raise.

### 20.6 관련 파일

- DB / RPC: `db_init.sql` 의 `approve_event_proposal` (충돌 감지 블록),
  `reject_event_proposal` (잠금 검사), `revise_proposal_position` (신규),
  `notify_on_proposal_invalidated` 트리거,
  `event_proposals.position_invalidated_at`, `position_invalidation_reason`,
  `event_proposals_invalidated_idx` 부분 인덱스
- Migration: `supabase/migrations/20260427_proposal_position_invalidation.sql`
- Model: `lib/models/event_proposal.dart::positionInvalidatedAt`,
  `positionInvalidationReason`, `needsPositionRevision`
- Repository: `lib/data/proposal_repository.dart::revisePosition`
- UI:
  - `lib/screens/proposal_board_screen.dart` — 빨간 "수정 필요" 라벨
  - `lib/screens/proposal_detail_screen.dart` — 빨간 배너 + admin 버튼 잠금 +
    제안자 "위치 재선택" 버튼
  - `lib/widgets/proposal/revise_position_dialog.dart` — 위치/연도 다이얼로그

---

## 21. 제안 라이프사이클 종합 — 단계별 데이터/스토리지 변화 표

§18~§20 까지의 모든 단계를 한 자리에 모은 **종합 표 + 다이어그램**. 각 단계가
어떤 DB 테이블/뷰/스토리지를 어떻게 바꾸는지 한눈에 파악할 수 있다.

### 21.1 종합 흐름도

```
                                        [STORAGE]                              [DB]
사역자 제안 작성  ┌─ [Edge Function] ──► proposal-characters/<uid>/<draft>/<code>.png
   (이미지 생성)  └─                  ─► proposal-scenes/<uid>/<draft>/scene_N.png
                                        (upsert: 같은 경로면 덮어쓰기)

사역자 "제안 등록"   ────────────────────────────────────────► event_proposals INSERT
                                                              (status='pending')

                ┌────────────── 두 갈래 ──────────────┐
                ▼                                       ▼
    관리자 "거절"                              관리자 "승인"
        │                                          │
        ├─ proposal-scenes/* 삭제                  ├─ events INSERT (UNIQUE title)
        ├─ proposal-characters/* 삭제              │   character_codes,
        │   (단, code 가 다른 row 에서             │   scene_image_paths='proposal-scenes/...'
        │    재사용 중이면 보존)                   │   (story_index 시프트)
        ├─ event_proposals row 유지 →             ├─ characters UPSERT (신규 인물)
        │   status='rejected'                      │   avatar_storage_path='proposal-characters/...'
        ├─ 알림: notify_on_proposal_reviewed       │   is_active=관리자 결정
        └─ (UI: 본인이 row 자체 삭제 가능)         ├─ quiz_questions INSERT (choices 셔플)
                                                   ├─ event_proposals UPDATE
                                                   │   status='approved', approved_event_id
                                                   ├─ 같은 era+after_idx 다른 pending →
                                                   │   position_invalidated_at = now()
                                                   └─ 알림: 승인 + 충돌자에게 "수정 필요"
                                                          │
                                                          ▼
                                              운영자: make sync-approved-proposal-assets
                                              ┌──────────── Phase A ─────────────┐
                                              │ proposal-* → 로컬 assets/        │
                                              │ proposal-characters → characters │
                                              │ characters.avatar_storage_path    │
                                              │   = '<code>.png' (PATCH)         │
                                              │ synced_to_local_at = now()       │
                                              ├──────────── Phase B (diff) ──────┤
                                              │ DB events vs 로컬 dir → 차이 정리 │
                                              │ DB characters vs 로컬 PNG → 차이  │
                                              ├──────────── Step C ──────────────┤
                                              │ make thumbnails                  │
                                              ├──────────── Step D ──────────────┤
                                              │ make update-pubspec-assets       │
                                              └───────────────────────────────────┘
                                                          │
                                                          ▼
                                              운영자: flutter build + 앱 배포


[삭제 제안 분기]
사역자 "이 이야기 삭제 제안" → event_proposals INSERT (proposal_type='delete')

                ┌────────────── 관리자 ──────────────┐
                ▼                                       ▼
    "거절"                                       "승인"
        └─ status='rejected'                     ├─ DELETE FROM events
                                                 │   (cascade quiz_questions,
                                                 │    user_event_progress)
                                                 ├─ 다른 events 에 안 쓰이면
                                                 │   DELETE FROM characters
                                                 ├─ proposal-scenes/ 정리
                                                 ├─ proposal-characters/ 정리
                                                 │   (방금 삭제된 캐릭터만)
                                                 └─ event_proposals UPDATE
                                                     status='approved'
```

### 21.2 단계별 변경 항목 표

| 단계 | event_proposals | events | events_ordered (view) | characters | character_eras (view) | quiz_questions | proposal-scenes/ | proposal-characters/ | 로컬 `assets/` | pubspec.yaml |
|------|-----------------|--------|------------------------|------------|------------------------|----------------|-------------------|----------------------|----------------|--------------|
| **1. 제안 작성** (이미지 생성) | — | — | — | — | — | — | INSERT `<uid>/<draft>/scene_N.png` | INSERT `<uid>/<draft>/<code>.png` (신규 인물만) | — | — |
| **2. 제안 등록** (`submit_event_proposal`) | INSERT row (status='pending') | — | — | — | — | — | (변동 없음) | (변동 없음) | — | — |
| **3. 제안 수정** (재제출) | UPDATE row | — | — | — | — | — | OVERWRITE (같은 경로) | OVERWRITE (같은 경로) | — | — |
| **4. 거절** (`reject_event_proposal`) | UPDATE status='rejected' | — | — | — | — | — | DELETE 전체 | DELETE (이 제안에서만 쓰는 신규 캐릭터만) | — | — |
| **5. 승인** (`approve_event_proposal`) | UPDATE status='approved', approved_event_id | INSERT (UNIQUE title 검증) | (자동 갱신) | UPSERT 신규 + is_active 결정 | (자동 갱신) | INSERT (choices **셔플** + answer_index 재계산) | (그대로) | (그대로) | — | — |
| **5a. 충돌 감지** (같은 era + 같은 after_idx 의 다른 pending) | UPDATE position_invalidated_at = now() | — | — | — | — | — | — | — | — | — |
| **5b. 위치 재선택** (`revise_proposal_position`) | UPDATE after_story_index, start/end_year, position_invalidated_at = NULL | — | — | — | — | — | — | — | — | — |
| **6. 삭제 제안 등록** (`submit_delete_proposal`) | INSERT (proposal_type='delete') | — | — | — | — | — | — | — | — | — |
| **7. 삭제 승인** (`approve_delete_proposal`) | UPDATE status='approved' | **DELETE row** | (자동 갱신) | DELETE (이 이벤트만 쓰던 캐릭터) | (자동 갱신) | DELETE cascade | (그대로 — 클라이언트가 정리 호출) | DELETE (방금 삭제된 캐릭터의 PNG) | — | — |
| **8. Sync Phase A** (추가) | UPDATE synced_to_local_at | — | — | UPDATE avatar_storage_path = `<code>.png` | — | — | (그대로) | MOVE → `characters/<code>.png` 버킷 | DOWNLOAD `assets/avatars/<code>.png`, `assets/story_images/<title>/scene_N.png` | — |
| **9. Sync Phase B** (diff 정리) | — | — | — | — | — | — | — | — | DELETE 로컬 dir/PNG (DB 와 차이) | — |
| **10. Sync Step C** (`make thumbnails`) | — | — | — | — | — | — | — | — | GENERATE `assets/avatars_thumbs/`, `assets/story_images_thumbs/<title>/scene_N.jpg` | — |
| **11. Sync Step D** (`make update-pubspec-assets`) | — | — | — | — | — | — | — | — | — | UPDATE `flutter.assets:` 의 story_images_thumbs/<title>/ 엔트리 |
| **12. 앱 배포** (`flutter build` + release) | — | — | — | — | — | — | — | — | (번들에 포함) | (번들에 포함) |

> 📌 **메모**:
> - **events_ordered, character_eras 는 VIEW** — events/characters 변경 시 자동
>   재계산. 별도 인덱스 재구성/INSERT/DELETE 필요 없음.
> - **quiz_questions** 는 events FK `ON DELETE CASCADE` — 이벤트 hard delete 시
>   퀴즈도 자동 삭제.
> - **user_event_progress** 도 events FK `ON DELETE CASCADE` — hard delete 시
>   사용자 학습 진도가 함께 cascade 삭제됨 (수용한 트레이드오프).
> - **events.deleted_at / characters.is_active** 컬럼은 backward-compat 위해
>   유지하되 신규 흐름에서는 set 되지 않음 (vestigial).
> - **avatars_thumbs/** 는 pubspec.yaml 에 글롭 패턴 (`assets/avatars_thumbs/`) 으로
>   등록되어 있어 PNG 추가/삭제 시 pubspec 변경 불필요. 반면
>   **story_images_thumbs/** 는 디렉토리별로 따로 등록되어 있어 추가/삭제 시
>   pubspec 동기화 필요 (`make update-pubspec-assets` 가 처리).

### 21.3 Title UNIQUE 제약 — 왜 필요한가

`events.title` 은 GLOBAL UNIQUE 다. 두 가지 이유:

1. **로컬 번들 디렉토리명 충돌**: 빌드 시 `assets/story_images_thumbs/<title>/`
   가 만들어진다. 같은 title 의 이야기 두 개가 있으면 디렉토리가 합쳐져 어느
   장면이 어느 이벤트의 것인지 모호해짐.
2. **사용자 식별성**: 같은 제목의 이야기 두 개가 있으면 검색/공유 링크/딥링크가
   불명확.

검증 지점은 두 곳:
- **`submit_event_proposal` RPC** — 제안 제출 단계에서 다음 둘 중 하나라도
  걸리면 raise:
  - 활성 events 에 같은 제목 존재
  - 다른 사역자의 pending NEW 제안에 같은 제목 존재 (대소문자/공백 정규화 후 비교)
- **`events.title UNIQUE` 제약** — 승인 RPC 의 INSERT 단계에서 마지막 방어선.

### 21.4 Quiz answer_index 셔플 — 왜 필요한가

`approve_event_proposal` 가 `quiz_questions` 에 INSERT 할 때 `choices` 배열을
**0..3 의 무작위 순열로 재배치** 하고 `answer_index` 를 새 위치로 재계산한다.

목적: 사역자가 무의식 중에 항상 1번째 자리에 정답을 두는 습관이 있어도 사용자
에게는 정답 위치가 분산되어 보임. 패턴 학습으로 인한 추측 정확도 저하.

구현은 SQL `random()` + `row_number() over (order by random())` 으로 4개 인덱스의
무작위 순열을 만든 뒤, 원래 `choices[answer_index]` 가 새 인덱스 어디로 갔는지를
추적해 `answer_index` 갱신.

### 21.5 관련 파일

- DB / RPC: `db_init.sql` (모든 RPC 본문),
  `events.title UNIQUE` 제약,
  `event_proposals.position_invalidated_at`,
  `event_proposals.synced_to_local_at`
- Migration (이번 라운드 통합): `supabase/migrations/20260427_proposal_lifecycle_overhaul.sql`
- Sync 스크립트: `tools/supabase/sync_approved_proposal_assets.py`
  (Phase A 추가 / Phase B diff 정리 / Step C thumbnails / Step D pubspec)
- Make 타겟: `make sync-approved-proposal-assets[-all|-dry|-clean]`,
  `make thumbnails`, `make update-pubspec-assets`
