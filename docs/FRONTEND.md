# 프론트엔드 도메인 레퍼런스

> 이 문서는 `.agents/skills/frontend` 스킬이 참조하는 프론트엔드 도메인 가이드이다.
> UI/UX 상세는 `docs/UI_GUIDE.md`를 함께 참조.

## 1. 파일 범위

```
lib/
├── main.dart                          # Firebase 모니터링 + Supabase 초기화 엔트리포인트
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
    ├── bible_book_meta.dart           # 성경 책/장 메타데이터 + 권 이름 정경 순 정규화
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
- 오늘 지도 현재 핀은 `loadThumbnailDataUrlForEvent()`로 첫 장면을 data URL로 변환한다. 일반 로딩 결과가 비어도 썸네일 인덱스의 짧은 디렉토리와 `scene_01` 후보를 직접 확인하며, 일시적인 실패 결과는 캐시하지 않아 다시 시도할 수 있다.

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
| SavedBibleVerse | `models/saved_bible_verse.dart` | id, userId, translation, bookNo, bookName, chapterNo, verseNo, verseText, comment, isSaved, highlightColor, createdAt, updatedAt | `SavedBibleVerse.fromMap()` |
| UserCompanionDiaryEntry | `models/user_companion_diary_entry.dart` | id, userId, entryDate, title, body, createdAt, updatedAt | `UserCompanionDiaryEntry.fromMap()` |
| QuizQuestion | `models/quiz_question.dart` | id, question, choices, answerIndex, explanation, `confusedChoiceLabel` | 생성자 직접 |
| QuizAttemptSummary | `models/quiz_attempt_summary.dart` | eventId, correctCount, totalCount, wrongCount, confusedCount, selectedAnswers, updatedAt, needsReview | `QuizAttemptSummary.fromMap()` |
| EventProposal | `models/event_proposal.dart` | id, proposalType ('new'/'delete'), targetEventId, 제안 본문 전체 필드, proposedCharacters, quizQuestions, status, reviewed* | `EventProposal.fromMap()` |
| QuizDraft | `models/event_proposal.dart` | question, choices(3), answerIndex(0~2), explanation. `isValid` getter 로 목회자 작성 선택지 3개 + 해설 필수 검증. | `QuizDraft.fromMap()` / `.toMap()` |
| ProposedCharacter | `models/event_proposal.dart` | code, name, prompt, storagePath. 제안 시 신규 생성한 캐릭터 메타 | `ProposedCharacter.fromMap()` |
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
dailyExplorationJourneyProvider // FutureProvider<List<StoryEvent>>, KST 날짜별 이전·오늘·다음 추천 사건
dailyExplorationCatalogProvider // 전체 시대 사건을 단일 조회해 오늘 탐험 덱과 내정보에 공유
dailyMissionEventProvider       // 위 journey의 오늘 사건을 제공하는 호환 provider

// auth_providers.dart
authStateProvider               // StreamProvider<AuthState>

// font_scale_providers.dart
fontScaleRepositoryProvider     // Provider<FontScaleRepository>
fontScaleProvider               // NotifierProvider<FontScaleController, FontScale>
```

### 3.1.1 FontScale / ColorPalette (앱 전역 표시 설정)

`state/font_scale_providers.dart` — `FontScale` enum(`normal` 1.0x / `large` 1.2x / `veryLarge` 1.4x)과 Riverpod 프로바이더. 표시 라벨은 `작게` / `보통` / `크게`이며, 저장값이 없는 새 설치의 기본값은 `보통`(1.2x)이다. 저장 키는 표시 의미에 맞춘 `small` / `normal` / `large`를 쓰고, 이전 키 `normal` / `large` / `veryLarge`도 바뀐 라벨의 의미를 유지하도록 각각 `보통` / `크게` / `크게`로 이관한다. `fontScaleBuilder`가 `MediaQuery.textScaler`에 주입해 앱 전역 텍스트에 적용된다. 저장소는 `data/font_scale_repository.dart`의 `SharedPreferences` 래퍼 사용. `veryLarge`에서는 공통 버튼, 홈 선택 카드, 이야기 썸네일 카드의 핵심 텍스트를 줄바꿈·가변 높이·내부 스크롤 중 하나로 끝까지 읽게 한다. 예외로 이야기 상세 장면 카드의 이미지 앞면 캡션은 이미지를 가리지 않도록 모든 배율에서 한 줄 말줄임표로 고정하고, 전체 설명은 카드를 뒤집은 뒷면에서 스크롤해 읽는다.

`state/color_palette_providers.dart` — `AppColorPalette` enum(`classic` / `atlasNavy` / `colorfulMap` / `blackMap`)과 Riverpod 프로바이더. 표시 라벨은 `클래식` / `네이비` / `파스텔` / `다크`이며, 저장값이 없는 새 설치의 기본값은 `네이비`다. `classic`은 main 브랜치의 어두운 올리브 chrome과 베이지 패널, `atlasNavy`는 네이비/청록, `colorfulMap`은 파스텔 보라 primary 와 청록·오렌지·핑크 역할색, `blackMap`은 검은 지도 톤과 금빛 포인트를 사용한다. 다크 팔레트의 `primary`/`primaryDeep`은 어두운 표면색이 아니라 다크 표면 위에서 보이는 청록 액션색이며, `panelSurface`는 불투명한 어두운 표면으로 유지한다. `StoryBibleApp`이 선택된 팔레트로 `AppTheme.light(palette:)`를 다시 만들고, `AppPaletteTheme` extension을 통해 공통 버튼, 홈 상단 유틸리티 버튼, 선택 시트 배경/질감/핸들, 시대·인물·구간 선택 카드, 사건 카드 표면/텍스트, 스텝퍼, 주간 미션 헤더/사건 row, 프로필 요약/다이어리/통독/캘린더, 공지사항 리스트, 프로필 수정/설정 시트, 통독 진행률 페이지, 성경 본문 절 번호, 구절 검색 그리드, 알림 패널, 이야기 카드 선택/완료 테두리에 같은 색 조합을 적용한다. 밝은 고정 표면과 다크 팔레트의 밝은 텍스트를 섞지 않도록 `cardSurface`, `softSurface`, `mutedSurface`, `text`, `mutedText`를 함께 사용한다. 프로필의 흰색 쉘은 다크 팔레트에서 검은 쉘로 바꾸고, 홈 스크롤 선택 패널과 스테퍼는 같은 팔레트 표면으로 이어지게 한다. `FontScaleBottomSheet`의 `다크` 색 조합 미리보기는 액션색 대신 `pageBottom`/`panelSurface`/`cardSurface`/`currentFill`을 써서 선택 전에도 어두운 조합으로 보이게 한다. 저장소는 `data/color_palette_repository.dart`의 `SharedPreferences` 래퍼 사용. 제거된 `brightCoast` 또는 알 수 없는 저장값은 `atlasNavy`로 보정된다.

### 3.1.2 하단 시스템 inset 정규화

`utils/system_insets.dart` — 일부 모바일 WebView/브라우저가 내비게이션 바가 없어도 작은 `MediaQuery.padding.bottom` 값을 보고하는 문제를 막는다. `MaterialApp.builder`의 `fontScaleBuilder`가 작은 bottom inset(16px 미만)을 0으로 정규화해 gesture-only/내비바 없음 환경에서는 화면 맨 아래까지 쓰고, 홈 인디케이터나 3-button 내비게이션처럼 의미 있는 inset 은 그대로 보존한다. 루트 `Scaffold.bottomNavigationBar`가 이 시스템 안전영역을 이미 포함하므로 `StoryHomeScreen`의 지도 하단 시트는 본문 안에서 같은 inset 을 다시 더하지 않는다.

루트 `StoryRootNavigationBar`는 `SafeArea` 바깥까지 동일한 불투명 팔레트 표면을
칠하고, `StoryHomeScreen`의 `SystemUiOverlayStyle`도 같은 색을 시스템
내비게이션 바에 적용한다. gesture-only 기기는 앱 바가 화면 끝까지 이어지고,
홈 인디케이터나 3-button 영역이 있으면 탭 콘텐츠는 그 위에 놓이면서 시스템 영역
배경만 같은 색으로 자연스럽게 이어진다.

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
| `initialize()` | 앱 시작 시 eras를 로드하고 사용자 기록 5종과 landmarks를 병렬 조회한다. 동시 호출은 같은 Future를 공유한다. |
| `selectTestament(String)` | 구약/신약 전환 |
| `selectEra(String)` | 시대 단수 선택 → characters + events만 병렬 로드. 전역 사용자 기록은 다시 조회하지 않는다. |
| `refreshUserScopedData()` | 인증 전환/당겨서 새로고침 시 진행·감정·저장·통독·퀴즈 기록을 병렬 조회해 한 번의 상태 변경으로 반영 |
| `toggleEraMulti(String)` | v2 — 시대 멀티 선택 토글 |
| `setSelectedEras(Set<String>)` | v2 — 여러 시대 events/characters 합산 |
| `setSelectionMode(SelectionMode)` | v2 — timeline/region/character 모드 진입 |
| `clearMapExplorationSelection()` | 루트 지도 탭 진입·이탈 시 시대·방법·사건 선택만 비우고 사용자 진행 기록은 유지 |
| `selectLandmark(String?)` | v2 — region 모드에서 선택된 landmark 변경 |
| `toggleCharacter(String code)` | 인물 선택/해제 토글 (person.code 기반) |
| `selectEvent(String?)` | 이벤트 선택/해제 |
| `setBibleRead(...)` / `setQuizCompleted(...)` | 부분 진행도 저장. 둘 다 완료되면 감정 새김 버튼이 열린다 |
| `setEmotionMark(...)` | 감정/100자 메모 저장 후 읽기+퀴즈+감정 조건이 모두 맞으면 완료 처리. 상세 UI의 메모 입력칸은 한 줄부터 최대 5줄까지 실시간 확장한다 |
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
| StoryHomeScreen | `screens/story_home_screen.dart` | 앱 루트 셸. 화면 폭 `StoryRootNavigationBar`로 `오늘`·`성경`·`지도`·`내정보` 4개 탭을 전환한다. `오늘`은 구약 7시대→신약 3시대와 각 시대의 `rankInEra`를 절대 순서로 삼고, 가장 최근 감정 새기기 다음 사건(기록이 없으면 원역사 첫 사건)을 현재 추천으로 삼는다. 현재 시대 전체 번호 핀과 사건 사이 점선, 낮은 `다이어리`/`통독` 액션을 보여 준다. 상단 `오늘` 헤더는 로그인 프로필 닉네임과 KST 당일 탐험 수·다이어리 작성 여부·통독 장 수, 세 활동 중 하나 이상을 한 날짜의 연속일을 표시한다. 비로그인은 사용자 활동을 노출하지 않고 연속 0일부터 시작한다. 당일 활동으로 연속일이 올라가면 연속 라벨 내용을 흐리게 하고 중앙의 큰 불 아이콘을 더 또렷하게 확대·축소 반복하며, 불 뒤의 은은한 글로우와 네 방향 반짝임을 함께 표시한다. 반짝임은 밝은 팔레트에서 각 팔레트의 진한 주색을 쓰고 다크에서만 금빛을 유지한다. 완료한 이야기·다이어리·통독 라벨 중앙에는 큰 완료 마크를 표시한다. KST 자정 타이머가 당일 수치를 0/x/0으로 다시 계산하며, 연속 라벨은 세 완료 기준 안내 팝업을 연다. 헤더 전체의 탭·드래그와 안내 팝업 입력은 뒤쪽 지도에 전달하지 않는다. `오늘`과 `지도`는 공유 `GlobalKey`와 `StoryMapPanelController`로 하나의 지도 상태를 재부착해 WebView 재로딩을 피한다. 오늘 지도는 패널 밖에서 팬/줌/회전을 허용하고, 패널 입력 중에만 gesture suspension을 적용한다. 루트 네비게이션 표면은 시스템 하단 영역까지 같은 색으로 이어진다. `지도` 루트 탭은 진입과 이탈 양쪽에서 시대·방법·사건 선택을 비우므로 `오늘`의 현재 시대를 물려받지 않고 매번 시대/방법 선택부터 시작한다. 다이어리/통독은 비로그인 시 `내정보로 이동` 팝업으로 `내정보` 탭을 열며, 로그인 상태에서는 오늘 다이어리 작성·상세·수정·삭제와 다음 통독 위치 이동을 지원한다. 사건 상세의 읽기·퀴즈도 같은 팝업을 사용한다. 기존 시대·시간순·인물·장소 탐색은 `지도` 탭으로 유지한다. |
| BibleVerseSearchScreen | `screens/bible_verse_search_screen.dart` | `오늘` 탭 상단 돋보기에서 여는 구절 기반 이야기 검색 화면. 신약/구약, 권, 장, 절을 고르면 `events_ordered.bible_refs` 범위에 해당 절이 포함된 이야기를 지도와 요약 없는 공용 카드로 보여 준다. 제목·장소·등장인물은 각각 한 줄 가로 수동 스크롤로 끝까지 확인하며, 카드 탭은 기존 `EventDetailPage` 흐름으로 이어진다. 현재 절 배경은 셀의 왼쪽·위쪽 테두리에서 3px 안으로 넣는다. |
| ~~LoginScreen~~ | ~~`screens/login_screen.dart`~~ | 삭제됨 — InlineLoginPromptCard로 대체 |
| SavedVersesScreen | `screens/saved_verses_screen.dart` | 저장한 성경 구절 전체보기. 상단에는 아이콘형 이전 버튼과 `저장한 성경 구절` 제목을 같은 row에 두고, 본문 카드는 좌측 버튼 폭에 밀리지 않고 화면 가로 공간을 모두 사용한다. `<`는 호출한 내정보/성경 화면으로 돌아가고, 말씀 row를 누르면 목록 route를 즉시 닫아 해당 권·장·절을 바로 표시한다. |
| CompanionDiaryEntriesScreen | `screens/companion_diary_entries_screen.dart` | 프로필 `다이어리` 카드/chevron 탭에서 여는 전체보기. `이번 달`을 기본으로 하고 `전체`·`이번 달` 필터와 월 기록일/연속일을 보여 준다. 별도 날짜 헤더는 두지 않고, 카드 첫 줄의 제목 오른쪽에 `날짜 · KST 시간`을 표시한다. 아주 큰 글자에서는 날짜·시간 줄 수를 제한하지 않아 줄임표 없이 전부 표시한다. 항목을 누르면 상세 팝업에서 수정/삭제한다. |
| BibleProgressScreen | `screens/bible_progress_screen.dart` | 프로필 `통독 진행률` 카드/chevron에서 여는 전용 페이지. 기존 구약·신약/권 선택과 장별 완료 표, 권별 완료율을 팔레트 표면 위에 유지하며 장을 누르면 해당 성경 리더로 이동한다. 완료 장 배경은 셀의 왼쪽·위쪽 외곽선 안으로 3px 들어와 테두리를 덮지 않는다. 팝업이나 페이지 안 `이어읽기` 액션은 사용하지 않는다. |
| CompanionDiaryEditorScreen | `screens/companion_diary_editor_screen.dart` | 다이어리 작성·수정 전용 페이지. 날짜, 선택 제목, 1000자 본문, 감사·기도·말씀 묵상·하루 돌아보기 질문, 비공개 안내와 하단 저장 버튼을 팔레트 토큰으로 렌더링한다. 오늘의 말씀 연결 영역은 두지 않으며, 비어 있는 제목은 `제목 없는 다이어리`로 저장한다. |
| AppPublicationsScreen | `screens/app_publications_screen.dart` | 프로필 헤더의 메가폰에서 여는 공지사항/사용법 목록. 가장 밖 표면은 테두리 없이 음영만 두고, 공지 사이에는 구분선을 두지 않는다. 상세의 본문 URL 줄 또는 `link_url`은 자동 링크 줄로 렌더링해 `url_launcher`로 외부 브라우저에서 연다. 별도 링크 액션 버튼은 두지 않는다. |
| LegalDocumentsScreen | `screens/legal_documents_screen.dart` | 설정의 `개인정보 보호`에서 여는 법률 문서 목록과 상세. 본문을 감싸는 가장 밖 표면은 테두리 없이 음영으로만 배경과 구분한다. |
| ProposalBoardScreen | `screens/proposal_board_screen.dart` | 제안 게시판 (웹 전용) |
| ProposalSubmitScreen | `screens/proposal_submit_screen.dart` | 새 이야기 제안 작성/수정 (5-step wizard: 안내 → 시대 → 인물·위치 → 세부 → **퀴즈**). Step 3의 시간순 구간은 선택한 시대의 기존 `StoryEvent.unitCode/unitTitle/unitOrder` 후보를 드롭다운으로 고르며, 새 구간 코드를 직접 추가하지 않는다. 마지막 Step 4 는 목회자 작성 선택지 3개 퀴즈 1~3문항 + 제출 버튼. |
| ProposalDetailScreen | `screens/proposal_detail_screen.dart` | 제안 상세 + 댓글. `proposal_type='delete'` 일 때 빨간 삭제 제안 배너 + "수정" 버튼 비노출 + 승인 시 `approveDelete` 분기. 새 이야기 승인은 위치 override + 등장인물 노출 여부를 다이얼로그에서 함께 확정한다. 같은 위치 제안이 먼저 승인되어 무효화된 pending 제안도 관리자가 새 위치를 골라 바로 승인할 수 있다. |
| NotificationHistoryScreen | `screens/notification_history_screen.dart` | 알림 전체보기 (최근 30일, 2026-04-22). AppBar, 빈 상태, divider, 알림 타입 아이콘은 현재 색 조합을 따른다. |

`StoryHomeScreen`은 사건 상세 진입 시 도장을 재생할 지도 루트도 함께 보존한다. `오늘`의 현재 이야기에서 감정을 새기면 공유 지도를 `오늘` 표현으로 유지한 채 해당 사건을 잠시 현재 위치로 고정해 도장을 재생하고, 상세의 `<`도 `오늘`로 돌아간다. `지도`에서 필터링한 사건은 기존 필터를 복원한 `지도` 위에서 도장을 재생하고 `<`도 `지도`로 돌아간다. 장 단위 통독 읽음 시각은 낙관적 상태와 Supabase payload 모두 UTC로 정규화하며, 프로필 달력과 오늘 활동 집계에서만 KST 날짜로 변환한다.

인증 사용자 ID가 바뀌거나 로그아웃되면 루트의 `StoryHomeScreen`이 `StoryController.clearUserScopedData()`를 한 번 호출한다. 단독 route로 쓰는 `ProfileTabPage`만 자체 초기화한다. 공개 시대·이야기·지도 탐색 상태는 유지하되 완료/본문/퀴즈 결과, 감정 새김, 저장 이야기, 통독 장·읽음 시각을 모두 비우며, 내정보가 별도로 들고 있는 프로필·저장 말씀·다이어리·중보기도 미리보기 캐시도 함께 폐기한다. 로그아웃 전에 시작된 비동기 조회는 인증 전환 revision 또는 사용자 ID가 달라지면 결과를 반영하지 않는다.

> **리팩토링 상태**: `story_home_screen.dart`는 초기 7,172줄 → 현재 ~1,016줄 (−86%).
> 프로필 탭 2,700+줄이 `ProfileTabPage`로 분리되어 자체 상태 관리 + 외부 콜백으로 결합도 최소화.
> 퀴즈 완료 시 진행도 새로고침은 `GlobalKey<ProfileTabPageState>`로 처리.

## 5. 위젯 (Widgets)

### 5.1 도메인 위젯

| 위젯 | 파일 | 역할 |
|------|------|------|
| TodayActivityHeader | `widgets/home/today_activity_header.dart` | 상태바 안전영역까지 덮는 모서리 없는 전체 폭 헤더다. 하단 `StoryRootNavigationBar`와 같은 팔레트 표면색을 쓰고, `오늘` 제목과 해 아이콘 없이 `샬롬 👋 {닉네임}님,`과 `오늘도 주님과 함께 걸어볼까요!`를 두 줄로 표시한다. 닉네임만 14.2px로 아주 살짝 키우며 비로그인은 `사용자`를 쓴다. 초대 문구 아래에는 활동 라벨을 포함한다. |
| TodayActivityLabelRail | `widgets/home/today_activity_header.dart` | 헤더 내부 초대 문구 아래에 KST 당일 `연속:`·`이야기:`·`다이어리:`·`통독:` 네 라벨을 고정 4열로 둔다. 연속 조건을 채우면 불 아이콘만 더 또렷하게 커졌다 작아지고 은은한 금빛 글로우와 네 방향 반짝임이 반복되며, 밝은 팔레트의 반짝임은 배경 대비가 높은 `primaryDeep`, 다크는 금빛을 사용한다. 이야기·다이어리·통독의 완료 체크는 정적으로 유지한다. 불·이야기는 단색 Material 아이콘, 다이어리·통독은 내정보의 `edit_note`·`menu_book` 아이콘과 맞춘다. 네 활동 아이콘은 `TodayActivityIcons`에 모아 오늘 할 일 가이드와 같은 glyph를 공유한다. 가로 스크롤 없이 축소 적응하며, 연속 라벨은 산정 기준 팝업을 연다. |
| TodayHomePage | `widgets/home/today_home_page.dart` | 조작 가능한 공유 3D 지도 위에 전체 폭 `TodayActivityHeader`, 40px 영역과 17px 아이콘의 `찾기`·`큰글자`·`테마`, 이야기 덱과 퀵 액션 카드를 조합한다. 유틸리티 버튼 테두리는 퀵 액션 카드처럼 역할색 20%로 옅게 표시한다. 오늘 탭이 활성화될 때마다 가이드 PNG 없이 `TodayTodoGuide`의 68% 불투명 팔레트 프레임 안에 테마별 내부 패널을 두고, `[불 아이콘] 매일 할 일: [이야기 아이콘] 이야기, [다이어리 아이콘] 다이어리, [통독 아이콘] 통독`과 가운데 정렬된 `(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)`를 안내한다. 클래식·네이비·파스텔은 84% 불투명 밝은 종이색, 다크는 88% 불투명 다크 카드 표면과 흰색 계열 `text`·`mutedText`를 사용한다. 네 단색 활동 아이콘은 헤더 라벨과 같은 `TodayActivityIcons`와 역할색을 공유한다. `화면 아무데나 누르면 사라집니다`는 지도 탭과 동일한 `MapHintDismissBadge`를 프레임 상단에 겹쳐 사용한다. 화면 첫 터치는 안내만 즉시 닫고 지도·카드 동작으로 전달하지 않는다. 가이드는 모든 글자 배율에서 닫기 배지를 포함한 전체 외곽이 상단 4개 활동 라벨과 아래 이야기 덱의 시대 라벨 사이 가시 영역 정중앙에 오도록 한다. 현재 이야기 시대의 모든 사건을 번호 핀과 시간순 점선으로 렌더한다. 완료 사건은 지도 탭과 동일하게 감정을 핀 중앙에 두고 이야기 번호를 우측 아래 배지로 표시하며, 미완료 사건 중 같은 시대의 직전·직후는 `이전`·`다음` 라벨, 현재는 핀 안쪽 44px 원으로 자른 첫 장면 data URL 썸네일과 `현재` 배지로 구분한다. 겹친 핀의 우선순위는 `현재 > 다음 > 이전 > 나머지`다. |
| HomeJourneyOverlay | `widgets/home/home_journey_overlay.dart` | 구약 7시대→신약 3시대와 시대 내 순번으로 전체 이야기를 좌우 `PageView` 카드 덱으로 렌더한다. 현재 카드는 크게 표시하고 이전·다음 카드 표면은 하단선을 맞춘 채 현재 표면 높이의 약 70%로 줄인다. 카드 간격은 3~5px이며, 정상 글자 크기 덱 높이는 186px다. 오늘 KST 기준 탐험 완료 전에는 추천=현재 카드에 `오늘의 이야기`만 표시하고, 하나라도 완료한 뒤에는 추천 위치에서도 `현재 이야기`를 표시한다. 마지막 이야기를 완료하면 마지막 카드를 현재 위치로 유지하고, 다른 카드를 고른 경우에도 `현재 이야기`만 표시한다. 현재 카드 위에는 공용 `— 시대명 —` 구분선을 둔다. 현재 제목은 한 줄 폭을 넘을 때 0.85초 뒤 끝까지 자동 이동하고 2초 머문 다음 처음으로 돌아가 같은 이동을 반복한다. 이동 속도는 약 38px/s로 기존보다 조금 빠르게 유지하며, 글자 배율이 바뀌면 진행 중 이동을 취소하고 새 폭으로 다시 계산한다. 현재 지역·연대와 인물 pill은 각각 가로 스크롤로 확인한다. 이전·다음 카드는 더 작은 글자와 8:5 썸네일을 사용하고 제목·지역/연대는 한 줄 말줄임표, 등장인물은 현재 카드와 같은 이미지+라벨 pill 가로 스크롤로 표시한다. 시대 변경 `시대명·이동`과 첫·마지막의 `이야기`/`없음` 2줄 경계 배지는 덱 최상위 레이어에서 그린다. 좌상단 이야기 순서 배지는 글자 배율과 무관하게 숫자를 중앙에 맞춘다. 작게 1.0x·보통 1.2x·크게 1.4x에서 모두 가로·세로 overflow 없이 유지한다. 덱 아래 퀵 액션의 화면 라벨은 `다이어리`·`통독`이고, 기록이 없으면 `오늘을 기록` 안내와 `+ 기록하기` CTA를 표시한다. 오늘 다이어리 기록이 있으면 제목은 굵은 선택 글자 배율 한 줄 수동 가로 스크롤과 우측 흐림으로, 본문은 글자 배율과 관계없이 최대 3줄 말줄임표로 분리해 표시한다. `+`·`→`는 고정 원형 테두리 중앙에 두고, 두 CTA는 좌측 아이콘·정보 열이 아닌 퀵 액션 카드 전체 가로 중앙에 맞춘다. `크게` 글자와 좁은 폭에서는 아이콘과 CTA 라벨을 버튼 폭에 맞춰 함께 축소해 외곽선을 넘지 않는다. 오늘 이야기와 CTA의 유도 glow는 활성 상태 동안 계속 재생한다. |
| StoryRootNavigationBar | `widgets/home/story_root_navigation_bar.dart` | 루트의 `오늘`·`성경`·`지도`·`내정보` 4탭 화면 폭 하단 네비게이션. 본문 높이는 60px이며, 외부 여백·둥근 표면·그림자·상단 구분선을 쓰지 않는다. 탭 콘텐츠는 시스템 안전영역 위에 두고, 바깥 표면과 시스템 내비게이션 바 색은 같은 팔레트 색으로 화면 맨 아래까지 이어진다. |
| StoryMapPanel | `widgets/story_map_panel.dart` | 운영 지도는 `StoryTerrain3dMap` + MapLibre GL JS 3D 단일 경로다. Android/iOS 는 네이티브 WebView, Flutter Web 은 `HtmlElementView` iframe 브릿지로 같은 HTML 렌더러를 띄운다. OpenFreeMap Liberty style 과 공개 Terrarium DEM 에 pitch/bearing/exaggeration 을 적용하며, 별도 API key나 지도 배경 선택 환경변수를 받지 않는다. 예전 flutter_map 2D tile/layer/pin 폴백은 제거됐다. `activeLandmarks` 와 `eraRegionLandmarks` 는 MapLibre 내부 GeoJSON source 로 전달되고, country boundary/region polygon/label/path/hit-zone 은 MapLibre layer 로, 사건 숫자·감정 핀과 non-region 랜드마크는 DOM marker 로 그린다. `fitEventIds`가 있으면 지도에는 `events` 전체를 유지하면서 해당 사건 좌표만 카메라 bounds에 사용한다. `fitTightClusterMaxZoom`은 가까운 사건 묶음의 확대 상한을 화면별로 조절하고, `showEventPath`는 reveal 상태와 무관하게 사건 사이 점선을 켠다. `StoryEventMarkerPresentation`은 같은 DOM 핀 렌더러에 `mapTimeline` 또는 `dailyJourney` 표현 모드를 전달한다. 두 모드 모두 완료 사건은 감정을 주 표식으로 두고 번호를 우측 아래 배지로 표시한다. 오늘의 미완료 사건만 `이전`·`현재`·`다음` 역할과 현재 썸네일을 주 표식으로 사용한다. 하단 선택 패널 위 pointer 입력은 지도 브릿지에 짧은 tap suppression 과 gesture suspension 을 전달해 패널 버튼/스크롤이 아래 지도 region·랜드마크 선택이나 카메라 이동으로 새지 않게 한다. tap suppression 은 오동작 방지를 위해 길게 유지하되 gesture suspension 은 pointer down/move 동안만 짧게 갱신하고 pointer up/cancel 에서 즉시 해제한다. 접힌 하단 시트는 실제 보이는 peek/header 높이만 hit 영역으로 두고, 접기 직후 지도 제스처 suspension 을 즉시 clear 해 위쪽 지도 영역이 바로 drag/pitch 입력을 받게 한다. **`onMapInteraction`** 콜백은 MapLibre 쪽 사용자 제스처 이벤트로 부모의 hint overlay dismiss 를 트리거한다. 이야기 간 이동 glow 는 같은 위치 사건 분산 좌표를 재사용해 현재/목표 사건 핀 중심에 맞춘다. `skipAnimation()`은 ordered reveal 타이머까지 멈추고 모든 핀을 즉시 노출한다. `playEmotionStamp(event, stampLabel)` 은 감정 새김 직후 같은 분산 좌표의 지도 핀 위에 감정 도장을 재생한다. reveal/전환/감정 새김의 중복 실행은 내부 guard 로 막는다. Android WebView 는 Hybrid Composition 으로 생성해 SurfaceProducer/ImageReader 버퍼 경고를 줄이면서 route 전환 때 지도를 트리에서 내리지 않는다. |
| StoryTerrain3dMap | `widgets/map/story_terrain_3d_map.dart` | 운영 3D 전용 지도. MapLibre GL JS 를 HTML string 으로 로드하고 OpenFreeMap Liberty style + Mapzen Terrarium DEM 을 연결한다. Android/iOS 는 `webview_flutter`의 `WebViewWidget`을 사용하고, Flutter Web 은 `story_terrain_web_view_web.dart`의 iframe `HtmlElementView`를 사용한다. Web 에서는 `WebViewController`를 만들지 않고, iframe 과 `window.postMessage`로 `ready`, `eventTap`, `landmarkTap`, 카메라/오버레이 갱신 JS 를 왕복시킨다. Web iframe 은 same-origin blob URL 로 로드하고, ready 메시지를 놓치지 않도록 parent message listener 를 먼저 붙인다. Web 의 platform view 가 Flutter UI 입력을 가로채지 않도록 상단 유틸리티 row, 홈 하단 선택 패널, floating action, 알림 dropdown, 지도 위 dialog/modal bottom sheet 는 `WebPointerInterceptor` 로 감싼다. Android/iOS 에서는 이 wrapper 가 child 를 그대로 반환하는 no-op 이다. Android WebView 에서는 Flutter gesture arena 가 지도 드래그/핀치를 빼앗지 않도록 eager gesture recognizer 를 사용하고, renderer OOM 을 줄이기 위해 worker/cache/antialias/pitch 를 제한한 저부하 모드로 terrain 을 끈다. Android Activity 는 WebView renderer exit 을 처리해 renderer 가 죽어도 앱 프로세스까지 종료되지 않게 한다. renderer 설정이 바뀔 때만 지도 HTML 을 새로 로드하고, 카메라 변화는 JS `easeTo()`/`fitBounds()`, country boundary/region polygon/라벨/path/event hit-zone 은 GeoJSON `setData()` 로 갱신한다. 루트 탭 재부착, 앱 resume, 회전/크기 변경 때는 보존된 같은 WebView/MapLibre에 debounced `resize()`와 repaint만 호출하며 HTML/style을 다시 로드하지 않는다. WebView 안 `ResizeObserver`도 컨테이너와 캔버스 크기를 다시 맞춘다. 사건 숫자/감정 핀과 non-region 랜드마크는 각각의 GeoJSON point 를 MapLibre DOM Marker 로 투영해 지역별 collision/terrain symbol 배치와 무관하게 지도 좌표 위에 고정한다. 감정 핀은 노란 오로라를 상시 표시하고, 감정/선택/전환/도장 대상 사건은 DOM marker z-index 우선순위를 높여 겹친 핀 위에서도 숫자·감정이 보이게 한다. 인물 선택 이야기 경로는 선택 인물별 GeoJSON line feature 로 나뉘며 `colorForCharacter` 색상과 작은 offset 을 사용해 복수 인물 이동 점선을 함께 보여 준다. 줌/드래그/option-key 조작/지도 컨트롤 입력 직후에는 tap hit-test 를 짧게 무시해 커서 아래 region·랜드마크 팝업이 우발적으로 뜨지 않게 하고, 모바일 포인터 탭 직후 MapLibre click 이 중복으로 들어오면 추가 hit-test 를 무시한다. 지역 선택 단계에서는 투명한 region hit fill layer 를 `queryRenderedFeatures` 로 먼저 조회하고, iOS WebView/terrain 조합에서 hit 이 빠질 경우 화면 좌표를 위경도로 역변환해 polygon point-in-polygon 으로 다시 판정한다. 라벨뿐 아니라 폴리곤 내부 탭도 같은 지역 선택으로 처리하고, 겹친 region 은 작은 bbox 를 우선한다. 사건 0개 region 은 polygon/label/hit layer 에 올리지 않는다. 기본 지도 symbol label layer 는 숨겨 영어/현지어 지명 대신 앱의 한국어 라벨만 보이게 한다. JS channel 또는 Web postMessage 로 region/event tap 을 Flutter 로 전달한다. 확대/이동 중 발생하는 타일·서브리소스 실패는 반복 로그로 올리지 않는다. 준비 중에는 움직이는 원형 진행 표시를 보여 준다. 최초 style과 캔버스 크기가 모두 정상일 때만 `ready`로 인정하며, 5초 timeout/main frame/초기 JS 실패는 자동 재생성 없이 수동 `다시 시도`를 보여 준다. 수동 재시도는 WebView/iframe 자체를 새로 만들고 이전 세션 메시지를 무시한다. 재시도도 실패하면 버튼 대신 앱을 완전히 종료한 뒤 다시 실행하라는 안내와 개인 정보 없는 운영 non-fatal 1건을 남긴다. |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 인물 선택 + 이벤트 목록 통합. **헤더(`headerOverride`) 는 sticky** — `Column [header, Expanded(CustomScrollView)]` 구조로 사건 카드 스크롤 시 헤더(toggle + stepper) 가 함께 위로 사라지지 않는다. 헤더는 접기/펼치기 toggle 과 라벨형 stepper 를 유지하고, 이전/다음 액션은 홈 지도 위 큰 플로팅 버튼에서만 제공한다. 다크 팔레트에서는 하단 스크롤 패널과 헤더가 같은 팔레트 그라데이션으로 이어져 지도와 분리된다. step 2 인물 카드는 아바타 오른쪽 위에 `+N` 사건 수 배지를 올리고, 이름 아래에는 `characters.tagline`의 짧은 정체성 문구(왕국/왕 순서/대표 행적/함께 활동한 인물 등)를 표시한다. 카드 폭이 좁아도 한글 단어 중간이 끊기지 않도록 정체성 문구는 단어 단위로 짧게 줄바꿈하고, 여유 있는 고정 높이와 최대 3줄 설명으로 real 데이터의 긴 인물 문구도 overflow 없이 담는다. step 2/3 카드 표면과 텍스트는 팔레트 `cardSurface`/`text`/`mutedText`를 사용한다. step 3 사건 카드(`EventTimelineRow`) 는 `committedSelectedCharacterCodes` + `colorForCommittedCharacter` 를 그대로 forwarding 해 카드 안 인물 pill 이 지도 path 색과 매칭된다. 최근 퀴즈 결과가 있으면 팔레트 카드 표면 위에 의미색을 섞어 상태를 표시한다(정답 0개=빨강, 일부 정답=주황, 모두 정답=초록). 감정 새김이 있으면 사건 카드 좌상단 배지를 컬러 감정 이모지로 바꾸고 우측 하단의 작은 초록 원에 이야기 순번을 함께 표시한다. 감정 새김 직후에는 상세 페이지를 잠시 닫고 0.5초 뒤 해당 사건 카드 위에 `CompletionCelebration` 감정 도장+별가루를 기존 속도로 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. |
| CharacterPanel | `widgets/character_panel.dart` | 팔레트 기반 인물 선택 패널. 패널 배경, 정렬 드롭다운, 인물 카드, 이름/설명 텍스트, 선택 테두리를 `AppPaletteTheme`로 그려 시간순/장소 선택 패널과 같은 밝기 체계를 유지한다 |
| ~~StoryListPanel~~ | ~~`widgets/story_list_panel.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| ParchmentDialog | `widgets/parchment_dialog.dart` | 이야기 상세/공지 상세 등 공용 모달. 표면, 제목, 보조 텍스트, 닫기 버튼, 보조 액션, 입력 필드는 현재 `AppPaletteTheme`를 따라 블랙 팔레트에서도 고정 크림색이 남지 않게 한다 |
| ParchmentPageScaffold | `widgets/parchment_page_scaffold.dart` | 양피지 배경 페이지 |
| ~~EraSelector~~ | ~~`widgets/era_selector.dart`~~ | 삭제됨 — StorySelectionPanel이 통합 |
| FontScaleBottomSheet | `widgets/font_scale_bottom_sheet.dart` | 전역 색 조합과 글자 크기를 바꾸는 바텀시트. 기본 호출은 두 섹션을 함께 보여 주고, `DisplaySettingsSection.theme/font`를 넘기면 `오늘` 헤더의 `테마`/`큰글자` 버튼에 맞는 한 섹션만 보여 준다. 작게·보통·크게 라벨은 같은 한 줄 `FittedBox.scaleDown` 영역을 써서 1.4x에서도 카드 안의 수직 위치가 같게 유지된다. 선택은 즉시 provider와 `SharedPreferences`에 반영한다. |
| GameUiSkin | `widgets/game_ui_skin.dart` | 레거시 양피지/게임풍 장식 헬퍼. 새 홈 선택 패널과 프로필 카드는 `AppPaletteTheme` 표면을 우선 사용한다 |
| ~~SearchBox~~ | ~~`widgets/search_box.dart`~~ | 삭제됨 — SearchBottomSheet로 대체 (필요 시 재생성) |

### 5.2 story_home_screen에서 추출한 위젯 (2차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| ParchmentTextureLayer | `widgets/parchment_texture_layer.dart` | 양피지 질감 오버레이 |
| SubPageScaffold | `widgets/sub_page_scaffold.dart` | 서브 페이지 공통 레이아웃. `showBackButton=false`이면 루트 탭에 embedded 된 성경/내정보 화면에서 상단 뒤로가기 chrome을 숨긴다. |
| SubPageFloatingHomeButton | `widgets/sub_page_floating_home_button.dart` | 드래그 가능한 홈 버튼 |
| InlineLoginPromptCard | `widgets/inline_login_prompt_card.dart` | 인라인 소셜 로그인 카드. 카카오/Google/Apple 로그인만 제공하며, 모바일 OAuth는 앱 바깥 기본 브라우저가 아니라 인앱 브라우저/Safari View Controller 계열 launch mode를 사용한다. Google 로그인은 재로그인 시 이전 계정으로 즉시 진입하지 않고 계정 선택 화면을 요청한다. Apple 네이티브 로그인이 가능한 Apple 기기 앱에서만 Apple 버튼을 추가 노출한다. |
| ShareIdInputDialog | `widgets/share_id_input_dialog.dart` | 7자리 공유 ID 입력 다이얼로그 |
| ProfileEditorDialog | `widgets/profile_editor_dialog.dart` | 프로필(닉네임/사진) 수정. 기도제목 편집 코드는 `profilePrayerFeaturePending` 상태로 보존하지만 현재 화면에서는 숨기며, 저장 시 기존 `prayer_request` 값을 유지한다. 프로필 페이지와 같은 팔레트 기반 표면과 작은 단색 아이콘 배지로 사진/닉네임 섹션을 구분하고, 저장 액션은 하단 CTA로 둔다 |

### 5.3 story_home_screen에서 추출한 페이지 (3차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (ConsumerStatefulWidget, 콜백으로 동작). 상단은 제목 아래 작은 글씨로 사건 연대(`start_year/end_year/time_precision`)와 장소(`place_name`)를 보여 주고 별표 저장 토글을 우측에 둔다. 상세의 큰 모달 표면, 배경 지식/요약 섹션, 장면 이미지 row, 본문+퀴즈 박스는 `AppPaletteTheme` 기반 표면과 텍스트를 써서 다크 팔레트에서도 고정 크림색/잉크색 조합이 나오지 않게 한다. **배경 지식 → 요약+장면 이미지 → 본문 읽고 퀴즈 풀기** 순서로 배치하며, `background_context`는 첫 번째 배경 지식 카드에 해설이 아닌 사실형 배경 1~2문장으로 표시한다. 이 문구는 절 주소나 이전/다음 링크, 시간순 구간명 대신 성경 흐름 안의 시대 배경과 사건 주제, 서신서 작성 배경을 알려 준다. 배경 지식 row 우측에는 사건 `character_codes`에 해당하는 등장인물 아바타를 겹치지 않는 가로 줄로 표시한다. 두 번째 카드에는 `요약: {summary}`를 한 문장으로 붙여 표시하고 전역 글자 배율을 그대로 적용하며, 같은 컨테이너 안에서 요약 아래에 장면 이미지 row를 둔다. 장면 이미지는 `scene_captions`가 있으면 이미지 하단 중앙의 반투명 rounded overlay에 모든 글자 배율에서 한 줄 말줄임표로 표시하고, 이미지를 누르면 자연스러운 카드 플립 애니메이션으로 전체 설명 뒷면을 보여 준다. 상세 하단 이전·다음 이야기 제목도 한 줄로 유지하며 넘치는 경우 끝까지 자동 스크롤하고 2초 머문 뒤 처음부터 반복한다. 하나님이 있으면 가장 왼쪽에 둔 뒤 나머지는 한글 이름 가나다 순으로 나열하며, 각 아바타 하단 중앙에 이름 라벨을 얹는다. 본문 읽기 버튼은 사건의 모든 `bible_refs`를 성경 리더의 사건 읽기 모드로 전달한다. 리더에서 마지막 본문까지 보고 **읽기 완료**를 누른 경우에만 읽음 처리하며, 리더의 뒤로가기(`<`)로 나가면 읽음 처리하지 않는다. 퀴즈 결과는 정답/오답/헷갈림으로 나누고 `user_quiz_attempts`에 저장해 버튼 라벨과 프로필 복습 팝업에 반영한다. 퀴즈 버튼은 `정답 N · 오답 N · 헷갈림 N` 형식으로 표시하고 정답 0개=빨강, 일부 정답=주황, 모두 정답=초록으로 칠한다. 퀴즈 **완료 취소**는 저장된 시도와 정답/오답/헷갈림 요약, 마지막 점수를 모두 지워 라벨을 `퀴즈 시작`으로, 버튼을 초기 액션 색으로 되돌린다. 본문 읽기 + 퀴즈 완료 후에만 **지도 위에 새기기** 버튼이 활성화된다. 새기기 팝업은 한 화면 위쪽의 **감정 선택** 바로 옆에 **필수**, 아래쪽의 **코멘트** 바로 옆에 **선택사항**을 표시하며, 감정만 선택해도 저장할 수 있다. 선택한 감정과 최대 100자 코멘트를 `user_event_emotion_marks`에 저장하면 사건 완료로 전환된다. 감정 선택 보기와 지도/카드 배지는 같은 컬러 감정 이모지 세트를 쓴다. 새김 완료 버튼은 코멘트가 있으면 `감정 - 코멘트`, 없으면 `감정`만 바로 보여 주고 "완료 취소"를 누르면 감정 row를 삭제해 지도 핀/카드 이모지도 제거한다. 감정 저장이 끝나면 부모 화면에 `onEmotionEngraved`를 알려 상세 페이지를 닫고 지도 핀/카드 감정 배지를 반영한 상태에서 0.5초 뒤 해당 지도 핀과 사건 카드 위 감정 도장+별가루를 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. 지도 위 감정 도장 및 이전/다음 이야기 전환 애니메이션은 내부 재진입 가드로 중복 실행을 막되, 평상시 지도·패널·상단 버튼 입력은 차단하지 않는다. 이전/다음 이야기 카드를 누르면 상세 페이지를 닫고 지도 위 현재 사건과 목표 사건 번호 핀이 약 2초간 함께 빛난 뒤 목표 상세 페이지를 열지만, 이 지도 노출은 route history 로 남기지 않는다. 새 상세의 `<` 버튼은 지도 대신 직전 상세로 돌아가고, 프로필 카드에서 진입한 상세의 루트 `<`는 프로필 페이지로 돌아간다. 사역자/관리자에게만 **"이 이야기 삭제 제안"** 버튼 노출 (`_DeleteProposalButton` 서브 위젯). 이미 완료된 사건으로 진입한 경우 우측 "다음 이야기" 카드를 `PulseHighlight` 로 짧게 몇 번만 박동. |
| EventQuizDialog | `widgets/event_quiz_dialog.dart` | 사건 상세에서 쓰는 사건 퀴즈 다이얼로그. 선택 후 **정답 확인**을 누르면 해당 문항의 정답/오답/헷갈림과 해설을 즉시 보여 주고, **다음**으로 이동한다. 마지막에는 전체 문항, 내 선택, 해설 리뷰를 확인한 뒤 `EventQuizResult`로 저장 값을 반환한다. 다크 팔레트에서는 다이얼로그, 질문/선택지/리뷰 카드가 모두 팔레트의 어두운 표면을 사용한다. |
| CompletionCelebration | `widgets/completion_celebration.dart` | 자식 위젯을 감싸 GlobalKey 로 `play(stampLabel:)` 호출 시 두 단계 축하 효과: (1) 별가루 + 초록 글로우 1.2s, (2) 끝나면 금박 도장이 슬램+흔듦+페이드 0.95s. 기본 라벨은 "완료"지만 이야기 완료에서는 선택 감정 심볼을 넘긴다. 도장 종료 시 옵션 `onComplete` 콜백 호출. EventDetailPage 의 read+quiz 박스에 부착. |
| PulseHighlight | `widgets/pulse_highlight.dart` | `active` 가 켜질 때 자식 외곽에 부드러운 glow 를 재생하는 래퍼. `pulseCount`가 있으면 지정한 횟수만 박동한 뒤 숨기고, `null`이면 active 동안 계속 반복한다. EventDetailPage 의 "다음 이야기" 카드와 프로필 CTA 유도에 사용한다. |
| EraPickRows | `widgets/v2/era_pick_rows.dart` | 시대 선택 칩 — 구약/신약 두 줄. HomeIntroPanel + ProfileTabPage `탐험한 이야기` 페이지에서 공유한다. 홈 인트로에서는 오른쪽 패널 끝까지 가로 레일을 쓰고, 마지막 칩이 둥근 모서리에 붙지 않도록 trailing scroll padding 을 둔다. 칩 라벨은 코드 기준 짧은 이름(`족장`, `출애굽`, `통일 왕국`, `사도`, `후기 사도` 등)을 쓰고, 검수 전 `era_nt_consummation`은 표시하지 않는다. `enabled=false`에서는 모든 칩을 무채색 `mutedSurface`로 바꾸고 자물쇠 아이콘을 표시한다. 선택한 칩만 옅은 강조색 테두리와 체크를 남겨 현재 잠긴 선택을 구분한다. `탐험한 이야기`의 이야기 진행률 영역에서 칩 뒤 검은 음영이 생기지 않도록 선택/비선택 칩 그림자를 제거한다. `eraIconFor(code)` 도 export. |
| HomeIntroPanel | `widgets/v2/home_intro_panel.dart` | 첫 화면의 하단 선택 패널. 큰 인트로 제목은 패널 안에 두지 않고 `MapHintOverlay`의 캐릭터 가이드로 띄운다. 두 단계: ① **여행할 시대** (구약/신약 칩, 단일 선택) ② **어떻게 볼까요?** (`시간 순` / `인물과 걷기` / `장소로 시작` 3개 컴팩트 버튼). 글자 크기와 무관하게 1행 3열을 유지하며, `크게`(1.4x)에서는 카드 높이를 늘려 2줄 설명이 잘리지 않게 한다. 각 버튼은 아이콘+제목을 같은 줄에 두고 아래에 2줄 설명형 문구를 붙이며, 카드 표면과 제목/설명/안내문 색은 현재 팔레트의 `cardUnselected*`, `text`, `mutedText`를 따른다. `시간 순`을 누르면 바로 사건을 펼치지 않고 `TimelineUnitPickPanel`에서 시대 내부 구간을 복수 선택한 뒤 `다음`으로 사건 목록을 연다. 인물 버튼 설명은 `선택한 인물의 사건을 / 시간 순으로 봅니다`로 2줄 안에 들어가게 유지한다. 시대를 고른 뒤에는 ① 영역(헤더+칩)을 0.86 opacity로 낮추고 칩 자체도 비활성 표면·자물쇠 상태로 바꿔, 다시 선택할 수 없음을 뚜렷하게 보여 준다. 다시 고를 때는 패널 위 큰 "시대 다시 선택" 버튼 또는 stepper 의 "시대/방법" 경로를 사용한다. ② 헤더는 팔레트 본문색 + 굵은 글씨로 차별화되어 다음 행동을 유도. 하단 안내 문구는 `FittedBox.scaleDown` + `maxLines:1` 로 좁은 폰에서도 1줄 보장하며, 홈 인트로 시트는 콘텐츠 높이에 맞춘 낮은 높이로 열어 아래 빈 양피지 공간을 줄인다. |
| 시대 선택 직후 가이드 | `screens/story_home_screen_state.dart` | `MapHintOverlay`에 `시대명 - 권 이름 목록`과 `선택된 시대를 보는 방법을 선택하세요`를 두 개의 불릿으로 표시한다. 이 단계에서는 가이드 얼굴 PNG와 원형 슬롯을 숨기고 말풍선을 기존 아바타 공간까지 넓힌다. 권 목록은 선택 시대 사건들의 실제 `bible_refs`를 중복 제거하고 66권 정경 순서로 나열한다. 아래에는 괄호 없이 가운데 정렬한 `다른 시대를 선택하려면` 제목과 `시대 다시 선택`·`또는`·`시대/방법` 액션 pill을 배치한다. 제목과 액션은 위의 두 핵심 불릿보다 한 단계 작은 글자를 쓰고, 작게·보통·크게에서 pill 단위로 자연스럽게 줄바꿈한다. 새 이야기가 추가되면 별도 고정 문구 수정 없이 권 목록도 함께 갱신된다. |
| TimelineUnitPickPanel | `widgets/v2/timeline_unit_pick_panel.dart` | 시간 순 보기 step 2. `StoryEvent.unitCode/unitTitle/unitOrder`로 이벤트를 묶어 낮은 가로 스크롤 카드 레일로 표시한다. 모바일 폭에서는 약 3.5개 카드가 보이고, 시트는 구간 개수와 무관하게 가로 1줄 레일 높이에 맞춘다. 상단에는 `구간 선택` 헤더와 `전체 선택`/`전체 해제` 토글을 둔다. 이 패널은 자체 팔레트 표면을 깔아 블랙 테마에서도 밝은 부모 표면 위에 밝은 글자가 얹히지 않게 한다. 구간 카드는 기본 낮은 높이를 유지하되 `크게`(1.4x)에서는 제목 3줄과 설명 4줄을 모두 담도록 높이를 늘린다. 제목 앞에 시간순 번호를 붙이고, 선택 상태는 체크 아이콘 대신 현재 팔레트의 선택색을 옅게 섞은 배경으로만 드러낸다. 제목/설명/토글은 팔레트 표면과 글자색을 사용한다. 제목 바로 아래에 `N개 이야기`를 붙이고 남은 영역에는 구약/신약 curated 구간 설명을 25~35자 내외의 한 문장, 최대 4줄로 ellipsis 없이 보여 준다. 사용자가 하나 이상 구간을 선택하면 헤더의 팔레트 액션색 `N개 다음` pill 로 해당 구간의 사건만 시간순 reveal 한다. 구약 시대는 `assets/events`의 curated `unit_*` 값으로 원역사 2개, 족장 3개, 출애굽 3개, 사사 3개, 왕정 3개, 분열왕국 5개, 포로/귀환 3개 구간이 보이도록 나눈다. |
| MapHintOverlay | `widgets/v2/map_hint_overlay.dart` | 지도 위 캐릭터 가이드 말풍선. 반투명 바깥 프레임은 현재 팔레트의 `utilityBackground`, 공용 `MapHintDismissBadge`는 `currentAccentDeep`, 본문 말풍선은 `characterAccent` 역할색을 사용하며 텍스트와 아이콘은 흰색으로 고정한다. `화면 아무데나 누르면 사라집니다` 배지는 `Stack`으로 바깥 프레임 상단 중앙 경계에 얕게 겹치도록 조금 더 위에 두며, 오늘 탭도 같은 배지를 공유한다. 프레임은 아바타·말풍선 row의 아래 8px 여백과 위치는 유지하고 위쪽만 12px로 확장해 지도 가시 영역을 보존한다. 기본 안내 본문 왼쪽에는 `assets/avatars_thumbs/guide.png`를 1.13배로 확대해 담고 원형 슬롯 지름은 기본 48px·첫 화면 70px 이지만, 시대 선택 직후 정보 가이드는 `showAvatar=false`로 슬롯과 간격을 제거해 말풍선이 프레임의 전체 정보 폭을 사용한다. 첫 화면 제목은 `FittedBox.scaleDown` + `maxLines:1`로, 단계 문구는 같은 글자 크기로 유지한다. 첫 화면/시대 선택/region/인물/시간순 단계마다 상황별 안내 문구를 사용하며, 어느 지도·안내문·하단 시트 입력도 hint를 dismiss 한다. dismiss flag 는 `StoryHomeScreen._mapHintDismissed`. |
| ProfileEmotionDiary | `widgets/profile/profile_emotion_diary.dart` | `내정보`의 독립 `다이어리` 레이어 KST 달력. 감정·통독 `read_at`·다이어리를 날짜별로 묶고 날짜 숫자 아래 한 줄에 같은 원형 활동 배지를 표시한다. 감정은 웃는 얼굴, 통독은 `menu_book`, 다이어리는 `edit_note`를 사용하며 세 활동을 모두 한 날은 1.5배 큰 초록색 채움 원 안의 흰 체크 하나로 합친다. 두 활동 배지는 좁은 날짜 셀에서 `FittedBox.scaleDown`으로 함께 축소해 가로 오버플로를 막는다. 접힘 상태는 오늘 주와 이전 주, 펼침 상태는 월 달력과 이전/다음 월 이동을 제공한다. 선택 날짜 아래의 `감정과 코멘트`, 통독 요약, 다이어리에도 같은 원형 배지를 재사용한다. 읽은 장은 `권 N장 · 권 N장` 한 줄 요약과 초과분 상세 팝업으로 보여 주며 기록이 없으면 다른 루트 탭에서 기록하도록 안내한다. 별도 `다이어리`·`통독 진행률` 카드는 `이야기 탐험 요약`과 이 달력 사이에 놓고 내정보 안에서는 작성·이어읽기 액션을 숨긴다. |
| ProfileCompanionDiary | `widgets/profile/profile_companion_diary.dart` | 프로필 `다이어리` 카드와 날짜별 일지 흐름을 담당한다. 프로필 카드에는 오늘 기록이 없으면 `오늘` 탭 작성 안내를, 있으면 제목을 굵은 선택 글자 배율 한 줄 수동 가로 스크롤과 우측 흐림으로 표시하고, 본문은 노트 장식 뒤의 오른쪽 공간까지 사용해 최대 3줄 말줄임표로 표시한다. 카드/chevron은 이번 달 기록일·연속일 및 `전체`·`이번 달` 필터를 가진 전체 일지 페이지를 열며 최초 필터는 `이번 달`이다. 실제 작성·수정은 `CompanionDiaryEditorScreen` 전용 페이지에서 처리한다. 작성된 일지는 공용 미리보기 카드와 상세 팝업에서 확인하고 삭제할 수 있다. 본문은 1000자까지 입력받는다. |
| CompanionDiaryEntryPreviewCard | `widgets/profile/companion_diary_entry_card.dart` | 프로필/전체보기에서 공유하는 다이어리 미리보기 카드와 상세/삭제 다이얼로그 헬퍼. 날짜/시간 메타가 있으면 제목과 같은 줄 오른쪽에 둔다. 상세 팝업 본문은 팔레트 표면·얇은 테두리·`AppRadii.lg` 둥근 모서리를 가진 별도 rectangle에 담는다. 프로필 메인 달력 아래 카드와 전체보기는 같은 수정/삭제 상세 흐름을 재사용한다. |
| ProfileEmotionStats | `widgets/profile/profile_emotion_stats.dart` | 프로필 감정 통계 계산 헬퍼. 감정을 새긴 고유 이야기 수, `EventEmotionOption`별 개수, 감정별 event id 목록을 제공한다. |
| ProfileEventReviewGrid | `widgets/profile/profile_event_review_grid.dart` | 완료·저장한 이야기·복습·감정 필터·구절 찾기 결과가 공유하는 사건 목록. 프로필에서는 요약을 숨긴 `StoryEventThumbCard`를 기본 2열로 배치하고, 첫 era 및 era 변경 지점만 가는 경계선+era 이름으로 표시한다. 썸네일은 기존 정사각형 높이의 절반 지름인 원형으로 줄여 카드 전체 높이를 낮춘다. 제목·장소·등장인물은 모두 한 줄이며 사용자가 각각 가로로 밀어 끝까지 확인하고, 우측 끝에는 강한 투명 그라데이션을 넣어 스크롤 가능성을 알린다. 등장인물은 이미지+라벨 pill을 유지한다. 좁은 구절 찾기 결과 열에서도 같은 카드 표현을 재사용하며, 작게 1.0x·보통 1.2x·크게 1.4x에서 overflow 없이 유지한다. 화면별 차이는 열 수와 전달하는 사건 필터뿐이다. |
| StoryMapPanelController | `widgets/story_map_panel.dart` | 지도 외부 제어 API. 줌/포커스/reveal 외에 상세 페이지 이전/다음 이동용 `playEventTransition(from, to)` 로 현재/목표 사건 번호 핀을 함께 빛나게 하는 1회성 전환을 재생한다. 같은 사건을 `from/to`로 넘기면 프로필 카드 진입용 단일 핀 pulse 를 약 1초 재생한다. 이 전환 카메라는 하단 선택 패널 padding 을 반영해 `fitBounds` 로 더 넓게 잡아 목표 원형핀이 패널 뒤에 숨지 않게 한다. `playEmotionStamp(event, stampLabel)` 은 감정 새김 직후 해당 핀 위에 지도 도장을 재생한다. 두 효과 모두 `map_math.buildRankedEventPointMap`의 분산 좌표를 사용해 번호 핀 중심과 맞춘다. |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (자체 상태 관리, 구절 탭 선택 + 하단 액션바). 선택한 구절은 밑줄/좌측 강조로 표시하고 하단에 파랑·노랑 하이라이트, 저장, 복사 버튼을 보여 준다. 저장은 200자 묵상 코멘트 다이얼로그를 띄우며 빈 코멘트도 정상 저장한다. 하이라이트는 코멘트 없이 즉시 `user_saved_verses.highlight_color`에 저장하고, 같은 색을 다시 누르면 하이라이트를 해제한다. 저장된 말씀의 하이라이트를 해제할 때는 저장 row와 코멘트는 유지한다. 복사는 `권 장:절 본문` 형식으로 클립보드에 넣는다. 저장 취소는 전체 저장 말씀 화면의 `saved_verse_actions.dart` 공유 확인 로직을 사용한다. 일반 진입의 구약/신약·권·장 선택 줄은 한 묶음으로 가운데 정렬하며 본문 목록 첫 항목이라 본문과 함께 위로 스크롤된다. **이전 장·다음 장**과 그 아래 **통독 읽음 처리**는 하단 고정 바가 아니라 해당 장의 마지막 절 아래에 둔다. 비로그인 상태에서 저장/하이라이트나 저장 말씀 버튼을 누르면 `onLoginRequired`로 홈의 3초 스낵바 + **이동** 액션을 띄운다. 이야기 상세에서 진입하면 사건 읽기 모드로 전환해 해당 `bible_refs` 범위의 절만 표시하고, 여러 본문이면 **다음**으로 순차 이동한 뒤 마지막에 **읽기 완료** 버튼을 보여 준다. 이 완료 버튼으로 닫힌 경우에만 사건 읽음 처리가 되며, 비로그인 상태에서는 저장 처리 대신 로그인 유도로 돌아간다. 루트 성경 탭의 일반 재진입은 현재 권·장을 보존하지만, 오늘 통독 **이어읽기**와 내정보의 특정 장 이동은 명시적 이동마다 리더 인스턴스를 새로 시작해 보존된 이야기 본문 위치보다 요청한 통독 권·장을 우선한다. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 주간 미션 탭. 인물/지역 모드 중 하나를 시드로 고르고 지도 + 하단 사건 카드 row 를 보여 준다. 카드 설명은 숨기고 제목은 우측 흐림이 있는 한 줄 수동 스크롤로 표시한다. 카드 탭은 홈 지도/하단 패널을 해당 사건으로 준비한 뒤 기존 사건 상세로 진입하므로 진행도는 `user_event_progress`/`user_quiz_attempts`/`user_event_emotion_marks`와 그대로 연동된다. 진행률 카드는 고정 높이 없이 글자 크기에 맞춰 늘어나고 금주 헤더 사이에는 별도 여백을 두며, 금주 인물/지역 헤더와 사건 카드 row 는 현재 팔레트 표면을 사용한다 |
| ProfileTabPage | `widgets/profile_tab_page.dart` | `내정보` 탭의 진행 화면. 상태바부터 프로필 헤더 끝까지 하단 루트 네비게이션과 같은 팔레트 표면색을 연속해 사용한다. 밝은 본문 쉘은 헤더와 12px 간격을 두어 라운드 상단이 겹치지 않게 한다. 별도 `내정보` 제목 없이 34px 프로필 사진과 15px 닉네임을 바로 보여 주며, 사진/닉네임 탭은 프로필 수정 팝업을 연다. 블랙 팔레트의 닉네임 입력값은 팔레트 `text`색으로 밝게 표시한다. `이야기 탐험 요약`은 음영으로 구분하고, `복습` 수치는 모든 퀴즈 시도의 오답 문항 수와 헷갈림 문항 수를 합산하며, `완료`를 누르면 제목이 `완료`이고 기본 필터도 `완료`인 페이지를 연다. 전체 사건 카탈로그는 오늘 provider와 공유하고 활성 인물은 한 번만 조회한다. `다이어리`·`통독 진행률` 카드의 기본 최소 높이는 118px로 줄이고, 큰 글자에서는 내용만큼 확장한다. 그 아래 독립 `다이어리` 레이어를 배치하며, 다이어리 바깥 레이어는 테두리 없이 그림자로 구분한다. 비로그인 미리보기는 약한 1.5px 블러와 엷은 덮개로 배경 구성을 식별할 수 있게 하되, 배경 전체는 `IgnorePointer`로 입력을 차단하고 로그인 카드만 작동한다. |
| QuizTabPage | `widgets/quiz/quiz_tab_page.dart` | 매일/주간 미션과 알림 딥링크 호환 화면. `지도` 탭에는 기존 `미션` 버튼을 유지하고, 날짜별 추천 핵심 진입점은 `오늘` 탭의 이야기 탐험 카드로도 제공한다. |
| DailyExplorationSection | `widgets/quiz/daily_exploration_section.dart` | 날짜 시드로 고른 오늘의 사건을 지도 + 사건 카드로 표시한다. 상단 소개 영역은 네비게이션 아이콘 + **오늘의 미션** 라벨을 먼저 보여 주고, 그 아래 "오늘은 {시대 이모지+텍스트} {인물 avatar+텍스트}과 함께 {핀 이모지+장소}에 도착했어요." 문장을 별도 rounded chip 없이 배치한다. 소개 영역과 본 미션 블록은 고정 크림색이 아니라 현재 팔레트의 `softSurface`/`cardSurface` 계열을 써서 다크 팔레트에서도 밝은 고정 표면이 남지 않게 한다. 소개 아래의 본 미션 블록은 하나의 rounded rectangle 단위로 묶고, 맨 위에 나침반 이모지 + **오늘의 사건** 라벨을 둔다. 제목 아래에는 가운데 정렬된 "「사건명」 사건" 메인 버튼을 길게 배치하고, **인물 루트 / 장소 사건**은 `함께 보기` 보조 버튼 row로 분리한다. 매일 미션의 핵심 CTA와 감정 문구는 오늘 사건 보기의 선택 버튼/사건 영역에만 표시한다. 인물 루트는 오늘 인물+시대의 전체 사건 흐름, 장소 사건은 오늘 장소/region+시대의 사건 묶음을 같은 지도와 `EventTimelineRow`로 보여 주는 보조 탐색이며, 지도 위 인물 코드 legend 는 숨긴다. 미션 사건 카드는 설명을 숨기고 제목을 우측 흐림이 있는 한 줄 수동 가로 스크롤로 표시한다. 장소 사건은 1개만 있어도 눌러 볼 수 있고, 해당 조합에 포함된 사건 수를 그대로 표시한다. 본 미션 블록 안에서 버튼 row 아래 지도 높이를 확보하고, 필요하면 구분선/사건 카드 row는 세로 스크롤 아래에서 이어 보여 준다. 해당 사건에 오늘 KST 감정을 새겼으면 축복 문구, 이전 날짜 감정만 있으면 다시 미션 문구를 구분선 아래에 표시한다. 별도 daily DB 없이 기존 사건 상세 진행도에 연동된다. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 주간 미션 (embedded 모드 지원). **두 모드** — `WeeklyMode.character` (랜덤 인물 + 그 인물의 사건) / `WeeklyMode.region` (랜덤 시대 + 사건이 있는 랜덤 region + 그 region 사건). 시드(`seedFromKey(weekKey)`)로 50/50 결정. 헤더는 모드별 분기 ("금주 인물" / "금주 지역: 시대 · 지역"). 지도 = StoryMapPanel(decorate=false, region 모드는 `eraRegionLandmarks: [region]`). 하단 = EventTimelineRow이며, 카드 설명을 숨기고 제목을 우측 흐림이 있는 한 줄 수동 가로 스크롤로 표시한다. 카드 탭은 일반 사건 상세로 이어져 프로필 진행도와 연동된다. 주간 인물 지도 legend 는 상단 헤더와 중복되므로 숨기며, 매일 미션 전용 다시 미션/축복 문구는 표시하지 않는다. 진행률 카드는 고정 높이를 쓰지 않아 아주 큰 글자에서도 내용만큼 늘어나며, 금주 헤더 사이에는 여백을 두고 헤더와 하단 사건 row 는 팔레트 표면으로 렌더링한다. |
| CharacterAvatar | `widgets/character_avatar.dart` | 인물 아바타 (주간/프로필 공용) |
| FadingHorizontalTextScroll | `widgets/fading_horizontal_text_scroll.dart` | 호출 화면이 지정한 글자 배율의 굵은 제목을 한 줄로 렌더하고, 넘칠 때만 우측 흐림을 보여 주며 사용자가 가로로 밀어 전체를 확인할 수 있게 한다. |

사건 상세의 가장 밖 모달 표면, 계정 삭제 확인 팝업, 공지·법적 안내 본문의 가장 밖 표면은 테두리를 두지 않고 기존 음영을 유지한다. 내부 정보 카드와 입력란의 테두리는 구조 구분을 위해 유지한다.

루트 셸은 지도·성경·내정보를 최초 방문 뒤 모두 유지한다. 현재 탭만 paint/tick/input하고 나머지는 `Offstage` + `TickerMode` + `IgnorePointer`로 숨긴다. 따라서 성경·내정보 뒤의 `StoryMapPanel` WebView는 인스턴스를 보존하되 플랫폼 뷰 합성에서 빠지고 MapLibre 제스처도 비활성화되며, 성경 장/스크롤과 내정보 화면별 캐시는 탭 재진입 때 dispose되지 않는다. 돌아오면 같은 State와 WebView 인스턴스를 즉시 다시 사용하고, 새 레이아웃 크기에 맞춘 `resize()`만 실행한다.

비로그인 상태에서 사건 상세의 **읽기**·**퀴즈 시작**을 누르면 공용 로그인 안내 팝업을 띄운다.
팝업은 `내정보 화면에서 로그인한 뒤 다시 이용해 주세요.`와 **내정보로 이동** 버튼을
사용하며, 확인하면 `ProfileTabPage` 로그인 카드에 진입한다. 성경 구절 저장/하이라이트,
저장 말씀 버튼, 이야기 저장/감정 새김처럼 그 밖의 사용자별 저장 액션은 기존
`StoryHomeScreen`의 3초 로그인 유도 스낵바와 **이동** 액션을 유지한다.

### 5.4 도메인 횡단 공유 위젯 (4차 리팩토링)

| 위젯 | 파일 | 사용처 |
|------|------|--------|
| EventShortPopup | `widgets/shared/event_short_popup.dart` | story_map_panel 콜아웃 + weekly_tab_page 단축 팝업 |
| StoryBottomPanelStyle | `widgets/story_bottom_panel_style.dart` | `지도` 탭 하단 선택 패널의 팔레트 그라데이션, 위쪽 radius, 테두리, 그림자, 반응형 좌우 여백을 제공한다. `오늘`은 이 패널 표면을 사용하지 않고 카드를 지도 위에 직접 띄운다. |
| LoginRequiredDialog | `widgets/login_required_dialog.dart` | 사건 상세 읽기·퀴즈와 오늘 다이어리·통독의 비로그인 안내를 `내정보` 문구와 이동 버튼으로 통일한다. |

### 5.6 Notifications (2026-04-22)

| 위젯/파일 | 파일 | 역할 |
|----------|------|------|
| NotificationBellButton | `widgets/notification/notification_bell_button.dart` | 프로필 헤더 종 아이콘 + 배지, Overlay 드롭다운 관리. 팝오버는 최대 340px이며 좁은 화면에서는 좌우 8px 여백 안의 가용 폭으로 줄인다. |
| NotificationBadge | `widgets/notification/notification_badge.dart` | 빨간색 ! 배지 (미독 1개 이상 시 표시) |
| NotificationDropdown | `widgets/notification/notification_dropdown.dart` | bell 탭 시 열리는 반응형 팝오버 — 미독 5개 + "모두 읽음" / "전체 보기" |
| NotificationListTile | `widgets/notification/notification_list_tile.dart` | 드롭다운/히스토리 공용 row (타입별 아이콘, 상대시간, 미독 점) |
| NotificationDeepLink | `widgets/notification/notification_deep_link.dart` | deep_link 파싱 + 모바일/태블릿 "컴퓨터로 확인" 다이얼로그 |
| PushService | `services/push_service.dart` | FCM 토큰 발급/등록, 포그라운드 메시지 handler |
| AppMonitoringService | `services/app_monitoring_service.dart` | 운영 릴리스의 Analytics 수집과 모바일 Crashlytics 전역·비치명 오류 보고. Supabase 인증 스트림 오류를 직접 처리해 세션 만료를 전역 fatal로 승격하지 않는다. |
| AppNotification 모델 | `models/app_notification.dart` | `list_my_notifications` RPC 반환 row 파싱 |
| Providers | `state/notification_providers.dart` | `unreadNotificationCountProvider` (polling Stream) + 목록 Future providers. `모두 읽음`/개별 읽음 직후 count/list/history provider 를 함께 invalidate 해 빨간 `!` 배지와 드롭다운 빈 상태가 즉시 갱신된다. |

Firebase 설정 가이드: `docs/guides/PUSH_SETUP.md`. 인프라 전반 원리: `docs/guides/INFRA_GUIDE.md`.

`AppMonitoringService`는 `ENV=real|prod`인 릴리스 빌드에서만 자동 수집한다.
`ENV=dev`와 일반 디버그 실행은 Analytics/Crashlytics를 모두 끄고, 웹은
Crashlytics를 호출하지 않는다. real 디버그에서 콘솔 연결을 점검할 때만
`--dart-define=FIREBASE_MONITORING_ENABLED=true`를 명시한다. 핵심 저장 실패는
기능을 구분하는 고정 reason과 스택 트레이스만 기록하며 감정 메모, 다이어리 본문,
기도제목, 이메일, Supabase 사용자 ID는 첨부하지 않는다.
기능 분석은 `story_opened`, `story_bible_read_completed`, `quiz_completed`,
`emotion_engraving_started`, `emotion_mark_saved`, `story_completed`,
`diary_entry_saved`, `bible_chapter_completed`, `account_created` 9개 이벤트로
제한한다. `emotion_engraving_started`는 로그인 사용자가 **지도 위에 새기기**를
눌러 팝업을 연 때, `emotion_mark_saved`는 감정 저장이 성공한 뒤 기록한다.
`story_bible_read_completed`는 이야기 본문의 마지막 범위에서 **읽기 완료**를
누르고 미완료→완료로 바뀐 때, `bible_chapter_completed`는 일반 통독에서
한 장을 새로 읽음 처리한 때 각각 1회 기록한다. 저장형 이벤트는 Supabase
저장 성공 뒤에만 기록하고 다이어리 내용·감정 종류·통독한 권/장·사용자 ID는
보내지 않는다. 로그인
여부는 `login_state=signed_in|signed_out` 사용자 속성으로만 구분한다.
서버에서 이미 정리된 refresh token이 로컬에 남아 있으면 Supabase SDK가 시작 중
세션을 제거하고 로그아웃 상태로 전환한다. 이때 인증 스트림의
`refresh_token_not_found`/`refresh_token_already_used` 오류는 예상 가능한 세션 종료로
처리해 Crashlytics에 보고하지 않고, 그 밖의 인증 스트림 오류만 비치명 오류로 남긴다.
AndroidManifest와 iOS Info.plist의 네이티브 기본 수집값도 false로 두고, 위 정책을
통과한 실행에서만 SDK 런타임 API로 다시 활성화해 Firebase 초기화 직후의 개발
이벤트가 운영 지표에 섞이지 않게 한다.

### 5.7 Proposal (사역자 제안 워크플로)

| 위젯/파일 | 파일 | 역할 |
|----------|------|------|
| BibleRefsPicker | `widgets/proposal/bible_refs_picker.dart` | 성경 구절 참조 picker |
| CharacterCodesPicker | `widgets/proposal/character_codes_picker.dart` | 기존 characters 다중 선택 |
| NewCharacterDialog | `widgets/proposal/new_character_dialog.dart` | 신규 캐릭터(아바타 포함) 생성 다이얼로그 |
| ProposalCharacterRow | `widgets/proposal/proposal_character_row.dart` | 선택된 등장인물 아바타 줄 |
| ProposalLocationPicker | `widgets/proposal/proposal_location_picker.dart` | 제안 이야기의 `landmark_id` 1개 선택. 구체 장소(anchor/minor 등)를 고르는 것이 기본이고, 정확한 지점을 특정하기 어려울 때만 넓은 region row 를 장소로 고를 수 있다. |
| ProposalScenesEditor | `widgets/proposal/proposal_scenes_editor.dart` | 장면 텍스트 + 장면 이미지 편집 |
| ProposalStatusChip | `widgets/proposal/proposal_status_chip.dart` | pending/approved/rejected 칩 |
| SceneCharactersGrid | `widgets/proposal/scene_characters_grid.dart` | 장면별 등장 인물 체크 그리드 |
| **ProposalQuizEditor** | `widgets/proposal/proposal_quiz_editor.dart` | 목회자 작성 선택지 3개 퀴즈 1~3개 편집기. 사용자용 4번 보기 "헷갈렸어요"는 승인 시 자동 추가. Step 4 에서 사용. |
| **DeleteEventProposalSheet** | `widgets/proposal/delete_event_proposal_sheet.dart` | 기존 이야기 삭제 제안 바텀시트 (2026-04-22). EventDetailPage 에서 호출. |
| **ApproveProposalDialog** | `widgets/proposal/approve_proposal_dialog.dart` | 관리자 새 이야기 승인 전 최종 검토. 같은 era 의 현재 이야기 목록에서 삽입 위치를 override 하고, 제안자가 고른 위치는 금색 `제안 위치`, 관리자가 승인할 위치는 초록 `최종 선택` 배지로 함께 보여 준다. 신규/기존 등장인물의 `is_active` 노출 여부도 확정한다. |

### 5.5 큰 화면의 part 파일 분해 (4차 리팩토링)

대규모 파일(>1,000줄)을 도메인별 part 파일로 분해해 가독성 향상. 동작은 동일.

| 부모 파일 | 분해 후 줄 수 | part 파일 |
|----------|-------------|----------|
| `widgets/story_selection_panel.dart` | 1648 → 561 (−66%) | `selection/panel_chrome.dart` (~280)<br>`selection/step_chip.dart` (~340)<br>`selection/selection_cards.dart` (~465) |
| `widgets/story_map_panel.dart` | 3D 지도 orchestration + 상태 part 로 정리 | `story_map_panel_state.dart`<br>`story_map_panel_widgets.dart`<br>`map/story_terrain_3d_map.dart`<br>+ 순수 좌표 함수 → `utils/map_math.dart` |
| `widgets/profile_tab_page.dart` | 2628 → 1755 (−33%) | `profile/profile_intercessory_prayer.dart` (~225)<br>`profile/profile_helpers.dart` (~260)<br>`profile/profile_left_panel.dart`<br>`profile/profile_right_panel.dart` (헬퍼만 잔존)<br>`profile/profile_progress_section.dart` (2026-05-08, "진행률 표시" 섹션)<br>`profile/profile_settings_sheet.dart` (2026-05-08, 설정 시트) |
| `widgets/weekly_tab_page.dart` | 884 → 574 (−35%) | `weekly/weekly_avatar.dart` (~67)<br>`weekly/weekly_list_panel.dart` (~258)<br>+ 순수 함수 3개 → `utils/weekly_selection.dart` |

### ProfileTabPage 외부 콜백

`ProfileTabPage`는 페이지가 열려 있는 동안 KST 자정이 지나면 오늘 루틴
체크 상태를 다시 불러온다. 자정 타이머는 `durationUntilNextKstMidnight`로
UTC 기준 다음 KST 자정까지의 양수 delay를 계산해, 한국 오후 시간대에 타이머가
즉시 반복 실행되며 진행도 조회가 폭주하지 않게 한다.
모바일 폭에서는 `RefreshIndicator`로 아래로 당겨 새로고침할 수 있고,
완료/감정/저장/통독/다이어리 미리보기를 다시 불러온다.
프로필 메인에는 이야기 카드 덱 대신 독립 `다이어리` 달력을 두며, 추천 이전·오늘·
다음 이야기 탐험은 루트의 `오늘` 탭에서 담당한다.

`복습` 세부 화면은 감정 카테고리와 퀴즈 오답·헷갈림 항목을 서로 다른 단일
rounded card로 보여 주며, 각 필터 아래 구분선과 같은 공용 2열 이야기 카드를
인라인으로 표시한다. 프로필 메인의 다이어리 달력은 반복하지 않는다.

`ProfileTabPage`는 자체 상태(25+개 필드)를 내부에서 모두 관리하며, 외부 의존성은 콜백 8개로만 노출된다:

```dart
ProfileTabPage(
  key: _profileTabKey,  // ← 퀴즈 완료 후 진행도 새로고침용
  onStartQuiz: (eventId) => ...,
  onOpenEventDetail: (event, {source}) => ...,
  onOpenBibleReader: ({bookNo, chapterNo, verseNo}) => ...,
  onExploreStoriesFromHome: () => ...,
  onBackToHome: () => ...,
  onOpenAppPublications: () => ...,
  onNavigateNotification: (notification) => ...,
  onOpenNotificationHistory: () => ...,
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
| `topMissionButton(...)` | Widget | `지도` 탭에 남는 미션 버튼. 오늘 매일 미션 완료 여부에 따라 강조/완료 상태를 표시한다. |
| `bibleDropdownFrame<T>(...)` | Widget | 성경 드롭다운 프레임 |
| `storySection(...)` | Widget | 이야기 섹션 (제목 + 내용 + action) |
| `storySceneRow(...)` | Widget | 4장면 이미지 가로 배열 + 선택적 하단 캡션 overlay |
| `bibleMoveButton(...)` | Widget | "이동" 액션 버튼 (성경 리더) |
| `lockedPreviewOverlay(...)` | Widget | 잠금 프리뷰 오버레이 |

## 6. 의존 패키지

Flutter 런타임은 3.44.7 stable, Dart는 3.12 이상을 기준으로 하며 CI도 같은
Flutter 패치 버전을 고정한다.

iOS는 Flutter 3.44의 Swift Package Manager 통합과 UIScene 생명주기를 사용한다.
현재 플러그인은 모두 SwiftPM을 지원하므로 CocoaPods 통합과 `Podfile`은 제거했다.
Android는 API 36과 NDK 28.2.13676358, AGP 8.11.1, Gradle 8.14.4, Kotlin
2.2.20을 기준으로 한다.

| 패키지 | 버전 | 용도 |
|--------|------|------|
| flutter_riverpod | ^3.3.2 | 상태 관리 (`StateProvider` 등 legacy API는 명시적 legacy import) |
| supabase_flutter | ^2.16.0 | Supabase SDK. 모바일 OAuth callback은 내부 `app_links`가 처리하므로 Android `flutter_deeplinking_enabled`와 iOS `FlutterDeepLinkingEnabled`를 `false`로 유지해 Flutter Navigator의 중복 named-route 처리를 막는다 |
| flutter_map | ^8.3.1 | 제안 위치 선택기 등 보조 2D 지도와 `LatLngBounds` 유틸 |
| latlong2 | ^0.9.1 | 좌표 계산 |
| path_provider_foundation | 2.4.2 | iOS/macOS 경로 플러그인; 2.6.0 native-asset 아키텍처 경고 회피 |
| shared_preferences | ^2.5.5 | 로컬 키-값 저장 (색 조합, 글자 크기 등 사용자 선호 설정) |
| google_sign_in | ^7.2.0 | Android 네이티브 Google 로그인 |
| sign_in_with_apple | ^8.1.0 | Apple 네이티브 로그인 (iOS/macOS 앱 전용) |
| image_picker | ^1.2.3 | 프로필 이미지 |
| crypto | ^3.0.6 | SHA256 (Apple 로그인 nonce) |
| cupertino_icons | ^1.0.8 | iOS 스타일 아이콘 |
| firebase_core | ^3.15.2 | Firebase 초기화 (FCM), iOS 13 지원 유지 |
| firebase_messaging | ^15.2.10 | FCM 토큰/메시지 — 푸시 알림, iOS 13 지원 유지 |
| firebase_analytics | ^11.6.0 | 앱 실행·이용 현황과 재방문 분석, iOS 13 지원 유지 |
| firebase_crashlytics | ^4.3.10 | Android/iOS 충돌 및 비치명 오류 보고, iOS 13 지원 유지 |
| flutter_local_notifications | ^22.1.0 | 포그라운드 로컬 알림 (iOS/Android) |

## 7. 코딩 컨벤션

- **포맷**: `dart format` (Dart 공식 스타일)
- **린트**: `flutter_lints` 6.0 (`analysis_options.yaml`)
- **네이밍**: Dart 공식 — `camelCase` 변수, `PascalCase` 클래스
- **UI 텍스트**: 한국어로 작성
- **위젯**: `ConsumerWidget` 또는 `ConsumerStatefulWidget` (Riverpod)
- **상수**: `const` 생성자 최대 활용
- **에러 처리**: try-catch + `state.copyWith(error: ...)` 패턴
