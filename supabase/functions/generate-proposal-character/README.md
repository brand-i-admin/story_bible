# `generate-proposal-character` Edge Function

제안 작성 폼의 "새 캐릭터 만들기" 다이얼로그가 호출. 기존 `characters` 테이블에
없는 새 성경 인물 아바타를 Vertex Imagen 4.0 으로 생성하고, `proposal-characters`
버킷에 업로드한다.

## 특징
- `tools/images/generate_avatars_vertex.py` 와 **같은 common style + negative
  prompt** 를 사용해 메인 캐스트 아바타와 일관된 그림체로 나옴
  (`supabase/functions/_shared/character_style.ts` 에 동일 상수 정의)
- 모델: `imagen-4.0-generate-001` (text-to-image, `:predict` 엔드포인트)
- personGeneration 기본값 `allow_adult` (성경 인물은 전부 성인 표현으로 유도)
- 같은 `characterCode` 로 다시 호출하면 upsert → 재생성

## 배포

`generate-proposal-scene` 과 같은 secrets (`GOOGLE_CLOUD_PROJECT`,
`GCP_SERVICE_ACCOUNT_JSON`) 을 공유한다. 같은 GCP 서비스 계정 JSON 이면
두 함수 모두 동작.

```bash
supabase functions deploy generate-proposal-character
```

## 호출 계약

### Request
```ts
POST /functions/v1/generate-proposal-character
Authorization: Bearer <supabase JWT>
Content-Type: application/json

{
  "prompt": string,          // 필수. 인물 외형·복장·분위기 설명. 한글 가능
  "characterCode": string,   // 필수. 소문자/숫자/_ 만 (예: "caleb_disciple")
  "characterName": string,   // 선택. 한글 이름 (예: "갈렙의 제자")
  "draftId": string          // 필수. 제안 단위 폴더 구분자
}
```

### Response 200
```ts
{
  "storage_path": "proposal-characters/{uid}/{draft}/{code}.png",
  "prompt": "<최종 prompt (common style + user description)>",
  "character_code": "<sanitized code>",
  "character_name": "<echo>"
}
```

### Error codes
| HTTP | 의미 |
|------|------|
| 400  | 입력 누락 또는 code 포맷 이상 |
| 401  | JWT 없음/유효하지 않음 |
| 409  | 동일 code 로 이미 is_active=true 인 정규 캐릭터 존재 |
| 500  | secrets 미설정 |
| 502  | Imagen 응답 실패 |
