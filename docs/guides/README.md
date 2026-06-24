# Story Bible 개발 가이드 허브

`docs/guides`는 절차 문서가 섞여 있는 폴더가 아니라, 아래 계층대로 읽는다.
메인 문서는 결정을 내리는 곳이고, 하위 문서는 메인 문서를 실행할 때 필요한
세부 절차를 보완한다. 부록은 길거나 생성되는 레퍼런스라 평소 첫 진입점으로 보지 않는다.

## 0. 문서 구조

### 개발/배포 Flow

메인 문서:

- [develop-flow.md](develop-flow.md) — dev/real 실행, 검증, patch, real 배포 판단.

하위 문서:

- [CONTENT_UPDATE.md](CONTENT_UPDATE.md) — 새 이야기, 퀴즈, 장면 이미지, pubspec 반영 절차.
- [MAKE_TARGETS.md](MAKE_TARGETS.md) — Make target별 입력/출력/원격 DB·Storage 영향.

이 그룹은 "무엇을 언제 dev/real에 적용할지"를 결정한다. 새 이야기 중간 삽입,
real seed 적용, 앱 Store 배포 타이밍처럼 운영 판단이 필요하면 먼저 여기서 시작한다.

### 인프라 세팅/구축

메인 문서:

- [INFRA_GUIDE.md](INFRA_GUIDE.md) — Supabase, Firebase, GCP, Apple, OAuth의 현재 구조와 원리.

하위 문서:

- [DB_SETUP.md](DB_SETUP.md) — 신규/복구 Supabase 환경 구축 체크리스트.
- [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md) — `.env`, `.env.ops`, `.env.supabase.secrets`, Firebase client config 공유 기준.

이 그룹은 "현재 환경이 어떻게 이어져 있고, 새 컴퓨터나 새 Supabase 프로젝트를 어떻게
재현하는지"를 다룬다.

### 기능 가이드

메인 문서:

- [PUSH_SETUP.md](PUSH_SETUP.md) — Firebase/FCM 푸시 알림 설정과 장애 확인 순서.

기능별 가이드가 늘어나면 이 그룹 아래에 추가한다. 현재는 푸시 알림이 유일한 기능 전용
운영 문서다.

### 테스트 가이드

메인 문서:

- [TEST_GUIDE.md](TEST_GUIDE.md) — 현재 테스트 파일, 검증 책임, 변경 유형별 최소 검증.

보조 문서:

- [../TESTING.md](../TESTING.md) — 저장소 전체 테스트 전략.

### 부록/참고

- [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md) — Codex 작업 규칙과 웹 제안 기능의 긴 구조 참고. 현재 운영 경로는 `develop-flow.md`와 `CONTENT_UPDATE.md`가 우선이다.
- [story_guide.md](story_guide.md) — 현재 `assets/200_stories/*.json` 기준 전체 사건 카탈로그. `make build-guides`가 생성한다.

## 1. 빠른 선택

| 상황 | 먼저 볼 문서 | 함께 볼 문서 |
|------|------------|----------------|
| 앱 기능/UI만 개발하고 빌드/배포 | [develop-flow.md](develop-flow.md) | [../FRONTEND.md](../FRONTEND.md), [TEST_GUIDE.md](TEST_GUIDE.md) |
| DB schema/RLS/RPC/cron patch가 필요한 기능 개발 | [develop-flow.md](develop-flow.md) | [../BACKEND.md](../BACKEND.md), [../../supabase/patches/README.md](../../supabase/patches/README.md) |
| 새 이야기 추가/삭제 승인 후 release sync | [develop-flow.md](develop-flow.md) | [CONTENT_UPDATE.md](CONTENT_UPDATE.md), [MAKE_TARGETS.md](MAKE_TARGETS.md) |
| 기존 퀴즈/landmark/seed 수정 | [develop-flow.md](develop-flow.md) | [MAKE_TARGETS.md](MAKE_TARGETS.md), [../DATA_PIPELINE.md](../DATA_PIPELINE.md) |
| `make` 명령 내부 동작 확인 | [MAKE_TARGETS.md](MAKE_TARGETS.md) | [../DATA_PIPELINE.md](../DATA_PIPELINE.md) |
| 새 컴퓨터나 팀원 환경 파일 공유 | [INFRA_GUIDE.md](INFRA_GUIDE.md) | [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md) |
| 새 Supabase 프로젝트 구축/복구 | [INFRA_GUIDE.md](INFRA_GUIDE.md) | [DB_SETUP.md](DB_SETUP.md) |
| Firebase/FCM 푸시 설정 | [PUSH_SETUP.md](PUSH_SETUP.md) | [INFRA_GUIDE.md](INFRA_GUIDE.md) |
| 테스트 영향 범위 확인 | [TEST_GUIDE.md](TEST_GUIDE.md) | [../TESTING.md](../TESTING.md) |
| 전체 사건 목록 확인 | [story_guide.md](story_guide.md) | [../DATA_PIPELINE.md](../DATA_PIPELINE.md) |

## 2. 중복 정리 원칙

- 메인 문서는 판단 기준과 표준 순서를 담는다.
- 하위 문서는 명령의 내부 동작, 체크리스트, 환경 파일처럼 실행 세부사항을 담는다.
- 같은 내용이 여러 문서에 필요하면 메인 문서에는 결론만 두고, 세부사항은 하위 문서로 링크한다.
- 부록 문서는 생성물이나 긴 역사적 레퍼런스로 둔다. 평소 운영 절차의 canonical 문서로 삼지 않는다.

## 3. HTML 문서

시각화가 들어간 HTML 버전은 [html/index.html](html/index.html)에서 시작한다.
좌측 탭은 위 구조와 같은 그룹과 들여쓰기를 사용한다.

HTML과 `story_guide.md`는 아래 명령으로 다시 생성한다.

```bash
make build-guides
```

## 4. 최신성 점검 기준

- 명령은 `Makefile`, `scripts/`, `.pre-commit-config.yaml`, `.github/workflows/flutter_ci.yml`과 맞춘다.
- 로컬 환경 파일 설명은 `.gitignore`, `*.example`, `scripts/common.sh`, `Makefile`의 env 로딩 방식과 맞춘다.
- DB/Storage/RPC 설명은 `db_init.sql`, `supabase/functions/`, `lib/data/`와 맞춘다.
- 콘텐츠 수와 제목은 `assets/200_stories/*.json`을 기준으로 한다.
- 테스트 파일과 테스트 수는 `test/`와 `tools/**/test_*.py`를 기준으로 한다.
