---
name: data-pipeline
description: "Story Bible 데이터/에셋 파이프라인 작업 스킬. Python seed builder, 생성 SQL, 성경/이야기 JSON, 퀴즈, 랜드마크, 썸네일, Vertex AI 이미지 생성, Supabase Storage sync, Makefile target 작업에 사용한다."
---

# Data Pipeline

## 작업 순서

1. 파이프라인 도구를 실행하거나 수정하기 전 `docs/DATA_PIPELINE.md`를 읽는다.
2. Python 작업은 `.venv`와 `requirements.txt` 기준으로 진행한다.
3. 표준 흐름은 Make target을 우선 사용하고, 실행 전 target 의존성을 확인한다.
4. 비용이 들거나 원격 상태를 바꾸는 작업은 dry-run/limit 옵션을 먼저 사용하고 의도를 확인한다.
5. deterministic parsing/building 로직에는 Python 테스트를 추가하거나 갱신한다.
6. 흐름이 바뀌면 `docs/DATA_PIPELINE.md`, `Makefile` help, `AGENTS.md`를 갱신한다.

## 주요 Make Target

```bash
make seed-bible-verses
make build-character-meta
make seed-stories-characters
make seed-quizzes
make seed-landmarks
make seed-era-boundaries
make generate-avatars
make generate-story-images
make thumbnails
make update-pubspec-assets
make check-pubspec-assets
```

## PDCA 적용

- Plan: 입력 파일, 생성 파일, 원격 영향, 비용 가능성을 먼저 확인한다.
- Do: parser/builder는 구조화된 JSON/SQL 생성 로직으로 수정한다.
- Check: 생성물 diff가 너무 크면 원인과 범위를 분리하고, Python 단위 테스트와 asset/polygon/forbidden pattern 검사를 실행한다.
- Act: 실패한 검증을 반영해 재생성하거나, 통과 결과와 남은 수동 확인 항목을 보고한다.

## 가드레일

- Vertex AI 대량 생성은 비용이 들 수 있으므로 가볍게 실행하지 않는다.
- 생성 SQL은 검토 없이 production에 적용하지 않는다.
- 이야기/인물 데이터 변경 시 `assets/events`, `tools/seed/character_meta.json`, 생성 seed SQL의 일관성을 확인한다.
- 가능하면 ad-hoc 문자열 조작보다 JSON/SQL builder와 구조화 parser를 사용한다.

## 검증

```bash
python3 tools/run_unit_tests.py
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
python3 tools/lint/check_forbidden_patterns.py
```
