# ARCHITECTURE — 이야기 성경 기술 아키텍처

> 최종 수정: 2026-04-16

## 1. 시스템 구성도

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                        │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────┐  │
│  │ screens/ │←─│  state/   │←─│     data/        │  │
│  │ widgets/ │  │ Riverpod  │  │  repositories    │  │
│  └──────────┘  └───────────┘  └────────┬─────────┘  │
│                                        │             │
└────────────────────────────────────────┼─────────────┘
                                         │ supabase_flutter SDK
                                         ▼
                            ┌─────────────────────────┐
                            │       Supabase           │
                            │  ┌───────────────────┐   │
                            │  │   PostgreSQL       │   │
                            │  │  + pgvector        │   │
                            │  │  + RLS             │   │
                            │  └───────────────────┘   │
                            │  ┌───────┐ ┌──────────┐  │
                            │  │ Auth  │ │ Storage  │  │
                            │  └───────┘ └──────────┘  │
                            └─────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              에셋 파이프라인 (로컬)                    │
│  tools/*.py → Vertex AI Imagen → assets/            │
│  tools/*.py → SQL 생성 → Supabase SQL Editor        │
└─────────────────────────────────────────────────────┘
```

## 2. Flutter 앱 레이어

### 2.1 레이어 구조

```
lib/
├── main.dart              # 엔트리포인트: .env 로드, Supabase 초기화, ProviderScope
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
       │                     └── StoryState: eras, persons, events, selectedEraId,
       │                                     selectedPersonIds, selectedEventId,
       │                                     completedEventIds, searchQuery, ...
       │
       ├── userRepositoryProvider (Provider<UserRepository>)
       │
       └── authStateProvider (StreamProvider<AuthState>)
```

### 2.3 화면 구성

| 화면 | 파일 | 역할 |
|------|------|------|
| 메인 화면 | `screens/story_home_screen.dart` | 3열 레이아웃: 인물패널 + 지도 + 타임라인 |
| 로그인 | `screens/login_screen.dart` | Apple/Google/Kakao 소셜 로그인 |
| 노트 목록 | `screens/profile_notes_screen.dart` | 개인 노트 CRUD |
| 노트 편집 | `screens/profile_note_editor_screen.dart` | 노트 에디터 |
| 구절 목록 | `screens/saved_verses_screen.dart` | 북마크 구절 관리 |
| 법률 문서 | `screens/legal_documents_screen.dart` | 이용약관, 개인정보처리방침 |

## 3. 데이터 흐름 — 파일 간 연결 관계

### 3.1 전체 흐름

```
┌─────────────────────────────────────────────────────┐
│                    Supabase (DB)                     │
└────────────┬────────────────┬────────────────────────┘
             │                │
    ┌────────▼──────┐  ┌──────▼──────────┐
    │StoryRepository│  │UserRepository   │
    │ (이야기/시대)  │  │(사용자/노트/구절)│
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
  └→ app.dart → MaterialApp + 첫 화면(LoginScreen)
```

**데이터 계층 (아래→위 방향):**
```
models/ (순수 데이터 상자)
  ├── Era, Person, StoryEvent     ← 이야기 도메인
  ├── AppUserProfile, UserNote    ← 사용자 도메인
  └── BibleVerse, QuizQuestion    ← 보조 도메인

data/ (Supabase 쿼리 + Model 변환)
  ├── story_repository.dart
  │     fetchEras() → List<Era>
  │     fetchPersonsByEra() → List<Person>
  │     fetchEventsByEra() → List<StoryEvent>
  │     fetchEventsForPerson() → List<StoryEvent>
  │     searchEventsByText() → 퍼지 검색
  │     fetchQuizQuestions() → List<QuizQuestion>
  │     upsertEventProgress() → 학습 진행도 저장
  │
  ├── user_repository.dart
  │     fetchUserProfile() → AppUserProfile
  │     fetchUserNotesPage() → 노트 페이지네이션
  │     fetchSavedVersesPage() → 저장 구절 페이지네이션
  │     fetchIntercessoryPrayerPage() → 중보기도 목록
  │     fetchPersonStudyProgress() → 인물별 진행도
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
  │     eras, persons, events, selectedEraId
  │     selectedPersonIds, completedEventIds, searchQuery
  │
  └── auth_providers.dart
        authStateProvider → 현재 로그인 사용자
```

**UI 계층 (메인 화면 허브):**
```
story_home_screen.dart (메인 화면 — 모든 것의 허브)
  ├── EraSelector           → 시대 탭 바
  ├── StorySelectionPanel   → 시대→인물→사건 3단계 선택
  │     ├── selection/panel_chrome.dart     (part)
  │     ├── selection/step_chip.dart        (part)
  │     └── selection/selection_cards.dart  (part)
  ├── StoryMapPanel         → flutter_map 지도 + 핀/마커
  │     └── map/pin_marker.dart            (part)
  ├── StoryListPanel        → 이벤트 타임라인 리스트
  ├── WeeklyTabPage         → 주간 인물 학습
  │     ├── weekly/weekly_avatar.dart      (part)
  │     └── weekly/weekly_list_panel.dart  (part)
  ├── ProfileTabPage        → 프로필 + 진행도
  │     ├── profile/profile_left_panel.dart       (part)
  │     ├── profile/profile_right_panel.dart      (part)
  │     ├── profile/profile_helpers.dart          (part)
  │     ├── profile/profile_intercessory_prayer.dart (part)
  │     └── profile/profile_person_overview.dart  (part)
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
eras ──< person_eras >── persons
  │                         │
  └──< events ──< event_persons >──┘
          │
          ├──< event_bible_refs
          ├──< quiz_questions
          └──< user_event_progress >── (auth.users)

bible_verses (독립 — 31,904절 KRV)

user_profiles ──< user_notes
              ├──< user_saved_verses
              ├──< user_intercessory_prayers
              ├──< user_daily_attendance
              └──< user_daily_study
```

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
stories JSON (소스)
  ├→ build_avatar_prompts_json.py → avatar_prompts.json
  │     ├→ generate_avatars_vertex.py → assets/avatars/
  │     │     └→ generate_runtime_thumbnails.py → assets/avatars_thumbs/
  │     ├→ build_persons_seed_sql.py → persons_seed.sql
  │     └→ build_200_stories_seed_sql.py → 200_stories_seed.sql
  ├→ rewrite_story_scenes_for_image_generation.py → story_scenes 보강
  │     └→ generate_event_story_images_vertex.py → assets/story_images/
  │           └→ generate_runtime_thumbnails.py → assets/story_images_thumbs/
  └→ build_krv_seed_sql.py → krv_bible_verses.sql (독립)
```

## 6. 서브에이전트 아키텍처

도메인별 레퍼런스 MD + Claude 스킬로 컨텍스트를 분리:

| 도메인 | 레퍼런스 | 스킬 | 파일 범위 |
|--------|----------|------|----------|
| 프론트엔드 | `docs/FRONTEND.md` | `$frontend` | `lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/` |
| 백엔드 | `docs/BACKEND.md` | `$backend` | `db_init.sql`, `supabase/`, `lib/data/` |
| 데이터 파이프라인 | `docs/DATA_PIPELINE.md` | `$data-pipeline` | `tools/*.py`, `assets/`, `Makefile` |
| 테스트 | `docs/TESTING.md` | `$testing` | `test/`, `.pre-commit-config.yaml` |

## 7. 환경 설정

| 환경변수 | 용도 |
|----------|------|
| `SUPABASE_URL_DEV` | 개발 Supabase URL |
| `SUPABASE_ANON_KEY_DEV` | 개발 익명 키 |
| `SUPABASE_URL_PROD` | 운영 Supabase URL |
| `SUPABASE_ANON_KEY_PROD` | 운영 익명 키 |
| `GOOGLE_CLOUD_PROJECT` | Vertex AI 프로젝트 ID |
| `ENV` | 런타임 환경 (`dev` / `prod`) — `--dart-define=ENV=prod` |
