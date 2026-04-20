# DB Schema Refactor Overview

이 문서는 이번 DB 개편에서 중요한 테이블들을 테이블별로 간단히 정리한 문서다.

핵심 목적은 3가지다.

- 생성된 이미지/썸네일을 DB가 이해하게 만들기
- 사용자 JSON 반영을 job 단위로 안전하게 관리하기
- 이야기 순서를 `식별자`와 `정렬값`으로 분리하기

---

## 1. `persons`

인물 기본 정보 테이블이다.

### 이 테이블이 하는 일

- 인물 자체의 대표 정보 저장
- 앱이 빠르게 읽는 인물 목록 제공
- 대표 아바타/썸네일 경로 제공

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | 인물 PK | 내부 조인 기준 |
| `code` | 인물 고유 코드 | JSON, seed, asset 연결 기준 |
| `name` | 인물 이름 | 앱 표시용 |
| `tagline` | 짧은 소개 문구 | 인물 카드/소개 UI |
| `description` | 상세 설명 | 인물 설명 UI |
| `avatar_url` | 원본 아바타 경로 | 생성/보관 기준 |
| `avatar_thumb_url` | 썸네일 경로 | 앱 표시 우선 경로 |
| `is_active` | 사용 여부 | 비활성 인물 제외 처리 |

### 한 줄 요약

`persons`는 인물의 대표 정보와 대표 아바타 경로를 가진 기본 테이블이다.

---

## 2. `events`

성경 이야기 이벤트 기본 정보 테이블이다.

### 이 테이블이 하는 일

- 한 이야기의 핵심 텍스트/연대/장소 정보 저장
- 앱에서 스토리 목록과 상세 정보를 읽는 기준
- 대표 이미지와 정렬 정보를 들고 있음

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | 이벤트 PK | 내부 조인 기준 |
| `code` | 이벤트 영구 식별자 | seed, media, merge 기준 |
| `display_number` | 사람이 보는 번호 | 운영/표시용 번호 |
| `era_id` | 시대 FK | 시대별 필터링 |
| `title` | 이야기 제목 | 앱 표시용 |
| `summary` | 짧은 요약 | 목록/상세 요약 |
| `story` | 상세 본문 | 상세 화면 |
| `short_story` | 짧은 설명 | 카드/요약 UI |
| `story_scenes` | 장면 설명 목록 | 이미지 생성 입력/요약 |
| `timeline_rank` | 실제 정렬 기준 | 중간 삽입 포함 정렬 |
| `start_year` | 시작 연대 | 연대 정보 |
| `end_year` | 종료 연대 | 연대 정보 |
| `time_sort_key` | 연대 기반 보조 정렬값 | timeline tie-breaker |
| `time_precision` | 연대 정확도 | exact/approx 구분 |
| `place_name` | 장소명 | 지도/상세 표시 |
| `lat` | 위도 | 지도 표시 |
| `lng` | 경도 | 지도 표시 |
| `thumb_url` | 대표 썸네일 경로 | 이벤트 대표 이미지 |
| `story_asset_dir` | 원본 장면 이미지 폴더 | 원본 asset 경로 요약 |
| `story_thumbnail_dir` | 장면 썸네일 폴더 | 썸네일 asset 경로 요약 |
| `story_scene_count` | 장면 수 | UI/검증용 |
| `source_import_job_id` | 어떤 import job에서 왔는지 | 변경 추적/감사 |

### 한 줄 요약

`events`는 이야기의 대표 레코드이며, 텍스트/연대/장소/대표 이미지/정렬 정보를 모두 갖는 중심 테이블이다.

---

## 3. `person_generated_assets`

인물 아바타 생성 결과 상세 테이블이다.

### 이 테이블이 하는 일

- 아바타 생성 이력 저장
- 원본/썸네일 경로 저장
- 어떤 모델/도구로 만들었는지 추적

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | PK | 내부 관리용 |
| `person_id` | 대상 인물 FK | 어떤 인물 자산인지 연결 |
| `original_path` | 원본 아바타 경로 | 원본 보관/재처리 |
| `thumbnail_path` | 아바타 썸네일 경로 | 앱 소비 경로 |
| `status` | 자산 상태 | ready, failed 등 |
| `generator` | 생성 스크립트 이름 | 생성 출처 추적 |
| `generator_model` | 사용 모델 | 모델 추적 |
| `generated_at` | 생성 시각 | 운영/감사 |
| `content_hash` | 파일 해시 | 중복/검증 |
| `metadata` | 부가 정보 JSON | 프롬프트/추가 속성 |
| `created_at` | 생성 레코드 시각 | 감사 |
| `updated_at` | 수정 시각 | 감사 |

### 한 줄 요약

`person_generated_assets`는 인물 아바타의 생성 상세 기록 테이블이다.

---

## 4. `event_scene_generated_assets`

이벤트 장면 이미지 생성 결과 상세 테이블이다.

### 이 테이블이 하는 일

- 장면별 이미지 결과 저장
- 몇 번째 장면인지 추적
- 썸네일과 원본을 모두 관리

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | PK | 내부 관리용 |
| `event_id` | 대상 이벤트 FK | 어떤 이야기인지 연결 |
| `scene_index` | 장면 번호 | 1, 2, 3, 4 식 구분 |
| `original_path` | 원본 장면 이미지 경로 | 원본 보관 |
| `thumbnail_path` | 장면 썸네일 경로 | 앱 표시 |
| `status` | 자산 상태 | ready, failed 등 |
| `prompt_text` | 생성 프롬프트 | 운영/검토 |
| `generator` | 생성 스크립트 이름 | 생성 출처 추적 |
| `generator_model` | 사용 모델 | 모델 추적 |
| `generated_at` | 생성 시각 | 감사 |
| `content_hash` | 파일 해시 | 검증/중복 확인 |
| `metadata` | 부가 정보 JSON | scene persons, refs 등 |
| `created_at` | 생성 레코드 시각 | 감사 |
| `updated_at` | 수정 시각 | 감사 |

### 한 줄 요약

`event_scene_generated_assets`는 한 이야기의 각 장면 이미지를 개별 레코드로 관리하는 테이블이다.

---

## 5. `import_jobs`

사용자 JSON 반영 작업 자체를 추적하는 테이블이다.

### 이 테이블이 하는 일

- 입력 JSON을 하나의 작업 단위로 관리
- 검증/승인/배포 상태를 추적
- 운영자가 “이 작업이 어디까지 갔는지” 볼 수 있게 함

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | import job PK | 작업 식별자 |
| `submitted_by_user_id` | 제출 사용자 | 누가 요청했는지 추적 |
| `source_name` | 입력 파일 이름 | 운영 확인 |
| `source_sha256` | 입력 파일 해시 | 동일 입력 판별 |
| `source_storage_key` | 원본 저장 위치 | 원본 파일 추적 |
| `status` | 작업 상태 | received, validated, approved 등 |
| `requested_at` | 접수 시각 | 작업 추적 |
| `validated_at` | 검증 완료 시각 | 작업 추적 |
| `approved_at` | 승인 시각 | 운영 승인 기록 |
| `promoted_at` | 실제 반영 시각 | 배포 기록 |
| `notes` | 작업 메모 | 운영 메모 |
| `metadata` | 부가 JSON 정보 | diff/설정값 등 |
| `created_at` | 생성 시각 | 감사 |
| `updated_at` | 수정 시각 | 감사 |

### 한 줄 요약

`import_jobs`는 “사용자 JSON 처리 작업”을 추적하는 헤더 테이블이다.

---

## 6. `import_job_artifacts`

import job에서 생성된 산출물 목록 테이블이다.

### 이 테이블이 하는 일

- 어떤 job에서 어떤 산출물이 나왔는지 저장
- normalized JSON, seed SQL, diff summary 같은 결과물을 연결

### 주요 컬럼 설명

| 컬럼 | 의미 | 언제 쓰는가 |
| --- | --- | --- |
| `id` | PK | 내부 관리용 |
| `import_job_id` | import job FK | 어떤 작업 결과물인지 연결 |
| `artifact_type` | 산출물 종류 | normalized_json, seed_sql 등 |
| `relative_path` | 산출물 경로 | 파일 위치 추적 |
| `payload` | 추가 JSON 메타데이터 | 리뷰/요약 정보 |
| `created_at` | 생성 시각 | 감사 |

### 한 줄 요약

`import_job_artifacts`는 import job이 만든 결과물들을 나열하는 상세 테이블이다.

---

## 7. 테이블 관계를 아주 간단히 보면

- `persons`
  - 인물 기본 정보
- `person_generated_assets`
  - 인물 이미지 상세
- `events`
  - 이야기 기본 정보
- `event_scene_generated_assets`
  - 이야기 장면 이미지 상세
- `import_jobs`
  - 사용자 입력 작업 헤더
- `import_job_artifacts`
  - 사용자 입력 작업 산출물 상세

즉 구조는 이렇게 이해하면 된다.

- 기본 정보는 `persons`, `events`
- 생성 상세는 `*_generated_assets`
- 사용자 입력 작업 추적은 `import_jobs`, `import_job_artifacts`

---

## 8. 가장 중요한 설계 포인트

### `code`

- 영구 식별자
- 가능하면 변경하지 않음

### `display_number`

- 사람이 이해하는 번호
- 정렬 기준이 아님

### `timeline_rank`

- 실제 정렬 기준
- 중간 삽입을 가능하게 하는 핵심 값

즉:

- `code` = 누구인가
- `display_number` = 사람에게 어떻게 보일까
- `timeline_rank` = 어떤 순서에 놓일까

이렇게 역할을 분리했다.

---

## 9. 짧은 요약

이번 DB 개편은 다음처럼 이해하면 가장 쉽다.

- `persons`, `events`
  - 앱이 읽는 대표 데이터
- `person_generated_assets`, `event_scene_generated_assets`
  - 이미지 생성 결과 상세 데이터
- `import_jobs`, `import_job_artifacts`
  - 사용자 JSON 반영 작업을 안전하게 추적하는 데이터

그리고 가장 중요한 구조 변화는:

- `정체성(code)`과
- `표시용 번호(display_number)`와
- `실제 순서(timeline_rank)`

를 분리한 것이다.
