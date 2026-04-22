# Story Bible — 인터랙티브 성경 지도 학습 앱

Flutter + Supabase 기반. 215개 성경 이야기를 인물별로 지도 위에 표시하고, 퀴즈/학습 추적/기도 공유 기능을 제공한다.

## 빌드 & 실행

```bash
flutter pub get              # 의존성 설치
flutter run                  # 앱 실행 (기본 dev 환경)
flutter run --dart-define=ENV=prod  # 운영 환경 실행
flutter analyze              # 린트 검사
flutter test                 # 전체 테스트
dart format .                # 코드 포맷
```

## 도메인별 스킬 (서브에이전트)

작업 영역에 따라 적절한 스킬을 사용하면 해당 도메인의 컨텍스트만 로드하여 토큰 효율적으로 작업할 수 있다.

| 작업 | 스킬 | 참조 문서 | 파일 범위 |
|------|------|----------|----------|
| UI/위젯/화면/상태 변경 | `$frontend` | `docs/FRONTEND.md`, `docs/UI_GUIDE.md` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| DB 스키마/쿼리/인증 변경 | `$backend` | `docs/BACKEND.md` + 공식 `supabase`, `supabase-postgres-best-practices` | `db_init.sql`, `supabase/`, `lib/data/` |
| 에셋 생성/DB 시딩 | `$data-pipeline` | `docs/DATA_PIPELINE.md` | `tools/*.py`, `assets/`, `Makefile` |
| 테스트 작성/실행 | `$testing` | `docs/TESTING.md` | `test/`, `.pre-commit-config.yaml` |
| 대규모 리팩토링/파일 분해/중복 제거 | `$refactor` | `.claude/skills/refactor/SKILL.md` | 전체 (도메인 횡단) |

### Supabase 공식 스킬 (신규 환경 세팅 시)

`$backend` 스킬은 Supabase 공식 [agent-skills](https://github.com/supabase/agent-skills) 플러그인과 병행 동작한다. 새 개발 환경에서는 최초 1회 설치 필요. 설치 명령과 활용 가이드는 `docs/BACKEND.md` §8 참조.

## 병렬 탐색 권장 케이스

긴 탐색/분석 작업은 메인 에이전트가 직접 하지 말고 `Agent` 도구로 subagent를 띄워 **병렬로 처리**하라. 메인 컨텍스트를 절약하고 응답이 빠르다.

| 케이스 | 권장 방법 |
|--------|----------|
| 여러 큰 파일(>1,000줄)의 구조 비교 분석 | 파일별로 `general-purpose` agent를 병렬로 띄움 |
| grep으로 안 잡히는 영향 범위 조사 | `general-purpose` agent에게 "X를 사용하는 모든 곳 찾고 요약" 위임 |
| 도메인 횡단 리팩토링 계획 수립 | 도메인별 agent를 병렬로 띄워 각자 분석 → 메인이 통합 |
| 단일 파일 즉시 수정 | subagent 띄우지 말 것 (오버헤드만 큼) |

**원칙**: 탐색은 병렬, 수정은 직렬. 코드 수정 단계에서 여러 agent를 동시에 띄우면 동일 파일 충돌 가능성이 있으므로 메인이 직접 수정한다.

## 문서 동기화 규칙 (중요)

코드를 수정할 때 아래 문서들도 함께 업데이트해야 한다. 한 곳만 바뀌면 곧 낡은 정보가 된다.

| 변경 유형 | 업데이트 대상 |
|----------|--------------|
| 새 위젯/화면/모델/상태 추가·이동·삭제 | `docs/FRONTEND.md` (파일 표, 위젯 목록), `docs/UI_GUIDE.md` (UI 패턴 변경 시) |
| DB 스키마/RLS/Repository 변경 | `docs/BACKEND.md` (테이블·함수·Repository 섹션), `db_init.sql` |
| 새 Python 스크립트/Makefile 타겟 | `docs/DATA_PIPELINE.md`, `Makefile` help 문자열 |
| 테스트 전략/커버리지 변화 | `docs/TESTING.md` |
| 중요한 아키텍처 결정 | `docs/ADR.md` (새 ADR 번호로 추가) |
| 스킬/훅/플러그인 구조 변경 | `CLAUDE.md` (도메인 스킬 표, 문서 인덱스) |
| 빌드/실행 명령 변경 | `CLAUDE.md` (빌드 & 실행 섹션) |
| 의존성 추가/제거 | `pubspec.yaml` + `docs/FRONTEND.md` §6 (의존 패키지) |
| PRD 수준의 기능 추가/삭제 | `docs/PRD.md` |

**작업 흐름 규칙**:
1. 코드 변경을 마쳤으면 스스로 질문: "이 변경으로 위 표의 어떤 문서가 오래됐는가?"
2. 해당 문서를 같은 PR/커밋에 포함해 업데이트한다.
3. 변경이 크면 (예: story_home_screen 대규모 분리) `docs/ARCHITECTURE.md`의 다이어그램/설명도 검토한다.
4. `docs/ADR.md`는 **결정이 뒤집히거나 새 결정이 생길 때만** 추가한다 (기존 ADR은 역사로 보존).

각 도메인 스킬(`$frontend`, `$backend` 등)은 자신이 담당하는 문서를 유지 관리할 책임이 있다. 스킬 실행 후 관련 md도 최신 상태인지 확인하라.

## 문서 인덱스

| 문서 | 내용 |
|------|------|
| `docs/PRD.md` | 제품 요구사항 — 뭘 만드는지 |
| `docs/ARCHITECTURE.md` | 기술 아키텍처 — 어떻게 만드는지 |
| `docs/ADR.md` | 아키텍처 결정 기록 — 왜 이렇게 만드는지 |
| `docs/UI_GUIDE.md` | UI/UX 가이드 — 어떻게 보여야 하는지 |
| `docs/FRONTEND.md` | 프론트엔드 도메인 상세 |
| `docs/BACKEND.md` | 백엔드 도메인 상세 |
| `docs/DATA_PIPELINE.md` | 데이터 파이프라인 상세 |
| `docs/TESTING.md` | 테스트 전략 상세 |
| `docs/CONTENT_UPDATE.md` | 새 인물·이야기 등록 → 앱 반영 워크플로우 (사역자 제안 → 관리자 승인 → 운영자 이미지·앱 출시 → 사용자) |
| `docs/WORKFLOW_GUIDE.md` | 작업 흐름 + 유지보수 규칙 (스킬/Agent 동작 방식, 커밋/푸시 정책, DB 변경 체크리스트) |
| `docs/PUSH_SETUP.md` | Firebase/FCM 푸시 알림 설정 가이드 (Firebase Console → flutterfire → Edge Function 배포) |

## 코딩 컨벤션

- **언어**: Dart 3.8+, Python 3.10+ (tools/)
- **포맷**: `dart format` (Dart), `black` (Python)
- **린트**: `flutter_lints` 5.0 (`analysis_options.yaml`)
- **상태관리**: Riverpod 2.6 — `NotifierProvider` + 불변 `StoryState`
- **UI 텍스트**: 한국어
- **모델**: 순수 데이터 클래스, `fromMap()` 팩토리 패턴
- **에러**: try-catch + `state.copyWith(error: ...)` 패턴

## TDD 규칙

**TDD는 "새 기능 개발 방법"이 아니라 "모든 코드 변경의 순서 원칙"이다.** 요청이 들어오면
코드를 고치기 전에 반드시 다음 순서를 따른다 (상세: `docs/WORKFLOW_GUIDE.md` §5):

1. 관련 테스트가 이미 있는지 확인 (`test/` grep)
2. 요구사항 ↔ 기존 테스트 비교 — 충돌 시 "기존 테스트 수정"은 **사용자 확인** 대상
3. 테스트 먼저 갱신/추가 → `flutter test` 실패(Red) 확인
4. 구현 변경 → 통과(Green) 확인
5. 리팩토링 (테스트는 그대로, 구현만 정리)

작업 유형별:
- **새 기능** → 실패 테스트 먼저 작성
- **기존 기능 수정** → 기존 테스트와 요구사항 비교 후 테스트부터 수정
- **버그 수정** → 버그를 재현하는 실패 테스트 먼저 추가
- **리팩토링** → 기존 테스트를 안전망으로 두고 구현만 변경 (Green 유지)

`test/` 구조는 `lib/` 미러링: `test/models/`, `test/state/`, `test/data/`, `test/widgets/`. mock은 `mocktail`.

### 테스트 변경 정책 (중요)

테스트 코드는 **"이 기능이 이렇게 동작해야 한다"는 명세(spec)**이다. 따라서:

- **새 테스트 추가**: 자유롭게 가능 (기존 동작을 바꾸지 않으므로)
- **기존 테스트 수정**: 반드시 **사용자에게 먼저 확인**받는다. "이 테스트를 이렇게 바꿔도 될까요?" 형태로 질문.
- **기존 테스트 삭제**: 반드시 **사용자에게 먼저 확인**받는다. 삭제 이유와 영향을 설명.
- 예외: `dart fix --apply`에 의한 순수 문법 변경(const 추가 등)은 동작이 안 바뀌므로 확인 불필요.

## Git 훅 & CI

### 로컬 (pre-commit framework)
- **pre-commit**: `dart format`, `black`, 큰 파일/머지 충돌/YAML/EOL/공백 검사, **import_sorter**, **forbidden pattern**(`print(`/시크릿 차단)
- **pre-push**: `flutter analyze` + `flutter test` + **에셋 경로 검증**(`tools/app/verify_asset_paths.py`)
- 실행: `pre-commit run --all-files` (수동)

### 원격 (GitHub Actions)
- **`.github/workflows/flutter_ci.yml`** — push/PR 시 analyze + test + coverage 자동 실행
- 로컬 hook을 `--no-verify`로 우회해도 PR 머지 전에 잡힘

### 룰
- 시크릿(SUPABASE_SERVICE_ROLE_KEY, API key)은 **절대 커밋 금지** (forbidden pattern hook이 자동 차단)
- `print(`은 코드에 쓰지 말 것 — 로깅이 필요하면 `debugPrint` 사용
- **`git push`는 사용자가 명시적으로 "푸시해줘"라고 지시할 때만 실행한다.** 커밋은 지시받으면 하되, push는 절대 자동으로 하지 않는다.
- **커밋도 사용자가 "커밋해줘"라고 지시할 때만.** 코드 변경 후 자동 커밋하지 않는다.

## 에셋 파이프라인

`Makefile`로 관리. 상세는 `docs/DATA_PIPELINE.md` 참조.

```bash
make seed-bible-verses           # 성경 구절 SQL 생성
make build-character-meta        # 인물 메타 JSON 생성 (카탈로그 + 아바타 프롬프트)
make seed-stories-characters     # 이야기 + 인물 SQL 생성 (권장)
make generate-avatars            # Vertex AI 아바타 생성
make generate-story-images       # Vertex AI 장면 이미지
make thumbnails                  # 썸네일 생성
make upload-character-avatars    # Supabase Storage `characters/` 버킷으로 아바타 업로드 (1회)
make all                         # 전체 파이프라인
```

## Supabase Edge Functions

웹 앱이 AI 이미지 생성을 안전하게 호출하기 위한 서버리스 함수.
상세: `docs/BACKEND.md` §7, `supabase/functions/generate-proposal-scene/README.md`

```bash
supabase functions deploy generate-proposal-scene
```

필요 secrets: `GOOGLE_CLOUD_PROJECT`, `GCP_SERVICE_ACCOUNT_JSON`.

## 환경 설정

- `.env` 파일에 `SUPABASE_URL_DEV`, `SUPABASE_ANON_KEY_DEV`, `GOOGLE_CLOUD_PROJECT` 등
  - 신규 환경 세팅: `cp .env.example .env` 후 실제 값 채우기
  - `.env`는 `.gitignore` 대상 (시크릿 포함) — **절대 커밋 금지**
- `ENV` 환경 전환: `--dart-define=ENV=dev|prod`
- Python: `.venv` 활성화 필수 (`source .venv/bin/activate`)

## Worktree 작업 규칙 (중요)

Claude Code는 작업 격리를 위해 `.claude/worktrees/<name>` 에 git worktree를 만든다.
worktree는 git이 추적하지 않는 파일(`.env`, `.venv`, `build/` 등)을 **자체 복사본으로
보유**하므로 제거 시 주의 필요.

### Worktree 생성 시
1. 메인 repo의 `.env`를 새 worktree로 복사: `cp /path/to/main/.env <worktree>/.env`
2. `flutter pub get` 실행으로 `pubspec.lock`/`.dart_tool/` 재생성

### Worktree 제거 시 (사용자 지시 받은 경우만)
**반드시 사용자에게 아래 체크리스트를 안내하고 승인받은 후 실행한다:**

```
⚠️ worktree 제거 전 확인:
□ 작업 브랜치가 원격에 푸시되고 머지 완료되었는가?
□ worktree 안에 .env, .venv, 로컬 편집 중 파일이 남아 있지 않은가?
  (.env는 .gitignore라 git worktree remove 시 복원 불가 — 필요하면 먼저 복사)
□ 브랜치를 로컬에서도 삭제할 것인가? (git branch -d <branch>)
```

제거 명령: `git worktree remove <path>` → 실패 시 `--force`. 폴더 직접 `rm -rf` 금지
(고아 레코드 남음, `git worktree prune` 필요).

## DB 변경 규칙

1. `db_init.sql`이 스키마의 단일 진실 소스
2. 스키마 변경 → `db_init.sql` 수정 → 마이그레이션 생성
3. RLS 정책 확인 필수 (공개 읽기 vs 사용자 전용)
