# 푸시 알림 설정 가이드

Story Bible 앱은 Firebase Cloud Messaging(FCM) HTTP v1 API 로 푸시 알림을 보낸다. 이 문서는 **신규 환경 세팅 시 1회만** 수행하는 Firebase Console 작업과 Flutter/Supabase 연동 절차를 단계별로 안내한다.

현재 코드 상태: `firebase_core`/`firebase_messaging` 의존성과 `lib/firebase_options.dart` 는 이미 들어 있다. Firebase 프로젝트를 새로 나누거나 재설정하면 `flutterfire configure` 를 다시 실행하고, `web/firebase-messaging-sw.js` 의 Firebase config 도 함께 동기화한다.

## 1. Firebase 프로젝트 생성

1. https://console.firebase.google.com/ 접속.
2. "프로젝트 추가" → 이름 `story-bible` (자유).
3. 기존 `GOOGLE_CLOUD_PROJECT` 아바타 생성용 GCP 프로젝트가 있다면, 같은 프로젝트에 Firebase 를 연결할 수 있다 (드롭다운에서 기존 프로젝트 선택).

## 2. 앱 등록 (Web / iOS / Android)

### Web
- 프로젝트 설정 → "앱 추가" → `</>` 아이콘 → 닉네임 `story-bible-web`.
- **"Firebase Hosting 설정"은 체크 해제**.
- 발급된 SDK config 는 `flutterfire configure` 로 자동 주입되므로 그대로 닫아도 됨.

### iOS
- "앱 추가" → iOS 아이콘.
- Bundle ID: Xcode 에서 `ios/Runner.xcodeproj` General 탭 "Bundle Identifier" 확인 (기본값 예: `com.example.storyBible`).
- 나머지 단계 건너뛰고 "콘솔로 계속".

### Android
- "앱 추가" → Android 아이콘.
- Package name: `android/app/build.gradle` 의 `applicationId`.

## 3. 서비스 계정 키 발급 (Edge Function 용)

1. 프로젝트 설정 → **"서비스 계정"** 탭.
2. **"새 비공개 키 생성"** 클릭 → JSON 파일 다운로드.
3. 파일명 예: `firebase-admin-sdk.json`.
4. **절대 git 에 커밋 금지** — `.gitignore` 에 이미 포함된 경로에 저장.

## 4. 웹 푸시용 VAPID 키

1. 프로젝트 설정 → **"Cloud Messaging"** 탭.
2. 하단 "Web configuration" 섹션 → "Key pair 생성" → 키 복사.
3. `.env` 에 `FCM_VAPID_KEY=<복사한 키>` 로 저장.
   - `scripts/common.sh` 가 `.env` 를 읽어 `run_*.sh` / `build_*.sh` 실행 시
     `--dart-define=FCM_VAPID_KEY=...` 로 자동 주입한다.
   - `lib/services/push_service.dart` 의 `String.fromEnvironment('FCM_VAPID_KEY')`
     가 이 값을 받아 Flutter Web 토큰 발급에 사용.
   - 값이 비어 있어도 앱은 정상 동작 (웹 푸시만 비활성화, 인앱 알림은 OK).

## 5. flutterfire 자동 설정

```bash
# 1) Firebase CLI 로그인
npm install -g firebase-tools
firebase login

# 2) FlutterFire CLI 설치
dart pub global activate flutterfire_cli

# 3) 자동 설정 (대화형) — Step 2 에서 만든 앱들을 선택
flutterfire configure
```

이 명령이 다음을 자동 수행한다:
- `lib/firebase_options.dart` **덮어씀** (현재 placeholder 대체)
- `android/app/google-services.json` 배치
- `ios/Runner/GoogleService-Info.plist` 배치
- `web/index.html` 에 Firebase SDK 스크립트 주입

## 6. 플랫폼별 설정 — flutterfire 자동 vs 수동

`flutterfire configure` 가 처리하는 범위와 남은 수동 작업을 구분해 정리.

### Android — ✅ 전부 자동

`flutterfire configure` 가 다음을 모두 처리:

- `android/app/google-services.json` 자동 배치
- `android/settings.gradle.kts` 에 `com.google.gms.google-services` 플러그인 선언 (`apply false`)
- `android/app/build.gradle.kts` 의 `plugins {}` 블록에 플러그인 적용

Android 13+ 런타임 `POST_NOTIFICATIONS` 권한은 `firebase_messaging` 이 필요 시 자동 요청.
**추가 수동 작업 없음.**

### iOS — ⚠️ 2가지 수동 필요 (이 프로젝트 저장소에 이미 적용 완료)

`flutterfire configure` 는 `GoogleService-Info.plist` 만 배치한다. 아래 두 가지는 별도 편집 필요:

1. **`ios/Runner/Info.plist`** — 백그라운드 푸시 수신 허용

   ```xml
   <key>UIBackgroundModes</key>
   <array>
     <string>fetch</string>
     <string>remote-notification</string>
   </array>
   ```

2. **`ios/Runner/Runner.entitlements`** — APNs 환경 등록

   ```xml
   <key>aps-environment</key>
   <string>development</string>
   ```

   Release 빌드 시 `production` 으로 바꾸거나, Xcode "Signing & Capabilities" 로
   "Push Notifications" capability 를 추가해 Xcode 가 자동 관리하게 둔다.

App Store 배포 시에는 Apple Developer Console 에서 App Identifier 의 Push
Notifications 기능이 체크되어 있어야 한다 (개발 단계에서는 불필요).

### Web — ⚠️ Service Worker 수동 생성 (이 프로젝트 저장소에 이미 작성됨)

`flutterfire configure` 는 `firebase-messaging-sw.js` 를 생성하지 않는다. 이미
`web/firebase-messaging-sw.js` 를 작성해 두었으며, 내용은 `lib/firebase_options.dart`
의 `web` 섹션과 동일한 config 를 가진다. **Firebase config 값이 바뀌면
(flutterfire 재실행 시) 이 파일도 동기화 필요.**

SW 역할:
- 백그라운드 메시지 수신 시 브라우저 알림 표시
- 알림 클릭 시 이미 열린 앱 탭으로 포커스 + `postMessage` 로 deep_link 전달

`web/index.html` 수정은 불필요 — `firebase_messaging` Flutter 플러그인이 JS SDK 로드를 자체 처리한다.

## 7. Supabase Edge Function 배포

```bash
# 1) Firebase 서비스 계정 JSON 을 시크릿으로 등록
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-admin-sdk.json)"

# 2) send-push 함수 배포
supabase functions deploy send-push
```

`supabase secrets set` 으로 저장한 값은 앱이나 git 에 들어가지 않고 해당 Supabase 프로젝트의 Edge Function 런타임 환경변수로 저장된다. 즉 `FIREBASE_SERVICE_ACCOUNT` 는 `send-push` 함수 안에서만 읽을 수 있는 서버용 비밀이다.

## 8. DB → send-push 자동 디스패치 (2026-05-11 도입)

DB 트리거/pg_cron 이 `send-push` 를 직접 호출하는 인프라가 `db_init.sql` 에 통합돼 있다. 다음 3가지를 만족하면 자동 동작한다:

1. **pg_net 확장 활성화** — Dashboard → Database → Extensions → `pg_net` ON
2. **Supabase Vault 에 두 secret 등록** — Dashboard → Integrations → Vault → Secrets → New secret
   - `service_role_key` — ⚙ Project Settings → API Keys → `service_role` 값
   - `supabase_url` — ⚙ Project Settings → API → "Project URL" (예: `https://<ref>.supabase.co`)
3. **db_init.sql 적용** — `make db-init ENV=<env>` 또는 Dashboard → SQL Editor 에 `db_init.sql` 전체 붙여넣고 Run. 새 헬퍼/트리거/`dispatch_daily_quiz_push`/pg_cron 모두 자동 등록된다.

자동 발송 경로:
- 새 이야기/인물 승인 (admin → `approve_event_proposal`) → broadcast row INSERT → 트리거 → push
- 매일 KST 9시 → `dispatch_daily_quiz_push()` (push-only, bell drop 안 쌓임)
- 매주 월요일 KST 9시 → `pick_weekly_character()` (push-only)
- 매주 수/금 KST 9시 → `notify_weekly_progress()` (push-only)

설정 검증 SQL:
```sql
-- Vault secret 2건
select name, length(decrypted_secret) as len
  from vault.decrypted_secrets where name in ('service_role_key','supabase_url');
-- broadcast 트리거
select tgname from pg_trigger where tgname = 'trg_push_after_broadcast';
-- pg_cron 4건
select jobname, schedule, active from cron.job order by jobname;
```

## 9. 동작 확인

1. 앱 재빌드 후 콘솔에 `[push] token: <긴 문자열>` 출력 확인.
2. Supabase Dashboard → Table Editor → `user_push_tokens` 에서 해당 토큰 row 확인.
3. Supabase SQL Editor 에서 즉시 푸쉬 테스트:

   ```sql
   -- 매일 퀴즈 푸쉬 발송 (전체 유저 + 본인 디바이스)
   select public.dispatch_daily_quiz_push();
   ```

   → 본인 휴대폰에 "오늘의 퀴즈가 도착했어요" 알림이 오면 통과.

4. send-push 함수 로그 (Supabase Dashboard → Functions → send-push → Logs):
   - 정상: `[send-push] sent: N, failed: 0`
   - 실패 시: `FIREBASE_SERVICE_ACCOUNT` 누락이 가장 흔한 원인

5. broadcast 흐름 테스트 — 관리자 계정으로 임의 제안을 승인하면 본인+다른 사용자 디바이스에 "새 이야기가 등록되었어요" 푸쉬 + bell drop 둘 다 옴.

## 장애 시 확인 순서

| 현상 | 원인 | 해결 |
|------|------|------|
| `DefaultFirebaseOptions` 예외 | placeholder 상태 | `flutterfire configure` 실행 |
| 토큰 발급 null | 브라우저 권한 거부 / iOS simulator | 실기기/브라우저 권한 허용 |
| `register_push_token` 실패 | 로그아웃 상태 | 로그인 후 재시도 |
| FCM 404 UNREGISTERED | 토큰 만료 | Edge Function 이 자동 정리 |
