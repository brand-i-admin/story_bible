# 프론트엔드 도메인 레퍼런스

> 이 문서는 `.agents/skills/frontend` 스킬이 참조하는 프론트엔드 도메인 가이드이다.
> UI/UX 상세는 `docs/UI_GUIDE.md`를 함께 참조.

## 1. 파일 범위

```
lib/
├── main.dart                          # 엔트리포인트
├── app.dart                           # MaterialApp + 테마 (AppTheme.light)
├── theme/                             # 디자인 시스템 단일 진실 소스
│   ├── tokens.dart                    # AppColors / AppRadii / AppSpacing / AppShadows / AppFontSizes
│   ├── typography.dart                # AppTextStyles (sb-h1/h2/h3/body/...)
│   ├── surfaces.dart                  # AppSurfaces (modal/dialog/floating/card)
│   └── app_theme.dart                 # ThemeData 빌더
├── models/                            # 데이터 모델 (14개)
├── state/                             # Riverpod 상태 관리
├── data/                              # 로컬 저장소 래퍼 (SharedPreferences 등)
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

자세한 패턴/절차는 `.agents/skills/refactor/SKILL.md` 참조.

### 장면 이미지 로딩

- `SceneAssetLoader`는 먼저 `assets/story_images_thumbs/index.json`을 읽어 `event.title`을 앱 번들용 짧은 썸네일 디렉토리(`nt_apostolic_034` 등)로 변환한다.
- 긴 한글 제목 디렉토리는 Android asset bundle 단계에서 URL-encoded 파일명이 길어질 수 있으므로, 앱 번들에는 `index.json`과 짧은 디렉토리를 등록한다.
- 오래된 개발 빌드나 제안 자산을 위해 제목 기반 디렉토리 fallback과 Supabase Storage URL fallback은 유지한다. 로컬 번들에 새 이야기 썸네일이 없고 `event.sceneImagePaths`가 있으면 기본 Supabase client로 public URL을 만들어 `Image.network` 경로를 반환한다.

## 2. 모델 클래스

| 모델 | 파일 | 핵심 필드 | 팩토리 |
|------|------|----------|--------|
| Era | `models/era.dart` (40줄) | id, code, testament, name, displayOrder, mapCenter*, mapZoom | `Era.fromMap()` |
| Character | `models/person.dart` (30줄) | id, code, name, tagline, description, avatarUrl, displayOrder | 생성자 직접. DB 이름이 비어 있거나 code/영어로 내려오면 `data/character_name_fallbacks.dart`의 한글 표시명으로 보정 |
| StoryEvent | `models/story_event.dart` | id, eraId, title, summary, backgroundContext (배경 지식 카드 문구), storyScenes (List<String>), sceneCaptions (List<String>, 이미지 하단 설명), sceneCharacters (List<List<String>>), **unitCode/unitTitle/unitOrder** (시간 순 보기 구간), **landmarkId** (v2 위치 모델 진실 소스), placeName/lat/lng (events_ordered view derive), storyIndex, rankInEra, globalRank, characterCodes, bibleRefs (List<BibleRef>) | `StoryEvent.fromMap()` |
| BibleRef | `models/bible_ref.dart` | book, from, to (`displayText` getter) | `BibleRef.fromMap`, `BibleRef.fromList` |
| BibleVerse | `models/bible_verse.dart` (28줄) | translation, bookNo, bookName, chapterNo, verseNo, verseText | `BibleVerse.fromMap()` |
| Landmark | `models/landmark.dart` | id, code, name, description, emoji, category, lat, lng, **kind** ('region'/'anchor'/'minor'/'point'), **polygon** (region 만, List<LatLng>), **parentLandmarkId**, **aliasGroupId**, displayPriority, eraCodes, relatedEventCodes (`isRegion/isAnchor/isMinor/latLng` getter) | `Landmark.fromMap()` |
| AppUserProfile | `models/app_user_profile.dart` (33줄) | userId, shareId, nickname, photoUrl, prayerRequest | `AppUserProfile.fromMap()` |
| SavedBibleVerse | `models/saved_bible_verse.dart` | id, userId, translation, bookNo, bookName, chapterNo, verseNo, verseText, comment, createdAt | `SavedBibleVerse.fromMap()` |
| UserCompanionDiaryEntry | `models/user_companion_diary_entry.dart` | id, userId, entryDate, title, body, createdAt, updatedAt | `UserCompanionDiaryEntry.fromMap()` |
| QuizQuestion | `models/quiz_question.dart` | id, question, choices, answerIndex, explanation, `confusedChoiceLabel` | 생성자 직접 |
| QuizAttemptSummary | `models/quiz_attempt_summary.dart` | eventId, correctCount, totalCount, wrongCount, confusedCount, selectedAnswers, updatedAt, needsReview | `QuizAttemptSummary.fromMap()` |
| EventProposal | `models/event_proposal.dart` | id, proposalType ('new'/'delete'), targetEventId, 제안 본문 전체 필드, proposedCharacters, quizQuestions, status, reviewed* | `EventProposal.fromMap()` |
| QuizDraft | `models/event_proposal.dart` | question, choices(3), answerIndex(0~2), explanation. `isValid` getter 로 목회자 작성 선택지 3개 + 해설 필수 검증. | `QuizDraft.fromMap()` / `.toMap()` |
| ProposedCharacter | `models/event_proposal.dart` | code, name, prompt, storagePath. 제안 시 신규 생성한 캐릭터 메타 | `ProposedCharacter.fromMap()` |
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

// font_scale_providers.dart
fontScaleRepositoryProvider     // Provider<FontScaleRepository>
fontScaleProvider               // NotifierProvider<FontScaleController, FontScale>
```

### 3.1.1 FontScale (앱 전역 글자 크기)

`state/font_scale_providers.dart` — `FontScale` enum(`normal` 1.0x / `large` 1.2x / `veryLarge` 1.4x)과 Riverpod 프로바이더. `fontScaleBuilder`가 `MediaQuery.textScaler`에 주입해 앱 전역 텍스트에 적용된다. 저장소는 `data/font_scale_repository.dart`의 `SharedPreferences` 래퍼 사용.

### 3.1.2 하단 시스템 inset 정규화

`utils/system_insets.dart` — 일부 모바일 WebView/브라우저가 내비게이션 바가 없어도 작은 `MediaQuery.padding.bottom` 값을 보고하는 문제를 막는다. `MaterialApp.builder`의 `fontScaleBuilder`가 작은 bottom inset(16px 미만)을 0으로 정규화해 gesture-only/내비바 없음 환경에서는 화면 맨 아래까지 쓰고, 홈 인디케이터나 3-button 내비게이션처럼 의미 있는 inset 은 그대로 보존한다. 단, Android 폰에서 시스템 inset 이 0으로 보고되어도 3-button 네비바가 실제로 하단을 덮는 경우를 위해 `StoryHomeScreen` 하단 시트는 작은 fallback inset 을 더해 마지막 콘텐츠가 가려지지 않게 한다.

### 3.2 StoryState (불변 상태 클래스)

```dart
class StoryState {
  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Character> characters;
  final List<StoryEvent> events;
  final String? selectedEraId;             // 단일 시대 선택
  final SelectionMode? selectionMode;      // v2 — 'timeline' | 'region' | 'character'
  final String? selectedLandmarkId;        // v2 — region 모드에서 선택된 landmark id
  final Set<String> selectedCharacterCodes;        // character.code 기반
  final Map<String, Color> selectedCharacterColors; // key = character.code
  final Set<String> selectedTimelineUnitCodes;      // timeline 모드 구간 복수 선택
  final String? selectedEventId;
  final Set<String> completedEventIds;
  final Set<String> bibleReadEventIds;
  final Set<String> quizCompletedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final String searchQuery;
  final List<StoryEvent> searchResults;
  final bool isSearching;
  final String selectedTestament;  // 'old' | 'new'

  // 지도 관련 (2026-04-29)
  final List<Landmark> landmarks;               // 시대별 랜드마크 + region polygon 카탈로그
}
```

3D 지도 첫 화면은 하단 시트에 아라비아반도가 가려지지 않도록 이집트·사우디아라비아·
걸프·이란까지 포함하는 남쪽 확장 경계를 사용한다. 서쪽 map bounds 는 이탈리아가
왼쪽 여백에 걸리는 정도로 제한한다.
첫 화면과 `시대/방법` 단계로 돌아올 때는 약 1초 동안 한 박자 가까운 줌인 3D pitch
상태에서 기본 줌과 정면 pitch 로 ease-out 전환해 지도가 확대·축소/틸트 가능하다는
감각을 준다.
후보 region 경계 선택 화면은 3D terrain renderer 를 유지하되 카메라 pitch/bearing 을
0으로 전환해 폴리곤 경계가 원근감으로 기울어 보이지 않게 한다.
지역 선택 직후 카메라는 사건 좌표가 아니라 선택 region polygon bounds 에
`fitBounds` 로 맞춘다. 이 기준은 하단 선택 시트가 접힌 상태의 가시 영역이다.
사건/region fit 은 하단 시트 padding 이 커질수록 상단 padding 도 크게 늘려, 핀
묶음과 후보 region 이 화면 위쪽 오버레이 뒤에 몰리지 않고 북쪽 지도 여백과 탭 가능한
영역을 확보하게 한다.
분열왕국 시대(`era_divided_kingdom`)는 지역 모드에서 `북이스라엘`과 `남유다`를
큰 축으로 고르게 한다. 엘리야의 호렙 산처럼 왕국 영토 밖에서 진행되는 사건은 별도
region으로 남길 수 있지만, 남북 왕국 이야기는 세부 지파/성읍으로 쪼개지 않고 두
큰 region 아래 landmark로 묶는다.

### 3.3 StoryController 주요 메서드

| 메서드 | 역할 |
|--------|------|
| `initialize()` | 앱 시작 시 eras 로드, 초기 상태 설정 |
| `selectTestament(String)` | 구약/신약 전환 |
| `selectEra(String)` | 시대 단수 선택 → characters + events 로드 |
| `toggleEraMulti(String)` | v2 — 시대 멀티 선택 토글 |
| `setSelectedEras(Set<String>)` | v2 — 여러 시대 events/characters 합산 |
| `setSelectionMode(SelectionMode)` | v2 — timeline/region/character 모드 진입 |
| `selectLandmark(String?)` | v2 — region 모드에서 선택된 landmark 변경 |
| `toggleCharacter(String code)` | 인물 선택/해제 토글 (person.code 기반) |
| `selectEvent(String?)` | 이벤트 선택/해제 |
| `setBibleRead(...)` / `setQuizCompleted(...)` | 부분 진행도 저장. 둘 다 완료되면 감정 새김 버튼이 열린다 |
| `setEmotionMark(...)` | 감정/100자 메모 저장 후 읽기+퀴즈+감정 조건이 모두 맞으면 완료 처리 |
| `markEventCompleted({eventId, isCompleted})` | 최종 완료 여부 기록 + 학습 출석일 갱신 |
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
| StoryHomeScreen | `screens/story_home_screen.dart` | 메인 화면 (인물+지도+타임라인+프로필). 상단 유틸리티 row 는 `돋보기`, `성경`, `퀴즈`, `프로필`, `글자`, 알림 순서이며 돋보기는 `BibleVerseSearchScreen`으로 이동해 성경 구절 기반 이야기 검색을 연다. 글자 크기 버튼은 프로필과 종 모양 사이에서 바텀시트를 연다. `아주크게` 글자 크기에서는 홈 인트로 보기 방식 카드가 1행 3열을 유지하되 카드 높이가 텍스트 배율에 맞춰 늘어나고, 인물/구간/사건 카드 높이도 함께 늘어나 카드 밖 텍스트 overflow 를 막는다. 시트 헤더는 **단일 toggle 동그라미** — 연한 초록 pill (`_activeColor.withAlpha(0.16)` + 0.45 border) 안에 ▲/▼ 한 개. 옛 indicator bar 는 제거 (드래그로 오해되던 문제). 헤더는 toggle 과 라벨형 stepper(`시대/방법 → 장소/인물/구간 → 이야기`)만 유지하고, 이전/다음 액션은 하단 패널 바로 위 큰 플로팅 버튼으로만 노출한다. 이전 계열은 좌측 갈색 버튼, 다음 계열은 우측 초록 버튼으로 배치하며, 버튼 뒤에는 별도 사각 음영을 두지 않는다. 지도 위 우측 확대/축소/출처 버튼은 두지 않으며, 지도 설명은 프로필 설정으로 이동했다. 핀 reveal 중에는 지도 우측 중앙에 큰 반투명 `>>` 버튼을 띄워 사용자가 기다리지 않고 모든 핀을 즉시 표시한 뒤 사건 목록으로 넘어갈 수 있게 한다. 하단 시트는 화면 맨 아래(`bottom: 0`) 에 붙되 intro/region picker/timeline unit picker/event cards 별 예상 콘텐츠 높이를 기준으로 열린다. 모바일에서는 좌우 margin 없이 화면 폭을 모두 쓰고, tablet/desktop 에서는 지도 위 floating panel 감각을 위해 좌우 여백을 둔다. 의미 있는 `bottomInset` 이 있을 때는 시트 높이에 더하고, Android 폰에서 inset 이 0으로 보고되어도 하단 네비바가 콘텐츠를 가리지 않도록 작은 fallback inset 을 적용한다. Android 시스템 뒤로가기는 `PopScope` + `utils/home_back_navigation.dart` 로 홈 내부 흐름을 되감는다: region 사건 목록→region 선택→홈, character 사건 선택→인물 선택→홈, timeline 사건 목록→구간 선택→홈, 시대만 고른 intro→시대 미선택 홈. 초기/모드별 hint 는 `MapHintOverlay` 가 표시하며, 첫 화면에서는 "오늘은 성경 어디를 여행해볼까요?", `시간 순·인물·장소` 선택 안내 아래 번호 없는 괄호 구절 검색 안내를 지도 위 캐릭터 가이드로 노출한다. dismiss state 는 `_mapHintDismissed`. 인물 모드의 region 라벨과 path 표시 우선순위는 `StoryTerrain3dMap` 안의 MapLibre 레이어 z-order 와 GeoJSON 갱신으로 처리한다. |
| BibleVerseSearchScreen | `screens/bible_verse_search_screen.dart` | 홈 상단 돋보기에서 여는 구절 기반 이야기 검색 화면. 상단에는 기존 서브페이지 `<` 버튼과 성경 리더와 같은 크기의 중앙 정렬 제목을 두고, `bibleBooks`와 `fetchBibleVersesByChapter`로 신약/구약, 권, 장을 성경 리더의 `bibleDropdownFrame` 가로 row 로 고른 뒤 해당 장의 절 번호를 프로필 달력처럼 선으로 나눈 버튼 그리드로 표시한다. 절 버튼 아래에는 선택한 절을 `창 1:1` 같은 짧은 참조 pill 과 본문이 함께 있는 작은 말씀 카드로 보여 준다. `StoryRepository.fetchEventsContainingBibleVerse`가 `events_ordered.bible_refs` 범위 안에 해당 절이 포함되는 이야기를 찾으며, 결과는 절 버튼 전체 아래에 `ProfileEventReviewGrid`/`StoryEventThumbCard`를 재사용해 홈 하단 패널·프로필 복습 카드와 같은 시각 상태(완료, 감정, 퀴즈 결과)로 보여 준다. 카드 탭 시 홈의 `EventDetailPage` 흐름으로 이어진다. |
| ~~LoginScreen~~ | ~~`screens/login_screen.dart`~~ | 삭제됨 — InlineLoginPromptCard로 대체 |
| SavedVersesScreen | `screens/saved_verses_screen.dart` | 저장한 성경 구절 전체보기. 상단에는 아이콘형 이전 버튼과 `저장한 성경 구절` 제목을 같은 row에 두고, 본문 카드는 좌측 버튼 폭에 밀리지 않고 화면 가로 공간을 모두 사용한다. |
| CompanionDiaryEntriesScreen | `screens/companion_diary_entries_screen.dart` | 프로필 "오늘의 동행 일지" 전체보기. 상단에는 아이콘형 이전 버튼과 `동행 일지 리스트` 제목을 같은 row에 둔다. 사용자가 작성한 동행 일지를 최신 날짜순으로 표시하며, 본문 카드는 좌측 버튼 폭에 밀리지 않고 화면 가로 공간을 모두 사용한다. 각 항목은 프로필 탭과 같은 `CompanionDiaryEntryPreviewCard`를 사용해 날짜 → `📝`+제목 → 본문 최대 3줄 순서로 보여 주고, 탭하면 전체 본문 상세 팝업에서 수정/삭제한다. |
| LegalDocumentsScreen | `screens/legal_documents_screen.dart` | 법률 문서 |
| ProposalBoardScreen | `screens/proposal_board_screen.dart` | 제안 게시판 (웹 전용) |
| ProposalSubmitScreen | `screens/proposal_submit_screen.dart` | 새 이야기 제안 작성/수정 (5-step wizard: 안내 → 시대 → 인물·위치 → 세부 → **퀴즈**). 마지막 Step 4 는 목회자 작성 선택지 3개 퀴즈 1~3문항 + 제출 버튼. |
| ProposalDetailScreen | `screens/proposal_detail_screen.dart` | 제안 상세 + 댓글. `proposal_type='delete'` 일 때 빨간 삭제 제안 배너 + "수정" 버튼 비노출 + 승인 시 `approveDelete` 분기. 새 이야기 승인은 위치 override + 등장인물 노출 여부를 다이얼로그에서 함께 확정한다. 같은 위치 제안이 먼저 승인되어 무효화된 pending 제안도 관리자가 새 위치를 골라 바로 승인할 수 있다. |
| NotificationHistoryScreen | `screens/notification_history_screen.dart` | 알림 전체보기 (최근 30일, 2026-04-22) |

> **리팩토링 상태**: `story_home_screen.dart`는 초기 7,172줄 → 현재 ~1,016줄 (−86%).
> 프로필 탭 2,700+줄이 `ProfileTabPage`로 분리되어 자체 상태 관리 + 콜백 3개로 결합도 최소화.
> 퀴즈 완료 시 진행도 새로고침은 `GlobalKey<ProfileTabPageState>`로 처리.

## 5. 위젯 (Widgets)

### 5.1 도메인 위젯

| 위젯 | 파일 | 역할 |
|------|------|------|
| StoryMapPanel | `widgets/story_map_panel.dart` | 운영 지도는 `StoryTerrain3dMap` + MapLibre GL JS 3D 단일 경로다. Android/iOS 는 네이티브 WebView, Flutter Web 은 `HtmlElementView` iframe 브릿지로 같은 HTML 렌더러를 띄운다. OpenFreeMap Liberty style 과 공개 Terrarium DEM 에 pitch/bearing/exaggeration 을 적용하며, 별도 API key나 지도 배경 선택 환경변수를 받지 않는다. 예전 flutter_map 2D tile/layer/pin 폴백은 제거됐다. `activeLandmarks` 와 `eraRegionLandmarks` 는 MapLibre 내부 GeoJSON source 로 전달되고, country boundary/region polygon/label/path/hit-zone 은 MapLibre layer 로, 사건 숫자·감정 핀과 non-region 랜드마크는 DOM marker 로 그린다. 하단 선택 패널 위 pointer 입력은 지도 브릿지에 짧은 tap suppression 을 전달해 패널 버튼/스크롤이 아래 지도 region·랜드마크 선택으로 새지 않게 한다. **`onMapInteraction`** 콜백은 MapLibre 쪽 사용자 제스처 이벤트로 부모의 hint overlay dismiss 를 트리거한다. 이야기 간 이동 glow 는 같은 위치 사건 분산 좌표를 재사용해 현재/목표 사건 핀 중심에 맞춘다. `skipAnimation()`은 ordered reveal 타이머까지 멈추고 모든 핀을 즉시 노출한다. `playEmotionStamp(event, stampLabel)` 은 감정 새김 직후 같은 분산 좌표의 지도 핀 위에 감정 도장을 재생한다. reveal/전환/감정 새김의 중복 실행은 내부 guard 로 막는다. |
| StoryTerrain3dMap | `widgets/map/story_terrain_3d_map.dart` | 운영 3D 전용 지도. MapLibre GL JS 를 HTML string 으로 로드하고 OpenFreeMap Liberty style + Mapzen Terrarium DEM 을 연결한다. Android/iOS 는 `webview_flutter`의 `WebViewWidget`을 사용하고, Flutter Web 은 `story_terrain_web_view_web.dart`의 iframe `HtmlElementView`를 사용한다. Web 에서는 `WebViewController`를 만들지 않고, iframe 과 `window.postMessage`로 `ready`, `eventTap`, `landmarkTap`, 카메라/오버레이 갱신 JS 를 왕복시킨다. Web iframe 은 same-origin blob URL 로 로드하고, ready 메시지를 놓치지 않도록 parent message listener 를 먼저 붙인다. Web 의 platform view 가 Flutter UI 입력을 가로채지 않도록 상단 유틸리티 row, 홈 하단 선택 패널, floating action, 알림 dropdown, 지도 위 dialog/modal bottom sheet 는 `WebPointerInterceptor` 로 감싼다. Android/iOS 에서는 이 wrapper 가 child 를 그대로 반환하는 no-op 이다. Android WebView 에서는 Flutter gesture arena 가 지도 드래그/핀치를 빼앗지 않도록 eager gesture recognizer 를 사용하고, renderer OOM 을 줄이기 위해 worker/cache/antialias/pitch 를 제한한 저부하 모드로 terrain 을 끈다. Android Activity 는 WebView renderer exit 을 처리해 renderer 가 죽어도 앱 프로세스까지 종료되지 않게 한다. renderer 설정이 바뀔 때만 지도 HTML 을 새로 로드하고, 카메라 변화는 JS `easeTo()`/`fitBounds()`, country boundary/region polygon/라벨/path/event hit-zone 은 GeoJSON `setData()` 로 갱신한다. 사건 숫자/감정 핀과 non-region 랜드마크는 각각의 GeoJSON point 를 MapLibre DOM Marker 로 투영해 지역별 collision/terrain symbol 배치와 무관하게 좌표 위에 고정한다. 감정 핀은 노란 오로라를 상시 표시하고, 감정/선택/전환/도장 대상 사건은 DOM marker z-index 우선순위를 높여 겹친 핀 위에서도 숫자·감정이 보이게 한다. 인물 선택 이야기 경로는 선택 인물별 GeoJSON line feature 로 나뉘며 `colorForCharacter` 색상과 작은 offset 을 사용해 복수 인물 이동 점선을 함께 보여 준다. 줌/드래그/option-key 조작/지도 컨트롤 입력 직후에는 tap hit-test 를 짧게 무시해 커서 아래 region·랜드마크 팝업이 우발적으로 뜨지 않게 하고, 모바일 포인터 탭 직후 MapLibre click 이 중복으로 들어오면 추가 hit-test 를 무시한다. 지역 선택 단계에서는 투명한 region hit fill layer 를 `queryRenderedFeatures` 로 먼저 조회하고, iOS WebView/terrain 조합에서 hit 이 빠질 경우 화면 좌표를 위경도로 역변환해 polygon point-in-polygon 으로 다시 판정한다. 라벨뿐 아니라 폴리곤 내부 탭도 같은 지역 선택으로 처리하고, 겹친 region 은 작은 bbox 를 우선한다. 사건 0개 region 은 polygon/label/hit layer 에 올리지 않는다. 기본 지도 symbol label layer 는 숨겨 영어/현지어 지명 대신 앱의 한국어 라벨만 보이게 한다. JS channel 또는 Web postMessage 로 region/event tap 을 Flutter 로 전달한다. 확대/이동 중 발생하는 타일·서브리소스 실패는 debug 로그로만 남기고, 초기 MapLibre `ready` timeout 또는 main frame 실패만 지도 실패 안내로 표시한다. |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 인물 선택 + 이벤트 목록 통합. **헤더(`headerOverride`) 는 sticky** — `Column [header, Expanded(CustomScrollView)]` 구조로 사건 카드 스크롤 시 헤더(toggle + stepper) 가 함께 위로 사라지지 않는다. 헤더는 접기/펼치기 toggle 과 라벨형 stepper 를 유지하고, 이전/다음 액션은 홈 지도 위 큰 플로팅 버튼에서만 제공한다. step 2 인물 카드는 아바타 오른쪽 위에 `+N` 사건 수 배지를 올리고, 이름 아래에는 `characters.tagline`의 짧은 정체성 문구(왕국/왕 순서/대표 행적/함께 활동한 인물 등)를 표시한다. 카드 폭이 좁아도 한글 단어 중간이 끊기지 않도록 정체성 문구는 단어 단위로 짧게 줄바꿈하고, 여유 있는 고정 높이와 최대 3줄 설명으로 real 데이터의 긴 인물 문구도 overflow 없이 담는다. step 3 사건 카드(`EventTimelineRow`) 는 `committedSelectedCharacterCodes` + `colorForCommittedCharacter` 를 그대로 forwarding 해 카드 안 인물 pill 이 지도 path 색과 매칭된다. 최근 퀴즈 결과가 있으면 카드 배경색으로 상태를 표시한다(정답 0개=빨강, 일부 정답=주황, 모두 정답=초록). 감정 새김이 있으면 사건 카드 좌상단 배지를 컬러 감정 이모지로 바꾸고 우측 하단의 작은 초록 원에 이야기 순번을 함께 표시한다. 감정 새김 직후에는 상세 페이지를 잠시 닫고 0.5초 뒤 해당 사건 카드 위에 `CompletionCelebration` 감정 도장+별가루를 기존 속도로 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. |
| CharacterPanel | `widgets/character_panel.dart` | 인물 카드 (아바타, 설명) |
| ~~StoryListPanel~~ | ~~`widgets/story_list_panel.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| ParchmentDialog | `widgets/parchment_dialog.dart` | 이야기 상세 모달 |
| ParchmentPageScaffold | `widgets/parchment_page_scaffold.dart` | 양피지 배경 페이지 |
| ~~EraSelector~~ | ~~`widgets/era_selector.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| FontScaleBottomSheet | `widgets/font_scale_bottom_sheet.dart` | 글자 크기 3단계 선택 바텀시트 + `showFontScaleSheet` 헬퍼 |
| GameUiSkin | `widgets/game_ui_skin.dart` | 커스텀 UI 테마 데코레이션 |
| ~~SearchBox~~ | ~~`widgets/search_box.dart`~~ | 삭제됨 — SearchBottomSheet로 대체 (필요 시 재생성) |

### 5.2 story_home_screen에서 추출한 위젯 (2차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| ParchmentTextureLayer | `widgets/parchment_texture_layer.dart` | 양피지 질감 오버레이 |
| SubPageScaffold | `widgets/sub_page_scaffold.dart` | 서브 페이지 공통 레이아웃 (앱바+배경) |
| SubPageFloatingHomeButton | `widgets/sub_page_floating_home_button.dart` | 드래그 가능한 홈 버튼 |
| InlineLoginPromptCard | `widgets/inline_login_prompt_card.dart` | 인라인 로그인 카드. 기본 버튼 순서: 카카오 → Google. Apple 네이티브 로그인이 가능한 Apple 기기 앱에서만 Apple 버튼을 추가 노출한다. |
| ShareIdInputDialog | `widgets/share_id_input_dialog.dart` | 7자리 공유 ID 입력 다이얼로그 |
| ProfileEditorDialog | `widgets/profile_editor_dialog.dart` | 프로필(닉네임/사진/기도제목) 수정 |

### 5.3 story_home_screen에서 추출한 페이지 (3차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (ConsumerStatefulWidget, 콜백으로 동작). 상단은 제목 아래 작은 글씨로 사건 연대(`start_year/end_year/time_precision`)와 장소(`place_name`)를 보여 주고 별표 저장 토글을 우측에 둔다. **배경 지식 → 요약+장면 이미지 → 본문 읽고 퀴즈 풀기** 순서로 배치하며, `background_context`는 첫 번째 배경 지식 카드에 해설이 아닌 사실형 배경 1~2문장으로 표시한다. 이 문구는 절 주소나 이전/다음 링크, 시간순 구간명 대신 성경 흐름 안의 시대 배경과 사건 주제, 서신서 작성 배경을 알려 준다. 배경 지식 row 우측에는 사건 `character_codes`에 해당하는 등장인물 아바타를 겹치지 않는 가로 줄로 표시한다. 두 번째 카드에는 `요약: {summary}`를 한 문장으로 붙여 표시하고 같은 컨테이너 안에서 요약 아래에 장면 이미지 row를 둔다. 장면 이미지는 `scene_captions`가 있으면 이미지 하단 중앙에 한 줄 반투명 rounded overlay + 흰 글씨로 설명을 요약 표시하고 이미지를 누르면 자연스러운 카드 플립 애니메이션으로 전체 설명 뒷면을 보여 준다. 하나님이 있으면 가장 왼쪽에 둔 뒤 나머지는 한글 이름 가나다 순으로 나열하며, 각 아바타 하단 중앙에 이름 라벨을 얹는다. 본문 읽기 버튼은 사건의 모든 `bible_refs`를 성경 리더의 사건 읽기 모드로 전달한다. 리더에서 마지막 본문까지 보고 **읽기 완료**를 누른 경우에만 읽음 처리하며, 리더의 뒤로가기(`<`)로 나가면 읽음 처리하지 않는다. 퀴즈 결과는 정답/오답/헷갈림으로 나누고 `user_quiz_attempts`에 저장해 버튼 라벨과 프로필 지역 복습 팝업에 반영한다. 퀴즈 버튼은 `정답 N · 오답 N · 헷갈림 N` 형식으로 표시하고 정답 0개=빨강, 일부 정답=주황, 모두 정답=초록으로 칠한다. 본문 읽기 + 퀴즈 완료 후에만 **지도 위에 새기기** 버튼이 활성화되고, 8개 감정 중 하나와 100자 메모를 `user_event_emotion_marks`에 저장하면 사건 완료로 전환된다. 감정 선택 보기와 지도/카드 배지는 같은 컬러 감정 이모지 세트를 쓴다. 새김 완료 버튼은 `감정 - 메모` 형식으로 바로 보여 주고 "완료 취소"를 누르면 감정 row를 삭제해 지도 핀/카드 이모지도 제거한다. 감정 저장이 끝나면 부모 화면에 `onEmotionEngraved`를 알려 상세 페이지를 닫고 지도 핀/카드 감정 배지를 반영한 상태에서 0.5초 뒤 해당 지도 핀과 사건 카드 위 감정 도장+별가루를 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. 프로필 "장소로 시작"/"인물과 걷기"에서 열린 상세는 새김 또는 이전/다음 이동 시 프로필 route 를 닫고 홈 지도 route 를 드러내 같은 지도 애니메이션을 보여 준다. 지도 위 감정 도장 및 이전/다음 이야기 전환 애니메이션은 내부 재진입 가드로 중복 실행을 막되, 평상시 지도·패널·상단 버튼 입력은 차단하지 않는다. 이전/다음 이야기 카드를 누르면 상세 페이지를 닫고 지도 위 현재 사건과 목표 사건 번호 핀이 약 2초간 함께 빛난 뒤 목표 상세 페이지를 연다. 사역자/관리자에게만 **"이 이야기 삭제 제안"** 버튼 노출 (`_DeleteProposalButton` 서브 위젯). 이미 완료된 사건으로 진입한 경우 우측 "다음 이야기" 카드를 `PulseHighlight` 로 박동. |
| EventQuizDialog | `widgets/event_quiz_dialog.dart` | 사건 상세에서 쓰는 사건 퀴즈 다이얼로그. 선택 후 **정답 확인**을 누르면 해당 문항의 정답/오답/헷갈림과 해설을 즉시 보여 주고, **다음**으로 이동한다. 마지막에는 전체 문항, 내 선택, 해설 리뷰를 확인한 뒤 `EventQuizResult`로 저장 값을 반환한다. |
| CompletionCelebration | `widgets/completion_celebration.dart` | 자식 위젯을 감싸 GlobalKey 로 `play(stampLabel:)` 호출 시 두 단계 축하 효과: (1) 별가루 + 초록 글로우 1.2s, (2) 끝나면 금박 도장이 슬램+흔듦+페이드 0.95s. 기본 라벨은 "완료"지만 이야기 완료에서는 선택 감정 심볼을 넘긴다. 도장 종료 시 옵션 `onComplete` 콜백 호출. EventDetailPage 의 read+quiz 박스에 부착. |
| PulseHighlight | `widgets/pulse_highlight.dart` | `active` 인 동안 자식 외곽에 1.4s 사이클로 0→1→0 박동하는 골드 glow 를 그리는 래퍼. EventDetailPage 의 "다음 이야기" 카드에 부착해 다음 이동 동선을 시각적으로 유도. |
| AvatarProgressRing | `widgets/avatar_progress_ring.dart` | 아바타 둘레에 초록 원형 progress 호를 그리는 래퍼 (12시 방향 시계방향, 항상 초록). 옵션 `name` 을 주면 아바타 내부 하단에 솔리드 다크 pill 라벨을 오버레이해 외부 텍스트 라인을 제거. ProfileTabPage 인물 진행도 행에서 LinearProgressIndicator 대체로 사용. |
| EraPickRows | `widgets/v2/era_pick_rows.dart` | 시대 선택 칩 — 구약/신약 두 줄. HomeIntroPanel + ProfileTabPage 의 "장소로 시작" 탭 공유. 홈 인트로에서는 오른쪽 패널 끝까지 가로 레일을 쓰고, 마지막 칩이 둥근 모서리에 붙지 않도록 trailing scroll padding 을 둔다. 칩 라벨은 코드 기준 짧은 이름(`족장`, `출애굽`, `통일 왕국`, `사도`, `후기 사도` 등)을 쓰고, 검수 전 `era_nt_consummation`은 표시하지 않는다. `eraIconFor(code)` 도 export. |
| HomeIntroPanel | `widgets/v2/home_intro_panel.dart` | 첫 화면의 하단 선택 패널. 큰 인트로 제목은 패널 안에 두지 않고 `MapHintOverlay`의 캐릭터 가이드로 띄운다. 두 단계: ① **여행할 시대** (구약/신약 칩, 단일 선택) ② **어떻게 볼까요?** (`시간 순` / `인물과 걷기` / `장소로 시작` 3개 컴팩트 버튼). 글자 크기와 무관하게 1행 3열을 유지하며, `아주크게`에서는 카드 높이를 늘려 2줄 설명이 잘리지 않게 한다. 각 버튼은 아이콘+제목을 같은 줄에 두고 아래에 2줄 설명형 문구를 붙이며, `시간 순`을 누르면 바로 사건을 펼치지 않고 `TimelineUnitPickPanel`에서 시대 내부 구간을 복수 선택한 뒤 `다음`으로 사건 목록을 연다. 인물 버튼 설명은 `선택한 인물의 사건을 / 시간 순으로 봅니다`로 2줄 안에 들어가게 유지한다. 시대를 고른 뒤에는 ① 영역(헤더+칩) 이 `AnimatedOpacity` 0.55 로 흐려지고 입력이 잠겨, 다시 고를 때는 패널 위 큰 "시대 다시 선택" 버튼 또는 stepper 의 "시대/방법" 경로를 사용한다. ② 헤더는 `ink800` + 굵은 글씨로 차별화되어 다음 행동을 유도. 하단 안내 문구는 `FittedBox.scaleDown` + `maxLines:1` 로 좁은 폰에서도 1줄 보장하며, 홈 인트로 시트는 콘텐츠 높이에 맞춘 낮은 높이로 열어 아래 빈 양피지 공간을 줄인다. |
| TimelineUnitPickPanel | `widgets/v2/timeline_unit_pick_panel.dart` | 시간 순 보기 step 2. `StoryEvent.unitCode/unitTitle/unitOrder`로 이벤트를 묶어 낮은 가로 스크롤 카드 레일로 표시한다. 모바일 폭에서는 약 3.5개 카드가 보이고, 시트는 구간 개수와 무관하게 가로 1줄 레일 높이에 맞춘다. 상단에는 `구간 선택` 헤더와 `전체 선택`/`전체 해제` 토글을 둔다. 구간 카드는 기본 낮은 높이를 유지하되 `아주크게`에서는 제목 3줄과 설명 4줄을 모두 담도록 높이를 늘린다. 제목 앞에 시간순 번호를 붙이고, 선택 상태는 체크 아이콘 대신 연한 초록 배경으로만 드러낸다. 제목 바로 아래에 `N개 이야기`를 붙이고 남은 영역에는 구약/신약 curated 구간 설명을 25~35자 내외의 한 문장, 최대 4줄로 ellipsis 없이 보여 준다. 사용자가 하나 이상 구간을 선택하면 헤더의 초록 `N개 다음` pill 로 해당 구간의 사건만 시간순 reveal 한다. 구약 시대는 `assets/200_stories`의 curated `unit_*` 값으로 원역사 2개, 족장 3개, 출애굽 3개, 사사 3개, 왕정 3개, 분열왕국 5개, 포로/귀환 3개 구간이 보이도록 나눈다. |
| MapHintOverlay | `widgets/v2/map_hint_overlay.dart` | 지도 위 흐릿한 검정 캐릭터 가이드 말풍선. 반투명 오버레이 안에는 중앙 정렬 상단 배지 "화면 아무데나 누르면 사라집니다"와 상황별 안내 문구를 표시하고, 배지와 본문 사이에는 한 줄 정도 여백을 둔다. 안내 본문 왼쪽 원형 슬롯에는 `assets/avatars_thumbs/guide.png`를 중앙 기준 1.13배로 살짝 확대해 담고, 오른쪽 채팅 말풍선 안에 이모티콘 없는 안내 문장을 넣는다. 원형 슬롯 지름은 기본 48px 이며 첫 화면 안내에서만 70px 로 키워 캐릭터 표정을 더 잘 보이게 한다. 첫 화면 제목은 `FittedBox.scaleDown` + `maxLines:1` 로 좁은 폰에서도 한 줄을 유지하고, 단계 문구는 같은 본문 글자 크기를 유지해 줄마다 크기가 달라 보이지 않게 한다. 첫 화면 = 시대와 `시간 순·인물·장소` 선택 안내, 시대 선택 직후 = 선택한 시대 설명 + 보기 방식 선택 안내, region picker 단계 = "노란 지역을 눌러…", character step 2 = "인물을 골라 「다음」 버튼…", timeline step 2 = "구간 카드를 고른 뒤…" 메시지를 쓴다. 안내가 떠 있는 동안 지도·안내문·하단 시트 어디든 pointer down 이 들어오면 dismiss 한다. 지도 오버레이 영역은 `IgnorePointer` 로 입력을 막지 않아 첫 탭도 아래 MapLibre hit-test 로 전달되고, 하단 시트 입력은 힌트 dismiss 와 기존 버튼/스크롤 동작을 함께 처리한다. MapLibre 일반 탭도 `onMapInteraction` 으로 부모에 전달된다. 장소 선택 모드 전환 직후에는 버튼 터치 누수 방지 suppression 을 짧게 정리해 후속 region 탭을 빠르게 받는다. dismiss flag 는 `StoryHomeScreen._mapHintDismissed`. |
| ProfileMiniMap | `widgets/profile/profile_mini_map.dart` | 프로필 "장소로 시작" 탭의 미니 맵. 선택된 시대의 region 폴리곤을 진행률로 알파 채움(검정→시대컬러), 라벨에 완료 이야기 수와 지역 퀴즈 정답/풀이 수를 `x/x`로 함께 표시한다. region 폴리곤이나 라벨을 누르면 그 지역 사건 카드 팝업이 열리고, 사건 카드 순서대로 `순번 → 첫 장면 썸네일 → 제목/정답·오답·헷갈림`을 표시하며 빨강/주황/초록 복습 상태를 카드 배경색으로 보여 준다. 모든 사건에 감정이 새겨진 region 은 지도 색과 이질감이 적은 옅은 채움 + 골드 경계선만 남겨 딱지를 모은 느낌을 준다. point-in-polygon 으로 사건↔region 매핑. |
| ProfileEmotionDiary | `widgets/profile/profile_emotion_diary.dart` | 프로필 "나의 다이어리" 탭. `user_event_emotion_marks.updated_at`을 KST 날짜로 묶어 접힘 상태에서는 지난주+이번주 2주(일~토)를 보여 주고, 펼치면 해당 월 달력과 이전/다음 월 이동을 제공한다. 이전달 날짜가 지난주 줄에 걸리면 월간 보기와 같이 흐린 색으로 표시한다. 패널 헤더는 연도/월, 펼치기/접기 버튼, 펼친 상태의 이전/다음 달 버튼을 같은 줄에 배치한다. 날짜 셀은 카드/버튼 테두리 없이 표시하되 날짜 사이에 옅은 그리드 선을 두고, 오늘 날짜 숫자만 원형으로 강조한다. 감정이 없는 주는 날짜 숫자만 보이도록 낮은 row로, 감정이 있는 주는 해당 주에서 가장 많이 새긴 날짜 기준으로 1~2개=1줄, 3개 이상=2줄 높이를 확보한다. 하루 4개 이상은 달력 셀에 감정 3개와 `+x`를 보여 준다. `user_companion_diary_entries.entry_date`가 있는 날짜에는 날짜 숫자 옆에 작은 원형 `📝` 배지를 겹쳐 표시해 좁은 셀에서도 폭 overflow가 나지 않게 한다. 연도/월 헤더 위에는 감정 카테고리 8개 통계 칩을 개수순 4열로 표시하고, 칩을 누르면 해당 감정을 새긴 이야기 목록 팝업을 연다. 달력 아래에는 프로필 좌측 활동 탭처럼 "오늘의 동행 일지"와 "오늘의 내 감정" 선택 탭을 두며 기본값은 동행 일지다. 동행 일지 탭에서는 선택한 날짜의 일지를 하루 1개 작성/수정/삭제하고, 작성 전에는 안내 문구와 + 버튼, 작성 후에는 `CompanionDiaryEntryPreviewCard`로 `📝` 원형 배지 + 큰 제목 + 본문 최대 3줄을 표시한다. 미리보기 본문은 이모지 컬럼에 맞추지 않고 카드 왼쪽부터 쓰며, 카드를 탭하면 전체 본문 상세 팝업이 열리고 수정/삭제 버튼은 이 상세 팝업에만 둔다. + 버튼은 작성 후 숨긴다. "전체보기"는 동행 일지 탭 내용 아래쪽에 표시하고 `CompanionDiaryEntriesScreen`으로 이동한다. 오늘의 내 감정 탭은 선택한 날짜의 감정 row 목록만 표시하며 별도 우측 날짜 라벨은 두지 않는다. 감정 row를 누르면 홈 지도/지역 복원 준비를 기다리지 않고 사건 상세 페이지로 바로 진입하며, 짧은 전환 로딩만 패널 입력을 막는다. 같은 이야기에 감정을 다시 새기면 기존 row의 `updated_at`이 갱신되어 최신 날짜에만 나타난다. 재새김 저장 직후에는 프로필 경로에서 들어왔더라도 홈 지도 루트로 돌아와 해당 사건 핀 위 도장 애니메이션을 재생하고, 애니메이션 중 전체 홈 입력을 잠근다. |
| ProfileCompanionDiary | `widgets/profile/profile_companion_diary.dart` | 프로필 동행 일지 탭 콘텐츠. 달력에서 선택한 날짜의 일지 작성과 전체보기 진입 버튼을 담당하며, 작성된 일지는 공용 미리보기 카드와 상세 팝업에서 수정/삭제한다. 본문은 1000자까지 입력받는다. |
| CompanionDiaryEntryPreviewCard | `widgets/profile/companion_diary_entry_card.dart` | 프로필/전체보기에서 공유하는 동행 일지 미리보기 카드와 상세/편집/삭제 다이얼로그 헬퍼. |
| ProfileEmotionStats | `widgets/profile/profile_emotion_stats.dart` | 프로필 감정 통계 계산 헬퍼와 공용 칩 row. 감정을 새긴 고유 이야기 수, `EventEmotionOption`별 개수, 감정별 event id 목록을 제공하며, `ProfileEmotionDiary`가 달력 연월 헤더 위 통계 칩 UI로 재사용한다. |
| ProfileEventReviewGrid | `widgets/profile/profile_event_review_grid.dart` | 프로필 복습 사건 목록 공용 그리드. `StoryEventThumbCard`를 3열로 배치하고 첫 era 및 era 변경 지점만 가는 경계선+era 이름으로 표시한다. 기록 탭 오답/헷갈림 팝업이 공유한다. |
| StoryMapPanelController | `widgets/story_map_panel.dart` | 지도 외부 제어 API. 줌/포커스/reveal 외에 상세 페이지 이전/다음 이동용 `playEventTransition(from, to)` 로 현재/목표 사건 번호 핀을 함께 빛나게 하는 1회성 전환을 재생한다. 이 전환 카메라는 하단 선택 패널 padding 을 반영해 `fitBounds` 로 더 넓게 잡아 목표 원형핀이 패널 뒤에 숨지 않게 한다. `playEmotionStamp(event, stampLabel)` 은 감정 새김 직후 해당 핀 위에 지도 도장을 재생한다. 두 효과 모두 `map_math.buildRankedEventPointMap`의 분산 좌표를 사용해 번호 핀 중심과 맞춘다. |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (자체 상태 관리, 우측 별 아이콘으로 단일 구절 저장/해제). 새 저장 시 200자 묵상 코멘트 다이얼로그를 띄우며, 닫으면 빈 코멘트로 저장한다. 저장 취소는 `saved_verse_actions.dart` 공유 확인 로직을 사용해 코멘트가 있으면 확인 팝업, 없으면 즉시 취소 + 스낵바로 처리한다. 구절 본문 탭은 선택 상태를 만들지 않는다. 일반 진입은 책/장 탐색과 저장 구절 이동을 유지한다. 비로그인 상태에서 별표 저장이나 저장 말씀 버튼을 누르면 `onLoginRequired`로 홈의 3초 스낵바 + **이동** 액션을 띄운다. 이야기 상세에서 진입하면 사건 읽기 모드로 전환해 해당 `bible_refs` 범위의 절만 표시하고, 여러 본문이면 **다음**으로 순차 이동한 뒤 마지막에 **읽기 완료** 버튼을 보여 준다. 이 완료 버튼으로 닫힌 경우에만 사건 읽음 처리가 되며, 비로그인 상태에서는 저장 처리 대신 로그인 유도로 돌아간다. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 주간 탐험 탭. 인물/지역 모드 중 하나를 시드로 고르고 지도 + 하단 사건 카드 row 를 보여 준다. 카드 탭은 홈 지도/하단 패널을 해당 사건으로 준비한 뒤 기존 사건 상세로 진입하므로 진행도는 `user_event_progress`/`user_quiz_attempts`/`user_event_emotion_marks`와 그대로 연동된다. |
| ProfileTabPage | `widgets/profile_tab_page.dart` | `UsersRepository`, `ProfilesRepository`, `PrayerRequestsRepository`, `SavedVersesRepository`, `StoryProgressRepository`, `appUserProvider`, `userProfileProvider`, `userPrayerProvider`, `savedVersesProvider`, `userProgressProvider`, `userAnsweredQuizItemsProvider`를 사용해 프로필 상단 그리드와 활동 탭을 그린다. 좌측 탭 컨테이너는 탭과 콘텐츠 양에 맞춰 가변 높이로 잡고, 기도/저장/말씀처럼 정보가 적은 탭은 짧게, 기록 탭처럼 통계가 많은 탭은 한 화면에 카드가 보이도록 확장한다. 기록 탭은 퀴즈 통계만 세 개의 버튼형 카드로 아이콘+라벨과 문항/이야기 수를 2줄에 배치하며, 카드 높이와 간격을 확보해 텍스트가 중앙에 오도록 정렬한다. 감정 카테고리 8개 칩은 우측 진행도 영역의 `나의 다이어리` 달력 연월 헤더 위로 이동했다. 기도 탭은 최근 기도 제목 3개와 기도 작성 CTA, 저장 탭은 최근 푼 이야기 카드 3개와 전체 보기 CTA, 말씀 탭은 `SavedVerseRow` 디자인으로 저장한 말씀을 최신순 최대 3개와 `...`로 미리 보여 주고 하단 전체 보기로 `SavedVersesScreen`에 진입한다. 저장/말씀 탭을 누르면 각각 저장한 이야기와 저장한 말씀 미리보기를 다시 불러와 상세/성경 화면에서 방금 저장한 항목이 바로 반영되게 한다. 우측 진행도 영역은 `나의 다이어리 → 인물과 걷기 → 장소로 시작` 순서이며, 인물과 걷기 목록은 각 인물이 처음 등장한 이야기의 `globalRank` 기준으로 빠른 순서에 배치한다. 인물 상세 팝업의 사건 목록은 3열 고정 높이 카드 그리드로 표시해 제목·요약·인물 pill 이 작은 폭에서도 overflow 되지 않게 한다. 나의 다이어리는 한국 시간 기준 달력과 날짜별 감정 기록, 선택 날짜의 동행 일지 작성/수정/삭제, 동행 일지 전체보기를 제공하고, 감정 칩을 누르면 해당 감정을 새긴 이야기 목록을 연다. 최근 활동은 퀴즈 완료, 저장한 말씀, 기도, 감정 기록을 함께 섞어 최대 3개만 보여 준다. 설정 시트는 개인정보 보호, 지도 설명, 로그아웃을 제공하며, 지도 설명은 운영 지도 배경의 출처와 라이선스를 보여 준다. user_profiles에 이름/닉네임/아바타가 없으면 users row를 보강값으로 사용한다. |
| QuizTabPage | `widgets/quiz/quiz_tab_page.dart` | 홈 상단 "탐험" 버튼이 여는 페이지. 두 탭: **매일 탐험** (`DailyExplorationSection`, KST 날짜 시드로 오늘의 사건 1개 선택) + **주간 탐험** (embedded WeeklyTabPage). 둘 다 지도와 하단 사건 카드를 보여 주고, 카드 탭 시 홈 지도/하단 패널 경유로 기존 사건 상세에 진입한다. 알림 딥링크는 `/daily-exploration`(구 `/daily-quiz` 호환)과 `/weekly`를 지원한다. |
| DailyExplorationSection | `widgets/quiz/daily_exploration_section.dart` | 날짜 시드로 고른 오늘의 사건을 지도 + 사건 카드로 표시한다. 상단 소개 영역은 네비게이션 아이콘 + **오늘의 탐험** 라벨을 먼저 보여 주고, 그 아래 "오늘은 {시대 이모지+텍스트} {인물 avatar+텍스트}과 함께 {핀 이모지+장소}에 도착했어요." 문장을 별도 rounded chip 없이 배치한다. 소개 아래의 본 탐험 블록은 하나의 rounded rectangle 단위로 묶고, 맨 위에 나침반 이모지 + **오늘의 사건** 라벨을 둔다. 제목 아래에는 가운데 정렬된 "「사건명」 사건" 메인 버튼을 길게 배치하고, **인물 루트 / 장소 사건**은 `함께 보기` 보조 버튼 row로 분리한다. 매일 탐험의 핵심 CTA와 감정 문구는 오늘 사건 보기의 선택 버튼/사건 영역에만 표시한다. 인물 루트는 오늘 인물+시대의 전체 사건 흐름, 장소 사건은 오늘 장소/region+시대의 사건 묶음을 같은 지도와 `EventTimelineRow`로 보여 주는 보조 탐색이며, 지도 위 인물 코드 legend 는 숨긴다. 장소 사건은 1개만 있어도 눌러 볼 수 있고, 해당 조합에 포함된 사건 수를 그대로 표시한다. 본 탐험 블록 안에서 버튼 row 아래 지도 높이를 확보하고, 필요하면 구분선/사건 카드 row는 세로 스크롤 아래에서 이어 보여 준다. 해당 사건에 오늘 KST 감정을 새겼으면 축복 문구, 이전 날짜 감정만 있으면 재탐험 문구를 구분선 아래에 표시한다. 별도 daily DB 없이 기존 사건 상세 진행도에 연동된다. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 주간 탐험 (embedded 모드 지원). **두 모드** — `WeeklyMode.character` (랜덤 인물 + 그 인물의 사건) / `WeeklyMode.region` (랜덤 시대 + 사건이 있는 랜덤 region + 그 region 사건). 시드(`seedFromKey(weekKey)`)로 50/50 결정. 헤더는 모드별 분기 ("금주 인물" / "금주 지역: 시대 · 지역"). 지도 = StoryMapPanel(decorate=false, region 모드는 `eraRegionLandmarks: [region]`). 하단 = EventTimelineRow (홈과 동일 카드/스크롤/포커스 동기). 카드 탭은 일반 사건 상세로 이어져 프로필 진행도와 연동된다. 주간 인물 지도 legend 는 상단 헤더와 중복되므로 숨기며, 매일 탐험 전용 재탐험/축복 문구는 표시하지 않는다. |
| CharacterAvatar | `widgets/character_avatar.dart` | 인물 아바타 (주간/프로필 공용) |

비로그인 상태에서 사건 상세 **퀴즈 시작**,
성경 구절 별표/저장 말씀 버튼, 사건 읽기 완료 저장, 이야기 저장/감정 새김처럼
사용자별 저장이 필요한 액션을 누르면 `StoryHomeScreen`의 공통 로그인 유도
스낵바가 3초 표시되고 **이동** 액션으로 `ProfileTabPage` 로그인 카드에 진입한다.

### 5.4 도메인 횡단 공유 위젯 (4차 리팩토링)

| 위젯 | 파일 | 사용처 |
|------|------|--------|
| EventShortPopup | `widgets/shared/event_short_popup.dart` | story_map_panel 콜아웃 + weekly_tab_page 단축 팝업 |

### 5.6 Notifications (2026-04-22)

| 위젯/파일 | 파일 | 역할 |
|----------|------|------|
| NotificationBellButton | `widgets/notification/notification_bell_button.dart` | 상단 종 아이콘 + 배지, Overlay 드롭다운 관리 |
| NotificationBadge | `widgets/notification/notification_badge.dart` | 빨간색 ! 배지 (미독 1개 이상 시 표시) |
| NotificationDropdown | `widgets/notification/notification_dropdown.dart` | bell 탭 시 열리는 팝오버 — 미독 5개 + "모두 읽음" / "전체 보기" |
| NotificationListTile | `widgets/notification/notification_list_tile.dart` | 드롭다운/히스토리 공용 row (타입별 아이콘, 상대시간, 미독 점) |
| NotificationDeepLink | `widgets/notification/notification_deep_link.dart` | deep_link 파싱 + 모바일/태블릿 "컴퓨터로 확인" 다이얼로그 |
| PushService | `services/push_service.dart` | FCM 토큰 발급/등록, 포그라운드 메시지 handler |
| AppNotification 모델 | `models/app_notification.dart` | `list_my_notifications` RPC 반환 row 파싱 |
| Providers | `state/notification_providers.dart` | `unreadNotificationCountProvider` (polling Stream) + 목록 Future providers |

Firebase 설정 가이드: `docs/guides/PUSH_SETUP.md`. 인프라 전반 원리: `docs/guides/INFRA_GUIDE.md`.

### 5.7 Proposal (사역자 제안 워크플로)

| 위젯/파일 | 파일 | 역할 |
|----------|------|------|
| BibleRefsPicker | `widgets/proposal/bible_refs_picker.dart` | 성경 구절 참조 picker |
| CharacterCodesPicker | `widgets/proposal/character_codes_picker.dart` | 기존 characters 다중 선택 |
| NewCharacterDialog | `widgets/proposal/new_character_dialog.dart` | 신규 캐릭터(아바타 포함) 생성 다이얼로그 |
| ProposalCharacterRow | `widgets/proposal/proposal_character_row.dart` | 선택된 등장인물 아바타 줄 |
| ProposalLocationPicker | `widgets/proposal/proposal_location_picker.dart` | 지도 핀 선택 |
| ProposalScenesEditor | `widgets/proposal/proposal_scenes_editor.dart` | 장면 텍스트 + 장면 이미지 편집 |
| ProposalStatusChip | `widgets/proposal/proposal_status_chip.dart` | pending/approved/rejected 칩 |
| SceneCharactersGrid | `widgets/proposal/scene_characters_grid.dart` | 장면별 등장 인물 체크 그리드 |
| **ProposalQuizEditor** | `widgets/proposal/proposal_quiz_editor.dart` | 목회자 작성 선택지 3개 퀴즈 1~3개 편집기. 사용자용 4번 보기 "헷갈렸어요"는 승인 시 자동 추가. Step 4 에서 사용. |
| **DeleteEventProposalSheet** | `widgets/proposal/delete_event_proposal_sheet.dart` | 기존 이야기 삭제 제안 바텀시트 (2026-04-22). EventDetailPage 에서 호출. |
| **ApproveProposalDialog** | `widgets/proposal/approve_proposal_dialog.dart` | 관리자 새 이야기 승인 전 최종 검토. 같은 era 의 현재 이야기 목록에서 삽입 위치를 override 하고, 신규/기존 등장인물의 `is_active` 노출 여부를 확정한다. |

### 5.5 큰 화면의 part 파일 분해 (4차 리팩토링)

대규모 파일(>1,000줄)을 도메인별 part 파일로 분해해 가독성 향상. 동작은 동일.

| 부모 파일 | 분해 후 줄 수 | part 파일 |
|----------|-------------|----------|
| `widgets/story_selection_panel.dart` | 1648 → 561 (−66%) | `selection/panel_chrome.dart` (~280)<br>`selection/step_chip.dart` (~340)<br>`selection/selection_cards.dart` (~465) |
| `widgets/story_map_panel.dart` | 3D 지도 orchestration + 상태 part 로 정리 | `story_map_panel_state.dart`<br>`story_map_panel_widgets.dart`<br>`map/story_terrain_3d_map.dart`<br>+ 순수 좌표 함수 → `utils/map_math.dart` |
| `widgets/profile_tab_page.dart` | 2628 → 1755 (−33%) | `profile/profile_character_overview.dart` (~400)<br>`profile/profile_intercessory_prayer.dart` (~225)<br>`profile/profile_helpers.dart` (~260)<br>`profile/profile_left_panel.dart`<br>`profile/profile_right_panel.dart` (헬퍼만 잔존)<br>`profile/profile_progress_section.dart` (2026-05-08, "진행률 표시" 섹션)<br>`profile/profile_settings_sheet.dart` (2026-05-08, 설정 시트) |
| `widgets/weekly_tab_page.dart` | 884 → 574 (−35%) | `weekly/weekly_avatar.dart` (~67)<br>`weekly/weekly_list_panel.dart` (~258)<br>+ 순수 함수 3개 → `utils/weekly_selection.dart` |

### ProfileTabPage 외부 콜백

`ProfileTabPage`는 자체 상태(25+개 필드)를 내부에서 모두 관리하며, 외부 의존성은 콜백 3개로만 노출된다:

```dart
ProfileTabPage(
  key: _profileTabKey,  // ← 퀴즈 완료 후 진행도 새로고침용
  onStartQuiz: (eventId) => ...,
  onOpenEventDetail: (event, {source, sourceId}) => ...,
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
| `storySceneRow(...)` | Widget | 4장면 이미지 가로 배열 + 선택적 하단 캡션 overlay |
| `bibleMoveButton(...)` | Widget | "이동" 액션 버튼 (성경 리더) |
| `lockedPreviewOverlay(...)` | Widget | 잠금 프리뷰 오버레이 |

## 6. 의존 패키지

| 패키지 | 버전 | 용도 |
|--------|------|------|
| flutter_riverpod | ^2.6.1 | 상태 관리 |
| supabase_flutter | ^2.9.1 | Supabase SDK |
| flutter_map | ^8.2.1 | 프로필 미니맵/제안 위치 선택기 등 보조 2D 지도와 `LatLngBounds` 유틸 |
| latlong2 | ^0.9.1 | 좌표 계산 |
| google_sign_in | ^6.3.0 | Android Google 네이티브 로그인 |
| shared_preferences | ^2.5.5 | 로컬 키-값 저장 (글자 크기 등 사용자 선호 설정) |
| sign_in_with_apple | ^6.1.4 | Apple 네이티브 로그인 (iOS/macOS 앱 전용) |
| image_picker | ^1.1.2 | 프로필 이미지 |
| crypto | ^3.0.6 | SHA256 (Apple 로그인 nonce) |
| cupertino_icons | ^1.0.8 | iOS 스타일 아이콘 |
| firebase_core | ^3.8.0 | Firebase 초기화 (FCM) |
| firebase_messaging | ^15.1.5 | FCM 토큰/메시지 — 푸시 알림 |
| flutter_local_notifications | ^18.0.1 | 포그라운드 로컬 알림 (iOS/Android) |

## 7. 코딩 컨벤션

- **포맷**: `dart format` (Dart 공식 스타일)
- **린트**: `flutter_lints` 5.0 (`analysis_options.yaml`)
- **네이밍**: Dart 공식 — `camelCase` 변수, `PascalCase` 클래스
- **UI 텍스트**: 한국어로 작성
- **위젯**: `ConsumerWidget` 또는 `ConsumerStatefulWidget` (Riverpod)
- **상수**: `const` 생성자 최대 활용
- **에러 처리**: try-catch + `state.copyWith(error: ...)` 패턴
