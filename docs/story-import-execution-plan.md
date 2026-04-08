# Story Import Execution Plan

이 문서는 아래 구조를 실제로 구현하기 위한 실행 계획이다.

- 사용자 JSON 제출
- `import_job` 생성
- Trigger.dev 기반 검증/스테이징
- Discord 알림
- 내부 리뷰/승인
- GitHub Actions 승격

관련 문서:

- [story-import-automation.md](/Users/wonny/workspace/story_bible/docs/story-import-automation.md)
- [db-schema-refactor-overview.md](/Users/wonny/workspace/story_bible/docs/db-schema-refactor-overview.md)
- [generated-media-flow.md](/Users/wonny/workspace/story_bible/docs/generated-media-flow.md)

---

## 1. 구현 순서 체크리스트

### Phase 1. Intake 경로 만들기

- [ ] 외부 제출용 intake endpoint 결정
  - 권장: `Supabase Edge Function`
- [ ] 업로드 저장 bucket 준비
  - 예: `story-imports`
- [ ] JSON 원본 저장 경로 규칙 확정
  - 예: `raw/<job_id>/input.json`
- [ ] `import_jobs` row 생성 로직 연결
- [ ] `import_job_artifacts` 기록 로직 연결

### Phase 2. 자동 검증 / 스테이징 연결

- [ ] intake 완료 후 Trigger.dev task 시작
- [ ] `prepare_story_import_job.py` 실행 경로 연결
- [ ] validation 실패 시 상태를 `failed` 또는 `failed_validation`로 기록
- [ ] build 성공 시 산출물 경로를 `import_job_artifacts`에 기록
- [ ] diff summary를 operator가 볼 수 있게 저장

### Phase 3. Discord 알림 연결

- [ ] Discord bot 생성
- [ ] 운영 채널 구성
  - `#story-imports`
  - `#story-review`
  - 선택: `#story-import-failures`
- [ ] `received / build_ready / approved / promoted / failed` 상태 알림 연결
- [ ] review 링크와 job id를 메시지에 포함

### Phase 4. 내부 리뷰 UI

- [ ] import job 목록 화면
- [ ] import job 상세 화면
- [ ] validation error 화면
- [ ] diff summary 화면
- [ ] generated artifacts 링크 화면
- [ ] 승인 / 반려 버튼 연결

### Phase 5. 승격 경로

- [ ] 승인된 job만 promote 가능하게 제한
- [ ] GitHub Actions workflow 준비
- [ ] promote 시 asset 승격 / merge SQL 적용 / 상태 갱신 연결
- [ ] 성공 시 `promoted`, 실패 시 `failed`

### Phase 6. rollback 경로

- [ ] 직전 승인 job snapshot 참조 규칙 정의
- [ ] rollback 실행 주체 정의
  - 권장: GitHub Actions or 운영자용 admin action
- [ ] rollback 후 상태/로그 기록

---

## 2. 권장 시스템 경계

### Supabase

역할:

- JSON 원본 저장
- job 상태 저장
- artifact 메타데이터 저장
- 최종 stories / events / media row 저장

권장 보관 대상:

- raw input JSON
- normalized JSON
- seed SQL
- diff summary
- generated media manifests

### Trigger.dev

역할:

- 검증
- 스테이징 번들 생성
- 이미지/썸네일 생성 orchestrate
- 승인 대기
- promote/rollback 트리거

핵심 원칙:

- Trigger.dev는 orchestration을 담당
- 실제 도메인 로직은 기존 Python 스크립트를 최대한 재사용

### Discord

역할:

- 운영자 알림
- 상태 조회 보조
- 리뷰 요청 링크 전달

비권장 역할:

- 긴 diff 직접 검토
- JSON 직접 수정
- SQL 내용 전체 리뷰
- 실질적인 운영 UI 대체

### GitHub Actions

역할:

- 승인된 산출물만 staging/prod에 반영
- promote / rollback 실행 로그 남기기

---

## 3. Trigger.dev Task 설계

권장 task 분리는 아래 정도가 적당하다.

### `storyImport.intakeReceived`

입력:

- `jobId`
- `userId`
- `sourcePath`

역할:

- 기본 상태 확인
- 후속 validation task 실행

### `storyImport.validate`

입력:

- `jobId`

역할:

- JSON 구조 검사
- 필수 필드 검사
- `code` 중복 검사
- `timeline_rank` 숫자 검사
- `display_number` 중복/규칙 검사
- person / era code 유효성 검사

성공:

- 상태 `validated`

실패:

- 상태 `failed_validation` 또는 `failed`

### `storyImport.buildBundle`

입력:

- `jobId`

역할:

- `prepare_story_import_job.py` 실행
- normalized JSON 생성
- seed SQL 생성
- report 생성
- diff summary 생성

성공:

- 상태 `build_ready`

실패:

- 상태 `failed`

### `storyImport.notifyReviewReady`

입력:

- `jobId`

역할:

- Discord 알림 전송
- review 링크, 요약 변경 수, 제출자 정보 전송

### `storyImport.awaitApproval`

입력:

- `jobId`

역할:

- 사람이 승인/반려할 때까지 대기
- Trigger.dev wait 패턴 사용 가능

상태:

- `under_review`

### `storyImport.generateMedia`

입력:

- `jobId`

역할:

- 승인 후 또는 “이미지 생성 허용된 build_ready 상태”에서 실행
- 아바타/스토리 이미지 생성
- 썸네일 생성
- manifest 생성
- merge SQL 생성

중요:

- canonical asset 경로가 아니라 job 스코프 staging 경로에서 먼저 생성하는 쪽이 안전함

### `storyImport.promote`

입력:

- `jobId`
- `environment`

역할:

- 승인된 산출물만 승격
- asset 승격
- merge SQL 적용
- 최종 상태 갱신

성공:

- `promoted`

실패:

- `failed`

### `storyImport.rollback`

입력:

- `jobId`
- `targetJobId` 또는 `rollbackToApprovedJobId`

역할:

- 이전 승인 snapshot 기준으로 복구

---

## 4. Trigger.dev Payload 최소 규격

권장 공통 payload:

```json
{
  "jobId": "uuid-or-job-code",
  "requestedByUserId": "user-id",
  "environment": "staging",
  "sourceStoragePath": "raw/<job_id>/input.json"
}
```

review-ready payload 예시:

```json
{
  "jobId": "job_...",
  "status": "build_ready",
  "addedCodes": ["evt_new_001"],
  "changedCodes": ["evt_n024"],
  "reviewUrl": "https://admin.example.com/import-jobs/job_..."
}
```

---

## 5. Discord Bot이 해야 할 일

### 필수 기능

- import job 상태 알림 전송
- 실패 알림 전송
- review 링크 전송
- 승인 필요 알림 전송

### 권장 추가 기능

- `/job status <job_id>`
- `/job latest`
- `/job artifacts <job_id>`

### 메시지에 꼭 넣을 정보

- job id
- 제출자
- 상태
- added / changed / unchanged 수
- validation 실패 요약
- review 링크

### 메시지 예시

```text
[story-import] build_ready
job: job_20260408_xxx
user: user_123
added: 1
changed: 2
review: https://admin.example.com/import-jobs/job_20260408_xxx
```

---

## 6. 내부 Review UI 화면 구성

최소 화면은 4개면 충분하다.

### 1. Import Job 목록

표시 항목:

- job id
- 제출자
- 상태
- 접수 시각
- 최근 업데이트 시각
- added/changed 건수

필요 액션:

- 상세 보기

### 2. Import Job 상세

표시 항목:

- 원본 파일 정보
- SHA-256
- 상태 이력
- validation 결과
- artifact 링크

필요 액션:

- 승인
- 반려
- 이미지 생성 시작
- promote 실행

### 3. Diff Summary 화면

표시 항목:

- added codes
- changed codes
- unchanged codes
- `timeline_rank` 변경 여부
- `display_number` 변경 여부

중요 비교 포인트:

- 새 story 추가인지
- 기존 story 수정인지
- 중간 삽입인지

### 4. Media Review 화면

표시 항목:

- 샘플 썸네일
- 장면 수
- 누락된 avatar/person reference
- 생성 실패 내역

필요 액션:

- 승인
- 재생성 요청

---

## 7. 승인 규칙

자동 승인하면 안 되는 것:

- 새 이야기 추가
- 기존 이야기 수정
- `code` 충돌 또는 변경
- `timeline_rank` 변경
- `display_number` 변경
- 기존 media overwrite

자동화 가능한 것:

- 기본 validation
- normalized JSON 생성
- seed SQL 생성
- diff summary 생성
- 이미지/썸네일 생성
- manifest 생성

---

## 8. GitHub Actions Workflow 역할

권장 workflow 이름 예시:

- `promote-story-import.yml`
- `rollback-story-import.yml`

### `promote-story-import.yml`

입력:

- `job_id`
- `environment`

역할:

- 승인 상태 확인
- artifact 다운로드
- asset 승격
- merge SQL 적용
- smoke verification
- `import_jobs` 상태 갱신

### `rollback-story-import.yml`

입력:

- `job_id`
- `rollback_to_job_id`

역할:

- 기준 snapshot 복원
- 상태 갱신
- Discord 실패/복구 알림

---

## 9. 가장 작은 MVP

처음부터 전부 만들 필요는 없다.

추천 MVP 순서는:

1. intake endpoint
2. `import_jobs` 기록
3. Trigger.dev `validate + buildBundle`
4. Discord `build_ready` 알림
5. 간단한 internal review page
6. 수동 promote

즉 처음엔:

- 자동 intake
- 자동 validation
- 자동 bundle 생성
- 사람 승인
- 수동 promote

이 정도면 충분하다.

---

## 10. 한 줄 요약

가장 좋은 구현 방식은:

`Supabase가 원본과 상태를 저장하고, Trigger.dev가 검증/번들 생성을 오케스트레이션하고, Discord가 운영자를 호출하고, 내부 리뷰 UI가 승인하고, GitHub Actions가 최종 반영하는 구조`

이다.
