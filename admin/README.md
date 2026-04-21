# Story Bible Admin (Flutter Web)

관리자가 새 이야기/인물을 직접 등록하는 어드민 웹.
모바일 앱과 의존성·빌드 완전 격리 (`admin/pubspec.yaml`).

외부 기여자 제출 기능은 폐기됨. 등록 요청은 앱 외부(구글폼/노션 등)로 수집하고,
관리자가 본 어드민 웹에서 직접 등록한다.

## 기술 스택

- Flutter Web (Material 3)
- Riverpod 2.6
- supabase_flutter (인증 + RPC + 테이블 쿼리)
- flutter_map (좌표 픽커)
- flutter_dotenv (`.env` 로 Supabase URL/Key 로드)

## 디렉토리 구조

```
admin/
├── pubspec.yaml
├── .env -> ../.env             # repo 루트의 .env 심볼릭 링크
├── lib/
│   ├── main.dart               # 진입점, Supabase.initialize
│   ├── app.dart                # auth 상태 → 로그인 vs 홈
│   ├── models/                 # Era
│   ├── data/admin_repository.dart
│   ├── state/admin_providers.dart
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── home_screen.dart
│   │   └── submit_event_screen.dart    # 등록 폼 (지도 picker 포함)
│   └── widgets/
└── test/
```

## 실행

```bash
cd admin
flutter pub get

flutter run -d chrome             # ENV=dev (기본) - .env의 SUPABASE_URL_DEV 사용
flutter build web --dart-define=ENV=prod
```

## 인증 + 권한

- **관리자 전용**. 비관리자가 로그인하면 등록 폼이 노출되지 않음.
- 관리자 부여: Supabase 대시보드에서 수동.
  ```
  Authentication → Users → 해당 사용자 → Edit
  → app_metadata 에 { "role": "admin" } 추가
  ```
  - 다음 로그인 시 JWT 의 `app_metadata.role == 'admin'` 으로 가게 됨
  - DB 의 `is_admin()` 함수가 이걸 보고 RLS + RPC 안에서 체크

## 핵심 흐름

### 등록 (관리자만 가능)

1. **시대 선택** → 같은 era 의 published 이야기 목록 자동 로드
2. **"이 이야기 다음에 배치"** 드롭다운 → `afterStoryIndex` 결정
3. **제목/요약/등장인물/성경본문/연도/장소** 입력
4. **지도 클릭**으로 lat/lng 자동 채움
5. **4개 장면** 시각 묘사 입력
6. **제출** → DB RPC `insert_event_at_position` 호출:
   - `is_admin()` 권한 체크 (관리자 아니면 에러)
   - era 단위 advisory lock 으로 동시성 보호
   - 뒤 인덱스를 `+1` 시프트 (UNIQUE `(era_id, story_index)` 제약 회피)
   - `events` row INSERT (status='published' 강제)
   - 누락된 인물 코드는 `is_active=false` placeholder 로 자동 생성

### 배포 후

- DB 는 즉시 반영 (사용자 폰의 다음 fetch 부터 새 이야기 노출)
- **이미지(아바타/장면 PNG) 는 앱 번들에 포함되어야 보임**
  → 운영자가 로컬에서 `make seed-persons seed-stories generate-avatars generate-story-images thumbnails update-pubspec-assets` 후 앱 재빌드/재배포
- 자세한 가이드: [docs/CONTENT_UPDATE.md](../docs/CONTENT_UPDATE.md)

## 테스트 (수동)

1. **dev Supabase 프로젝트** 에 [db_init.sql](../db_init.sql) 적용 (어드민 RPC + RLS 포함)
2. Supabase 대시보드에서 본인 계정에 `app_metadata.role = 'admin'` 부여
3. `cd admin && flutter run -d chrome`
4. 로그인 → 등록 폼 채우기 → 제출 → 모바일 앱에서 확인

## 향후 개선

- 이미지 미리보기 + 직접 업로드 (Supabase Storage 전환 시)
- 이야기 수정 / 삭제 화면
- Vertex 호출을 어드민에서 직접 트리거하는 Edge Function 연동
