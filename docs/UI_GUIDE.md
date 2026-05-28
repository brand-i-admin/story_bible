# UI 가이드 — 이야기 성경

> 최종 수정: 2026-04-22 (알림/제안/금주 인물 반영)
> 기존 `docs/story_bible_prototype_design.md`의 UX 설계를 기반으로 정리.

## 1. 디자인 철학

- **고지도/양피지 테마**: 성경 시대의 분위기를 시각적으로 전달
- **게임형 UI**: 진행도, XP, 완료 체크 등 게이미피케이션 요소
- **정보 밀도 vs 여백**: 데스크탑은 3열로 정보 밀도 높게, 모바일은 단계적 공개

## 2. 컬러 팔레트

> **단일 진실 소스**: `lib/theme/tokens.dart` (`AppColors` / `AppRadii` / `AppSpacing` / `AppShadows`).
> 위젯/화면에서 `Color(0x...)`를 직접 쓰지 말고 토큰만 참조한다. 출처: Claude Design 핸드오프 번들 `colors_and_type.css`.

### 2.1 기본 테마

```dart
// app.dart
import 'theme/app_theme.dart';

MaterialApp(theme: AppTheme.light(), ...)
// 내부적으로 ColorScheme.fromSeed(seedColor: AppColors.seed)
//        + scaffoldBackgroundColor: AppColors.parchmentBg
```

| 용도 | 토큰 | 코드 |
|------|------|------|
| 배경 (양피지) | `AppColors.parchmentBg` | `#EEE0C6` |
| 주 액센트 (브라운 시드) | `AppColors.seed` | `#8B5A2B` |
| 골드 액션 | `AppColors.gold` | `#D4A439` |
| 텍스트 본문 | `AppColors.ink700` | `#3E2723` |
| 카드 표면 | `AppColors.parchmentCard` | `#F7EBD8` |
| 완료 그린 | `AppColors.greenTop` / `greenBot` | `#48A86B` / `#2D7B4D` |

### 2.2 인물 색상 팔레트 (8색 고정)

> 코드: `AppColors.characterAt(index)` — `i % 8` 자동 순환.

복수 인물 선택 시 각 인물에 순서대로 할당:

| 인덱스 | 색상 | 코드 | 용도 |
|--------|------|------|------|
| 0 | 블루 | `#3B6C94` | 첫 번째 인물 |
| 1 | 오렌지 | `#B6673C` | 두 번째 인물 |
| 2 | 그린 | `#557C3E` | 세 번째 인물 |
| 3 | 로즈 | `#8A4E5D` | 네 번째 인물 |
| 4 | 그레이 | `#616161` | 다섯 번째 |
| 5 | 골드 | `#9E7C24` | 여섯 번째 |
| 6 | 브라운 | `#7B5D43` | 일곱 번째 |
| 7 | 인디고 | `#5C6B9F` | 여덟 번째 |

8명 초과 시 팔레트 순환 (`i % 8`).

## 3. 레이아웃

### 3.1 메인 화면 (풀스크린 지도 + 오버레이)

```
┌─────────────────────────────────────────────────────────────┐
│ [사건선택] [금주 인물] [성경] [프로필] [🔔] [이야기 등록*]  🔍 │
│                                                              + │
│                      (flutter_map 전체화면)                  - │
│                                                              ▶ │
│   [핀]        [핀]         [핀]                                │
│          [핀]      [핀]                                        │
│                                                                │
│   ┌─────────────────────────────────────────┐                 │
│   │   [1.시대] [2.인물] [3.사건] [구약|신약]  [다음] │           │
│   │   (3단계 선택 Panel, 드래그로 접기 가능)   │                 │
│   └─────────────────────────────────────────┘                 │
└─────────────────────────────────────────────────────────────┘

*'이야기 등록'은 웹 전용 (kIsWeb 분기).
🔔 = NotificationBellButton — 미독 1개 이상이면 빨간 `!` 배지.
```

### 3.2 반응형 기준

| 구분 | 너비 | 레이아웃 |
|------|------|----------|
| Desktop | ≥1280px | 3열 고정 |
| Tablet | 900~1279px | 좌/우 패널 폭 축소 |
| Mobile | <900px | 인물: Drawer, 이벤트: BottomSheet |

## 4. 주요 위젯 컴포넌트

### 4.1 위젯 목록

| 위젯 | 파일 | 역할 |
|------|------|------|
| StoryMapPanel | `widgets/story_map_panel.dart` | 인터랙티브 지도, 핀/마커 렌더링, 감정 새김이 있으면 큰 컬러 감정 이모지를 중심에 두고 우측 아래 작은 초록 원에 순서 번호를 표시, 이야기 간 이동 시 실제 번호 핀 분산 좌표에 맞춘 현재/목표 사건 핀 동시 glow 애니메이션 |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 시대·인물·사건 3단계 선택 통합 패널. 사건 카드 배지도 감정 새김이 있으면 큰 컬러 감정 이모지 + 우측 아래 작은 초록 순서 번호로 표시하고, 퀴즈 결과가 있으면 카드 배경색으로 정답 0개=빨강 / 일부 정답=주황 / 모두 정답=초록 상태를 보여 준다. 감정 새김 직후 0.5초 뒤 해당 카드 위에 감정 도장+별가루를 기존 속도로 재생하고, 도장 완료 후 1초 뒤 상세로 복귀한다 |
| CharacterPanel | `widgets/character_panel.dart` | 개별 인물 카드 (아바타, 이름, 설명) |
| ParchmentDialog | `widgets/parchment_dialog.dart` | 양피지 스타일 이야기 상세 모달 |
| ParchmentPageScaffold | `widgets/parchment_page_scaffold.dart` | 양피지 배경 페이지 템플릿 |
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (한 줄 제목 + 요약 이야기 + 장면 이미지 + 퀴즈) |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 금주의 인물 탭 |
| ProfileTabPage | `widgets/profile_tab_page.dart` | 프로필 탭 (아바타/이름/수정·설정 헤더는 첫 컨테이너 위에 분리, 기록, 기도, 저장한 이야기, 저장한 말씀, 진행도) |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (우측 별 아이콘 구절 저장 + 이야기 본문 읽기 모드). 일반 성경 진입은 책/장 탐색을 유지하고, 사건 상세에서 진입하면 해당 `bible_refs` 범위의 절만 표시한다. 여러 본문은 **다음**으로 순차 이동하고 마지막 본문에서 **읽기 완료**를 눌러야 읽음 처리된다. 구절 본문 탭은 선택/저장 동작을 만들지 않는다 |
| SearchBottomSheet | `widgets/search_bottom_sheet.dart` | 검색 입력 + 결과 (bottom sheet) |
| GameUiSkin | `widgets/game_ui_skin.dart` | 커스텀 테마 데코레이션 |
| NotificationBellButton | `widgets/notification/notification_bell_button.dart` | 상단 종 아이콘 + 빨간 ! 배지 + 드롭다운 |
| NotificationDropdown | `widgets/notification/notification_dropdown.dart` | 미독 최대 5개 + 모두 읽음 / 전체 보기 |

> 삭제된 위젯 (참고): `StoryListPanel`, `EraSelector`, `SearchBox` — 역할이 `StorySelectionPanel`·`SearchBottomSheet` 로 통합됨.

### 4.2 GameUiSkin 테마 시스템

`game_ui_skin.dart`에서 커스텀 데코레이션을 정의:
- 패널 배경: 양피지 질감 그래디언트
- 보더: 골드/브라운 테두리
- 그림자: 부드러운 드롭섀도
- 버튼: 골드 액션, 브라운 보조

### 4.3 디자인 시스템 모듈 (`lib/theme/`)

| 파일 | 책임 |
|------|------|
| `tokens.dart` | `AppColors` · `AppRadii` · `AppSpacing` · `AppShadows` · `AppFontSizes` · `AppLineHeights` |
| `typography.dart` | `AppTextStyles` — `.sb-h1/h2/h3/body/subtitle/chip/buttonLabel/hint/counter` |
| `surfaces.dart` | `AppSurfaces.modal/dialog/floating/card` BoxDecoration 팩토리 |
| `app_theme.dart` | `AppTheme.light()` 전역 ThemeData |

**규칙**:
- 신규 위젯은 토큰만 사용. `Color(0x...)`, 임의 패딩, 임의 라운딩 금지.
- 모달·다이얼로그·카드 등 표면은 `AppSurfaces` 팩토리부터 검토.
- 새 값이 정말 필요하면 토큰에 추가한 뒤 참조한다.

### 4.4 Polygon — 장소로 보기 region 표현 (Ancient Atlas Discovery 양식)

"지도에서 영역을 선택했다" 가 아니라 **"고대 성경 세계의 한 지역을 발견했다"**
느낌. GIS 식 striped/sharp polygon overlay 금지 — fantasy atlas / ancient
parchment / fog-of-war reveal 톤. **색 톤은 후보/선택 두 상태만 표현**:

- **후보** (`AppColors.regionCandidate` = 0xFFF2C04F) — 밝은 따뜻한 옐로우 골드.
  시대를 켰을 때 그 시대의 모든 region 이 노란색으로 떠오른다.
- **선택** (`AppColors.regionSelected` = 0xFF9CCB75) — 밝은 fresh sage green.
  특정 region 을 탭하면 초록으로 전환되어 후보들과 명확히 분리된다.

ancient atlas 양피지 위에서 또렷이 살아남도록 stepper accent 의 어두운 톤
(D2873E/77A85A) 보다 더 밝고 채도 높은 값을 사용. era 식별은 era_pick_rows 의
점·아이콘 색(`EraColors.forCode`)이 별도로 표시한다.

**4-layer 양식** (모두 정적 — pulse 애니메이션 제거):

| Layer | 값 | 의도 |
|-------|------|------|
| 1. Outer Glow | candidate/selected 색 alpha 비선택 0.12 / 선택 0.18, `MaskFilter.blur(outer, 9~12)` | 폴리곤 바깥 후광 — 절제. 옛 sin 펄스로 인한 "어두운 깜빡거림" 인상 제거 |
| **2a. White Wash** | `AppColors.regionParchmentWash` (#FFF7E8) alpha **0.45**, `MaskFilter.blur(solid, 2.5)` | **베이지 양피지 베이스 중성화** — 색 fill 위로 베이스가 비쳐 갈색·짙은녹으로 흐려지는 문제 차단. watercolor 결은 wash 너머로 은은히 비침 |
| 2b. Color Fill | candidate/selected 색 radial gradient (비선택 중앙 0.50 / 가장자리 0.36, 선택 중앙 0.62 / 가장자리 0.48), `MaskFilter.blur(solid, 2.5)` | wash 위로 의도된 톤이 또렷이 살아남. ancient atlas / fantasy map 의 정통 parchment+ink wash 2-pass 기법 |
| 3. Ink Border | 후보/선택 모두 fill 과 동일한 candidate/selected 색 그대로 (lerp 제거 — 갈색 섞임 없음). halo (strokeWidth 4~6 alpha 0.12~0.20 + blur 4) + inner fade gradient (clipPath + blurred stroke 8~12px) + 메인 (strokeWidth 2.0~2.6 alpha 0.70~0.85 + blur 0.8) 세 패스 | 한 덩어리 인지 + 잉크 번진 결. 외곽선 색이 fill 과 같아 시각적으로 한 영역으로 묶임 |

**Pulse 애니메이션 제거** — 옛 1.6초 주기 sin 펄스(alpha/sigma/width 변동)는
양피지 톤과 어울리지 않는 "어두운 색의 깜빡거림" 으로 인식돼 제거. `EraPolygonEntry.pulseT`
필드와 `story_map_panel._polygonGlowCtl` 도 함께 사라져 매 프레임 rebuild 비용 절감.
**Selection settle 애니메이션**(scale overshoot + glow boost, 500ms 1회)은 유지 —
선택 진입 시 한 번만 강조되고 끝나므로 거슬리지 않음.

**Selection settle 애니메이션 (production-grade, 500ms)** — region 이 새로
선택되면 2-phase 곡선으로 elevated state 에 settle:

- **Scale (500ms)**: 1.0 → +6% overshoot peak (~100ms, easeOutCubic) →
  +3% elevated (~400ms, easeOutQuad). **1.0 으로 안 돌아가고 +3% 에서 머무름**
  — 선택된 region 은 영구히 살짝 부풀어 시각적으로 "선택됨" 강조.
- **Glow boost (500ms)**: factor 1.0 (peak alpha +0.35 / sigma +12px / halo
  alpha +0.25) → ~150ms peak hold → factor 0.35 elevated 유지 (peak alpha
  +0.12 / sigma +4.2px / halo alpha +0.09). Scale 보다 늦게 settle 시작해
  layered depth 감.
- **발동 트리거**: `EraPolygonGlowLayer` (`StatefulWidget`) 가
  `didUpdateWidget` 에서 selection key 변화를 감지해
  `AnimationController.forward(from: 0)`. AnimationController 가 1.0 에서
  멈춘 뒤에도 painter 는 계속 elevated 값을 적용.

> 이전 sin hump (1.0 → 1.10 → 1.0) 디자인은 만화적 "boing" 효과로 production
> 미달이라 폐기. Apple/Linear 같은 production app 의 selection 패턴을 따라
> "도착 후 elevated 유지" 로 재설계.

추가: 정점은 **Catmull-Rom spline** 으로 곡선화 (tension 0.5) — 사람이 손으로
찍은 jagged polygon 도 부드러운 양피지 곡선으로 재현. closed loop wrap-around.

구현은 `lib/widgets/map/era_polygon_glow_layer.dart` 의 `EraPolygonGlowLayer`.
`flutter_map` 의 `PolygonLayer` 가 단색 fill 만 지원해 multi-layer + shader +
MaskFilter 조합을 위해 별도 `CustomPainter` 레이어로 분리. 클릭 hit-test 는
동일 좌표의 투명 `PolygonLayer<Landmark>` 가 담당.

구현은 `lib/widgets/map/era_polygon_glow_layer.dart` 의 `EraPolygonGlowLayer`.
`flutter_map` 의 `PolygonLayer` 가 단색 fill 만 지원해 multi-pass wash 효과를
적용할 수 없어 별도 `CustomPainter` 레이어로 분리. 클릭 hit-test 는 동일
좌표의 투명 `PolygonLayer<Landmark>` 가 담당해 책임 분리.

## 5. 인터랙션 패턴

### 5.1 시대 → 인물 → 이벤트 흐름

1. 구약/신약 토글 → 해당 시대 목록 표시
2. 시대 탭 선택 → 인물 목록 로드 + 지도 중심 이동
3. 인물 선택 (복수 가능) → 타임라인 병합 표시
4. 이벤트 카드 클릭 → 지도 핀 강조 + 상세 다이얼로그

### 5.2 검색 → 자동 네비게이션

1. 검색어 입력 (220ms 디바운스)
2. 결과 선택 → 시대/인물 자동 선택 + 이벤트 포커스
3. 지도 해당 위치로 이동

### 5.3 학습 완료

1. 이야기 상세 → 본문 읽기 + 퀴즈 시작 (4번 보기는 항상 "헷갈렸어요"). 본문 읽기는 사건에 연결된 절만 성경 리더에서 보여 주며, 여러 본문이면 **다음**으로 이동하고 마지막 **읽기 완료** 버튼을 눌러야 완료된다. 뒤로가기(`<`)로 나가면 읽음 처리하지 않는다
2. 정답 제출 → 정답/오답/헷갈림을 `user_quiz_attempts`에 저장
3. 본문 읽기와 퀴즈가 모두 완료되면 **지도 위에 새기기** 버튼 활성화
4. 감정 8개 중 하나를 고르고 100자 메모를 남기면 `user_event_emotion_marks` 저장
5. 읽기+퀴즈+감정 새김이 모두 끝났을 때 `user_event_progress.is_completed=true` 저장, 도장 문구는 "완료" 대신 선택 감정 심볼. 감정 새김 버튼은 `감정 - 메모`로 표시하고 "완료 취소" 시 감정 row를 삭제해 지도/카드 이모지를 제거한다
6. `notify_quiz_completed` RPC 호출 → 본인 인앱 bell 에 완료 알림 + 전체 진도율 표시
7. 퀴즈 버튼은 `정답 N · 오답 N · 헷갈림 N` 으로 표시하고 정답 0개=빨강, 일부 정답=주황, 모두 정답=초록으로 상태를 보여 준다
8. 지도 번호 핀은 숫자 중심을 유지하고 작은 컬러 감정 이모지 배지를 붙인다. 하단 사건 카드는 감정 새김이 있으면 좌상단 배지를 컬러 감정 이모지로 바꾸고, 우측 하단 작은 초록 원에 이야기 순번을 표시한다
9. 감정 저장 직후 상세 페이지를 잠시 닫아 지도 화면에서 핀/카드 변화를 먼저 보여 주고, 0.5초 뒤 사건 카드 위 감정 도장+별가루를 기존 속도로 재생한 다음 도장 완료 후 1초 뒤 같은 상세로 복귀한다. 지도 위 감정 도장 및 이전/다음 이야기 전환 애니메이션 중에는 투명 입력 차단막으로 다른 화면 조작을 막는다
10. 프로필 미니맵 지역 라벨은 완료 이야기 수와 퀴즈 정답/풀이 수를 `x/x`로 표시해 오답/헷갈림이 있는 지역을 드러낸다
11. 프로필 미니맵에서 region 폴리곤이나 라벨을 누르면 지역별 사건 카드 팝업을 열고, 사건 카드 순서대로 순번·첫 장면 썸네일·정답/오답/헷갈림을 표시하며 각 카드 배경색으로 미풀이/빨강/주황/초록 복습 상태를 보여 준다
12. 프로필 미니맵은 모든 이야기에 감정을 새긴 지역을 옅은 채움 + 경계선만 남겨 딱지를 모은 느낌으로 표시한다
13. 프로필 기록 탭의 정답/오답/헷갈려요 통계는 `N문항 · M이야기` 형식으로 문항 수와 복습 진입 시 보이는 이야기 수를 함께 보여 주고, 0개 상태 안내문은 한 줄로 유지한다. 오답/헷갈려요 섹션은 탭 시 팝업에서 해당 사건 카드를 3열 그리드로 보여 주며, 첫 era 와 era 변경 지점에만 가는 경계선+era 이름을 표시한다
14. 프로필 말씀 탭은 전체 저장 말씀 화면과 같은 `SavedVerseRow`를 재사용하고, 미리보기는 최대 2.5개만 보여 준 뒤 하단 전체 보기로 전체 목록에 진입한다
15. 프로필 "내 삶의 지도"는 감정 선택지 8개(기쁨/기대/감사/놀라움/안타까움/위로/두려움/기타)와 영역을 1:1로 대응시켜, 지도에 없는 별도 정서 이름이 카테고리처럼 보이지 않게 한다. 감정 영역 팝업은 기록 탭 오답/헷갈림 팝업과 같은 사건 그리드를 공유하되 카드 overflow 방지를 위해 2열로 표시하고, 한 era 만 있어도 처음에 era 경계 마커를 표시한다
16. 게이미피케이션(score/xp) 없음 — 완료 플래그만 기록 (ADR 참조)

### 5.4 알림 (Bell)

1. 상단 🔔 아이콘 클릭 → 드롭다운 오픈 (미독 최대 5개)
2. 알림 탭 → `mark_notification_read` RPC + deep link 라우팅
   (`/proposal/<id>`, `/event/<id>`, `/weekly` 중 하나)
3. 모바일/태블릿에서 제안 관련 알림 탭 → "컴퓨터에서 확인하세요" 다이얼로그
4. "전체 보기" → `NotificationHistoryScreen` (최근 30일, 읽은 것 포함)

## 6. 접근성

### 글자 크기 토글 (Aa)

홈 화면 상단 row 우측에 `Aa` 버튼을 배치한다. 탭 시 바텀시트가 열리며 미리보기 문구("태초에 하나님이 천지를 창조하시니라 (창세기 1:1)")와 3단계(작게/보통/크게) 버튼이 표시된다. 선택 즉시 `MediaQuery.textScaler`로 앱 전체 텍스트에 반영되고 `SharedPreferences`에 저장된다. 서브 페이지(`SubPageScaffold`, `ParchmentPageScaffold`)에는 별도 Aa 버튼을 두지 않는다 — 홈에서 한 번 설정하면 모든 화면에 전역 적용되기 때문이다.

## 7. 이미지 에셋 규격

| 에셋 | 원본 | 썸네일 | 형식 |
|------|------|--------|------|
| 인물 아바타 | `assets/avatars/` | `assets/avatars_thumbs/` | PNG |
| 장면 이미지 | `assets/story_images/` (4장/이벤트) | `assets/story_images_thumbs/` | PNG |
| UI 장식 | `assets/elements/` | — | PNG |
| 지도 | `assets/maps/` (GeoJSON) | — | GeoJSON |
