# `generate-proposal-scene` Edge Function

제안 작성 폼의 "이미지 생성" 버튼이 호출하는 Supabase Edge Function.
Vertex AI Gemini multimodal API 를 service-account OAuth 로 불러와 1장의
장면 이미지를 생성하고, 그 결과를 `proposal-scenes` 버킷에 업로드한다.

---

## 최초 1회 셋업

### 1) Supabase CLI

```bash
npm install -g supabase   # or brew install supabase/tap/supabase
supabase login            # 로그인 (브라우저로 토큰 발급)
supabase link --project-ref <your-project-ref>
```

`project-ref` 는 Dashboard URL 의 `/project/<ref>` 부분.

### 2) GCP service account

Vertex AI 가 enabled 된 GCP 프로젝트에서:

1. IAM & Admin → Service Accounts → Create service account
2. 권한: **Vertex AI User** (`roles/aiplatform.user`)
3. Keys → Add key → JSON → 다운로드 (이 JSON 파일 전체가 secret 값)

### 3) Supabase secrets 등록

Edge Function 이 런타임에 읽을 secret 3개를 등록.

```bash
# .env.supabase.secrets (로컬 전용 — .gitignore 대상)
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=global
GCP_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...","client_email":"...iam.gserviceaccount.com",...}
```

> `GCP_SERVICE_ACCOUNT_JSON` 은 **JSON 을 한 줄 문자열로**. `private_key` 내부
> 개행은 `\n` 으로 이스케이프. 셸에서는 큰따옴표로 감싸거나 파일 입력 사용.

등록:

```bash
supabase secrets set --env-file .env.supabase.secrets
supabase secrets list   # 확인
```

### 4) 함수 배포

```bash
supabase functions deploy generate-proposal-scene
```

배포 완료 후 Dashboard → Edge Functions 에서 로그를 볼 수 있다.

---

## 로컬 실행 (개발/디버그)

```bash
supabase start                          # 로컬 Supabase 스택 기동
supabase functions serve \
  --env-file .env.supabase.secrets \
  generate-proposal-scene

# 다른 터미널에서 테스트
curl -i -X POST http://127.0.0.1:54321/functions/v1/generate-proposal-scene \
  -H "Authorization: Bearer <YOUR_USER_JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "sceneText": "하늘이 열리고 빛이 내린다",
    "characterCodes": ["abraham","isaac"],
    "draftId": "00000000-0000-0000-0000-000000000001",
    "sceneIndex": 0,
    "eventTitle": "창조",
    "placeName": "메소포타미아"
  }'
```

예상 응답:

```json
{
  "storage_path": "proposal-scenes/<user-id>/<draft-id>/scene_0.png",
  "prompt": "Create one non-photoreal 2D Bible story illustration..."
}
```

---

## 호출 계약 (Request/Response)

### Request

```ts
POST /functions/v1/generate-proposal-scene
Authorization: Bearer <supabase JWT>
Content-Type: application/json

{
  "sceneText": string,          // 필수 — 장면 한 문장
  "characterCodes": string[],   // 선택 — 아바타 참조 인물 코드
  "draftId": string,            // 필수 — 프론트에서 만든 UUID (같은 draft 는 같은 폴더)
  "sceneIndex": number,         // 필수 — 0..9
  "eventTitle": string,         // 선택 — 제목 (prompt 에 포함)
  "placeName": string           // 선택 — 장소 이름 (prompt 에 포함)
}
```

### Response 200

```ts
{
  "storage_path": "proposal-scenes/{uid}/{draft}/scene_{idx}.png",
  "prompt": string   // 실제 Vertex 에 보낸 instruction 텍스트
}
```

### Error codes

| HTTP | 의미 |
|------|------|
| 400  | 입력 JSON 또는 필수 필드 누락 |
| 401  | JWT 없음/유효하지 않음 |
| 500  | `GOOGLE_CLOUD_PROJECT` 또는 `GCP_SERVICE_ACCOUNT_JSON` secret 누락 |
| 502  | Vertex 응답 실패 (쿼터, 필터링 거부 등) |

---

## 주의사항

- **한 번에 한 장만** 생성하도록 프론트가 모달 overlay 로 블록한다.
  서버 단에서는 `user_id + draft_id + scene_index` 로 유일한 path 를 쓰므로
  같은 사용자가 동시에 여러 요청을 보내도 파일이 덮어써질 뿐 데이터 손상은
  없음. 하지만 GCP 쿼터 절약을 위해 동시 호출은 피할 것.
- 생성된 이미지는 `proposal-scenes` 버킷이라 **public read**. 누구든 URL 만
  알면 볼 수 있다는 의미이므로 민감 정보는 prompt 에 담지 말 것.
- `private_key` 는 **절대 클라이언트 코드에 노출 금지**. Edge Function 런타임
  환경변수로만 주입.
- 로컬 디버그 시 `.env.supabase.secrets` 는 `.gitignore` 에 있음을 확인.
