# delete-account

로그인한 사용자가 앱 안에서 본인 계정을 삭제할 때 호출하는 Edge Function이다.

## 호출

```dart
await supabase.functions.invoke(
  'delete-account',
  body: {'confirmationId': '<앱에 표시된 계정 확인 아이디>'},
);
```

## 동작

1. Flutter 세션 JWT를 `auth.getUser()`로 검증한다.
2. `confirmationId`가 사용자 이메일, `user_profiles.share_id`, 또는 Auth UUID 중 하나와 일치하는지 확인한다.
3. 사용자 소유 Storage 경로를 삭제한다.
   - `profile-images/<userId>/...`
   - `proposal-scenes/<userId>/...`
   - `proposal-characters/<userId>/...`
   - `proposal-general-images/<userId>/...`
4. 단, 승인된 공개 콘텐츠가 아직 참조 중인 제안 이미지/캐릭터 파일은 보존한다.
   - `events.scene_image_paths`
   - `characters.avatar_storage_path`
5. `supabase.auth.admin.deleteUser(user.id)`를 service-role 권한으로 호출한다.
6. DB의 사용자별 row는 `auth.users(id) on delete cascade` FK로 함께 삭제된다.

## 배포

```bash
supabase functions deploy delete-account
```

필요 secret:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

둘 다 Supabase Edge Runtime에서 자동 주입된다.
