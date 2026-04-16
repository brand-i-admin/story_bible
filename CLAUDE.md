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
| DB 스키마/쿼리/인증 변경 | `$backend` | `docs/BACKEND.md` | `db_init.sql`, `supabase/`, `lib/data/` |
| 에셋 생성/DB 시딩 | `$data-pipeline` | `docs/DATA_PIPELINE.md` | `tools/*.py`, `assets/`, `Makefile` |
| 테스트 작성/실행 | `$testing` | `docs/TESTING.md` | `test/`, `.pre-commit-config.yaml` |
| 푸시 전 검증/PR 작성 | `$pre-push-pr` | 기존 스킬 | 전체 |

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

## 코딩 컨벤션

- **언어**: Dart 3.8+, Python 3.10+ (tools/)
- **포맷**: `dart format` (Dart), `black` (Python)
- **린트**: `flutter_lints` 5.0 (`analysis_options.yaml`)
- **상태관리**: Riverpod 2.6 — `NotifierProvider` + 불변 `StoryState`
- **UI 텍스트**: 한국어
- **모델**: 순수 데이터 클래스, `fromMap()` 팩토리 패턴
- **에러**: try-catch + `state.copyWith(error: ...)` 패턴

## TDD 규칙

- 새 기능 → 테스트 먼저 작성 (Red → Green → Refactor)
- 버그 수정 → 실패 테스트 먼저 추가
- `test/` 구조는 `lib/` 미러링: `test/models/`, `test/state/`, `test/data/`, `test/widgets/`
- mock: `mocktail` 사용

## Git 훅

- **pre-commit**: `dart format`, `black`, 파일 검사
- **pre-push**: `flutter analyze` + `flutter test`
- 실행: `pre-commit run --all-files` (수동)

## 에셋 파이프라인

`Makefile`로 관리. 상세는 `docs/DATA_PIPELINE.md` 참조.

```bash
make seed-bible-verses       # 성경 구절 SQL 생성
make build-avatar-prompts    # 아바타 프롬프트 생성
make seed-stories            # 이야기 SQL 생성
make generate-avatars        # Vertex AI 아바타 생성
make generate-story-images   # Vertex AI 장면 이미지
make thumbnails              # 썸네일 생성
make all                     # 전체 파이프라인
```

## 환경 설정

- `.env` 파일에 `SUPABASE_URL_DEV`, `SUPABASE_ANON_KEY_DEV`, `GOOGLE_CLOUD_PROJECT` 등
- `ENV` 환경 전환: `--dart-define=ENV=dev|prod`
- Python: `.venv` 활성화 필수 (`source .venv/bin/activate`)

## DB 변경 규칙

1. `db_init.sql`이 스키마의 단일 진실 소스
2. 스키마 변경 → `db_init.sql` 수정 → 마이그레이션 생성
3. RLS 정책 확인 필수 (공개 읽기 vs 사용자 전용)
