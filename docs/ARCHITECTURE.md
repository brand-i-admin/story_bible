# ARCHITECTURE — 이야기 성경 기술 아키텍처

> 최종 수정: 2026-04-22 (Notifications + FCM 반영)

## 1. 시스템 구성도

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Flutter App                                  │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────┐  ┌────────────┐  │
│  │ screens/ │←─│  state/   │←─│     data/        │  │ services/  │  │
│  │ widgets/ │  │ Riverpod  │  │  repositories    │  │ PushService│  │
│  └──────────┘  └───────────┘  └────────┬─────────┘  └─────┬──────┘  │
└────────────────────────────────────────┼──────────────────┼────────┘
                                         │ supabase SDK     │ firebase_messaging
                                         ▼                  ▼
                      ┌────────────────────────┐   ┌────────────────┐
                      │        Supabase        │   │    Firebase    │
                      │  ┌──────────────────┐  │   │  Cloud Msg     │
                      │  │  PostgreSQL       │  │   │  (FCM)         │
                      │  │  + pgvector       │  │   └────┬───────────┘
                      │  │  + RLS/트리거     │  │        │
                      │  │  + pg_cron        │  │        ├── APNs (iOS)
                      │  └──────────────────┘  │        ├── Play Services
                      │  ┌───────┐ ┌────────┐  │        └── Web Push
                      │  │ Auth  │ │Storage │  │
                      │  └───────┘ └────────┘  │
                      │  ┌──────────────────┐  │
                      │  │  Edge Functions  │  │──► Vertex AI (GCP)
                      │  │  - generate-     │  │    - Gemini Image
                      │  │    proposal-*    │  │    - Imagen
                      │  │  - send-push     │  │
                      │  └──────────────────┘  │
                      └────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                에셋 파이프라인 (로컬 머신)                         │
│  tools/*.py → Vertex AI → assets/  (아바타, 장면, 썸네일)         │
│  tools/*.py → SQL 생성 → psql/Supabase SQL Editor                 │
└─────────────────────────────────────────────────────────────────┘
```

**전체 인프라 원리 설명**: `docs/guides/INFRA_GUIDE.md`

## 2. Flutter 앱 레이어

### 2.1 레이어 구조

```
lib/
├── main.dart              # 엔트리포인트: dart-define 기반 Supabase 초기화, ProviderScope
├── app.dart               # MaterialApp: 테마(Material3, 양피지 배경), 라우팅
├── models/                # 순수 데이터 클래스 (Supabase 행 → Dart 객체)
├── data/                  # Repository 패턴 (Supabase 쿼리 캡슐화)
├── state/                 # Riverpod Provider/Notifier (비즈니스 로직)
├── screens/               # 전체 화면 위젯
└── widgets/               # 재사용 가능한 UI 컴포넌트
```

### 2.2 상태 관리

```
supabaseClientProvider (Provider<SupabaseClient>)
       │
       ├── storyRepositoryProvider (Provider<StoryRepository>)
       │          │
       │          └── storyControllerProvider (NotifierProvider<StoryController, StoryState>)
       │                     │
       │                     └── StoryState: eras, characters, events, selectedEraId,
       │                                     selectedCharacterIds, selectedEventId,
       │                                     completedEventIds, searchQuery, ...
       │
       ├── userRepositoryProvider (Provider<UserRepository>)
       │
       └── authStateProvider (StreamProvider<AuthState>)
```

### 2.3 화면 구성

| 화면 | 파일 | 역할 |
|------|------|------|
| 메인 화면 | `screens/story_home_screen.dart` | 3열 레이아웃: 인물패널 + 지도 + 타임라인, 상단 bell 아이콘 |
| 로그인 | `widgets/inline_login_prompt_card.dart` | 인라인 소셜 로그인 (카카오/Google/Apple) |
| 구절 목록 | `screens/saved_verses_screen.dart` | 북마크 구절 관리 |
| 법률 문서 | `screens/legal_documents_screen.dart` | 이용약관, 개인정보처리방침 |
| 제안 게시판 | `screens/proposal_board_screen.dart` | 사역자/관리자 제안 목록 (웹 전용) |
| 제안 작성 | `screens/proposal_submit_screen.dart` | 5단계 제안 작성/수정 |
| 제안 상세 | `screens/proposal_detail_screen.dart` | 제안 상세 + 댓글 + 승인/거절 |
| 알림 히스토리 | `screens/notification_history_screen.dart` | 최근 30일 알림 전체 보기 |

## 3. 데이터 흐름 — 파일 간 연결 관계

### 3.1 전체 흐름

```
┌─────────────────────────────────────────────────────┐
│                    Supabase (DB)                     │
└────────────┬────────────────┬────────────────────────┘
             │                │
    ┌────────▼──────┐  ┌──────▼──────────┐
    │StoryRepository│  │UserRepository   │
    │ (이야기/시대)  │  │(사용자/구절/기도)│
    └────────┬──────┘  └──────┬──────────┘
             │                │
             │ Model 객체로 변환 (fromMap)
             │                │
      ┌──────▼────────────────▼──────┐
      │      StoryController         │
      │ (비즈니스 로직 + 상태 갱신)    │
      └──────────────┬───────────────┘
                     │
              ┌──────▼──────┐
              │  StoryState  │  ← 불변 데이터 클래스
              │  (ref.watch)  │
              └──────┬───────┘
                     │
    ┌────────────────┼────────────────────┐
    │                │                    │
┌───▼────┐   ┌──────▼──────┐   ┌─────────▼──────┐
│지도 패널│   │선택 패널    │   │  프로필 탭     │
│(핀 표시)│   │(시대/인물)  │   │  (진행도)      │
└────────┘   └─────────────┘   └────────────────┘
```

### 3.2 파일별 역할과 연결

**앱 시작:**
```
main.dart → Supabase 초기화 + ProviderScope
  └→ app.dart → MaterialApp + 첫 화면(StoryHomeScreen)
```

**데이터 계층 (아래→위 방향):**
```
models/ (순수 데이터 상자)
  ├── Era, Character, StoryEvent     ← 이야기 도메인
  ├── AppUserProfile              ← 사용자 도메인
  └── BibleVerse, QuizQuestion    ← 보조 도메인

data/ (Supabase 쿼리 + Model 변환)
  ├── story_repository.dart
  │     fetchEras() → List<Era>
  │     fetchCharactersByEra() → List<Character>
  │     fetchEventsByEra() → List<StoryEvent>
  │     fetchEventsForCharacter() → List<StoryEvent>
  │     searchEventsByText() → 퍼지 검색
  │     fetchQuizQuestions() → List<QuizQuestion>
  │     upsertEventProgress() → 학습 진행도 저장
  │     fetchSavedEventIds() / toggleSavedEvent() → 저장한 이야기
  │
  ├── user_repository.dart
  │     fetchUserProfile() → AppUserProfile
  │     fetchSavedVersesPage() → 저장 구절 페이지네이션
  │     fetchIntercessoryPrayerPage() → 중보기도 목록
  │     fetchCharacterStudyProgress() → 인물별 진행도
  │     recordAttendance() / recordStudyDay() → 출석/학습 기록
  │
  └── auth_repository.dart
        signInWithApple/Google/Kakao() → 소셜 로그인

state/ (비즈니스 로직)
  ├── story_controller.dart (Riverpod Notifier)
  │     ← story_repository, user_repository 사용
  │     → StoryState 갱신
  │
  ├── story_state.dart (불변 상태)
  │     eras, characters, events, selectedEraId
  │     selectedCharacterIds, completedEventIds, searchQuery
  │
  └── auth_providers.dart
        authStateProvider → 현재 로그인 사용자
```

**UI 계층 (메인 화면 허브):**
```
story_home_screen.dart (메인 화면 — 모든 것의 허브)
  ├── StorySelectionPanel   → 시대→인물→사건 3단계 선택 (EraSelector 기능 통합)
  │     ├── selection/panel_chrome.dart     (part)
  │     ├── selection/step_chip.dart        (part)
  │     └── selection/selection_cards.dart  (part)
  ├── StoryMapPanel         → StoryTerrain3dMap(MapLibre/OpenFreeMap 3D) + Flutter overlay
  ├── WeeklyTabPage         → 주간 인물 학습
  │     ├── weekly/weekly_avatar.dart      (part)
  │     └── weekly/weekly_list_panel.dart  (part)
  ├── ProfileTabPage        → 프로필 + 진행도
  │     ├── profile/profile_left_panel.dart       (part)
  │     ├── profile/profile_right_panel.dart      (part)
  │     ├── profile/profile_helpers.dart          (part)
  │     ├── profile/profile_intercessory_prayer.dart (part)
  │     └── profile/profile_character_overview.dart  (part)
  ├── ParchmentDialog       → 이야기 상세 모달
  ├── BibleReaderPage       → 성경 리더
  ├── EventDetailPage       → 사건 상세
  └── SearchBottomSheet     → 검색
```

**유틸 (어디서든 import 가능한 순수 함수):**
```
utils/
  ├── bible_book_meta.dart     ← BibleReaderPage, SearchBottomSheet
  ├── map_math.dart            ← StoryMapPanel
  ├── scene_asset_loader.dart  ← EventDetailPage, ParchmentDialog
  └── weekly_selection.dart    ← WeeklyTabPage
```

## 4. DB 스키마 개요 (번호 조정됨: 이전 §3)

상세는 `docs/BACKEND.md` 참조. 핵심 테이블:

```
eras ──< events                          (events.era_id)
              │
              ├── character_codes text[]    (인물 매핑은 events row 자체에 임베드)
              ├── bible_refs jsonb       (성경 참조 임베드)
              ├── story_scenes jsonb     (장면 텍스트 임베드)
              └── scene_characters jsonb    (장면별 인물 임베드)

events ──< quiz_questions
       ├──< user_event_progress >── (auth.users)
       ├──< user_quiz_attempts >── (auth.users)
       └──< user_event_emotion_marks >── (auth.users)

persons       (어드민이 is_active 토글로 노출 제어)
events_ordered (view: rank_in_era / global_rank 동적 계산)
character_eras    (view: 인물 첫 등장 story_index 기반 era별 순서)

bible_verses (독립 — 31,904절 KRV)

user_profiles ──< user_notes
              ├──< user_saved_verses
              ├──< user_intercessory_prayers
              └──< user_daily_activity  (attended + studied 플래그)
```

> v3 schema: `event_characters` / `event_bible_refs` 테이블, `events.code` / `events.time_sort_key` / `events.story` / `events.short_story` 컬럼 폐기. 자세한 사유는 ADR-012/013 참조.

## 4. 인증 흐름

```
사용자 → 소셜 로그인 (Apple/Google/Kakao)
       → Supabase Auth → auth.users 생성
       → on_auth_user_created 트리거
       → user_profiles 자동 생성 (share_id 7자리 코드 포함)
       → 앱에서 ensureSignedInUser() → 프로필 보정 + 출석 기록
```

## 5. 에셋 파이프라인 DAG

상세는 `docs/DATA_PIPELINE.md` 참조. 의존 관계:

```
stories JSON (소스 — 각 항목에 story_index 직접 박힘)
  ├→ build_character_meta_json.py   → character_meta.json (모든 개인 인물 + 아바타 프롬프트)
  │     ├→ generate_avatars_vertex.py → assets/avatars/ (기존 png 보존)
  │     │     └→ generate_runtime_thumbnails.py → assets/avatars_thumbs/
  │     ├→ build_characters_seed_sql.py → characters_seed.sql (is_active 토글 보존 UPSERT)
  │     └→ build_200_stories_seed_sql.py → 200_stories_seed.sql (events 한 테이블)
  ├→ generate_event_story_images_vertex.py → assets/story_images/
  │     └→ generate_runtime_thumbnails.py → assets/story_images_thumbs/
  └→ build_krv_seed_sql.py → krv_bible_verses.sql (독립)
```

## 6. Codex 스킬 아키텍처

도메인별 레퍼런스 MD + Codex 프로젝트 스킬로 컨텍스트를 분리:

| 도메인 | 레퍼런스 | 스킬 | 파일 범위 |
|--------|----------|------|----------|
| 프론트엔드 | `docs/FRONTEND.md`, `docs/UI_GUIDE.md` | `.agents/skills/frontend` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| 백엔드 | `docs/BACKEND.md` | `.agents/skills/backend` | `db_init.sql`, `supabase/`, `lib/data/` |
| 데이터 파이프라인 | `docs/DATA_PIPELINE.md` | `.agents/skills/data-pipeline` | `tools/`, `assets/`, `Makefile` |
| 테스트 | `docs/TESTING.md`, `docs/guides/TEST_GUIDE.md` | `.agents/skills/testing` | `test/`, `tools/**/test_*.py`, `.pre-commit-config.yaml` |

## 7. 환경 설정

| 환경변수 | 용도 |
|----------|------|
| `ENV` | 앱 런타임 환경 (`dev` / `real` / `prod`) — scripts가 `--dart-define`으로 주입 |
| `SUPABASE_URL` | 앱이 사용할 Supabase URL — scripts가 `.env`의 선택 환경 값에서 주입 |
| `SUPABASE_ANON_KEY` | 앱이 사용할 Supabase anon key — scripts가 `.env`의 선택 환경 값에서 주입 |
| `SUPABASE_URL_DEV` / `SUPABASE_ANON_KEY_DEV` | scripts가 읽는 개발 Supabase 공개값 (`.env`) |
| `SUPABASE_URL_PROD` / `SUPABASE_ANON_KEY_PROD` | scripts가 읽는 운영 Supabase 공개값 (`.env`) |
| `SUPABASE_SERVICE_ROLE_KEY_*` / `SUPABASE_DB_URL_*` | 로컬 운영도구 전용 비밀값 (`.env.ops`, 앱 번들 제외) |
| `GOOGLE_CLOUD_PROJECT` | Vertex AI 프로젝트 ID |
