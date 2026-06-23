# Story Bible 개발 가이드 허브

`docs/guides`는 운영 절차 문서가 모여 있는 폴더다. 일부 주제가 서로 겹치기
때문에, 아래 표의 "먼저 볼 문서"를 기준으로 읽는다.

## 빠른 선택

| 질문 | 먼저 볼 문서 | 보조 문서 |
|------|--------------|-----------|
| 평소 dev/real 실행, 검증, 배포 순서가 궁금하다 | [develop-flow.md](develop-flow.md) | [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md) |
| 새 이야기, 퀴즈, 장면 이미지, pubspec을 반영해야 한다 | [CONTENT_UPDATE.md](CONTENT_UPDATE.md) | [story_guide.md](story_guide.md), [../DATA_PIPELINE.md](../DATA_PIPELINE.md) |
| 다른 컴퓨터나 팀원에게 어떤 로컬 환경 파일을 공유해야 할지 정한다 | [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md) | [INFRA_GUIDE.md](INFRA_GUIDE.md), [scripts/README.md](../../scripts/README.md) |
| 새 Supabase 프로젝트를 만들거나 복구해야 한다 | [DB_SETUP.md](DB_SETUP.md) | [INFRA_GUIDE.md](INFRA_GUIDE.md) |
| Firebase/FCM 푸시를 처음 세팅하거나 점검한다 | [PUSH_SETUP.md](PUSH_SETUP.md) | [INFRA_GUIDE.md](INFRA_GUIDE.md), [DB_SETUP.md](DB_SETUP.md) |
| 테스트 영향 범위와 현재 테스트 파일을 찾는다 | [TEST_GUIDE.md](TEST_GUIDE.md) | [../TESTING.md](../TESTING.md) |
| 전체 Codex 작업 규칙과 웹 제안 기능 구조를 본다 | [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md) | [../BACKEND.md](../BACKEND.md), [../FRONTEND.md](../FRONTEND.md) |

## 현재 문서 역할

- [develop-flow.md](develop-flow.md): 일상 개발과 real 배포 판단의 표준 경로.
- [CONTENT_UPDATE.md](CONTENT_UPDATE.md): 로컬 JSON/이미지/seed 기반 콘텐츠 운영 절차.
- [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md): `.env`, `.env.ops`, `.env.supabase.secrets`와 Firebase config 공유 기준.
- [DB_SETUP.md](DB_SETUP.md): 신규/복구 Supabase 환경 구축 체크리스트.
- [INFRA_GUIDE.md](INFRA_GUIDE.md): Supabase, Firebase, GCP, Apple, OAuth가 맞물리는 원리 설명.
- [PUSH_SETUP.md](PUSH_SETUP.md): Firebase와 `send-push`를 연결하는 1회성 설정 절차.
- [TEST_GUIDE.md](TEST_GUIDE.md): 현재 `test/`와 `tools/**/test_*.py` 테스트 카탈로그.
- [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md): PDCA/TDD/Codex 작업 흐름과 사역자 웹 제안 기능의 구조 참고. 현재 운영 경로는 `CONTENT_UPDATE.md`가 우선이다.
- [story_guide.md](story_guide.md): 현재 `assets/200_stories/*.json` 기준 전체 사건 카탈로그.

## HTML 문서

시각화가 들어간 HTML 버전은 [html/index.html](html/index.html)에서 시작한다.

HTML과 `story_guide.md`는 아래 명령으로 다시 생성한다.

```bash
make build-guides
```

## 최신성 점검 기준

- 명령은 `Makefile`, `scripts/`, `.pre-commit-config.yaml`, `.github/workflows/flutter_ci.yml`과 맞춘다.
- 로컬 환경 파일 설명은 `.gitignore`, `*.example`, `scripts/common.sh`, `Makefile`의 env 로딩 방식과 맞춘다.
- DB/Storage/RPC 설명은 `db_init.sql`, `supabase/functions/`, `lib/data/`와 맞춘다.
- 콘텐츠 수와 제목은 `assets/200_stories/*.json`을 기준으로 한다.
- 테스트 파일과 테스트 수는 `test/`와 `tools/**/test_*.py`를 기준으로 한다.
