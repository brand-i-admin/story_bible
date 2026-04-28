# send-push Edge Function

인앱 `notifications` / `broadcast_notifications` row 가 생성될 때 FCM HTTP v1 API 로 푸시 알림을 실제로 발송하는 함수.

## 배포

```bash
# 1. Firebase 서비스 계정 JSON 을 Supabase 시크릿으로 등록
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-admin-sdk.json)"

# 2. 함수 배포
supabase functions deploy send-push
```

## 입력 스키마

**개인 알림:**
```json
{
  "user_id": "uuid",
  "title": "제안이 승인되었어요",
  "body": "...",
  "deep_link": "/proposal/abc-123",
  "type": "proposal_approved"
}
```

**브로드캐스트:**
```json
{
  "broadcast": true,
  "title": "새 이야기가 등록되었어요",
  "body": "...",
  "deep_link": "/event/xyz",
  "type": "new_event",
  "target": "all"
}
```

## 반환

```json
{ "sent": 3, "failed": 1, "cleaned_tokens": 0 }
```

## DB 트리거 연결 (pg_net)

현재 DB 트리거 (`notify_on_proposal_comment` 등) 는 `notifications` row 만 INSERT 한다. 푸시 발송까지 자동화하려면 다음 두 가지 중 하나로 연결:

### A. `notifications` AFTER INSERT 트리거 + pg_net (권장)

Supabase 프로젝트에서 `pg_net` 확장 활성화 후:

```sql
create or replace function public._dispatch_push_on_notification()
returns trigger
language plpgsql
security definer
as $$
begin
  perform net.http_post(
    url := 'https://<project>.functions.supabase.co/send-push',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body,
      'deep_link', new.deep_link,
      'type', new.type
    )
  );
  return new;
end;
$$;

create trigger trg_dispatch_push
after insert on notifications
for each row execute function public._dispatch_push_on_notification();
```

`app.supabase_service_role_key` 는 Supabase 대시보드 → Database → Settings → Parameters 에서 설정.

### B. 클라이언트에서 supabase.functions.invoke

테스트/수동 발송 경로. 일상 운영에는 부적합 (클라이언트가 꺼져 있으면 발송 안 됨).

## 설계 메모

- **순차 전송**: 현재 유저 규모(~1000명) 에선 OK. 수만 명 이상이면 `Promise.all` 병렬화 혹은 배치 API 필요.
- **무효 토큰 정리**: FCM 이 404/UNREGISTERED 응답 시 `user_push_tokens` 에서 자동 삭제.
- **브로드캐스트 범위**: MVP 는 `target='all'` 만 지원. `pastor_or_admin` 은 향후 user_profiles JOIN 으로 확장.
- **재시도 없음**: 일시 실패 시 재시도 로직 없음. 중요 알림은 인앱에도 저장돼 있으므로 푸시 유실은 용인 가능.
