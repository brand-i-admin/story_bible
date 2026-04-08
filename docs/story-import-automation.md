# Story Import Automation

이 문서는 특정 사용자가 전달한 story JSON을 자동화 파이프라인으로 처리할 때의 권장 구조와, 중간 삽입이 가능한 timeline ordering 전략을 정리한다.

## 목표

- 사용자 JSON을 바로 프로덕션 DB/asset에 반영하지 않는다.
- 먼저 검증 가능한 스테이징 번들을 만든다.
- 사람 검토 후에만 승격한다.
- 이벤트 identity와 정렬 순서를 분리해서, 중간 삽입 시 기존 이벤트 code를 흔들지 않는다.

## 1. 권장 자동화 전략

권장 흐름은 다음과 같다.

1. 사용자 JSON 수신
2. `import_job` 생성
3. JSON 검증
4. 정규화 산출물 생성
5. diff / 리뷰 자료 생성
6. 샘플 검토 및 승인
7. 승인된 산출물만 DB/asset에 반영

핵심은 “즉시 반영”이 아니라 “검토 가능한 배포 산출물 생성”이다.

## 2. `import_job` 추적 구조

이번 변경에서 다음 테이블을 추가했다.

- `public.import_jobs`
- `public.import_job_artifacts`

이 테이블은:

- 누가 JSON을 보냈는지
- 어떤 입력 파일이었는지
- SHA-256이 무엇인지
- 현재 상태가 무엇인지
- 어떤 산출물이 생성됐는지

를 추적하는 메타데이터 레이어다.

또한 `events.source_import_job_id`를 추가해서, 나중에 어떤 이벤트가 어느 import job에서 왔는지 추적할 수 있게 했다.

## 3. 스테이징 번들 생성 스크립트

새 스크립트:

- [`tools/prepare_story_import_job.py`](/Users/wonny/workspace/story_bible/tools/prepare_story_import_job.py)

이 스크립트는 다음만 수행한다.

- 입력 JSON을 job 디렉터리로 복사
- 기초 검증 수행
- [`tools/build_200_stories_seed_sql.py`](/Users/wonny/workspace/story_bible/tools/build_200_stories_seed_sql.py) 를 job 입력에 대해 실행
- normalized JSON / seed SQL / report / diff summary 생성

중요:

- canonical DB를 수정하지 않는다.
- canonical `assets/...`를 수정하지 않는다.
- 리뷰 가능한 산출물만 만든다.

기본 출력 경로는 `.omx/import_jobs/<job_id>/` 이다.

## 4. 실행 예시

```bash
python3 tools/prepare_story_import_job.py \
  --input-json /path/to/user_story.json \
  --user-id user_123
```

성공 시 생성되는 대표 산출물:

- `.omx/import_jobs/<job_id>/job.json`
- `.omx/import_jobs/<job_id>/build/200_stories_normalized.json`
- `.omx/import_jobs/<job_id>/build/200_stories_seed.sql`
- `.omx/import_jobs/<job_id>/build/200_stories_report.json`
- `.omx/import_jobs/<job_id>/review/diff_summary.json`

주의:

- `--verse-source-sql` 과 `--avatar-prompt-json` 전제 파일이 없으면 스크립트는 build 단계까지 가지 않고 `validated_only` 상태로 멈춘다.
- 이 경우에도 raw JSON, job metadata, 기초 검증 결과는 남는다.

## 5. 왜 중간 삽입이 현재 구조에서 취약했는가

기존에는 사실상 다음 값들이 서로 강하게 묶여 있었다.

- story number
- `code`
- `time_sort_key`

기존 시드 로직은 `time_sort_key = year * 1000 + number` 형태라서, 이야기 하나가 중간에 들어오면 번호 체계 전체를 흔들 가능성이 있었다.

또한 generated media와 merge flow도 `event.code`에 묶여 있으므로, code가 바뀌면 기존 이미지/썸네일 연결도 같이 흔들릴 수 있다.

## 6. 새 정렬 전략

이번 변경에서는 `events`에 다음 컬럼을 추가했다.

- `display_number text`
- `timeline_rank numeric(18, 6)`

역할은 분리된다.

### `code`

- 영구 식별자
- 한 번 정해지면 가능하면 바꾸지 않는다.
- media manifest와 merge flow의 기준 key

### `display_number`

- 사람이 보는 표시용 번호
- `024`, `024A`, `024B` 같은 형태도 가능

### `timeline_rank`

- 실제 정렬 기준
- 중간 삽입 시 기존 이벤트의 `code`를 안 바꾸고도
  `23.5`, `24.1`, `24.2` 같은 방식으로 사이에 끼워 넣을 수 있다
- 현재는 숫자형이지만, 핵심은 “identity와 order를 분리했다”는 점이다

## 7. 앱 조회 전략

이제 이벤트 정렬은 `timeline_rank`, 그 다음 `time_sort_key` 순으로 가는 방향이 안전하다.

즉:

- `timeline_rank`가 우선
- `time_sort_key`는 연대 보조 정렬
- `code`는 identity

이 구조면 중간 삽입이 생겨도 앱이나 media 연결이 덜 흔들린다.

## 8. 사용자 JSON 권장 입력 필드

사용자 JSON이 다음 필드를 제공하면 자동화 안정성이 높아진다.

- `code`
  - 가능하면 영구 식별자로 사용
- `display_number`
  - 사람이 보는 번호
- `timeline_rank`
  - 중간 삽입 가능한 정렬 키
- `era` 또는 `era_code`
- `title`
- `persons`
- `bible_ref` 또는 `bible_refs`

이번 변경으로 [`tools/build_200_stories_seed_sql.py`](/Users/wonny/workspace/story_bible/tools/build_200_stories_seed_sql.py) 는

- `era_code`
- `bible_refs`
- 명시적 `code`
- 명시적 `display_number`
- 명시적 `timeline_rank`
- `number` 필드 기반 입력

을 더 유연하게 받을 수 있게 되었다.

## 9. 운영 권장사항

- 자동 승인 금지
  - 새 이야기 추가
  - 연대 순서 변경
  - 기존 story/code 덮어쓰기
- 항상 스테이징 번들 생성 후 리뷰
- asset 생성도 job 스코프로 분리
- 프로덕션에는 승인된 동일 산출물만 승격
- 롤백은 직전 승인 job 기준으로 수행

## 10. 요약

이번 변경의 핵심은 두 가지다.

1. `import_job` 기반으로 사용자 JSON을 안전하게 자동화할 수 있는 스테이징 경로를 만들었다.
2. `code`와 정렬 순서를 분리해서, 중간 삽입이 가능한 timeline 구조로 옮길 발판을 만들었다.
