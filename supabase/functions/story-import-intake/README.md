# story-import-intake

Supabase Edge Function 초안이다.

역할:

- 외부에서 story JSON intake 요청을 받는다.
- `import_jobs` row를 만든다.
- 원본 JSON을 Supabase Storage에 저장한다.
- `import_job_artifacts`에 raw input 기록을 남긴다.
- Trigger.dev webhook을 호출해 후속 검증/스테이징 작업을 시작한다.

## 요청 형식

```json
{
  "sourceName": "partner-story-batch.json",
  "stories": [
    {
      "code": "evt_example_001",
      "display_number": "024A",
      "timeline_rank": 2450,
      "era_code": "era_patriarch",
      "title": "세겜 도착: 첫 제단"
    }
  ],
  "note": "파트너사 4월 수집분",
  "externalRequester": {
    "name": "Alice",
    "email": "alice@example.com",
    "organization": "Example Org"
  },
  "metadata": {
    "campaign": "april_batch"
  }
}
```

## 응답 예시

```json
{
  "ok": true,
  "jobId": "8fd8d29c-....",
  "status": "received",
  "sourceStoragePath": "raw/<job_id>/partner-story-batch.json"
}
```

## 필요한 환경 변수

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STORY_IMPORTS_BUCKET`
- `TRIGGER_IMPORT_WEBHOOK_URL`
- `DEPLOYMENT_ENVIRONMENT`

## 참고

- 이 함수는 intake 전용이다.
- 실제 검증/정규화/이미지 생성은 Trigger.dev 쪽 task가 담당한다.
- external requester는 `auth.users` FK가 아닐 수 있으므로 `import_jobs.metadata`에 보관한다.
