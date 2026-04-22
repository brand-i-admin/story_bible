# 푸시 알림 설정 가이드

Story Bible 앱은 Firebase Cloud Messaging(FCM) HTTP v1 API 로 푸시 알림을 보낸다. 이 문서는 **신규 환경 세팅 시 1회만** 수행하는 Firebase Console 작업과 Flutter/Supabase 연동 절차를 단계별로 안내한다.

현재 코드 상태: `firebase_core`/`firebase_messaging` 의존성은 이미 설치되어 있지만, `lib/firebase_options.dart` 가 placeholder 라 런타임에 Firebase 초기화가 실패한다 (앱은 try-catch 로 계속 동작). 본 가이드를 마치면 푸시가 활성화된다.

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
3. 이 키는 `--dart-define=FCM_VAPID_KEY=<key>` 로 앱 실행 시 주입 (또는 Flutter Web 빌드 파라미터).

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

## 6. 플랫폼별 수동 설정

### Android — `android/app/build.gradle`

```gradle
// 파일 맨 아래에 추가
apply plugin: 'com.google.gms.google-services'
```

`android/build.gradle` 의 `dependencies` 블록에:

```gradle
classpath 'com.google.gms:google-services:4.4.2'
```

Android 13+ 는 `POST_NOTIFICATIONS` 런타임 권한이 필요하다. `firebase_messaging` 플러그인이 자동 요청.

### iOS — `ios/Runner/Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
```

Xcode → Runner → Signing & Capabilities → "+ Capability" → "Push Notifications" 추가.

### Web — Service Worker

`web/firebase-messaging-sw.js` 생성 (flutterfire configure 가 생성 안 하면 수동):

```js
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '<from firebase_options.dart>',
  authDomain: '...',
  projectId: '...',
  appId: '...',
  messagingSenderId: '...',
});

const messaging = firebase.messaging();
```

## 7. Supabase Edge Function 배포

```bash
# 1) Firebase 서비스 계정 JSON 을 시크릿으로 등록
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-admin-sdk.json)"

# 2) send-push 함수 배포
supabase functions deploy send-push
```

## 8. DB 트리거와 send-push 연결 (선택)

`notifications` row 가 생길 때 자동으로 푸시를 보내려면 `pg_net` 확장 + 디스패치 트리거가 필요하다. 상세는 [supabase/functions/send-push/README.md](../supabase/functions/send-push/README.md) §"DB 트리거 연결".

활성화 전에는 **인앱 bell 알림만** 동작 (푸시는 보내지 않음). 인앱 알림이 최우선 UX 이므로 Phase A 로 여기까지만 하고, 푸시 디스패치는 Phase B 에서 활성화해도 괜찮다.

## 9. 동작 확인

1. 앱 재빌드 후 콘솔에 `[push] token: <긴 문자열>` 출력 확인.
2. Supabase Dashboard → Table Editor → `user_push_tokens` 에서 해당 토큰 row 확인.
3. Supabase SQL Editor 에서 직접 호출:

   ```sql
   select public.notify_quiz_completed('<임의 event uuid>');
   ```

   → `notifications` 테이블에 row 삽입, bell 배지 표시.

4. send-push 테스트 (Supabase Dashboard → Functions 로그):

   ```bash
   curl -X POST \
     -H "Authorization: Bearer <service_role_key>" \
     -H "Content-Type: application/json" \
     -d '{"user_id":"<uuid>","title":"테스트","body":"FCM 연결 확인"}' \
     "https://<project>.functions.supabase.co/send-push"
   ```

## 장애 시 확인 순서

| 현상 | 원인 | 해결 |
|------|------|------|
| `DefaultFirebaseOptions` 예외 | placeholder 상태 | `flutterfire configure` 실행 |
| 토큰 발급 null | 브라우저 권한 거부 / iOS simulator | 실기기/브라우저 권한 허용 |
| `register_push_token` 실패 | 로그아웃 상태 | 로그인 후 재시도 |
| FCM 404 UNREGISTERED | 토큰 만료 | Edge Function 이 자동 정리 |
