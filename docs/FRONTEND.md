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

## 2. 모델 클래스

| 모델 | 파일 | 핵심 필드 | 팩토리 |
|------|------|----------|--------|
| Era | `models/era.dart` (40줄) | id, code, testament, name, displayOrder, mapCenter*, mapZoom | `Era.fromMap()` |
| Character | `models/person.dart` (30줄) | id, code, name, tagline, description, avatarUrl, displayOrder | 생성자 직접 |
| StoryEvent | `models/story_event.dart` | id, eraId, title, summary, storyScenes (List<String>), sceneCharacters (List<List<String>>), **landmarkId** (v2 위치 모델 진실 소스), placeName/lat/lng (events_ordered view derive), storyIndex, rankInEra, globalRank, characterCodes, bibleRefs (List<BibleRef>) | `StoryEvent.fromMap()` |
| BibleRef | `models/bible_ref.dart` | book, from, to (`displayText` getter) | `BibleRef.fromMap`, `BibleRef.fromList` |
| BibleVerse | `models/bible_verse.dart` (28줄) | translation, bookNo, bookName, chapterNo, verseNo, verseText | `BibleVerse.fromMap()` |
| Landmark | `models/landmark.dart` | id, code, name, description, emoji, category, lat, lng, **kind** ('region'/'anchor'/'minor'/'point'), **polygon** (region 만, List<LatLng>), **parentLandmarkId**, **aliasGroupId**, displayPriority, eraCodes, relatedEventCodes (`isRegion/isAnchor/isMinor/latLng` getter) | `Landmark.fromMap()` |
| AppUserProfile | `models/app_user_profile.dart` (33줄) | userId, shareId, nickname, photoUrl, prayerRequest | `AppUserProfile.fromMap()` |
| SavedBibleVerse | `models/saved_bible_verse.dart` (55줄) | id, userId, translation, bookNo, bookName, chapterNo, verseNo, verseText | `SavedBibleVerse.fromMap()` |
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

`utils/system_insets.dart` — 일부 모바일 WebView/브라우저가 내비게이션 바가 없어도 작은 `MediaQuery.padding.bottom` 값을 보고하는 문제를 막는다. `MaterialApp.builder`의 `fontScaleBuilder`가 작은 bottom inset(16px 미만)을 0으로 정규화해 gesture-only/내비바 없음 환경에서는 화면 맨 아래까지 쓰고, 홈 인디케이터나 3-button 내비게이션처럼 의미 있는 inset 은 그대로 보존한다.

### 3.2 StoryState (불변 상태 클래스)

```dart
class StoryState {
  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Character> characters;
  final List<StoryEvent> events;
  final String? selectedEraId;             // 단일 시대 선택
  final SelectionMode? selectionMode;      // v2 — 'region' | 'character' (시대 선택 후 분기)
  final String? selectedLandmarkId;        // v2 — region 모드에서 선택된 landmark id
  final Set<String> selectedCharacterCodes;        // character.code 기반
  final Map<String, Color> selectedCharacterColors; // key = character.code
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
후보 region 경계 선택 화면은 3D terrain renderer 를 유지하되 카메라 pitch/bearing 을
0으로 전환해 폴리곤 경계가 원근감으로 기울어 보이지 않게 한다.
지역 선택 직후 카메라는 사건 좌표가 아니라 선택 region polygon bounds 에
`fitBounds` 로 맞춘다. 이 기준은 하단 선택 시트가 접힌 상태의 가시 영역이다.
사건/region fit 은 하단 시트 padding 이 커질수록 상단 padding 도 크게 늘려, 핀
묶음과 후보 region 이 화면 위쪽 오버레이 뒤에 몰리지 않고 북쪽 지도 여백과 탭 가능한
영역을 확보하게 한다.

### 3.3 StoryController 주요 메서드

| 메서드 | 역할 |
|--------|------|
| `initialize()` | 앱 시작 시 eras 로드, 초기 상태 설정 |
| `selectTestament(String)` | 구약/신약 전환 |
| `selectEra(String)` | 시대 단수 선택 → characters + events 로드 |
| `toggleEraMulti(String)` | v2 — 시대 멀티 선택 토글 |
| `setSelectedEras(Set<String>)` | v2 — 여러 시대 events/characters 합산 |
| `setSelectionMode(SelectionMode)` | v2 — region/character 모드 진입 |
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
| StoryHomeScreen | `screens/story_home_screen.dart` | 메인 화면 (인물+지도+타임라인+프로필). 시트 헤더는 **단일 toggle 동그라미** — 연한 초록 pill (`_activeColor.withAlpha(0.16)` + 0.45 border) 안에 ▲/▼ 한 개. 옛 indicator bar 는 제거 (드래그로 오해되던 문제). 헤더는 명시적 이전 단계 버튼(`시대/방법 변경`, `장소 다시 선택`, `인물 다시 선택`)과 라벨형 stepper(`시대/방법 → 장소/인물 → 이야기`)를 toggle 양옆 같은 줄에 노출해 되돌아가기 경로를 알 수 있게 한다. 인물 선택 중에는 `이전`과 `N명 →` 액션을 작은 pill 로 함께 표시한다. 하단 시트는 화면 맨 아래(`bottom: 0`) 에 붙되 intro/region picker/event cards 별 예상 콘텐츠 높이를 기준으로 열려, 카드 아래에 큰 빈 양피지 영역을 만들지 않는다. 의미 있는 `bottomInset` 이 있을 때만 시트 높이에 더해 nav bar 영역을 피하고, gesture-only/내비바 없음 환경은 화면 끝까지 사용한다. Android 시스템 뒤로가기는 `PopScope` + `utils/home_back_navigation.dart` 로 홈 내부 흐름을 되감는다: region 사건 목록→region 선택→홈, character 사건 선택→인물 선택→홈, 시대만 고른 intro→시대 미선택 홈. 모드별 hint 는 `MapHintOverlay` 가 표시, dismiss state 는 `_mapHintDismissed`. 인물 모드의 region 라벨과 path 표시 우선순위는 `StoryTerrain3dMap` 안의 MapLibre 레이어 z-order 와 GeoJSON 갱신으로 처리한다. |
| ~~LoginScreen~~ | ~~`screens/login_screen.dart`~~ | 삭제됨 — InlineLoginPromptCard로 대체 |
| SavedVersesScreen | `screens/saved_verses_screen.dart` | 저장 구절 |
| LegalDocumentsScreen | `screens/legal_documents_screen.dart` | 법률 문서 |
| ProposalBoardScreen | `screens/proposal_board_screen.dart` | 제안 게시판 (웹 전용) |
| ProposalSubmitScreen | `screens/proposal_submit_screen.dart` | 새 이야기 제안 작성/수정 (5-step wizard: 안내 → 시대 → 인물·위치 → 세부 → **퀴즈**). 마지막 Step 4 는 목회자 작성 선택지 3개 퀴즈 1~3문항 + 제출 버튼. |
| ProposalDetailScreen | `screens/proposal_detail_screen.dart` | 제안 상세 + 댓글. `proposal_type='delete'` 일 때 빨간 삭제 제안 배너 + "수정" 버튼 비노출 + 승인 시 `approveDelete` 분기. |
| NotificationHistoryScreen | `screens/notification_history_screen.dart` | 알림 전체보기 (최근 30일, 2026-04-22) |

> **리팩토링 상태**: `story_home_screen.dart`는 초기 7,172줄 → 현재 ~1,016줄 (−86%).
> 프로필 탭 2,700+줄이 `ProfileTabPage`로 분리되어 자체 상태 관리 + 콜백 3개로 결합도 최소화.
> 퀴즈 완료 시 진행도 새로고침은 `GlobalKey<ProfileTabPageState>`로 처리.

## 5. 위젯 (Widgets)

### 5.1 도메인 위젯

| 위젯 | 파일 | 역할 |
|------|------|------|
| StoryMapPanel | `widgets/story_map_panel.dart` | 운영 지도는 `StoryTerrain3dMap` WebView + MapLibre GL JS 3D 단일 경로다. OpenFreeMap Liberty style 과 공개 Terrarium DEM 에 pitch/bearing/exaggeration 을 적용하며, 별도 API key나 지도 배경 선택 환경변수를 받지 않는다. 예전 flutter_map 2D tile/layer/pin 폴백은 제거됐다. `activeLandmarks` 와 `eraRegionLandmarks` 는 WebView 내부 GeoJSON source 로 전달되고, country boundary/region polygon/label/path/hit-zone 은 MapLibre layer 로, 사건 숫자·감정 핀과 non-region 랜드마크는 DOM marker 로 그린다. 하단 선택 패널 위 pointer 입력은 WebView 에 짧은 tap suppression 을 전달해 패널 버튼/스크롤이 아래 지도 region·랜드마크 선택으로 새지 않게 한다. **`onMapInteraction`** 콜백은 MapLibre 쪽 사용자 제스처 이벤트로 부모의 hint overlay dismiss 를 트리거한다. 이야기 간 이동 glow 는 같은 위치 사건 분산 좌표를 재사용해 현재/목표 사건 핀 중심에 맞춘다. reveal/전환/감정 새김의 중복 실행은 내부 guard 로 막는다. |
| StoryTerrain3dMap | `widgets/map/story_terrain_3d_map.dart` | 운영 3D 전용 WebView 지도. MapLibre GL JS 를 HTML string 으로 로드하고 OpenFreeMap Liberty style + Mapzen Terrarium DEM 을 연결한다. renderer 설정이 바뀔 때만 WebView 를 새로 로드하고, 카메라 변화는 JS `easeTo()`/`fitBounds()`, country boundary/region polygon/라벨/path/event hit-zone 은 GeoJSON `setData()` 로 갱신한다. 사건 숫자/감정 핀과 non-region 랜드마크는 각각의 GeoJSON point 를 MapLibre DOM Marker 로 투영해 지역별 collision/terrain symbol 배치와 무관하게 좌표 위에 고정한다. 인물 선택 이야기 경로는 선택 인물별 GeoJSON line feature 로 나뉘며 `colorForCharacter` 색상과 작은 offset 을 사용해 복수 인물 이동 점선을 함께 보여 준다. 줌/드래그/option-key 조작/지도 컨트롤 입력 직후에는 tap hit-test 를 짧게 무시해 커서 아래 region·랜드마크 팝업이 우발적으로 뜨지 않게 한다. 지역 선택 단계에서는 투명한 region hit fill layer 를 `queryRenderedFeatures` 로 먼저 조회하고, iOS WebView/terrain 조합에서 hit 이 빠질 경우 화면 좌표를 위경도로 역변환해 polygon point-in-polygon 으로 다시 판정한다. 라벨뿐 아니라 폴리곤 내부 탭도 같은 지역 선택으로 처리하고, 겹친 region 은 작은 bbox 를 우선한다. 사건 0개 region 은 polygon/label/hit layer 에 올리지 않는다. 기본 지도 symbol label layer 는 숨겨 영어/현지어 지명 대신 앱의 한국어 라벨만 보이게 한다. JS channel 로 region/event tap 을 Flutter 로 전달한다. 확대/이동 중 발생하는 타일·서브리소스 실패는 debug 로그로만 남기고, 초기 MapLibre `ready` timeout 또는 main frame 실패만 지도 실패 안내로 표시한다. |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 인물 선택 + 이벤트 목록 통합. **헤더(`headerOverride`) 는 sticky** — `Column [header, Expanded(CustomScrollView)]` 구조로 사건 카드 스크롤 시 헤더(toggle + stepper) 가 함께 위로 사라지지 않는다. 헤더는 이전 단계 버튼과 라벨형 stepper 를 유지해 스크롤 중에도 되돌아가기 경로가 사라지지 않는다. step 3 사건 카드(`EventTimelineRow`) 는 `committedSelectedCharacterCodes` + `colorForCommittedCharacter` 를 그대로 forwarding 해 카드 안 인물 pill 이 지도 path 색과 매칭된다. 최근 퀴즈 결과가 있으면 카드 배경색으로 상태를 표시한다(정답 0개=빨강, 일부 정답=주황, 모두 정답=초록). 감정 새김이 있으면 사건 카드 좌상단 배지를 컬러 감정 이모지로 바꾸고 우측 하단의 작은 초록 원에 이야기 순번을 함께 표시한다. 감정 새김 직후에는 상세 페이지를 잠시 닫고 0.5초 뒤 해당 사건 카드 위에 `CompletionCelebration` 감정 도장+별가루를 기존 속도로 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. |
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
| InlineLoginPromptCard | `widgets/inline_login_prompt_card.dart` | 카카오/Google/Apple 3단 인라인 로그인 카드 (버튼 순서: 카카오 → Google → Apple) |
| ShareIdInputDialog | `widgets/share_id_input_dialog.dart` | 7자리 공유 ID 입력 다이얼로그 |
| ProfileEditorDialog | `widgets/profile_editor_dialog.dart` | 프로필(닉네임/사진/기도제목) 수정 |

### 5.3 story_home_screen에서 추출한 페이지 (3차 리팩토링)

| 위젯 | 파일 | 역할 |
|------|------|------|
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (ConsumerStatefulWidget, 콜백으로 동작). 상단은 연도 메타 없이 제목과 별표 저장 토글을 한 줄로 보여 주고, **요약 이야기 → 장면 이미지 → 본문 읽고 퀴즈 풀기** 순서로 배치한다. 본문 읽기 버튼은 사건의 모든 `bible_refs`를 성경 리더의 사건 읽기 모드로 전달한다. 리더에서 마지막 본문까지 보고 **읽기 완료**를 누른 경우에만 읽음 처리하며, 리더의 뒤로가기(`<`)로 나가면 읽음 처리하지 않는다. 퀴즈 결과는 정답/오답/헷갈림으로 나누고 `user_quiz_attempts`에 저장해 버튼 라벨과 프로필 지역 복습 팝업에 반영한다. 퀴즈 버튼은 `정답 N · 오답 N · 헷갈림 N` 형식으로 표시하고 정답 0개=빨강, 일부 정답=주황, 모두 정답=초록으로 칠한다. 본문 읽기 + 퀴즈 완료 후에만 **지도 위에 새기기** 버튼이 활성화되고, 8개 감정 중 하나와 100자 메모를 `user_event_emotion_marks`에 저장하면 사건 완료로 전환된다. 감정 선택 보기와 지도/카드 배지는 같은 컬러 감정 이모지 세트를 쓴다. 새김 완료 버튼은 `감정 - 메모` 형식으로 바로 보여 주고 "완료 취소"를 누르면 감정 row를 삭제해 지도 핀/카드 이모지도 제거한다. 감정 저장이 끝나면 부모 화면에 `onEmotionEngraved`를 알려 상세 페이지를 닫고 지도 핀/카드 감정 배지를 반영한 상태에서 0.5초 뒤 해당 사건 카드 위 감정 도장+별가루를 기존 속도로 재생하며, 도장 완료 후 1초 기다렸다가 같은 상세로 돌아온다. 지도 위 감정 도장 및 이전/다음 이야기 전환 애니메이션은 내부 재진입 가드로 중복 실행을 막되, 평상시 지도·패널·상단 버튼 입력은 차단하지 않는다. 이전/다음 이야기 카드를 누르면 상세 페이지를 닫고 지도 위 현재 사건과 목표 사건 번호 핀이 약 2초간 함께 빛난 뒤 목표 상세 페이지를 연다. 사역자/관리자에게만 **"이 이야기 삭제 제안"** 버튼 노출 (`_DeleteProposalButton` 서브 위젯). 이미 완료된 사건으로 진입한 경우 우측 "다음 이야기" 카드를 `PulseHighlight` 로 박동. |
| EventQuizDialog | `widgets/event_quiz_dialog.dart` | 사건 상세/주간 퀴즈에서 쓰는 사건 퀴즈 다이얼로그. 선택 후 **정답 확인**을 누르면 해당 문항의 정답/오답/헷갈림과 해설을 즉시 보여 주고, **다음**으로 이동한다. 마지막에는 전체 문항, 내 선택, 해설 리뷰를 확인한 뒤 `EventQuizResult`로 저장 값을 반환한다. |
| CompletionCelebration | `widgets/completion_celebration.dart` | 자식 위젯을 감싸 GlobalKey 로 `play(stampLabel:)` 호출 시 두 단계 축하 효과: (1) 별가루 + 초록 글로우 1.2s, (2) 끝나면 금박 도장이 슬램+흔듦+페이드 0.95s. 기본 라벨은 "완료"지만 이야기 완료에서는 선택 감정 심볼을 넘긴다. 도장 종료 시 옵션 `onComplete` 콜백 호출. EventDetailPage 의 read+quiz 박스에 부착. |
| PulseHighlight | `widgets/pulse_highlight.dart` | `active` 인 동안 자식 외곽에 1.4s 사이클로 0→1→0 박동하는 골드 glow 를 그리는 래퍼. EventDetailPage 의 "다음 이야기" 카드에 부착해 다음 이동 동선을 시각적으로 유도. |
| AvatarProgressRing | `widgets/avatar_progress_ring.dart` | 아바타 둘레에 초록 원형 progress 호를 그리는 래퍼 (12시 방향 시계방향, 항상 초록). 옵션 `name` 을 주면 아바타 내부 하단에 솔리드 다크 pill 라벨을 오버레이해 외부 텍스트 라인을 제거. ProfileTabPage 인물 진행도 행에서 LinearProgressIndicator 대체로 사용. |
| EraPickRows | `widgets/v2/era_pick_rows.dart` | 시대 선택 칩 — 구약/신약 두 줄. HomeIntroPanel + ProfileTabPage 의 "장소로 시작" 탭 공유. `eraIconFor(code)` 도 export. |
| HomeIntroPanel | `widgets/v2/home_intro_panel.dart` | 첫 화면 "오늘은 성경 어디를 여행해볼까요?" 패널. 두 단계: ① **여행할 시대** (구약/신약 칩, 단일 선택) ② **어떻게 볼까요?** (장소에서 시작 / 인물과 걷기). 시대를 고른 뒤에는 ① 영역(헤더+칩) 이 `AnimatedOpacity` 0.55 로 흐려지고 ② 헤더는 `ink800` + 굵은 글씨로 차별화되어 다음 행동을 유도. 제목/하단 안내 문구는 `FittedBox.scaleDown` + `maxLines:1` 로 좁은 폰에서도 1줄 보장. |
| MapHintOverlay | `widgets/v2/map_hint_overlay.dart` | 지도 위 흐릿한 검정 패널 안내 문구. 상단 배지에 "화면 아무데나 누르면 사라집니다"를 통일 노출해 고정 안내가 아니라 임시 안내임을 드러낸다. 모드별로 다른 메시지: region picker 단계 = "노란 지역을 눌러…", character step 2 = "인물을 골라 「→」 버튼…". 안내가 떠 있는 동안 지도·안내문·하단 시트 어디든 pointer down 이 들어오면 dismiss 한다. 지도 오버레이 영역은 `IgnorePointer` 로 입력을 막지 않아 첫 탭도 아래 MapLibre hit-test 로 전달되고, 하단 시트 입력은 힌트 dismiss 와 기존 버튼/스크롤 동작을 함께 처리한다. MapLibre 일반 탭도 `onMapInteraction` 으로 부모에 전달된다. 장소 선택 모드 전환 직후에는 버튼 터치 누수 방지 suppression 을 짧게 정리해 후속 region 탭을 빠르게 받는다. dismiss flag 는 `StoryHomeScreen._mapHintDismissed`. |
| ProfileMiniMap | `widgets/profile/profile_mini_map.dart` | 프로필 "장소로 시작" 탭의 미니 맵. 선택된 시대의 region 폴리곤을 진행률로 알파 채움(검정→시대컬러), 라벨에 완료 이야기 수와 지역 퀴즈 정답/풀이 수를 `x/x`로 함께 표시한다. region 폴리곤이나 라벨을 누르면 그 지역 사건 카드 팝업이 열리고, 사건 카드 순서대로 `순번 → 첫 장면 썸네일 → 제목/정답·오답·헷갈림`을 표시하며 빨강/주황/초록 복습 상태를 카드 배경색으로 보여 준다. 모든 사건에 감정이 새겨진 region 은 지도 색과 이질감이 적은 옅은 채움 + 골드 경계선만 남겨 딱지를 모은 느낌을 준다. point-in-polygon 으로 사건↔region 매핑. |
| ProfileLifeMap | `widgets/profile/profile_life_map.dart` | 프로필 "내 삶의 지도" 탭의 감정 새김 지도. `EventEmotionOption`의 8개 감정(기쁨/기대/감사/놀라움/안타까움/위로/두려움/기타)과 지도 영역을 1:1로 맞추고, 각 영역의 최근 새김 수와 최근 남긴 한 줄을 보여 준다. 제목 옆 `?` 버튼은 기능 안내 팝업을 열어 감정 지도 의미, 감정 지역 탭 복습, 감정 분포로 얻을 수 있는 삶의 시야 인사이트, 한 줄 메모 활용법을 설명한다. 감정 영역 배지는 컬러 이모지+개수를 하나의 pill 로 표시하며, 영역 탭 시 `ProfileEventReviewGrid`로 사건 카드를 Era → storyIndex 순서의 2열 스크롤 그리드로 보여 주고 첫 era 및 era 변경 지점에 경계 마커를 표시한다. 최근 한 줄 날짜는 `utils/kst_date.dart`의 KST 달력 날짜 포맷터를 사용해 기기 로컬 시간대에 따라 다음 날로 밀리지 않게 표시한다. |
| ProfileEventReviewGrid | `widgets/profile/profile_event_review_grid.dart` | 프로필 복습/감정 사건 목록 공용 그리드. `StoryEventThumbCard`를 3열로 배치하고 첫 era 및 era 변경 지점만 가는 경계선+era 이름으로 표시한다. 내 삶의 지도 감정 영역 팝업과 기록 탭 오답/헷갈림 팝업이 공유한다. |
| StoryMapPanelController | `widgets/story_map_panel.dart` | 지도 외부 제어 API. 줌/포커스/reveal 외에 상세 페이지 이전/다음 이동용 `playEventTransition(from, to)` 로 현재/목표 사건 번호 핀을 함께 빛나게 하는 1회성 전환을 재생한다. 전환 glow 는 `map_math.buildRankedEventPointMap`의 분산 좌표를 사용해 번호 핀 중심과 맞춘다. |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (자체 상태 관리, 우측 별 아이콘으로 단일 구절 저장/해제). 구절 본문 탭은 선택 상태를 만들지 않는다. 일반 진입은 책/장 탐색과 저장 구절 이동을 유지한다. 이야기 상세에서 진입하면 사건 읽기 모드로 전환해 해당 `bible_refs` 범위의 절만 표시하고, 여러 본문이면 **다음**으로 순차 이동한 뒤 마지막에 **읽기 완료** 버튼을 보여 준다. 이 완료 버튼으로 닫힌 경우에만 사건 읽음 처리가 된다. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 금주 인물 학습 탭 (자체 데이터 로딩 + 상태) |
| ProfileTabPage | `widgets/profile_tab_page.dart` | 프로필 탭. 컴팩트 헤더(아바타 40px + 이름 + **수정 / 설정(톱니)** 두 버튼)는 첫 컨텐츠 컨테이너 위에 독립 배치하고, 아바타/이름 탭도 프로필 수정 다이얼로그로 진입한다. 컨테이너 안에는 **기록/기도/저장/말씀** 탭 + **"진행률 표시" 섹션** (탭 pinned, 컨텐츠 스크롤)을 둔다. 기도 탭의 "내 기도" 텍스트를 누르면 같은 프로필 수정 다이얼로그에서 기도제목을 바로 수정할 수 있다. 기록 탭은 푼 이야기 안의 퀴즈 문항 단위로 정답/오답/헷갈림 개수를 누적해 `N문항 · M이야기` 형식으로 보여 주고 오답/헷갈림 섹션 탭 시 팝업에서 `ProfileEventReviewGrid`로 해당 사건 카드를 Era → storyIndex 순서의 3열 스크롤 그리드로 표시한다. 저장 탭은 별표 저장한 이야기를 요약 없는 넓은 StoryEventThumbCard 가로 캐러셀과 전체 보기로 보여 준다. 말씀 탭은 `SavedVerseRow` 디자인으로 저장한 말씀을 최대 2.5개 미리 보여 주고 하단 전체 보기로 `SavedVersesScreen`에 진입한다. 장소 미니맵의 지역 라벨/폴리곤에서 퀴즈 복습 팝업으로 진입한다. 설정 시트(`profile_settings_sheet.dart`)에 개인정보 보호 / 글자 크기 변경 / 로그아웃 + admin@brand-i.net 푸터. |
| QuizTabPage | `widgets/quiz/quiz_tab_page.dart` | 홈 상단 "퀴즈" 버튼이 여는 페이지. 두 탭: **매일 퀴즈** (가변 선택지 + 제출 → 도장+별가루 + 해설) + **주간 퀴즈** (embedded WeeklyTabPage). |
| DailyQuizSection | `widgets/quiz/daily_quiz_section.dart` | `daily_quiz` 테이블의 최신 1문제. `choices` 배열 길이만큼 선택지를 렌더링하고, 선택 → 제출 → CompletionCelebration 발화 + 정/오답 결과 + 해설. |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 주간 학습 (embedded 모드 지원). **두 모드** — `WeeklyMode.character` (랜덤 인물 + 그 인물의 사건) / `WeeklyMode.region` (랜덤 시대 + 사건이 있는 랜덤 region + 그 region 사건). 시드(`seedFromKey(weekKey)`)로 50/50 결정. 헤더는 모드별 분기 ("금주 인물" / "금주 지역: 시대 · 지역"). 지도 = StoryMapPanel(decorate=false, region 모드는 `eraRegionLandmarks: [region]`). 하단 = EventTimelineRow (홈과 동일 카드/스크롤/포커스 동기). 카드 탭 시 `quizWeekKey` 함께 EventDetailPage 진입 → 진행도가 `weekly_quiz_progress` 테이블에 독립 저장. |
| CharacterAvatar | `widgets/character_avatar.dart` | 인물 아바타 (주간/프로필 공용) |

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
| flutter_map | ^8.2.1 | 프로필 미니맵/제안 위치 선택기 등 보조 2D 지도와 `LatLngBounds` 유틸 |
| latlong2 | ^0.9.1 | 좌표 계산 |
| flutter_dotenv | ^5.2.1 | .env 환경변수 |
| shared_preferences | ^2.5.5 | 로컬 키-값 저장 (글자 크기 등 사용자 선호 설정) |
| sign_in_with_apple | ^6.1.4 | Apple 로그인 |
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
