# Story Bible 인프라 가이드

## 0. 이 문서를 읽기 전에

"매번 튜토리얼 따라 하는데 왜 그런지 모르겠다"는 막연함을 없애기 위한 문서다. 각 인프라 조각이 **왜 필요한지, 어떻게 동작하는지, 시크릿은 어디 숨는지** 를 밑바닥까지 설명한다.

### 전체 인프라 지도

```
                  ┌────────────────────────────────────────────┐
                  │   Flutter 앱 (Web + iOS + Android)         │
                  └──┬──────────────┬─────────────┬────────────┘
                     │              │             │
          ┌──────────▼──┐   ┌───────▼──────┐  ┌───▼──────────┐
          │  Supabase   │   │   Firebase   │  │  Apple       │
          │  BaaS       │   │   (FCM)      │  │  (sign-in)   │
          │             │   │              │  │              │
          │ • Auth      │   │ • FCM Web    │  │  native      │
          │ • Postgres  │   │ • FCM iOS    │  │  idToken     │
          │ • Storage   │   │ • FCM Android│  └──────────────┘
          │ • Edge Fns  │   └──┬───────────┘
          │ • RLS/RPC   │      │
          └──────┬──────┘      ├────► APNs (Apple 서버)
                 │             │       └─ iOS 디바이스
                 │             └────► Web Push Service
                 │                     └─ Chrome/Safari
       ┌─────────▼────────┐   ┌─────────────────────────┐
       │   GCP            │   │  OAuth 2.0 Providers    │
       │ • Vertex AI      │   │ • Google (GCP OAuth)    │
       │ • IAM/서비스계정 │   │ • Apple (Dev Portal)    │
       └──────────────────┘   │ • Kakao (Kakao Dev)     │
                              └─────────────────────────┘
```

### 한 줄 요약

- **Supabase** — 중앙 허브. DB/Auth/Storage/함수. 프론트엔드가 유일하게 직접 대화하는 백엔드.
- **Firebase** — 푸시 전용. iOS/Android/Web 세 프로토콜을 단일 API 로 통합해줌.
- **GCP (Google Cloud)** — Vertex AI 이미지 생성. 그리고 Firebase 는 사실 GCP 프로젝트의 한 기능.
- **Apple Developer** — iOS 빌드 서명 + APNs 푸시 + Apple 로그인 3가지 경로의 증명서 발급처.
- **OAuth Providers** — Google/Apple/Kakao. 유저 신원 검증만 위임, Supabase가 JWT로 번역해 앱에 발급.

---

## 1. Supabase — 중앙 BaaS

### 1.1 왜 쓰는가

자체 서버(Node/Spring/Django)를 세우는 대신 다음을 한 번에 얻는다:

- **Postgres DB** — 실무 표준 RDBMS 그대로 노출 (꼼수 없음)
- **Auth** — 소셜 로그인 10여종 + 이메일 인증 + JWT 발급을 서버 코드 없이
- **Storage** — S3 호환 객체 저장소
- **Edge Functions** — Deno 기반 서버리스 TypeScript (필요한 서버 로직만 띄움)
- **Realtime** — Postgres 변경사항을 WebSocket 으로 스트림 (옵션)
- **RLS + RPC** — "프론트엔드가 DB에 직접 쿼리해도 안전"한 구조

스타트업/개인 프로젝트 규모에선 **백엔드 서버 팀 1명 분량**을 대체한다.

### 1.2 프로젝트 구성

| 구분 | dev | real |
|------|-----|------|
| 프로젝트 ref | `cvnutbizsgeycdjcbled` | `zmcffwcfmyhdykdhxhgy` |
| 엔드포인트 | `https://cvnutbizsgeycdjcbled.supabase.co` | `https://zmcffwcfmyhdykdhxhgy.supabase.co` |
| 앱 실행 ENV | `dev` | `real` 또는 `prod` |
| 운영 env suffix | `DEV` | `PROD` |

지역/풀러 host는 Supabase Dashboard의 Database connection string을 기준으로 확인한다.
현재 real 연결 예시는 [DB_SETUP.md](DB_SETUP.md)의 pooler 표를 우선한다.

### 1.3 주요 모듈과 실제 쓰임

#### Auth

- JWT(`eyJhbGci...`) 발급/검증/갱신
- 소셜 로그인 Provider 설정은 Supabase Dashboard → Authentication → Providers
- 3개 Provider 사용: Apple, Google, Kakao
- 발급한 JWT는 Flutter supabase_flutter SDK가 `SharedPreferences` 또는 `localStorage`에 자동 저장 → 재접속 시 세션 복원

#### Database (Postgres + RLS + Trigger + Function)

- **`db_init.sql`** = 단일 진실 소스. `make db-init` 시 DROP + CREATE 로 멱등하게 적용.
- 주요 테이블: `events`, `characters`, `eras`, `user_profiles`, `user_event_progress`, `event_proposals`, `event_proposal_comments`, `notifications`, `broadcast_notifications`, `user_push_tokens`, `weekly_character_selection` 등
- **RLS(Row Level Security)**로 클라이언트 직접 쿼리 허용하되 본인 것만 접근 (§7.4 에서 내부 동작 설명)
- **RPC**: 복잡한 로직은 plpgsql 함수로 감싸 `supabase.rpc('함수명')` 로 호출 — 예: `submit_event_proposal`, `notify_quiz_completed`

#### Storage

5개 버킷 (상세는 `../BACKEND.md` §6):
- `profile-images` — 유저 프로필 사진 (본인만 쓰기)
- `characters` — 인물 아바타 (admin 쓰기, 공개 읽기)
- `proposal-scenes` — 제안 장면 이미지 (Edge Function이 쓰기)
- `proposal-characters` — 제안 캐릭터 아바타
- `proposal-general-images` — 제안/운영 보조 이미지

각 버킷도 RLS policy 로 접근 제어.

#### Edge Functions

Deno TypeScript로 작성된 서버리스 함수. AWS Lambda 와 유사.

- `generate-proposal-scene` — 제안 장면 이미지를 Vertex AI Gemini 로 생성
- `generate-proposal-character` — 제안 캐릭터 아바타를 Imagen 으로 생성
- `send-push` — FCM 으로 푸시 전송

**왜 Edge Function이 필요한가**:
- GCP 서비스 계정 JSON 같은 비밀키를 서버에서만 써야 해서.
- 브라우저에서 직접 Vertex AI 를 호출하면 API 키가 공개돼 악용됨.

#### Realtime

Postgres WAL(Write-Ahead Log) 변경사항을 WebSocket 스트림. 이 프로젝트는 현재 **polling 방식**(`unreadNotificationCountProvider` 30초)을 쓰므로 Realtime 미사용. 향후 bell 배지를 즉각 갱신하려면 도입 가능.

#### pg_cron

DB 안에서 돌아가는 cron 스케줄러. pg_cron 확장을 활성화하면:
```sql
cron.schedule('weekly-character-monday-9am-kst', '0 0 * * 1',
  $$ select public.pick_weekly_character(); $$);
```
월요일 00:00 UTC (= KST 9시)에 주간 인물/탐색 선택을 갱신한다.

### 1.4 연결 설정 (`.env` / `.env.ops`)

```
# .env — 앱 실행용 공개값
SUPABASE_URL_PROD=https://zmcffwcfmyhdykdhxhgy.supabase.co
SUPABASE_ANON_KEY_PROD=eyJhbGciOiJIUzI1NiIs... # 클라이언트용 공개 키 (role=anon 포함)

# .env.ops — 로컬 운영도구용 비밀값 (앱 번들 제외)
SUPABASE_SERVICE_ROLE_KEY_PROD=eyJhbGciOiJIUzI1NiIs... # 서버 전용 RLS 우회 키
SUPABASE_DB_URL_PROD=postgresql://postgres.zmcff...:<pw>@aws-1-...supabase.com:5432/postgres
```

**`ANON_KEY` vs `SERVICE_ROLE_KEY` 차이**:
- 둘 다 JWT. 다른 점은 payload의 `role` 클레임.
- `anon` 키 = RLS 적용됨. 클라이언트가 써도 본인 데이터만 접근.
- `service_role` 키 = RLS 우회. 서버 사이드 코드/관리 도구 전용. **절대 클라이언트 노출 금지**.

---

## 2. Firebase Cloud Messaging (FCM) — 푸시 유일 경로

### 2.1 왜 쓰는가

iOS/Android/Web 세 플랫폼의 푸시가 서로 **완전히 다른 프로토콜**이다:

- **iOS** — APNs(Apple Push Notification service). Apple 독점. HTTP/2 + p8 키 서명 필요
- **Android** — Google Play Services 의 FCM 프로토콜
- **Web** — W3C Web Push Protocol (VAPID 서명 + 브라우저 Push Service)

각각 구현하면 관리 지옥. **Firebase 가 세 개를 하나의 HTTP API 로 통합**해준다. 특히 iOS: Firebase 에 APNs p8 키만 업로드해두면 Firebase 가 대신 APNs 를 호출한다.

### 2.2 프로젝트 구성 — `story-bible-491907`

Firebase Console 에서 앱 3개 등록:

| 플랫폼 | appId | 역할 |
|--------|-------|------|
| Web | `1:196457947669:web:a12ecb5408f22cc46f641c` | 브라우저 FCM 토큰 발급 |
| iOS | `1:196457947669:ios:d79e3acc88e573e86f641c` | APNs 토큰 → FCM 토큰 변환 |
| Android | `1:196457947669:android:458dd6388c71d4eb6f641c` | GCM/FCM 토큰 발급 |

### 2.3 네 가지 필수 자격 증명

| 자격 증명 | 발급 위치 | 저장 위치 | 용도 |
|----------|----------|----------|------|
| Firebase 서비스 계정 JSON | Firebase Console → 프로젝트 설정 → 서비스 계정 | Supabase secrets `FIREBASE_SERVICE_ACCOUNT` | Edge Function 이 FCM API 호출 시 OAuth 토큰 교환 |
| Web VAPID 키 쌍 (공개키) | Firebase Console → Cloud Messaging → Web 구성 | `.env` 의 `FCM_VAPID_KEY` | 브라우저 Push Service 구독 시 서버 식별 |
| APNs 인증 키 (p8) | Apple Developer → Keys → APNs | Firebase Console 에 업로드 | Firebase 가 iOS 디바이스에 푸시 중계 |
| Firebase SDK config | 자동 (flutterfire configure) | `lib/firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist` | 앱이 어느 Firebase 프로젝트로 토큰 발급할지 식별 |

### 2.4 동작 흐름

#### ① 토큰 발급 (Web 예시)

```
[Flutter 앱 시작]
  ↓
FirebaseMessaging.getToken(vapidKey: <VAPID_KEY>)
  ↓
Firebase JS SDK 가 브라우저 Push Service에 구독 요청
  ↓
브라우저가 VAPID 서명 확인 + Push Service endpoint 발급
  ↓
Firebase 가 endpoint + 키를 저장하고 FCM 토큰 반환 ("cC0Z47...")
  ↓
Flutter: supabase.rpc('register_push_token', { token, platform })
  ↓
Postgres user_push_tokens 테이블 upsert
```

#### ② 서버에서 푸시 전송

```
[DB 트리거가 notifications INSERT]
  ↓
_fire_push_broadcast / pg_net.http_post
  → send-push Edge Function 호출
  ↓
Edge Function send-push:
  1. user_push_tokens 조회 → FCM 토큰 목록
  2. Firebase 서비스 계정 JSON 으로 GCP OAuth access_token 교환 (§7.3 상세)
  3. POST fcm.googleapis.com/v1/projects/story-bible-491907/messages:send
     Authorization: Bearer <access_token>
     body: { message: { token, notification: {...}, data: {...} } }
  ↓
Firebase 내부:
  - Web 토큰 → Web Push Protocol 로 브라우저 Push Service 호출
  - iOS 토큰 → Apple APNs (p8 키로 서명) 호출
  - Android 토큰 → Google Play Services 로 직접 전달
  ↓
디바이스 수신:
  - Web (포그라운드): onMessage → Flutter → web.Notification 직접 호출
  - Web (백그라운드): firebase-messaging-sw.js 의 onBackgroundMessage → showNotification
  - iOS: 시스템 알림 센터
  - Android: 시스템 알림 trey
```

### 2.5 왜 `aps-environment` 가 development/production 두 개인가

Apple APNs 는 두 개의 **완전히 별개인 서버**를 운영한다:
- **Sandbox** (development) — 개발/Xcode Debug 빌드용
- **Production** — App Store/TestFlight 빌드용

`ios/Runner/Runner.entitlements` 의 `aps-environment` 값이 이 구분을 한다. Debug 빌드에 `production` 을 쓰면 푸시가 영원히 도달 안 한다(APNs 가 토큰을 인식 못 함). 반대도 마찬가지.

---

## 3. GCP (Google Cloud Platform) — AI 이미지 생성 + Firebase 의 뒷단

### 3.1 왜 쓰는가

- **Vertex AI (Gemini/Imagen)** — 제안 장면 이미지, 캐릭터 아바타 자동 생성
- Firebase 프로젝트는 **GCP 프로젝트의 한 면(facade)**. Firebase Console 의 설정은 내부적으로 GCP 리소스를 조작.

"Firebase 프로젝트 `story-bible-491907`"과 "GCP 프로젝트 `story-bible-491907`"은 **같은 프로젝트**다.

### 3.2 서비스 계정 두 개를 쓰는 이유

Edge Function 시크릿에 두 JSON 을 따로 둔다:

| 환경 변수 | 용도 | 필요 scope |
|----------|------|-----------|
| `GCP_SERVICE_ACCOUNT_JSON` | Vertex AI 호출 (generate-proposal-scene/character) | `cloud-platform` |
| `FIREBASE_SERVICE_ACCOUNT` | FCM API 호출 (send-push) | `firebase.messaging` |

**하나로 합쳐도 되지만 분리하는 이유**: 최소 권한 원칙. FCM 전용 계정이 유출돼도 Vertex AI 남용은 불가. 반대도 마찬가지. IAM에서 역할을 다르게 부여한다.

### 3.3 Vertex AI 호출 흐름 (`generate-proposal-scene` 예시)

```
[Flutter "이미지 생성" 버튼]
  ↓
supabase.functions.invoke('generate-proposal-scene', { sceneText, characterCodes, ... })
  ↓
Edge Function (Deno TypeScript):
  1. GCP_SERVICE_ACCOUNT_JSON 파싱 → private_key (RSA) 확보
  2. getGcpAccessToken(sa) → oauth2.googleapis.com/token 호출 (§7.3)
  3. Storage 에서 characters/<code>.png 를 base64 로 읽어 prompt 의 inlineData 로 첨부
  4. POST aiplatform.googleapis.com/v1/projects/.../locations/global/publishers/google/models/gemini-3-pro-image:generateContent
     Authorization: Bearer <access_token>
  5. 응답의 inline_data (PNG base64) 를 Storage proposal-scenes/<uid>/<draft>/scene_<idx>.png 로 업로드
  6. 클라이언트에 storage_path 반환
```

---

## 4. Apple Developer Portal + APNs — iOS 의 모든 것

### 4.1 왜 복잡한가

iOS 디바이스는 "Apple 이 발행한 서명"이 없으면 **아무것도 못 한다**. 앱 빌드(Provisioning Profile), 푸시(APNs Key), 로그인(Sign in with Apple Key) 모두 Apple 증명서 필요.

### 4.2 이 프로젝트에서 발급받아야 하는 것들

| 항목 | 발급 위치 | 용도 |
|------|----------|------|
| **App Identifier** `com.storybible.app` | Identifiers | 앱 고유 식별 + capability 활성화 |
| **APNs Authentication Key (p8)** | Keys → "Apple Push Notifications service" | Firebase 가 APNs 호출 시 서명 |
| **Sign in with Apple Key (p8)** | Keys → "Sign in with Apple" | Supabase 가 Apple idToken 검증 |
| **Provisioning Profile** | Profiles | 빌드 서명 + capability 포함 (Xcode 자동 생성) |

### 4.3 iOS 푸시 동작 흐름 (전체)

```
[앱 최초 실행 + 로그인]
  ↓
① FirebaseMessaging.requestPermission() → iOS 시스템 알림 권한 요청
  ↓ 사용자 "허용"
② iOS 가 APNs 와 통신 → APNs device token (64바이트 16진수) 획득
  ↓
③ Firebase SDK 가 APNs token 을 Firebase 서버에 등록 → FCM token 반환
  ↓
④ Flutter supabase.rpc('register_push_token', { token, platform: 'ios' })

[나중에 서버가 푸시 보낼 때]
  ↓
⑤ Edge Function send-push → fcm.googleapis.com/v1/.../messages:send
  ↓
⑥ Firebase 서버가 저장된 APNs p8 키로 JWT 서명 → api.push.apple.com 호출
   헤더: authorization: bearer <apns-jwt>, apns-topic: com.storybible.app
   body: { aps: { alert: {...} }, ...custom data }
  ↓
⑦ APNs → iOS 디바이스 (시스템 알림)
```

### 4.4 Sign in with Apple 의 Key 왜 따로인가

- **APNs 키**: "Apple이 Firebase에게 푸시 발송 권한을 위임" 증명
- **Sign in Apple 키**: "Apple이 Supabase에게 idToken 검증 권한을 위임" 증명

둘 다 같은 Developer 계정에서 발급하지만 **다른 목적의 RSA 키쌍**. 섞이면 안 됨.

---

## 5. OAuth 2.0 Identity Providers — 소셜 로그인 3종

### 5.1 이 프로젝트의 위임 구조

```
[앱]  ──► [Supabase Auth]  ──►  [Provider (Google/Apple/Kakao)]
                 │                         │
                 ◄──── callback ───────────┘
                 │ (code or idToken)
[앱] ◄── Supabase JWT ───┘
```

앱은 **Supabase JWT 만** 알면 된다. Provider 별 특성은 Supabase가 흡수.

### 5.2 Google 로그인 — Android native + OAuth fallback

#### 구성 (GCP Console)

1. https://console.cloud.google.com → APIs & Services → **Credentials**
2. Web OAuth Client
   - "+ CREATE CREDENTIALS" → "OAuth client ID" → 유형: **웹 애플리케이션**
   - **승인된 리디렉션 URI**: `https://zmcffwcfmyhdykdhxhgy.supabase.co/auth/v1/callback`
   - 생성된 Client ID + Client Secret → Supabase Dashboard → Authentication → Providers → Google 에 붙여넣기
   - 이 Web Client ID 는 Android native 로그인에서 `serverClientId` 로도 사용한다.
3. Android OAuth Client
   - 유형: **Android**
   - Package name: `com.storybible.app`
   - SHA-1/SHA-256: Play Console → App integrity → App signing key certificate 값을 등록한다.
   - 내부 테스트/직접 설치 빌드도 필요하면 upload key/debug key SHA 를 별도 Android Client 로 추가한다.
4. Supabase Dashboard → Authentication → URL Configuration → Redirect URLs 에 `com.storybible.app://login-callback` 추가

#### 동작

Android 앱은 Google의 embedded user-agent 차단(`403 disallowed_useragent`)을 피하기 위해
브라우저 OAuth 대신 `google_sign_in` 으로 네이티브 계정 선택 UI를 열고,
Google `idToken/accessToken` 을 Supabase `signInWithIdToken` 으로 전달한다.

```
사용자 "Google로 로그인" 클릭
  ↓
GoogleSignIn(serverClientId=<WEB_CLIENT_ID>).signIn()
  ↓
Google Play services 계정 선택/동의
  ↓
앱이 idToken + accessToken 수신
  ↓
supabase.auth.signInWithIdToken(OAuthProvider.google, idToken, accessToken)
  ↓
Supabase 가 Google 토큰 검증 후 Supabase JWT 발급
```

Web/iOS fallback 은 Supabase OAuth Authorization Code Flow 를 사용한다.

```
사용자 "Google로 로그인" 클릭
  ↓
supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: <앱 URL>)
  ↓
브라우저가 accounts.google.com/o/oauth2/auth?
  client_id=<GCP_CLIENT_ID>&
  redirect_uri=https://cvnut....supabase.co/auth/v1/callback&
  scope=email profile&
  response_type=code&
  state=<random>   ← CSRF 방지용
  ↓
사용자 Google 로그인 + 권한 동의
  ↓
Google이 Supabase callback 으로 redirect (URL에 code=... 포함)
  ↓
Supabase 서버가:
  - code 수신
  - Google token endpoint 호출: POST oauth2.googleapis.com/token
    { grant_type: 'authorization_code', code, client_id, client_secret, redirect_uri }
  - access_token + id_token(JWT) 수신
  - id_token 검증 (Google 공개키로 서명 확인)
  - payload 의 email/name 으로 auth.users 생성 또는 update
  - Supabase JWT 발급
  ↓
앱 URL로 최종 redirect (URL fragment 에 #access_token=supabase_jwt&...)
  ↓
Flutter SDK 가 URL 파싱해서 세션 저장
```

**왜 이 복잡한 과정**: 비밀번호를 앱에 **절대 노출 안 하려고**. 사용자는 Google 사이트에서만 입력, 앱은 "로그인 완료" 신호만 받는다.

### 5.3 Apple 로그인 — idToken 직접 검증 방식

Google 과 다르게 Apple 은 **앱 내 native dialog + idToken 즉시 반환** 방식을 선호. Supabase 는 `signInWithIdToken` 으로 Apple idToken 을 **직접 검증**한다.

```dart
// auth_repository.dart
final rawNonce = _client.auth.generateRawNonce();
final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [email, fullName],
  nonce: hashedNonce,  // ← Apple 에 해시 버전
);

await _client.auth.signInWithIdToken(
  provider: OAuthProvider.apple,
  idToken: credential.identityToken,
  nonce: rawNonce,     // ← Supabase 에 raw 버전
);
```

**이 nonce 이중 처리가 왜 있는지는 §7.2 에서 자세히**.

### 5.4 Kakao 로그인 — Google 과 동일 구조

Kakao Developers → 내 애플리케이션 → 카카오 로그인 활성화. Redirect URI는 동일하게 `https://cvnut....supabase.co/auth/v1/callback`. Supabase Dashboard → Kakao Provider 에 REST API 키 + Client Secret 등록. 나머지 흐름은 Google 과 똑같은 Authorization Code Flow.

---

## 6. 시크릿 관리 — 계층 구조

실수로 커밋하면 가장 아픈 부분.

### 6.1 각 시크릿의 집

| 시크릿 종류 | 파일/위치 | 누가 읽는가 | 유출 시 피해 |
|------------|----------|------------|-------------|
| `SUPABASE_ANON_KEY` | `.env` → scripts가 `--dart-define`으로 주입 | 클라이언트 | 낮음 (RLS로 보호) |
| `SUPABASE_SERVICE_ROLE_KEY` | `.env.ops`, Supabase secrets | 관리 스크립트, Edge Function | **치명적** (RLS 우회) |
| `GCP_SERVICE_ACCOUNT_JSON` | Supabase secrets 전용 | Edge Function (Vertex AI) | Vertex AI 비용 폭탄 |
| `FIREBASE_SERVICE_ACCOUNT` | Supabase secrets 전용 | Edge Function (send-push) | 무단 푸시 발송 |
| APNs p8 키 | Firebase Console 업로드 | Firebase 서버 내부 | Firebase 에서 앱에 무단 푸시 |
| Sign in Apple p8 키 | Supabase Dashboard 업로드 | Supabase 서버 내부 | Apple 로그인 위조 |
| Google OAuth Client Secret | Supabase Dashboard 업로드 | Supabase 서버 내부 | Google 로그인 위조 |
| Firebase SDK 공개 config (apiKey, appId) | `firebase_options.dart` → **git 커밋됨** | 클라이언트 | 낮음 (§6.3) |

### 6.2 `.env` / `.env.ops` 파일 규칙

- 둘 다 `.gitignore` 에 들어있어 **절대 커밋 안 됨**
- 신규 환경 세팅: `cp .env.example .env`, `cp .env.ops.example .env.ops` 후 실제 값 채우기
- `.env`: 앱 실행에 필요한 공개 URL/anon key, FCM VAPID 공개키
- `.env.ops`: service role key, DB URL 처럼 앱에 들어가면 안 되는 운영 비밀
- 스크립트(`scripts/common.sh`)가 실행 전 `.env` 를 파싱해 앱에 필요한 값만 `--dart-define` 으로 주입
- Supabase Edge Function secret은 `.env.ops`가 아니라 `.env.supabase.secrets` 템플릿으로 관리하고 `supabase secrets set --env-file .env.supabase.secrets`로 반영
- 다른 컴퓨터/팀원 공유 기준은 [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md)를 우선한다.

### 6.3 왜 Firebase `apiKey` 는 커밋해도 되는가

Google/Firebase 공개 apiKey 는 **인증/인가를 하지 않는다**. 단지 "어느 Firebase 프로젝트를 가리키는지" 식별 목적. 진짜 보호는:

- Firebase Console → Authentication → **승인된 도메인 목록**
- GCP Console → APIs & Services → Credentials → **API Restrictions** (Bundle ID, HTTP referrer 제한)

그래서 `firebase_options.dart` 가 GitHub에 있어도 해커가 이걸로 할 수 있는 일이 없다. 반면 **서비스 계정 JSON** 의 `private_key` 는 진짜 권한을 가진 RSA 개인키라 유출 시 치명적.

### 6.4 Git pre-commit hook 의 방어

`.pre-commit-config.yaml` 의 `forbidden-pattern` hook 이 다음 패턴을 스캔:

- `SUPABASE_SERVICE_ROLE_KEY=`
- `BEGIN RSA PRIVATE KEY`
- `-----BEGIN PRIVATE KEY-----`
- `sk_live_`, `sk_test_` (Stripe 등)

실수로 시크릿을 커밋하려 하면 자동 차단.

---

## 7. 자주 나오는 핵심 원리

"매번 보는데 정확히 모르겠다" 하는 것들.

### 7.1 JWT (JSON Web Token) — Supabase, Firebase, Google 모두 사용

#### 구조

`AAAA.BBBB.CCCC` 같은 3부분 문자열. 각각 base64url 인코딩.

```
header:    {"alg":"HS256","typ":"JWT"}
payload:   {"sub":"a6731503-...","role":"authenticated","exp":1800000000}
signature: HMAC_SHA256( base64(header) + "." + base64(payload), SECRET )
```

#### 왜 필요한가

- **Stateless 인증**: 서버가 세션 저장 안 해도 JWT 를 검증만 하면 유저 식별.
- 여러 서비스(Supabase, PostgREST, Postgres) 가 같은 JWT 를 독립적으로 검증 가능.

#### Supabase 에서 JWT 흐름

```
[Flutter] 로그인 성공 → Supabase가 JWT 발급
  ↓ 헤더 Authorization: Bearer eyJhbG...
[PostgREST] 수신 → 서명 검증 (Supabase JWT_SECRET) → payload.sub 추출
  ↓ 내부적으로 set_config('request.jwt.claims', payload) 호출
[Postgres] RLS 평가 시 auth.uid() → current_setting('request.jwt.claims')->>'sub' 반환
```

실제로 JWT 디코딩: https://jwt.io 에 붙여넣으면 payload 가 바로 보인다. 서명은 SECRET 없으면 검증 못 하지만 payload 읽기는 누구나 가능(base64 인코딩일 뿐). **그래서 JWT 에 비밀 정보를 넣으면 안 된다**.

### 7.2 Apple 로그인 nonce 가 두 번 쓰이는 이유

#### 문제

Apple이 발급한 idToken 을 누군가 탈취해서 **다른 앱에서 재사용**하면 어떻게 막을까?

#### 해결: Nonce (일회용 값) + 해시 바인딩

```
Step 1. 앱이 random 생성
  rawNonce = "x9f7Kp2qMn8dLv3s..."   (앱만 안다)

Step 2. 해시해서 Apple에 전달
  hashedNonce = SHA256(rawNonce) = "a3b7e9c1f5..."
  Apple dialog 에 nonce: hashedNonce 전달

Step 3. Apple이 idToken에 포함해 서명
  idToken.payload = {
    "iss": "https://appleid.apple.com",
    "aud": "com.storybible.app",
    "sub": "<Apple user id>",
    "nonce": "a3b7e9c1f5...",   ← 해시 nonce 가 박혀있음
    ...
  }

Step 4. 앱이 Supabase에 제출 — raw 와 idToken 둘 다
  supabase.auth.signInWithIdToken(idToken, nonce: rawNonce)

Step 5. Supabase 서버가 검증
  ① idToken 서명을 Apple 공개키로 검증 (진짜 Apple 발급 맞나)
  ② idToken.nonce 추출 → SHA256(전달받은 rawNonce) 와 비교
  ③ 일치하면 "이 토큰을 발급받은 게 정확히 이 앱이다" 확신 → 로그인 성공
```

#### 왜 해시를 Apple에 보내고 raw를 Supabase에 보내나

- **Apple 서버 로그에는 평문 nonce 가 남을 수 있다.** 만약 Apple 에 rawNonce 를 그대로 보냈다면 로그 유출 시 재사용 공격 가능.
- **해시 바인딩**: Apple은 "내가 본 해시"를 idToken에 박아 서명. Supabase는 "raw를 알고 있다"는 증거로 일치 여부만 확인. 공격자가 idToken을 훔쳐도 **rawNonce를 모르면 재사용 불가**.

즉 한 마디로: **Apple 로그에는 해시만, 실제 검증에는 raw — 이 분리로 replay attack 차단**.

### 7.3 Edge Function 이 GCP access_token 을 받는 원리

Edge Function 에서 Vertex AI 나 FCM 을 호출하려면 **access_token** (`ya29.a0A...`)이 필요하다. 이걸 어떻게 얻는가.

#### 핵심 아이디어

"서비스 계정 JSON 에 있는 **RSA 개인키로 JWT 를 서명**해서 Google에 제출하면, Google 은 그 서명을 자신이 저장한 공개키로 검증하고 access_token 을 준다."

#### 코드 (`supabase/functions/_shared/gcp_auth.ts`)

```typescript
export async function getGcpAccessToken(sa: GcpServiceAccount, scope: string) {
  const nowSec = Math.floor(Date.now() / 1000);

  // 1. JWT 작성
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,    // 서비스 계정 이메일
    scope: scope,            // "cloud-platform" 또는 "firebase.messaging"
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSec,
    exp: nowSec + 3600,
  };

  // 2. RSA 개인키로 서명 (RS256 = RSA + SHA256)
  const toSign = base64(header) + "." + base64(claims);
  const key = await crypto.subtle.importKey("pkcs8", pemToBytes(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key,
    new TextEncoder().encode(toSign));
  const jwt = toSign + "." + base64(signature);

  // 3. Google 토큰 엔드포인트로 JWT 제출
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  // 4. access_token 수신
  const { access_token } = await response.json();
  return access_token;  // "ya29.a0A..."
}
```

#### Google 쪽에서 일어나는 검증

1. `assertion` 으로 받은 JWT 파싱
2. `iss` 필드(서비스 계정 이메일) 로 IAM 에서 해당 계정 조회 → **그 계정의 공개키 목록** 획득
3. JWT signature 를 공개키로 검증 → 통과하면 "이 서비스 계정 소유자가 맞다"
4. `scope` 가 해당 계정에 허용된 권한 범위 내인지 확인
5. `exp` 가 지나지 않았는지
6. 전부 통과 → `access_token` 발급 (1시간 유효)

#### 왜 개인키로 서명하는가 (비밀번호 방식이 아니라)

- **비밀번호 방식** → 요청마다 비밀번호 전송 필요 → MITM 위험
- **공개키 암호 방식** → 서명은 개인키만 가능, 검증은 공개키로. 네트워크에 비밀은 절대 안 흐름
- **1시간 TTL** → 유출돼도 피해 범위 제한

이 원리가 이해되면 "서비스 계정 JSON = 비밀번호"가 아니라 "서명 용 RSA 개인키 + 식별자"로 보인다.

### 7.4 RLS (Row Level Security) 내부 동작

#### SQL 레벨에서 일어나는 일

```sql
create policy notifications_select_own on notifications
for select to authenticated using (auth.uid() = user_id);
```

이 정책을 건 테이블에 SELECT 가 오면 Postgres 가 내부적으로:

```sql
-- 클라이언트가 보낸 쿼리:
SELECT * FROM notifications;

-- Postgres 가 실제 실행하는 쿼리:
SELECT * FROM notifications
WHERE (auth.uid() = user_id);
```

마치 WHERE 절이 자동으로 붙는 것.

#### `auth.uid()` 는 어디서 오는가

```
[Flutter]
  supabase.from('notifications').select()
  → HTTP GET /rest/v1/notifications
  → Authorization: Bearer <JWT>

[PostgREST]
  → JWT 검증 (Supabase JWT_SECRET)
  → payload.sub 추출 = "a6731503-..."
  → Postgres 세션에 set_config('request.jwt.claims', '{...}') 호출
  → 쿼리 실행

[Postgres]
  auth.uid() 함수는:
    select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
  → "a6731503-..." UUID 반환
  → RLS policy 의 WHERE 에 사용됨
```

핵심은 **JWT 의 `sub` 클레임 → Postgres 세션 설정 → `auth.uid()` 반환** 체인. 이 체인이 깨지면 (JWT 만료, 서명 불일치 등) `auth.uid()` 는 NULL 반환 → RLS policy 실패 → 빈 결과.

#### `SECURITY DEFINER` 함수의 특권

어떤 RPC 함수는 **RLS 를 우회해야 한다** (예: `register_push_token` 은 auth.users 를 조회). 방법:

```sql
create or replace function public.register_push_token(...)
returns void
language plpgsql
security definer   -- ← 이 한 줄
set search_path = public
as $$
...
$$;
```

`security definer` = "이 함수는 **함수 작성자의 권한**으로 실행됨" (기본 invoker 권한이 아님). 작성자는 보통 `postgres` 수퍼유저 → RLS 우회. 대신 함수 안에서 **필요한 권한 체크를 직접** 한다 (`if not public.is_admin() then raise exception ...`).

### 7.5 Service Worker 라이프사이클 (웹 푸시)

브라우저가 **페이지가 닫혀도** JS 를 실행할 수 있는 유일한 방법.

#### 등록 → 설치 → 활성화

```
[Flutter 앱 시작]
  FirebaseMessaging.getToken(vapidKey: ...)
    → Firebase SDK 가 내부적으로 navigator.serviceWorker.register('/firebase-messaging-sw.js')
    ↓
  브라우저가 /firebase-messaging-sw.js 다운로드
    ↓
  install 이벤트 fire (SW 파일 파싱 + importScripts 로드)
    ↓
  activate 이벤트 fire (이전 SW 있으면 교체)
    ↓
  상태: "activated and running"
```

#### Push 수신

```
[서버가 푸시 전송]
  ↓ (브라우저 Push Service 경유)
[브라우저]
  → SW 가 idle 상태면 wake up
  → push 이벤트 fire
  → firebase-messaging-sw.js 의 onBackgroundMessage 콜백 실행
  → self.registration.showNotification(...) 호출
  → OS 알림 표시
  → 일정 시간 후 SW 다시 idle
```

#### 포그라운드/백그라운드 차이 (FCM Web 특수성)

Firebase JS SDK 는 탭이 `visible` 상태일 때 **SW 의 onBackgroundMessage 를 호출하지 않는다**. 대신 앱 자체의 `FirebaseMessaging.onMessage` 만 fire. 개발자가 직접 알림을 띄워야 한다. 이 프로젝트는 `lib/services/web_notification_web.dart` 가 그 역할.

#### Scope 규칙

```
등록된 경로: /firebase-messaging-sw.js
 → scope: / (루트 이하 전체)

등록된 경로: /push/sw.js
 → scope: /push/ (이하만)
```

한 origin 에 scope 가 겹치는 SW 여러 개 등록되면 마지막 등록된 것이 최종 통제. 이 프로젝트는 `flutter_service_worker.js` (PWA 용)와 `firebase-messaging-sw.js` 두 개 공존하는데, 서로 다른 경로에서 등록되어 충돌 없음.

### 7.6 CORS / CSP 간단 정리

브라우저가 "이 페이지에서 다른 도메인의 리소스를 마음대로 가져가면 안 됨" 을 강제하는 두 메커니즘.

#### CORS (Cross-Origin Resource Sharing)

"내 API 를 어느 origin 이 호출할 수 있게 허용할지" — **서버가 응답 헤더**로 선언.

```
Access-Control-Allow-Origin: *            ← 모든 origin 허용 (공개 API)
Access-Control-Allow-Origin: https://app.example.com   ← 특정 origin만
Access-Control-Allow-Headers: Authorization, Content-Type
Access-Control-Allow-Methods: GET, POST
```

Supabase Edge Function `_shared/cors.ts` 가 `*` 로 설정되어 있는 이유: Flutter 웹 앱이 여러 도메인(localhost dev, staging, prod)에서 서빙되어도 허용하려고. **JWT 가 실제 보안을 담당**하니 CORS 는 완전 공개해도 안전.

#### CSP (Content Security Policy)

"이 페이지에서 로드할 수 있는 스크립트/스타일/이미지의 origin 을 제한" — **페이지가 자체 헤더**로 선언.

```html
<meta http-equiv="Content-Security-Policy"
      content="script-src 'self' https://www.gstatic.com;
               connect-src 'self' https://*.supabase.co">
```

현재 이 프로젝트는 CSP 설정 없음 (`web/index.html` 기본 그대로). 필요 시 Firebase CDN (`www.gstatic.com`), Supabase (`*.supabase.co`), FCM 을 allowlist 에 추가.

---

## 8. 종합 라이프사이클 — "내 제안에 댓글 달리는 순간" end-to-end

실제로 인프라 전체가 어떻게 맞물리는지.

```
[관리자 A — Chrome 웹 브라우저]
  1. 제안 상세 화면에서 댓글 작성
     → supabase.rpc('add_proposal_comment', { proposal_id, body })

[Supabase Postgres]
  2. add_proposal_comment 함수 실행
     - is_pastor() or is_admin() 체크 → 통과
     - INSERT INTO event_proposal_comments

  3. AFTER INSERT 트리거 trg_notify_on_proposal_comment fire
     - proposer B, admin C/D 에게 notifications INSERT
     - 총 3개 row 생성

  4. AFTER INSERT on notifications 계열 트리거
     - `pg_net.http_post` → send-push Edge Function 호출

[Supabase Edge Function — send-push]
  5. 입력: { user_id: B, title, body, deep_link }
  6. Postgres 조회: user_push_tokens WHERE user_id = B
     → [웹 토큰 1개, iOS 토큰 1개] 반환
  7. Firebase 서비스 계정 JSON 으로 GCP access_token 교환
     - RSA 개인키로 JWT 서명
     - POST oauth2.googleapis.com/token
     - access_token 수신 (1시간 유효)
  8. 토큰 개수만큼 FCM API 호출
     - POST fcm.googleapis.com/v1/projects/story-bible-491907/messages:send
       Authorization: Bearer <access_token>
       body: { message: { token: <웹토큰>, notification: {...}, webpush: {...} } }
     - 한 번 더: { message: { token: <iOS토큰>, notification: {...}, apns: {...} } }

[Firebase 서버]
  9a. 웹 토큰 → Web Push Service (Chrome FCM) 로 전달
       - Chrome 자체 Push Service endpoint 에 전송
       - 디바이스 Chrome 이 받아서 SW 의 push 이벤트 fire
  9b. iOS 토큰 → APNs
       - Firebase 가 저장된 APNs p8 로 JWT 서명
       - POST api.push.apple.com/3/device/<apns-token>
       - APNs → B 의 iPhone

[B 의 Chrome 브라우저]
  10. SW 의 onBackgroundMessage (또는 포그라운드면 Flutter onMessage)
     - showNotification("제안에 댓글이 달렸어요", body, {...})
     - macOS 알림 센터 표시

[B 의 Flutter 앱 (30초 polling)]
  11. unreadNotificationCountProvider → rpc/unread_notification_count
     → 미독 카운트 +1 → bell 배지 업데이트

  12. 사용자가 bell 클릭 → rpc/list_my_notifications(limit=5, only_unread=true)
     → 새 알림 row 표시

[B 가 알림 탭]
  13. _handleNotificationTap 실행
     - rpc/mark_notification_read(id)
     - deep_link 파싱 → /proposal/<id>
     - 모바일이면 "컴퓨터에서 확인하세요" 다이얼로그
     - 웹이면 ProposalDetailScreen push
```

총 13 스텝. 각 스텝마다 다른 인프라가 관여한다.

---

## 9. 트러블슈팅 체크리스트

흔한 증상 → 의심 지점.

| 증상 | 의심할 곳 |
|------|----------|
| 로그인 후 RLS 쿼리 결과 비어있음 | JWT 만료 여부, 토큰이 실제로 Authorization 헤더에 붙는지 (Chrome Network 탭) |
| FCM 토큰 발급 실패 (null) | 권한(`Notification.permission`), VAPID 키, flutterfire config |
| `user_push_tokens` INSERT 안 됨 | 로그인 상태인지(`auth.uid()` null 이면 RPC raise), register_push_token RPC 실제 호출 여부 |
| `send-push` 에서 `invalid_grant` | 서비스 계정 JSON 의 `private_key` 형식 (줄바꿈 `\n` 처리), `exp` 가 `iat+3600` 넘지 않게 |
| iOS 디바이스에 푸시 안 감 | APNs p8 Firebase 업로드, `aps-environment` 값(dev/prod), App Identifier 의 Push capability |
| Chrome에 푸시 안 뜸 (토큰은 발급) | macOS 시스템 설정 → 알림 → Chrome → "알림 허용" + "알림 스타일 ≠ 없음" |
| Google 로그인 redirect 후 빈 화면 | Supabase Dashboard → Redirect URLs 에 현재 origin 등록됐는지, GCP OAuth Client 의 승인된 URI |
| Apple 로그인 `invalid_client` | Service ID 등록, Sign in Apple Key 업로드, Team/Key ID 일치 |
| Edge Function 502/500 | Supabase Dashboard → Functions → Logs 에서 stack trace, 필요한 secrets 모두 등록됐는지 |
| `make db-init` 후 RPC 호출 404 | PostgREST schema cache 미갱신 → `NOTIFY pgrst, 'reload schema'` |

---

## 10. 참고 링크

- Supabase Docs: https://supabase.com/docs
- Firebase Cloud Messaging: https://firebase.google.com/docs/cloud-messaging
- FCM HTTP v1 API: https://firebase.google.com/docs/cloud-messaging/send-message
- Apple APNs Docs: https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server
- Sign in with Apple: https://developer.apple.com/sign-in-with-apple/
- GCP 서비스 계정 인증: https://cloud.google.com/docs/authentication/provide-credentials-adc
- Vertex AI: https://cloud.google.com/vertex-ai/docs
- JWT 디코더 (디버깅용): https://jwt.io

---

## 문서 교차 참조

- `../BACKEND.md` — DB 테이블/RLS/Repository 상세
- `../FRONTEND.md` — Flutter 위젯/상태/모델
- `../ADR.md` — 왜 이런 결정을 했는지 (역사)
- `../ARCHITECTURE.md` — 상위 레벨 아키텍처 다이어그램
- `PUSH_SETUP.md` — Firebase 설정 단계별 체크리스트 (같은 폴더)
