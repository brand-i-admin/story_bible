# Trigger.dev Task Blueprint

이 문서는 story import 흐름을 Trigger.dev로 옮길 때의 최소 파일 구조와 task 구성 예시다.

현재 repo에는 Trigger.dev용 Node workspace가 아직 없다.  
따라서 아래는 “바로 옮겨붙일 수 있는 설계 초안”이다.

## 권장 파일 구조

```text
automation/
  trigger/
    src/
      tasks/
        story-import-intake.ts
        story-import-validate.ts
        story-import-build-bundle.ts
        story-import-notify-review.ts
        story-import-await-approval.ts
        story-import-generate-media.ts
        story-import-promote.ts
        story-import-rollback.ts
      lib/
        supabase.ts
        discord.ts
        storage.ts
        job-status.ts
      index.ts
    package.json
    tsconfig.json
```

## Task 목록

### `story-import-intake`

- 입력:
  - `jobId`
  - `sourceStoragePath`
  - `requestedByUserId`
- 역할:
  - 상태 확인
  - `story-import-validate` 실행

### `story-import-validate`

- 역할:
  - raw JSON 다운로드
  - 기초 구조 검증
  - `import_jobs.status = validated`
  - 실패 시 `failed_validation`

### `story-import-build-bundle`

- 역할:
  - `prepare_story_import_job.py` 실행
  - normalized JSON / seed SQL / diff summary 생성
  - artifact 등록
  - `build_ready`

### `story-import-notify-review`

- 역할:
  - Discord 채널에 build_ready 알림
  - review 링크 전송

### `story-import-await-approval`

- 역할:
  - 승인 이벤트가 올 때까지 대기
  - `under_review`

### `story-import-generate-media`

- 역할:
  - 필요 시 image/thumbnail generation
  - media manifest 생성
  - generated merge SQL 생성

### `story-import-promote`

- 역할:
  - approve된 job만 승격
  - asset 승격
  - merge SQL 적용
  - `promoted`

### `story-import-rollback`

- 역할:
  - 직전 승인 snapshot 복구
  - rollback 로그 기록

## 공통 payload 예시

```json
{
  "jobId": "job_20260408_...",
  "sourceStoragePath": "raw/<job_id>/input.json",
  "requestedByUserId": null,
  "environment": "staging"
}
```

## 실제 구현 원칙

- Trigger.dev는 orchestration만 담당한다.
- 기존 Python 스크립트는 최대한 그대로 재사용한다.
- 승인 전 canonical asset/DB를 직접 덮어쓰지 않는다.
- 상태 전이는 `import_jobs` 기준으로 기록한다.
