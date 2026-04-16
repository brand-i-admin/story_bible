---
name: data-pipeline
description: "에셋 생성/DB 시딩/Python 스크립트 실행 시 사용하는 스킬. docs/DATA_PIPELINE.md를 참조하여 tools/*.py, assets/, Makefile 범위에서 작업한다."
---

# Data Pipeline

## 개요

성경 데이터 시딩, 아바타/이미지 생성, 에셋 관리 등 데이터 파이프라인 작업 시 사용한다.

## 작업 순서

1. 먼저 `docs/DATA_PIPELINE.md`를 읽어 파이프라인 DAG, 스크립트 목록, 의존 관계를 파악한다.
2. `.venv`를 활성화한다: `source .venv/bin/activate`
3. 필요한 환경변수를 확인한다 (`.env`에서 `GOOGLE_CLOUD_PROJECT` 등).
4. `Makefile` 타겟을 확인하고 적절한 타겟을 실행한다:
   - 부분 실행: `make seed-bible-verses`, `make generate-avatars` 등
   - 전체 실행: `make all`
5. 새 스크립트 추가 시:
   - `tools/` 디렉토리에 추가
   - `Makefile`에 타겟 등록
   - `docs/DATA_PIPELINE.md` 업데이트
   - `black` 포맷 적용
6. SQL 생성 후: Supabase SQL Editor에서 실행하거나 `psql`로 적재.

## 파일 범위

```
tools/*.py                      # Python 스크립트 (12개)
tools/avatar_prompts.json       # 아바타 프롬프트 (생성됨)
assets/                         # 입력/출력 에셋
Makefile                        # 파이프라인 오케스트레이션
.venv/                          # Python 가상환경
```

## Makefile 타겟

```
make seed-bible-verses       # 성경 구절 SQL (독립)
make build-avatar-prompts    # avatar_prompts.json
make seed-stories            # 이야기 SQL (→ avatar-prompts 의존)
make seed-persons            # 인물 SQL (→ avatar-prompts 의존)
make generate-avatars        # Vertex AI 아바타 (→ avatar-prompts 의존)
make generate-story-images   # Vertex AI 장면 이미지
make thumbnails              # 썸네일 (→ avatars, story-images 의존)
make seed-all                # 전체 SQL
make generate-all            # 전체 이미지
make all                     # 전체 파이프라인
```

## 이 저장소 기본값

- Python 3.10+ 사용, `.venv` 가상환경
- `black` 포맷터 적용 (`tools/*.py`)
- Vertex AI Imagen API로 이미지 생성 (GCP 인증 필요)
- SQL은 파일로 생성 후 수동으로 Supabase에 적재

## 가드레일

- `docs/DATA_PIPELINE.md`를 읽지 않고 스크립트를 실행하지 않는다.
- `.venv`를 활성화하지 않고 Python 스크립트를 실행하지 않는다.
- Makefile의 의존 관계를 무시하고 타겟을 실행하지 않는다.
- Vertex AI API 호출은 비용이 발생하므로, 대량 생성 전 `--limit` 옵션으로 테스트한다.
- 생성된 SQL을 검토 없이 운영 DB에 적용하지 않는다.
