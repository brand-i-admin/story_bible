# send-push Edge Function

인앱 알림 시스템의 푸시 발송 엔드포인트. FCM HTTP v1 API 로 디바이스 푸시를 전송한다.

호출 경로(2026-05-11 이후):
- **`broadcast_notifications` AFTER INSERT 트리거** → `_fire_push_broadcast` → 이 함수 (자동, 새 이야기/인물 등록 시)
- **pg_cron 스케줄** → `_fire_push_broadcast` 직접 호출 (매일 미션/주간 미션/주간 다이어리)
- 수동: `supabase.functions.invoke('send-push', ...)`

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

## DB 트리거 연결 (2026-05-11 자동 연결됨)

`broadcast_notifications` AFTER INSERT → `trg_push_after_broadcast` → `_fire_push_broadcast`
→ 이 함수 호출. 별도 설정 없이 자동 발송. 상세는 `db_init.sql` "Push 디스패치 인프라" 섹션.

전제 조건(신규 환경 세팅 시):
1. `pg_net` 확장 활성화 (Dashboard → Database → Extensions → pg_net ON)
2. Supabase Vault 에 두 secret 등록 (Dashboard → Integrations → Vault → Secrets → New secret):
   - `service_role_key` — ⚙ Project Settings → API Keys → `service_role` 값
   - `supabase_url` — ⚙ Project Settings → API → "Project URL" (예: `https://<ref>.supabase.co`)
3. `supabase functions deploy send-push` (이 README의 상단 배포 절차)

설정 검증 SQL:
```sql
select name, length(decrypted_secret) as len
from vault.decrypted_secrets
where name in ('service_role_key', 'supabase_url');
```
2줄 결과가 나오면 성공. 인프라 변경 적용: `make db-init ENV=<env>` (db_init.sql 단일 진실 소스).

### 수동 발송 (테스트)

```ts
await supabase.functions.invoke('send-push', {
  body: { broadcast: true, title: '테스트', body: '본문', type: 'test' },
});
```
일상 운영용으로는 부적합 (클라이언트 종료 시 발송 안 됨).

## 설계 메모

- **순차 전송**: 현재 유저 규모(~1000명) 에선 OK. 수만 명 이상이면 `Promise.all` 병렬화 혹은 배치 API 필요.
- **무효 토큰 정리**: FCM 이 404/UNREGISTERED 응답 시 `user_push_tokens` 에서 자동 삭제.
- **브로드캐스트 범위**: MVP 는 `target='all'` 만 지원. `pastor_or_admin` 은 향후 user_profiles JOIN 으로 확장.
- **재시도 없음**: 일시 실패 시 재시도 로직 없음. 중요 알림은 인앱에도 저장돼 있으므로 푸시 유실은 용인 가능.
