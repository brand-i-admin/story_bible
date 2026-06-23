# 로컬 환경 파일 공유 가이드

> 다른 개발자나 내 다른 컴퓨터에서 앱 실행, DB seed, Storage 운영, Edge Function
> 배포를 재현할 때 어떤 파일을 git으로 공유하고 어떤 값은 별도 보안 채널로 전달해야
> 하는지 정리한다.

## 0. 결론

| 파일 | git 상태 | 공유 방식 | 필요한 작업 |
|------|----------|-----------|-------------|
| `.env.example` | 커밋됨 | 저장소로 공유 | 앱 실행용 공개 변수 이름과 예시를 유지 |
| `.env` | ignore | 비밀번호 관리자/안전 채널 | `scripts/run_*`, `scripts/build_*`, Vertex 로컬 도구 |
| `.env.ops.example` | 커밋됨 | 저장소로 공유 | DB/Storage 운영 변수 이름과 예시를 유지 |
| `.env.ops` | ignore | 비밀번호 관리자/안전 채널 | `make apply-*`, `make upload-*`, sync/cleanup 도구 |
| `.env.supabase.secrets.example` | 커밋됨 | 저장소로 공유 | Edge Function secret 변수 이름과 예시를 유지 |
| `.env.supabase.secrets` | ignore | 비밀번호 관리자/안전 채널 | `supabase secrets set --env-file ...` |
| `lib/firebase_options.dart` | 커밋됨 | 저장소로 공유 | Firebase client config |
| `android/app/google-services.json` | 커밋됨 | 저장소로 공유 | Android Firebase client config |
| `ios/Runner/GoogleService-Info.plist` | 커밋됨 | 저장소로 공유 | iOS Firebase client config |
| `firebase-admin-sdk*.json` 등 service account JSON | ignore | 비밀번호 관리자/플랫폼 secret | 로컬에서 `.env.supabase.secrets`에 한 줄 값으로 옮긴 뒤 원본은 보관/삭제 |

핵심 규칙은 간단하다. `*.example`과 Firebase client config는 저장소로 공유하고,
실제 secret 값이 들어간 `.env`, `.env.ops`, `.env.supabase.secrets`, service account
JSON 원본은 git에 올리지 않는다.

## 1. 앱 실행/빌드에 필요한 `.env`

`scripts/common.sh`는 루트의 `.env`만 읽고 Flutter에 `--dart-define`을 주입한다.
앱 번들에 `.env` 파일 자체는 들어가지 않는다.

```bash
cp .env.example .env
```

필수/선택 변수:

| 변수 | 필요 시점 | 설명 |
|------|-----------|------|
| `SUPABASE_URL_DEV` | `scripts/run_dev.sh`, dev build | dev Supabase URL |
| `SUPABASE_ANON_KEY_DEV` | `scripts/run_dev.sh`, dev build | dev anon key |
| `SUPABASE_URL_PROD` | `scripts/run_real.sh`, real build | real Supabase URL |
| `SUPABASE_ANON_KEY_PROD` | `scripts/run_real.sh`, real build | real anon key |
| `GOOGLE_CLOUD_PROJECT` | 로컬 Vertex 이미지 생성 | `make generate-avatars`, `make generate-story-images` 계열 |
| `FCM_VAPID_KEY` | Flutter Web 푸시 | 비어 있으면 웹 푸시만 비활성화 |

`SUPABASE_URL_*`와 `SUPABASE_ANON_KEY_*`는 클라이언트 공개값이지만, 이 저장소에서는
실제 환경 식별값을 불필요하게 노출하지 않기 위해 `.env` 실파일은 ignore한다.

## 2. DB/Storage 운영에 필요한 `.env.ops`

`Makefile`과 `tools/supabase/*.py`는 `.env`와 `.env.ops`를 함께 읽는다. real DB와
Storage를 건드리는 명령은 기본적으로 `ENV=real`을 명시해야 한다.

```bash
cp .env.ops.example .env.ops
```

필수 변수:

| 변수 | 필요 시점 | 설명 |
|------|-----------|------|
| `SUPABASE_SERVICE_ROLE_KEY_DEV` | dev Storage 업로드/정리 | RLS 우회 service role key |
| `SUPABASE_SERVICE_ROLE_KEY_PROD` | real Storage 업로드/정리 | 운영 service role key |
| `SUPABASE_DB_URL_DEV` | dev `psql` 적용 | `make db-init`, `make apply-seeds`, `make apply-patch` |
| `SUPABASE_DB_URL_PROD` | real `psql` 적용 | 운영 patch/seed 적용 |

`.env.ops`는 공유되어야 하는 “형식”은 맞지만, 실파일은 공유 저장소에 올리면 안 된다.
팀원이나 다른 컴퓨터에는 1Password, iCloud Keychain 보안 메모, Bitwarden, 회사 secret
manager 같은 안전 채널로 전달한다.

## 3. Edge Function secret에 필요한 `.env.supabase.secrets`

Supabase Edge Function은 `.env.ops`를 읽지 않는다. 배포된 함수가 쓰는 값은
Supabase Dashboard/CLI의 function secrets에 저장된다.

```bash
cp .env.supabase.secrets.example .env.supabase.secrets
supabase secrets set --env-file .env.supabase.secrets
```

변수:

| 변수 | 쓰는 함수 | 설명 |
|------|-----------|------|
| `GOOGLE_CLOUD_PROJECT` | `generate-proposal-scene`, `generate-proposal-character` | Vertex AI 프로젝트 |
| `GOOGLE_CLOUD_LOCATION` | `generate-proposal-scene`, `generate-proposal-character` | Vertex region, 기본 `global` |
| `GCP_SERVICE_ACCOUNT_JSON` | `generate-proposal-scene`, `generate-proposal-character` | 서비스 계정 JSON 전체를 한 줄 문자열로 저장 |
| `FIREBASE_SERVICE_ACCOUNT` | `send-push` | Firebase Admin SDK 서비스 계정 JSON 전체 |

서비스 계정 JSON 파일 원본은 로컬 임시 파일로만 다룬다. 저장소 루트에
`firebase-admin-sdk*.json`, `gcp-service-account*.json`, `google-service-account*.json`
같은 이름으로 저장하면 `.gitignore`가 막는다.

## 4. Firebase client config는 왜 커밋하는가

다음 파일은 Firebase 프로젝트 식별용 client config라 저장소에 포함한다.

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `web/firebase-messaging-sw.js`

이 값은 secret이 아니다. 보안은 Firebase Console의 승인 도메인, bundle id/package
제한, Supabase RLS, service account secret 분리로 지킨다.

## 5. 새 컴퓨터 세팅 체크리스트

1. 저장소를 clone한다.
2. `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`.
3. `flutter pub get`.
4. 앱 실행만 필요하면 `cp .env.example .env` 후 dev/real 공개값을 채운다.
5. DB/Storage 운영까지 필요하면 `cp .env.ops.example .env.ops` 후 service role/DB URL을 채운다.
6. Edge Function secret 갱신이 필요하면 `cp .env.supabase.secrets.example .env.supabase.secrets` 후 `supabase secrets set --env-file .env.supabase.secrets`.
7. `scripts/run_dev.sh`로 dev 실행을 검증한다.
8. 운영 명령은 dry-run이 있으면 먼저 dry-run으로 확인하고, real에는 `ENV=real`을 명시한다.

## 6. 커밋 전 확인

```bash
git status --short
git check-ignore -v .env .env.ops .env.supabase.secrets
python3 tools/lint/check_forbidden_patterns.py
```

`git status`에 `.env`, `.env.ops`, `.env.supabase.secrets`, service account JSON이 보이면
멈추고 `.gitignore` 또는 파일 위치를 먼저 확인한다.
