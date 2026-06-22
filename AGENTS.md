# Story Bible — Codex 작업 가이드

Flutter + Supabase 기반의 인터랙티브 성경 지도 학습 앱이다. 앱은 성경
이야기를 시대, 지역, 인물, 사건, 퀴즈, 학습 진행도, 노트, 기도 나눔,
제안, 알림, 푸시와 연결해 보여준다.

## 실행과 검증

```bash
flutter pub get
flutter run
scripts/run_real.sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

앱 실행 Supabase 환경은 `scripts/run_dev.sh` / `scripts/run_real.sh`로
선택한다. Makefile 운영 타겟은 기본 `ENV=dev`이며, real DB/Storage에
적용할 때만 명시적으로 `ENV=real`을 붙인다 (`prod`도 real alias로 허용).
Python 도구는 Python 3.10+와 로컬 가상환경을 기준으로 사용한다.
`scripts/run_*.sh`와 `scripts/build_*.sh`는 실행 전에 `flutter clean`과
`flutter pub get`을 자동으로 수행한다.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Codex 프로젝트 스킬

프로젝트 전용 Codex 스킬은 `.agents/skills/`에 둔다.

| 작업 | 스킬 | 먼저 읽을 문서 | 주요 파일 |
|------|------|----------------|-----------|
| UI, 위젯, 화면, 상태, 모델 | `$frontend` | `docs/FRONTEND.md`, `docs/UI_GUIDE.md` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| DB 스키마, RLS, 쿼리, 인증, Repository | `$backend` | `docs/BACKEND.md` | `db_init.sql`, `supabase/`, `lib/data/` |
| 에셋, seed, Python 파이프라인, Makefile | `$data-pipeline` | `docs/DATA_PIPELINE.md` | `tools/`, `assets/`, `Makefile` |
| 테스트, TDD, 커버리지, hook, CI | `$testing` | `docs/TESTING.md`, `docs/guides/TEST_GUIDE.md` | `test/`, `tools/**/test_*.py`, `.pre-commit-config.yaml` |
| 대형 리팩터링, 파일 분리, 중복 제거 | `$refactor` | `.agents/skills/refactor/SKILL.md` | 도메인 횡단 |
| 현재 작업 커밋, detached worktree 회수/정리 | `$worktree-commit` | `.agents/skills/worktree-commit/SKILL.md` | git worktree, 현재 diff |
| 푸시 전 검증, 한국어 PR 초안, 요청 시 commit/push | `$pre-push-pr` | `.agents/skills/pre-push-pr/SKILL.md` | 전체 저장소 |

작업에 필요한 스킬과 참조 문서만 로드한다. 많은 파일을 읽는 탐색은 병렬로
진행해도 되지만, 실제 파일 수정은 충돌을 피하기 위해 직렬로 진행한다.

## PDCA 작업 루프

이 저장소에서는 Codex 작업 안정성을 위해 PDCA(Plan-Do-Check-Act)를
기본 반복 개선 루프로 운용한다.

| 단계 | 의미 | Codex가 해야 할 일 | 산출물 |
|------|------|--------------------|--------|
| Plan | 계획 | 요청을 도메인으로 분류하고, 관련 문서/테스트/영향 범위를 확인한다. | 짧은 작업 계획, 대상 파일, 검증 범위 |
| Do | 실행 | 기존 패턴을 따라 작게 수정한다. 새 기능/버그는 테스트를 먼저 맞춘다. | 코드, 테스트, 문서 변경 |
| Check | 확인 | `git diff`, 포맷/analyze/test/도구 검증, secret, 문서 동기화 여부를 확인한다. | 검증 결과, 변경 요약, 위험 지점 |
| Act | 조치 | 실패 원인을 반영해 다시 수정하거나, 통과 결과와 남은 리스크를 보고한다. | 후속 수정, 최종 보고, 다음 단계 |

PDCA는 기존 TDD를 대체하지 않는다. TDD는 Do 단계 안에서 동작하는 더 좁은
규칙이고, PDCA는 요청 시작부터 최종 보고까지 감싸는 운영 루프다.

작업 크기에 따른 적용 기준:

- 작은 문구/문서 수정: Plan은 한두 문장, Check는 필요한 최소 검증.
- 일반 기능/버그 수정: 관련 테스트 확인 → Do → Check → 필요 시 Act로 재수정.
- DB/알림/결제/원격 작업: Plan과 Check/Act 결과를 반드시 자세히 남기고, 운영 반영은
  사용자 명시 요청 없이는 하지 않는다.
- 대형 리팩터링: Plan을 단계별로 나누고, 각 단계마다 작은 Do/Check/Act를 반복한다.

## 문서 동기화 규칙

코드가 바뀌면 같은 변경 안에서 관련 문서를 갱신한다.

| 변경 유형 | 갱신 대상 |
|-----------|-----------|
| 새 위젯/화면/모델/상태 추가, 이동, 삭제 | `docs/FRONTEND.md`; UI 패턴 변경 시 `docs/UI_GUIDE.md` |
| DB 스키마, RLS, RPC, Repository, Edge Function | `docs/BACKEND.md`, `db_init.sql`; 관계 변화는 `docs/ARCHITECTURE.md` |
| Python 도구, 에셋 파이프라인, Makefile target | `docs/DATA_PIPELINE.md`, `Makefile` help |
| 테스트 전략, 커버리지 구조, hook, CI | `docs/TESTING.md`, `docs/guides/TEST_GUIDE.md` |
| 중요한 아키텍처 결정 | `docs/ADR.md`에 새 ADR 추가 |
| Agent 스킬이나 작업 규칙 | `AGENTS.md`, 관련 `.agents/skills/*/SKILL.md` |
| 빌드/실행 명령 또는 의존성 | `AGENTS.md`, `pubspec.yaml`, 관련 문서 |
| PRD 수준 기능 추가/삭제 | `docs/PRD.md` |

기존 ADR 이력은 사용자가 요청하지 않는 한 다시 쓰지 않는다. 새 결정은 새 ADR로
남긴다.

## 아키텍처 문서 지도

코드 작업 시 핵심 문서:

| 문서 | 역할 |
|------|------|
| `docs/PRD.md` | 제품 의도와 요구사항 |
| `docs/ARCHITECTURE.md` | 시스템 구조와 파일 연결 관계 |
| `docs/ADR.md` | 결정 이력 |
| `docs/UI_GUIDE.md` | 시각 시스템, 지도/지역 패턴, 접근성 |
| `docs/FRONTEND.md` | Flutter/Riverpod 화면, 위젯, 상태, 모델 상세 |
| `docs/BACKEND.md` | Supabase 스키마, RLS, RPC, Repository, Edge Function |
| `docs/DATA_PIPELINE.md` | Python 도구, seed, assets, Make target |
| `docs/TESTING.md` | 테스트 전략과 로컬/CI 검증 |
| `docs/guides/` | 인프라, 푸시, 콘텐츠 업데이트, 테스트 운영 가이드 |

## 코딩 규칙

- Dart 3.8+, Flutter, Riverpod 2.6, Supabase Flutter.
- `tools/`의 Python은 Python 3.10+ 기준이며 `black`으로 포맷한다.
- 사용자에게 보이는 UI 문구는 한국어로 쓴다.
- 모델은 불변 데이터 클래스로 유지한다. Supabase row 기반 모델은 `fromMap()`을 쓴다.
- Repository는 `SupabaseClient`를 주입받고 row를 모델로 변환한다.
- Controller는 `try/catch`와 `state.copyWith(error: ...)` 패턴을 우선한다.
- Dart 앱/테스트 코드에서는 `print` 대신 `debugPrint`를 쓴다.

## 디자인 시스템

`lib/theme/`가 디자인 토큰의 단일 진실 소스다.

- 색상: `lib/theme/tokens.dart`의 `AppColors`
- radius/spacing/shadow: `AppRadii`, `AppSpacing`, `AppShadows`
- 타이포그래피: `lib/theme/typography.dart`의 `AppTextStyles`
- 표면 스타일: `lib/theme/surfaces.dart`의 `AppSurfaces`

새 UI 코드는 raw `Color(0x...)`, 임의 padding, 임의 radius보다 토큰을 먼저
사용한다. 오래된 양피지/게임풍 장식 표면의 기존 inline 색은 필요할 때 점진적으로
이전한다. `widgets/story_home_styles.dart`와 `widgets/game_ui_skin.dart`는
의도적으로 시그니처 장식 색을 가질 수 있다.

## TDD와 테스트

코드 변경 전 관련 테스트를 `rg`로 `test/`와 `tools/`에서 찾는다.

1. 새 기능은 실패 테스트를 먼저 추가한다.
2. 버그 수정은 버그를 재현하는 실패 테스트를 먼저 만든다.
3. 리팩터링은 기존 테스트를 green으로 유지하고, 추출한 순수 로직에는 테스트를 추가한다.
4. 기존 테스트 수정/삭제는 스펙 변경이다. 최종 보고에서 이유를 설명하고 diff를 좁게 유지한다.

자주 쓰는 검증 명령:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/run_unit_tests.py
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
python3 tools/lint/check_forbidden_patterns.py
tools/supabase/check_edge_functions.sh
python3 tools/lint/check_code_metrics.py
```

## Git과 안전

- 사용자가 명시적으로 요청하지 않으면 commit/push 하지 않는다.
- 사용자가 "커밋해줘", "현재 작업 커밋", "워크트리 커밋", "원래 브랜치에 반영",
  "작업트리 정리"를 요청하면 `$worktree-commit` 스킬로 현재 위치가 일반 브랜치인지
  detached/보조 worktree인지 먼저 판별한다.
- 사용자 또는 다른 작업자의 관련 없는 변경을 보존한다.
- `git reset --hard`, 광범위한 `rm -rf` 같은 파괴적 명령은 명시 승인 없이 쓰지 않는다.
- 작업 전 dirty state를 확인한다.
- secret을 commit하지 않는다. `.env`, service role key, Supabase PAT, private
  GCP/Firebase service account JSON, DB URL은 ignored local file이나 플랫폼 secret에 둔다.

## 데이터 파이프라인

주요 Make target:

```bash
make seed-bible-verses
make build-character-meta
make seed-stories-characters
make seed-quizzes
make generate-avatars
make generate-story-images
make thumbnails
make update-pubspec-assets
make check-pubspec-assets
```

Vertex AI와 Supabase Storage 관련 target은 비용이 들거나 원격 상태를 바꿀 수 있다.
가능하면 dry-run/limit 옵션을 먼저 쓰고, 대량 실행이나 운영 반영 전에는 의도를 확인한다.

## Supabase 규칙

- `db_init.sql`이 스키마 단일 진실 소스다.
- real 운영 DB 는 `db-init`으로 초기화하지 않고 `supabase/patches/*.sql` +
  `make apply-patch ENV=real PATCH=<file>`로 수정한다.
- Schema/RLS/RPC 변경은 `docs/BACKEND.md`와 함께 갱신한다.
- 새 테이블에는 RLS 정책과 grant가 필요하다.
- 생성된 seed SQL은 운영 적용 전에 검토한다.
- 학습 진행도/제안 이력이 엮인 story event hard delete는 피한다. 변경 전 ADR과
  backend 문서를 확인한다.
