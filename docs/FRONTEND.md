# 프론트엔드 도메인 레퍼런스

> 이 문서는 `$frontend` 스킬이 참조하는 프론트엔드 도메인 가이드이다.
> UI/UX 상세는 `docs/UI_GUIDE.md`를 함께 참조.

## 1. 파일 범위

```
lib/
├── main.dart                          # 엔트리포인트
├── app.dart                           # MaterialApp + 테마
├── models/                            # 데이터 모델 (14개)
├── state/                             # Riverpod 상태 관리 (3개)
├── screens/                           # 전체 화면 (6개)
├── widgets/                           # 재사용 UI 컴포넌트
│   ├── shared/                        # 도메인 횡단 공유 위젯 (event_short_popup 등)
│   ├── selection/                     # story_selection_panel part 파일
│   ├── map/                           # story_map_panel part 파일
│   ├── profile/                       # profile_tab_page part 파일 (extension)
│   └── weekly/                        # weekly_tab_page part 파일 (extension)
└── utils/                             # 공통 유틸리티
    ├── bible_book_meta.dart           # 성경 책/장 메타데이터
    ├── scene_asset_loader.dart        # 장면 이미지 로더
    ├── map_math.dart                  # 지도 수학/지오메트리 순수 함수
    └── weekly_selection.dart          # 주간 인물 선택 순수 함수
```

### 도메인 디렉토리 구성 (part 파일 패턴)

큰 위젯 파일(>1,000줄)은 메소드를 도메인별 part 파일로 분할.
- `widgets/X/` 디렉토리에 part 파일 위치
- 각 part 파일은 `part of '../X.dart';` 선언
- State 클래스 메소드는 `extension on _XState {...}` 형태로 정의
- private 멤버 접근 가능 (같은 라이브러리)
- 코드 변경 0건, 메소드 이동만으로 안전한 분해

자세한 패턴/절차는 `.claude/skills/refactor/SKILL.md` 참조.

## 2. 모델 클래스

| 모델 | 파일 | 핵심 필드 | 팩토리 |
|------|------|----------|--------|
| Era | `models/era.dart` (40줄) | id, code, testament, name, displayOrder, mapCenter*, mapZoom | `Era.fromMap()` |
| Character | `models/person.dart` (30줄) | id, code, name, tagline, description, avatarUrl, displayOrder | 생성자 직접 |
| StoryEvent | `models/story_event.dart` | id, eraId, title, summary, storyScenes (List<String>), sceneCharacters (List<List<String>>), lat/lng, storyIndex, rankInEra, globalRank, personCodes, bibleRefs (List<BibleRef>) | `StoryEvent.fromMap()` |
| BibleRef | `models/bible_ref.dart` | book, from, to (`displayText` getter) | `BibleRef.fromMap`, `BibleRef.fromList` |
| BibleVerse | `models/bible_verse.dart` (28줄) | translation, bookNo, bookName, chapterNo, verseNo, verseText | `BibleVerse.fromMap()` |
| AppUserProfile | `models/app_user_profile.dart` (33줄) | userId, shareId, nickname, photoUrl, prayerRequest | `AppUserProfile.fromMap()` |
| UserNote | `models/user_note.dart` (36줄) | id, userId, title, content, createdAt, updatedAt | `UserNote.fromMap()` |
| SavedBibleVerse | `models/saved_bible_verse.dart` (55줄) | id, userId, translation, bookNo, bookName, chapterNo, verseNo, verseText | `SavedBibleVerse.fromMap()` |
| QuizQuestion | `models/quiz_question.dart` (17줄) | id, question, choices, answerIndex, explanation | 생성자 직접 |
| CharacterStudyProgress | `models/character_study_progress.dart` (20줄) | person, completedCount, totalCount | 생성자 직접 |
| IntercessoryPrayerItem | `models/intercessory_prayer_item.dart` (33줄) | linkId, nickname, prayerRequest, photoUrl | `IntercessoryPrayerItem.fromMap()` |
| PagedResult<T> | `models/paged_result.dart` (13줄) | items, pageIndex, pageSize, hasNextPage | 생성자 직접 |

### 패턴 규칙
- Supabase 행을 받는 모델은 `fromMap(Map<String, dynamic>)` 팩토리 사용
- 모델은 순수 데이터 클래스 — 비즈니스 로직 없음
- 모든 필드는 `final` (불변)
- nullable 필드는 `?` 타입 사용

## 3. 상태 관리 (Riverpod)

### 3.1 Provider 구조

```dart
// story_controller.dart

supabaseClientProvider          // Provider<SupabaseClient>
storyRepositoryProvider         // Provider<StoryRepository>
storyControllerProvider         // NotifierProvider<StoryController, StoryState>

// auth_providers.dart
authStateProvider               // StreamProvider<AuthState>
```

### 3.2 StoryState (불변 상태 클래스)

```dart
class StoryState {
  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Character> persons;
  final List<StoryEvent> events;
  final String? selectedEraId;
  final Set<String> selectedCharacterCodes;        // person.code 기반
  final Map<String, Color> selectedCharacterColors; // key = person.code
  final String? selectedEventId;
  final Set<String> completedEventIds;
  final String searchQuery;
  final List<StoryEvent> searchResults;
  final bool isSearching;
  final String selectedTestament;  // 'old' | 'new'
}
```

### 3.3 StoryController 주요 메서드

| 메서드 | 역할 |
|--------|------|
| `initialize()` | 앱 시작 시 eras 로드, 초기 상태 설정 |
| `selectTestament(String)` | 구약/신약 전환 |
| `selectEra(String)` | 시대 선택 → persons + events 로드 |
| `toggleCharacter(String code)` | 인물 선택/해제 토글 (person.code 기반) |
| `selectEvent(String?)` | 이벤트 선택/해제 |
| `markEventCompleted({eventId, isCompleted})` | 이벤트 완료 여부 기록 + 학습 출석일 갱신 |
| `setSearchQuery(String)` | 검색어 변경 (220ms 디바운스) |
| `selectSearchResult(StoryEvent)` | 검색 결과 → 시대/인물/이벤트 자동 선택 |
| `mergedTimeline()` | 선택 인물 기준 이벤트 병합 타임라인 반환 (`globalRank` 정렬) |
| `colorForCharacter(String code)` | 인물 코드별 할당 색상 반환 |
| `personByCode(String code)` | 코드로 Character 객체 조회 |

### 3.4 색상 팔레트 (8색)

```dart
static const _palette = <Color>[
  Color(0xFF3B6C94), Color(0xFFB6673C), Color(0xFF557C3E), Color(0xFF8A4E5D),
  Color(0xFF616161), Color(0xFF9E7C24), Color(0xFF7B5D43), Color(0xFF5C6B9F),
];
```

## 4. 화면 (Screens)

| 화면 | 파일 | 역할 |
|------|------|------|
| StoryHomeScreen | `screens/story_home_screen.dart` | 메인 화면 (인물+지도+타임라인+프로필) |
| ~~LoginScreen~~ | ~~`screens/login_screen.dart`~~ | 삭제됨 — InlineLoginPromptCard로 대체 |
| ProfileNotesScreen | `screens/profile_notes_screen.dart` | 노트 목록 |
| ProfileNoteEditorScreen | `screens/profile_note_editor_screen.dart` | 노트 편집 |
| SavedVersesScreen | `screens/saved_verses_screen.dart` | 저장 구절 |
| LegalDocumentsScreen | `screens/legal_documents_screen.dart` | 법률 문서 |

> **리팩토링 상태**: `story_home_screen.dart`는 초기 7,172줄 → 현재 ~1,016줄 (−86%).
> 프로필 탭 2,700+줄이 `ProfileTabPage`로 분리되어 자체 상태 관리 + 콜백 3개로 결합도 최소화.
> 퀴즈 완료 시 진행도 새로고침은 `GlobalKey<ProfileTabPageState>`로 처리.

## 5. 위젯 (Widgets)

### 5.1 도메인 위젯

| 위젯 | 파일 | 역할 |
|------|------|------|
| StoryMapPanel | `widgets/story_map_panel.dart` | flutter_map 지도, 핀/마커 렌더링 |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 인물 선택 + 이벤트 목록 통합 |
| CharacterPanel | `widgets/character_panel.dart` | 인물 카드 (아바타, 설명) |
| ~~StoryListPanel~~ | ~~`widgets/story_list_panel.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| ParchmentDialog | `widgets/parchment_dialog.dart` | 이야기 상세 모달 |
| ParchmentPageScaffold | `widgets/parchment_page_scaffold.dart` | 양피지 배경 페이지 |
| ~~EraSelector~~ | ~~`widgets/era_selector.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| GameUiSkin | `widgets/game_ui_skin.dart` | 커스텀 UI 테마 데코레이션 |
| ~~SearchBox~~ | ~~`widgets/search_box.dart`~~ | 삭제됨 — SearchBottomSheet로 대체 (필요 시 재생성) |

### 5.2 story_home_screen에서 추출한 위젯 (2차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| ParchmentTextureLayer | `widgets/parchment_texture_layer.dart` | 양피지 질감 오버레이 |
| SubPageScaffold | `widgets/sub_page_scaffold.dart` | 서브 페이지 공통 레이아웃 (앱바+배경) |
| SubPageFloatingHomeButton | `widgets/sub_page_floating_home_button.dart` | 드래그 가능한 홈 버튼 |
| InlineLoginPromptCard | `widgets/inline_login_prompt_card.dart` | 카카오/Google/Apple 3단 인라인 로그인 카드 (버튼 순서: 카카오 → Google → Apple) |
| ShareIdInputDialog | `widgets/share_id_input_dialog.dart` | 7자리 공유 ID 입력 다이얼로그 |
| ProfileEditorDialog | `widgets/profile_editor_dialog.dart` | 프로필(닉네임/사진/기도제목) 수정 |

### 5.3 story_home_screen에서 추출한 페이지 (3차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (ConsumerWidget, 콜백으로 동작) |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (자체 상태 관리, 저장 구절 토글) |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 금주 인물 학습 탭 (자체 데이터 로딩 + 상태) |
| ProfileTabPage | `widgets/profile_tab_page.dart` | 프로필 탭 (인물 진행도 + 노트/말씀/중보기도 미리보기, 자체 데이터/상태 25+개) |
| CharacterAvatar | `widgets/character_avatar.dart` | 인물 아바타 (주간/프로필 공용) |

### 5.4 도메인 횡단 공유 위젯 (4차 리팩토링)

| 위젯 | 파일 | 사용처 |
|------|------|--------|
| EventShortPopup | `widgets/shared/event_short_popup.dart` | story_map_panel 콜아웃 + weekly_tab_page 단축 팝업 |

### 5.5 큰 화면의 part 파일 분해 (4차 리팩토링)

대규모 파일(>1,000줄)을 도메인별 part 파일로 분해해 가독성 향상. 동작은 동일.

| 부모 파일 | 분해 후 줄 수 | part 파일 |
|----------|-------------|----------|
| `widgets/story_selection_panel.dart` | 1648 → 561 (−66%) | `selection/panel_chrome.dart` (~280)<br>`selection/step_chip.dart` (~340)<br>`selection/selection_cards.dart` (~465) |
| `widgets/story_map_panel.dart` | 1500 → 1244 (−17%) | `map/pin_marker.dart` (~170)<br>+ 순수 함수 9개 → `utils/map_math.dart` |
| `widgets/profile_tab_page.dart` | 2628 → 1755 (−33%) | `profile/profile_character_overview.dart` (~400)<br>`profile/profile_intercessory_prayer.dart` (~225)<br>`profile/profile_helpers.dart` (~260) |
| `widgets/weekly_tab_page.dart` | 884 → 574 (−35%) | `weekly/weekly_avatar.dart` (~67)<br>`weekly/weekly_list_panel.dart` (~258)<br>+ 순수 함수 3개 → `utils/weekly_selection.dart` |

### ProfileTabPage 외부 콜백

`ProfileTabPage`는 자체 상태(25+개 필드)를 내부에서 모두 관리하며, 외부 의존성은 콜백 3개로만 노출된다:

```dart
ProfileTabPage(
  key: _profileTabKey,  // ← 퀴즈 완료 후 진행도 새로고침용
  onStartQuiz: (eventId) => ...,
  onOpenEventDetail: (event) => ...,
  onOpenBibleReader: ({bookNo, chapterNo, verseNo}) => ...,
)

// 퀴즈 완료 후 호출
_profileTabKey.currentState?.refreshProgressAfterQuizCompletion();
```

### 5.4 스타일 헬퍼

`widgets/story_home_styles.dart` — 양피지/고지도 테마용 공통 데코레이션/위젯 빌더:

| 함수 | 반환 | 용도 |
|------|------|------|
| `modalSurfaceDecoration()` | BoxDecoration | 모달 표면 |
| `floatingPanelDecoration(...)` | BoxDecoration | 플로팅 패널 |
| `interactiveCardDecoration(...)` | BoxDecoration | 인터랙티브 카드 (selected/completed) |
| `headerChipDecoration()` | BoxDecoration | 헤더 칩 |
| `softButtonDecoration(...)` | BoxDecoration | 부드러운 버튼 |
| `filledActionButton(...)` | Widget | 채워진 액션 버튼 |
| `modalCloseButton(...)` | Widget | 모달 닫기 버튼 |
| `mapControlButton(...)` | Widget | 지도 컨트롤 버튼 |
| `topUtilityButton(...)` | Widget | 상단 유틸리티 버튼 |
| `bibleDropdownFrame<T>(...)` | Widget | 성경 드롭다운 프레임 |
| `storySection(...)` | Widget | 이야기 섹션 (제목 + 내용 + action) |
| `storySceneRow(...)` | Widget | 4장면 이미지 가로 배열 |
| `bibleMoveButton(...)` | Widget | "이동" 액션 버튼 (성경 리더) |
| `lockedPreviewOverlay(...)` | Widget | 잠금 프리뷰 오버레이 |

## 6. 의존 패키지

| 패키지 | 버전 | 용도 |
|--------|------|------|
| flutter_riverpod | ^2.6.1 | 상태 관리 |
| supabase_flutter | ^2.9.1 | Supabase SDK |
| flutter_map | ^8.2.1 | 인터랙티브 지도 |
| latlong2 | ^0.9.1 | 좌표 계산 |
| flutter_dotenv | ^5.2.1 | .env 환경변수 |
| sign_in_with_apple | ^6.1.4 | Apple 로그인 |
| image_picker | ^1.1.2 | 프로필 이미지 |
| crypto | ^3.0.6 | SHA256 (Apple 로그인 nonce) |
| cupertino_icons | ^1.0.8 | iOS 스타일 아이콘 |

## 7. 코딩 컨벤션

- **포맷**: `dart format` (Dart 공식 스타일)
- **린트**: `flutter_lints` 5.0 (`analysis_options.yaml`)
- **네이밍**: Dart 공식 — `camelCase` 변수, `PascalCase` 클래스
- **UI 텍스트**: 한국어로 작성
- **위젯**: `ConsumerWidget` 또는 `ConsumerStatefulWidget` (Riverpod)
- **상수**: `const` 생성자 최대 활용
- **에러 처리**: try-catch + `state.copyWith(error: ...)` 패턴
