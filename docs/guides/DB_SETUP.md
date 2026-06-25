# DB / Supabase 환경 구축 가이드

> Story Bible 의 dev / real Supabase 환경을 새로 만들거나 복구할 때 따라가는
> 운영 순서다. 이 문서는 "무엇을 눌러야 하는가"보다 **왜 그 설정이 필요한가**를
> 함께 설명한다. 일상 개발/배포 순서는 [develop-flow.md](develop-flow.md)를 본다.
> 로컬 `.env*` 파일을 다른 컴퓨터나 팀원과 어떻게 공유할지는
> [LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md)를 본다.

문서 계층: 이 문서는 [INFRA_GUIDE.md](INFRA_GUIDE.md)를 보조하는 구축 하위
문서다. 현재 인프라 구조와 원리는 INFRA_GUIDE에서 먼저 잡고, 여기서는 새 환경을
실제로 세팅하는 순서를 따른다.

## 0. 현재 환경 지도

| 구분 | Supabase ref | 앱 ENV | 로컬 운영 ENV | 용도 |
|------|--------------|--------|---------------|------|
| dev | `cvnutbizsgeycdjcbled` | `dev` | `dev` | 개발/테스트 기본값 |
| real | `zmcffwcfmyhdykdhxhgy` | `real` 또는 `prod` | `prod` | 실제 운영 후보 |

주의할 점:

- Makefile 기본값은 항상 `ENV=dev`다.
- real 에 적용할 때만 `ENV=real`을 명시한다.
- 앱 런타임에서는 `real`과 `prod`를 둘 다 운영 환경 alias 로 허용한다.
- 로컬 운영 스크립트는 `ENV=real` 또는 `ENV=prod`를 `.env.ops`의
  `*_PROD` 값으로 매핑한다.
- Supabase Dashboard 상단의 `main / PRODUCTION` 표시는 Supabase branch 라벨이다.
  우리가 말하는 dev/real 구분은 **프로젝트 ref가 다르다**는 뜻이다.

## 1. 큰 원칙

### 1.1 앱에는 공개값만 들어간다

Flutter 앱이 알아야 하는 값은 다음 두 가지뿐이다.

```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

`anon` key 는 이름 때문에 비밀처럼 보이지만 클라이언트용 공개 키다. 대신 DB 에
RLS(Row Level Security)가 걸려 있어야 한다. 사용자가 이 키를 알더라도 자기 권한
밖의 데이터를 읽거나 쓰지 못하게 만드는 것이 Supabase 의 기본 보안 모델이다.

반대로 아래 값은 절대 앱에 들어가면 안 된다.

```text
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_DB_URL
Firebase / GCP service account JSON
Apple private key .p8
```

`service_role` key 는 RLS 를 우회한다. DB URL 은 비밀번호를 포함한다. service
account JSON 은 서버 권한으로 외부 API 를 호출한다. 이 값들은 로컬 운영 파일이나
Supabase 서버 secret 에만 둔다.

### 1.2 `.env`와 `.env.ops`를 나눈 이유

| 파일 | 포함 값 | 앱 번들 포함 여부 | 목적 |
|------|---------|------------------|------|
| `.env` | Supabase URL, anon key, FCM VAPID key | 포함하지 않음. scripts가 dart-define 으로 주입 | 앱 실행용 공개값 |
| `.env.ops` | service role, DB URL | 절대 포함하지 않음 | 로컬 운영/DB/Storage 도구용 비밀 |

예전처럼 `.env`를 `pubspec.yaml` asset 에 넣으면 앱 바이너리나 웹 번들 안에 파일이
들어갈 수 있다. 지금 구조는 `.env` 파일 자체를 앱 asset 으로 넣지 않고,
`scripts/run_*.sh`가 필요한 공개값만 `--dart-define`으로 넘긴다.

`--dart-define`도 완전한 비밀 저장소는 아니다. 그래서 여기에 넣는 값도 공개 가능한
값만 둔다.

### 1.3 `supabase secrets`와 Vault 는 다르다

둘 다 "Supabase 쪽 secret"이라 헷갈리지만 쓰는 위치가 다르다.

| 저장 위치 | 읽는 주체 | 예시 | 왜 필요한가 |
|-----------|-----------|------|-------------|
| Edge Function secrets | Deno Edge Function | `FIREBASE_SERVICE_ACCOUNT`, `GCP_SERVICE_ACCOUNT_JSON` | `send-push` / 이미지 생성 함수가 외부 API 호출 |
| Supabase Vault | Postgres SQL 함수 | `service_role_key`, `supabase_url` | DB 함수가 `pg_net`으로 Edge Function 호출 |

예를 들어 수요일 매일 탐험 푸시는 이런 경로로 움직인다.

```text
pg_cron
  -> public.dispatch_daily_exploration_push()
  -> public._fire_push_broadcast()
  -> vault.decrypted_secrets 에서 service_role_key / supabase_url 읽기
  -> pg_net.http_post('/functions/v1/send-push')
  -> send-push Edge Function
  -> Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  -> Firebase FCM HTTP v1 API
  -> 디바이스 푸시
```

따라서 푸시는 두 종류의 secret 이 모두 있어야 끝까지 동작한다.

## 2. 로컬 파일 세팅

### 2.1 `.env`

`.env.example`을 복사해 `.env`를 만든다.

```bash
cp .env.example .env
```

필수 값:

```bash
SUPABASE_URL_DEV=https://cvnutbizsgeycdjcbled.supabase.co
SUPABASE_ANON_KEY_DEV=<dev anon key>

SUPABASE_URL_PROD=https://zmcffwcfmyhdykdhxhgy.supabase.co
SUPABASE_ANON_KEY_PROD=<real anon key>

FCM_VAPID_KEY=<Firebase Web Push VAPID public key>
```

`FCM_VAPID_KEY`는 Flutter Web 푸시 토큰 발급에만 필요하다. iOS/Android 앱 실행에는
없어도 된다.

### 2.2 `.env.ops`

`.env.ops.example`을 복사해 `.env.ops`를 만든다.

```bash
cp .env.ops.example .env.ops
```

필수 값:

```bash
SUPABASE_SERVICE_ROLE_KEY_DEV=<dev service_role key>
SUPABASE_SERVICE_ROLE_KEY_PROD=<real service_role key>

SUPABASE_DB_URL_DEV=<dev psql URI>
SUPABASE_DB_URL_PROD=<real psql URI>
```

`SUPABASE_DB_URL_*`은 `make db-init`, `make apply-seeds` 같은 psql 기반 작업에 쓴다.
Supabase 의 direct host 형태는 DNS 환경에 따라 로컬에서 안 잡힐 수 있다.

direct host 가 실패하면 session pooler 5432 URI 를 쓴다.

```text
postgresql://postgres.<ref>:<password>@aws-...pooler.supabase.com:5432/postgres
```

현재 확인된 pooler 방향:

| 환경 | region | session pooler 후보 |
|------|--------|---------------------|
| dev | `ap-northeast-1` | `aws-1-ap-northeast-1.pooler.supabase.com` |
| real | `ap-northeast-2` | `aws-1-ap-northeast-2.pooler.supabase.com` |

Dashboard 의 Database connection string 이 우선이다. 위 host 는 현재 프로젝트에서
접속 확인한 값이며, Supabase 내부 변경이 있으면 Dashboard 값을 다시 확인한다.

대량 seed 적용에는 transaction pooler 6543보다 session pooler 5432가 안전하다.

## 3. 앱 실행 스크립트 원리

관련 파일:

- `scripts/common.sh`
- `scripts/run_dev.sh`
- `scripts/run_real.sh`
- `scripts/build_ios_dev.sh`
- `scripts/build_ios_real.sh`
- `scripts/build_android_dev.sh`
- `scripts/build_android_real.sh`

실행 예:

```bash
scripts/run_dev.sh
scripts/run_real.sh
scripts/run_dev.sh -d chrome
scripts/run_real.sh -d ios
```

스크립트가 하는 일:

1. `.env`에서 선택 환경의 `SUPABASE_URL_*`, `SUPABASE_ANON_KEY_*`를 읽는다.
2. URL 의 프로젝트 ref 와 anon key JWT 안의 `ref`가 기대값과 맞는지 검사한다.
3. `flutter clean`을 실행한다.
4. `flutter pub get`을 실행한다.
5. Flutter 를 다음 값으로 실행한다.

```bash
--dart-define=ENV=dev
--dart-define=SUPABASE_URL=<dev url>
--dart-define=SUPABASE_ANON_KEY=<dev anon>
```

real 실행 시에는 `ENV=real`, real URL, real anon key 를 넣는다.

앱 코드의 진입점은 `lib/main.dart`다. 여기서는 `.env` 파일을 직접 읽지 않는다.
`String.fromEnvironment()`로 `ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`만 읽는다.

## 4. Supabase 프로젝트 생성 후 Dashboard 설정

### 4.1 API Keys

Supabase Dashboard 에서 확인한다.

```text
Project Settings -> API
```

필요한 값:

- Project URL
- anon key
- service_role key

사용 위치:

| 값 | 저장 위치 |
|----|-----------|
| Project URL | `.env`의 `SUPABASE_URL_DEV/PROD`, Vault `supabase_url` |
| anon key | `.env`의 `SUPABASE_ANON_KEY_DEV/PROD` |
| service_role key | `.env.ops`의 `SUPABASE_SERVICE_ROLE_KEY_DEV/PROD`, Vault `service_role_key` |

service role 은 앱에 넣지 않는다.

### 4.2 Auth URL Configuration

위치:

```text
Authentication -> URL Configuration
```

현재 필요한 Redirect URLs:

```text
com.storybible.app://login-callback
http://localhost:*/**
```

의미:

- `com.storybible.app://login-callback`: iOS/Android 앱으로 OAuth 결과를 되돌려보내는
  deep link.
- `http://localhost:*/**`: Flutter Web 개발 서버 포트가 바뀌어도 로그인 callback 을
  허용하기 위한 개발용 wildcard.

`Site URL`은 redirect URL 이 명시되지 않았거나 이메일 템플릿에서 기본 URL 이 필요할
때 쓰는 fallback 에 가깝다. dev 와 real 의 localhost 포트가 달라도 Redirect URLs 에
`http://localhost:*/**`가 있으면 개발 로그인은 정상 동작한다.

배포 전 real 에서는 `Site URL`을 실제 웹 도메인으로 바꾼다.

```text
https://<real-domain>
```

그리고 Redirect URLs 에도 실제 웹 도메인을 추가한다.

### 4.3 Google / Kakao provider

위치:

```text
Authentication -> Sign In / Providers
```

Supabase 쪽에서 Google, Kakao provider 를 켠다.

각 provider 콘솔에는 Supabase callback URL 을 등록한다.

```text
https://<project-ref>.supabase.co/auth/v1/callback
```

dev 와 real 은 프로젝트 ref 가 다르므로 callback URL 도 각각 다르다.

```text
dev  : https://cvnutbizsgeycdjcbled.supabase.co/auth/v1/callback
real : https://zmcffwcfmyhdykdhxhgy.supabase.co/auth/v1/callback
```

원리:

1. 앱이 Supabase OAuth 시작 URL 을 연다.
2. 사용자가 Google/Kakao 에서 로그인한다.
3. Google/Kakao 가 Supabase callback 으로 인증 결과를 보낸다.
4. Supabase 가 자기 JWT 세션으로 변환한다.
5. Supabase 가 앱의 `redirectTo`로 되돌려보낸다.

provider callback 과 앱 redirect 는 서로 다르다.

| 종류 | 예시 | 역할 |
|------|------|------|
| provider callback | `https://<ref>.supabase.co/auth/v1/callback` | Google/Kakao/Apple 이 Supabase 로 돌아오는 주소 |
| app redirect | `com.storybible.app://login-callback` 또는 localhost | Supabase 가 앱으로 돌아가는 주소 |

### 4.4 Apple provider

현재 앱은 **Apple native-only** 방식이다.

관련 코드:

- `lib/data/auth_repository.dart`
- `lib/widgets/inline_login_prompt_card.dart`

현재 정책:

- iOS/macOS 앱에서만 Apple 버튼을 보여준다.
- Android/Web 에서는 Apple 버튼을 열지 않는다.
- Android/Web Apple OAuth 를 위해 Services ID, web callback, 6개월 client secret
  rotation 을 운영하지 않는다.

원리:

1. iOS/macOS 가 Apple 네이티브 로그인 sheet 를 연다.
2. 앱이 Apple `identityToken`을 받는다.
3. 앱이 Supabase `signInWithIdToken(provider: apple)`로 토큰을 넘긴다.
4. Supabase 가 Apple 토큰을 검증하고 Supabase 세션을 만든다.

나중에 Android/Web 에서도 Apple 로그인을 열고 싶다면 별도 작업이 필요하다.

- Apple Developer 에서 Services ID 생성
- Return URL / domain 검증
- `.p8`, Team ID, Key ID 로 Apple client secret 생성
- Supabase Apple provider 에 client secret 등록
- client secret 만료 전에 재생성
- Flutter 코드에 web authentication option 추가
- Android/Web Apple 버튼 노출

지금은 native-only 가 더 단순하고 운영 부담이 작다.

## 5. Edge Function secret 설정

Edge Function 은 Supabase 서버에서 실행되는 Deno 함수다. 앱이 직접 들고 있으면 안 되는
Firebase/GCP 키를 여기서 읽는다.

확인:

```bash
supabase secrets list --project-ref cvnutbizsgeycdjcbled
supabase secrets list --project-ref zmcffwcfmyhdykdhxhgy
```

필요한 secret:

| secret | 쓰는 함수 | 용도 |
|--------|-----------|------|
| `FIREBASE_SERVICE_ACCOUNT` | `send-push` | FCM HTTP v1 호출 |
| `GCP_SERVICE_ACCOUNT_JSON` | `generate-proposal-scene`, `generate-proposal-character` | Vertex AI 호출 |
| `GOOGLE_CLOUD_PROJECT` | 이미지 생성 함수 | GCP project id |
| `GOOGLE_CLOUD_LOCATION` | 이미지 생성 함수 | Vertex AI location |

등록 예:

```bash
supabase secrets set --project-ref <ref> \
  FIREBASE_SERVICE_ACCOUNT="$(cat firebase-admin-sdk.json)"
```

여러 값을 한 번에 넣을 때는 로컬 ignored 파일을 쓴다.

```bash
supabase secrets set --project-ref <ref> --env-file .env.supabase.secrets
```

`.env.supabase.secrets`는 git 에 커밋하지 않는다.

## 6. Edge Function 배포

항상 `--project-ref`를 명시한다. Supabase CLI 가 어떤 프로젝트에 link 되어 있는지에
의존하면 실수로 dev/real 을 바꿔 배포할 수 있다.

```bash
supabase functions deploy send-push \
  --project-ref cvnutbizsgeycdjcbled

supabase functions deploy send-push \
  --project-ref zmcffwcfmyhdykdhxhgy
```

이미지 생성 함수도 같은 방식이다.

```bash
supabase functions deploy generate-proposal-scene --project-ref <ref>
supabase functions deploy generate-proposal-character --project-ref <ref>
```

배포 상태 확인:

```bash
supabase functions list --project-ref cvnutbizsgeycdjcbled
supabase functions list --project-ref zmcffwcfmyhdykdhxhgy
```

`send-push`, `generate-proposal-scene`, `generate-proposal-character`, `delete-account`가 `ACTIVE`이면 된다.

## 7. DB 내부 secret / extension 설정

### 7.1 extension

Supabase Dashboard:

```text
Database -> Extensions
```

필요:

- `pg_net`: Postgres 에서 HTTP 요청을 보내기 위해 필요.
- `pg_cron`: 매일/매주 자동 작업을 DB 안에서 예약하기 위해 필요.
- `supabase_vault`: DB 함수가 secret 을 읽기 위해 필요.

### 7.2 Vault secrets

Supabase Dashboard:

```text
Integrations -> Vault -> Secrets
```

프로젝트마다 아래 두 secret 을 넣는다.

| name | value |
|------|-------|
| `service_role_key` | 해당 프로젝트 service_role key |
| `supabase_url` | 해당 프로젝트 URL |

왜 필요한가:

- `dispatch_daily_exploration_push()`는 Postgres 함수다.
- Postgres 함수 안에서는 Edge Function 환경변수를 직접 읽을 수 없다.
- 그래서 DB 쪽에서는 Vault 에 있는 `service_role_key`, `supabase_url`로
  `/functions/v1/send-push`를 HTTP 호출한다.

검증 SQL:

```sql
select name, length(decrypted_secret) as len
from vault.decrypted_secrets
where name in ('service_role_key', 'supabase_url');
```

2줄이 나오면 된다. 값 자체는 출력하지 않는다.

## 8. DB 초기화, patch, seed 적용

### 8.1 신규 프로젝트 최초 bootstrap

처음 환경을 만들거나 복구 상황에서 DB 를 정말 갈아엎을 때만 쓴다.
real 운영 DB 에서는 일반 배포 명령으로 사용하지 않는다.

```bash
make seed-all
CONFIRM_REAL_DB_INIT=1 make db-init ENV=real
make apply-seeds ENV=real
make upload-character-avatars ENV=real
```

dev 는 `ENV` 생략 가능하다.

```bash
make seed-all
make db-init
make apply-seeds
make upload-character-avatars
```

한 줄로 묶을 수도 있다.

```bash
make seed-all && CONFIRM_REAL_DB_INIT=1 make db-init ENV=real && make apply-seeds ENV=real && make upload-character-avatars ENV=real
```

### 8.2 운영 real DB 수정

real 을 배포한 뒤에는 `db-init ENV=real`로 초기화하지 않는다. 스키마/RLS/RPC/cron
같은 DB 구조 변경은 `supabase/patches/*.sql`에 여러 번 실행해도 안전한 patch 로
작성한 뒤 적용한다.

```bash
make apply-patch ENV=dev PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
```

원칙:

- `db_init.sql`에는 최종 desired schema 를 계속 반영한다.
- dev 에서는 `make db-init ENV=dev`로 reset 검증한다.
- real 에는 patch SQL 만 적용한다.
- real patch 전에는 백업과 dev 검증을 먼저 한다.

### 8.3 각 단계가 하는 일

| 단계 | 하는 일 | 원리 |
|------|---------|------|
| `make seed-all` | 로컬 JSON/assets 에서 SQL 파일 재생성 | DB 에 넣을 기준 콘텐츠를 코드와 같이 관리 |
| `make db-init ENV=...` | `db_init.sql` 실행 | schema, RLS, RPC, Storage bucket, trigger, cron 을 한 번에 생성 |
| `make apply-patch ENV=... PATCH=...` | idempotent patch SQL 적용 | 운영 DB 를 보존하면서 schema/RLS/RPC/cron 을 수정 |
| `make apply-seeds ENV=...` | 성경/랜드마크/인물/사건/퀴즈 seed 적용 | 공개 기준 데이터 삽입 |
| `make upload-character-avatars ENV=...` | 로컬 아바타 PNG 를 Supabase Storage 로 업로드 | 앱/Edge Function 이 인물 이미지를 공개 URL 로 읽게 함 |

`db-init`은 파괴적이다. 기존 DB 를 DROP/CREATE 한다. real 에서는 기본 차단되며,
정말 신규/복구 bootstrap 이면 `CONFIRM_REAL_DB_INIT=1`을 붙인다.

### 8.4 첫 실행에서 bucket not found 로그가 나오는 이유

처음 `CONFIRM_REAL_DB_INIT=1 make db-init ENV=real`을 실행하면 이런 로그가 나올 수 있다.

```text
Bucket not found
```

`db-init`은 SQL 실행 전에 기존 Storage bucket 을 비우려 한다. 아직 bucket 이 없는
새 프로젝트라면 비울 대상이 없으므로 정상이다. 이후 `db_init.sql`이 bucket 을
만든다. 단, service_role 키가 없거나 기존 bucket 비우기에 실패하면 기존 파일이
남지 않도록 `db-init`은 SQL 실행 전에 중단한다.

### 8.5 Makefile 환경 매핑

Makefile 은 이렇게 매핑한다.

| 입력 | 내부 ops env | DB URL |
|------|--------------|--------|
| 생략 또는 `ENV=dev` | `dev` | `SUPABASE_DB_URL_DEV` |
| `ENV=real` | `prod` | `SUPABASE_DB_URL_PROD` |
| `ENV=prod` | `prod` | `SUPABASE_DB_URL_PROD` |

기본값이 dev 인 이유는 실수로 real 을 밀지 않기 위해서다.

dry-run 으로 실제 어떤 명령이 나갈지 먼저 볼 수 있다.

```bash
make -n db-init
make -n apply-patch ENV=real PATCH=supabase/patches/example.sql
```

## 9. Firebase / Push 정책

### 9.1 현재 결정: dev 와 real 이 같은 Firebase 를 쓴다

현재 푸시 종류가 많지 않고, 운영 복잡도를 줄이기 위해 dev 와 real 이 같은 Firebase
프로젝트를 써도 된다.

장점:

- APNs / VAPID / Firebase service account 를 하나만 관리한다.
- iOS/Android/Web Firebase 설정 파일을 환경별로 갈라 관리하지 않아도 된다.
- `send-push` Edge Function secret 도 같은 Firebase service account 를 양쪽 Supabase
  프로젝트에 넣으면 된다.

주의점:

- 같은 앱 bundle id / package name 이면 dev 와 real 에 등록되는 FCM token 이 같은
  물리 앱으로 갈 수 있다.
- dev DB 에도 내 기기 token 이 등록되어 있으면 dev push 도 내 휴대폰에 온다.
- 푸시 문구만 보면 dev/real 구분이 안 될 수 있다.

운영 전까지는 괜찮다. 실제 사용자에게 배포한 뒤 dev 푸시가 섞이는 것이 걱정되면
다음 중 하나를 선택한다.

1. dev cron 을 끄고 수동 테스트 때만 푸시를 보낸다.
2. dev push 제목/body 에 `[DEV]` prefix 를 붙이는 별도 로직을 둔다.
3. dev/real 앱 bundle id 와 Firebase 프로젝트를 분리한다.

지금은 1번 또는 현재 유지가 가장 단순하다.

### 9.2 푸시가 도는 전체 경로

```text
Flutter 앱
  -> FirebaseMessaging.getToken()
  -> Supabase RPC register_push_token()
  -> public.user_push_tokens 저장

pg_cron 또는 trigger
  -> public.dispatch_daily_exploration_push()
  -> public._fire_push_broadcast()
  -> pg_net.http_post('/functions/v1/send-push')
  -> Edge Function send-push
  -> Firebase FCM
  -> iOS/Android/Web 디바이스
```

### 9.3 푸시 즉시 테스트

오전 9시 cron 을 기다리지 않고 바로 테스트하려면 SQL Editor 에서 실행한다.

```sql
select public.dispatch_daily_exploration_push();
```

이 함수는 KST 날짜 시드로 오늘의 사건 제목을 고르고 전체 push token 대상에게
"오늘의 탐험이 열렸어요" 알림을 보낸다.

테스트 전 확인:

```sql
select platform, count(*)
from public.user_push_tokens
group by platform
order by platform;
```

토큰이 0개이면 보낼 대상이 없다. 앱을 실기기에서 한 번 실행하고 로그인/푸시 권한 허용
후 token 등록이 되는지 먼저 확인한다.

DB 에서 Edge Function 을 호출한 응답은 `net._http_response`에서 볼 수 있다.

```sql
select id, status_code, timed_out, error_msg, left(content, 500) as content
from net._http_response
order by id desc
limit 10;
```

정상 응답 예:

```json
{"sent":1,"failed":0,"cleaned_tokens":0}
```

## 10. Auth 동작 확인

각 환경에서 최소 한 번씩 확인한다.

```bash
scripts/run_dev.sh
scripts/run_real.sh
```

확인 항목:

- Google 로그인 성공
- Kakao 로그인 성공
- Apple 로그인 성공
- 앱 재실행 후 세션 복원
- 로그아웃 후 다시 로그인

Apple 은 iOS/macOS 앱에서만 노출된다. Web/Android 에서 Apple 버튼이 안 보이는 것은
현재 정책상 정상이다.

## 11. 신규 환경 구축 순서 체크리스트

새 Supabase 환경을 하나 더 만들 때 순서대로 진행한다.

### 11.1 Supabase 프로젝트 생성

1. Supabase Dashboard 에서 새 프로젝트 생성.
2. Project URL, anon key, service_role key 확보.
3. Database connection string 확보.
4. direct host 가 로컬에서 안 잡히면 session pooler 5432 URI 확보.

### 11.2 로컬 env 반영

1. `.env`에 `SUPABASE_URL_<ENV>`, `SUPABASE_ANON_KEY_<ENV>` 추가.
2. `.env.ops`에 `SUPABASE_SERVICE_ROLE_KEY_<ENV>`, `SUPABASE_DB_URL_<ENV>` 추가.
3. `scripts/common.sh`에 프로젝트 ref 와 ENV suffix 매핑 추가.
4. 필요한 `scripts/run_*.sh`, `scripts/build_*_*.sh` 추가.
5. 운영 DB 변경은 `make -n apply-patch ENV=<env> PATCH=<file>`로 잘못된 DB URL 을 잡지 않는지 확인.

### 11.3 Auth 설정

1. Supabase URL Configuration 에 앱 deep link 추가.
2. 개발용 `http://localhost:*/**` 추가.
3. 배포 도메인이 있으면 Site URL 과 Redirect URLs 에 추가.
4. Google/Kakao provider 를 켠다.
5. 각 provider console 에 `https://<ref>.supabase.co/auth/v1/callback` 등록.
6. Apple 은 native-only 정책이면 iOS/macOS 네이티브 로그인 기준으로만 설정한다.

### 11.4 Edge Function secret 등록

1. Firebase service account JSON 준비.
2. GCP/Vertex service account JSON 준비.
3. `supabase secrets set --project-ref <ref> ...`로 등록.
4. `supabase secrets list --project-ref <ref>`로 이름 확인.

### 11.5 Edge Function 배포

```bash
supabase functions deploy send-push --project-ref <ref>
supabase functions deploy generate-proposal-scene --project-ref <ref>
supabase functions deploy generate-proposal-character --project-ref <ref>
```

확인:

```bash
supabase functions list --project-ref <ref>
```

### 11.6 DB extension / Vault 설정

1. `pg_net`, `pg_cron`, `supabase_vault` 활성화.
2. Vault 에 `service_role_key`, `supabase_url` 등록.
3. SQL 로 secret 길이 확인.

### 11.7 DB / Storage 부트스트랩

```bash
make seed-all
make db-init ENV=<env>
make apply-seeds ENV=<env>
make upload-character-avatars ENV=<env>
```

### 11.8 앱 검증

```bash
scripts/run_<env>.sh
```

확인:

- 홈 데이터 로드
- 지도/인물/퀴즈 화면 진입
- Google/Kakao/Apple 로그인
- 프로필 생성/복원
- 푸시 토큰 row 생성

### 11.9 푸시 검증

1. `user_push_tokens`에 token row 가 있는지 확인.
2. `select public.dispatch_daily_exploration_push();` 실행.
3. 실기기에 알림이 오는지 확인.
4. `net._http_response` 또는 Function logs 에서 `sent`, `failed` 확인.

## 12. "세팅 끝" 판단 기준

아래가 모두 true 이면 환경 구축은 끝난 것으로 본다.

- `scripts/run_dev.sh`가 dev Supabase 로 실행된다.
- `scripts/run_real.sh`가 real Supabase 로 실행된다.
- dev/real 모두 Google/Kakao/Apple 로그인이 된다.
- `make -n db-init` 기본값이 dev 를 가리킨다.
- `make -n apply-patch ENV=real PATCH=<file>`이 real/prod DB URL 을 가리킨다.
- real DB 에 필요한 patch 와 seed 가 적용되어 홈 데이터가 로드된다.
- Storage `characters` bucket 에 아바타가 업로드되어 있다.
- Supabase Functions 에 `send-push`가 ACTIVE 다.
- Edge Function secret 에 `FIREBASE_SERVICE_ACCOUNT`가 있다.
- Vault 에 `service_role_key`, `supabase_url`이 있다.
- `pg_net`, `pg_cron`, `supabase_vault`가 켜져 있다.
- `cron.job`에 월/수/금 정기 push job 3개가 있다.
- `user_push_tokens`에 실기기 token 이 들어간다.
- `dispatch_daily_exploration_push()`를 수동 실행하면 실기기에 알림이 온다.

## 13. 자주 헷갈리는 것

### dev 와 real 의 Site URL 포트가 달라도 되나?

개발 중에는 괜찮다. 실제 허용 여부는 Redirect URLs 가 결정한다.
`http://localhost:*/**`가 있으면 `localhost:3000`, `localhost:5050` 모두 허용된다.

배포 전 real 의 Site URL 은 실제 운영 도메인으로 바꾼다.

### Supabase CLI 가 어느 프로젝트에 연결되어 있는지 어떻게 보나?

```bash
supabase projects list
```

배포/secret 설정은 가능하면 항상 `--project-ref`를 붙인다.

```bash
supabase secrets list --project-ref zmcffwcfmyhdykdhxhgy
supabase functions list --project-ref zmcffwcfmyhdykdhxhgy
```

### real 을 기본값으로 바꿔도 되나?

바꾸지 않는다. Makefile 기본값은 dev 로 유지한다. real DB 초기화는 파괴적이므로
기본 차단되어 있고, 운영 변경은 `apply-patch ENV=real PATCH=...`로 적용한다.

### `SUPABASE_SERVICE_ROLE_KEY_*`를 `.env`에 넣으면 안 되나?

넣지 않는다. `.env`는 앱 실행 스크립트가 읽는 파일이고, 과거처럼 asset 에 섞일 위험을
만들 수 있다. service role 과 DB URL 은 `.env.ops`에만 둔다.

### 같은 Firebase 를 써도 되나?

지금 규모와 푸시 종류에서는 가능하다. 다만 dev 푸시가 같은 물리 기기로 올 수 있다는
점을 알고 있어야 한다. 운영 사용자가 늘어나면 dev cron 비활성화 또는 Firebase 분리를
다시 검토한다.

### DB host DNS 가 안 잡히면 Supabase 가 망가진 건가?

아니다. 앱은 `https://<ref>.supabase.co` API 를 쓰기 때문에 정상일 수 있다. psql 만
direct DB host DNS 문제를 만날 수 있다. 이때 session pooler URI 를 사용한다.
