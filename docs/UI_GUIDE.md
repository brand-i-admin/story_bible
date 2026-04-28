# UI 가이드 — 이야기 성경

> 최종 수정: 2026-04-22 (알림/제안/금주 인물 반영)
> 기존 `docs/story_bible_prototype_design.md`의 UX 설계를 기반으로 정리.

## 1. 디자인 철학

- **고지도/양피지 테마**: 성경 시대의 분위기를 시각적으로 전달
- **게임형 UI**: 진행도, XP, 완료 체크 등 게이미피케이션 요소
- **정보 밀도 vs 여백**: 데스크탑은 3열로 정보 밀도 높게, 모바일은 단계적 공개

## 2. 컬러 팔레트

### 2.1 기본 테마

```dart
// app.dart
ColorScheme.fromSeed(seedColor: Color(0xFF8B5A2B))  // 브라운 시드
scaffoldBackgroundColor: Color(0xFFEEE0C6)            // 양피지 배경
```

| 용도 | 색상 | 코드 |
|------|------|------|
| 배경 (양피지) | 연한 베이지 | `#EEE0C6` |
| 주 액센트 (브라운) | 따뜻한 갈색 | `#8B5A2B` |
| 골드 액션 버튼 | 골드 | `#D4A439` |
| 텍스트 (본문) | 다크 브라운 | `#3E2723` |

### 2.2 인물 색상 팔레트 (8색 고정)

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
| StoryMapPanel | `widgets/story_map_panel.dart` | 인터랙티브 지도, 핀/마커 렌더링 |
| StorySelectionPanel | `widgets/story_selection_panel.dart` | 시대·인물·사건 3단계 선택 통합 패널 |
| CharacterPanel | `widgets/character_panel.dart` | 개별 인물 카드 (아바타, 이름, 설명) |
| ParchmentDialog | `widgets/parchment_dialog.dart` | 양피지 스타일 이야기 상세 모달 |
| ParchmentPageScaffold | `widgets/parchment_page_scaffold.dart` | 양피지 배경 페이지 템플릿 |
| EventDetailPage | `widgets/event_detail_page.dart` | 사건 상세 페이지 (장면 이미지 + 퀴즈) |
| WeeklyTabPage | `widgets/weekly_tab_page.dart` | 금주의 인물 탭 |
| ProfileTabPage | `widgets/profile_tab_page.dart` | 프로필 탭 (진행도, 노트, 구절, 기도) |
| BibleReaderPage | `widgets/bible_reader_page.dart` | 성경 리더 페이지 (구절 북마크) |
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

1. 이야기 상세 → 퀴즈 시작 (4지선다)
2. 정답 제출 → `user_event_progress.is_completed=true` 저장
3. `notify_quiz_completed` RPC 호출 → 본인 인앱 bell 에 완료 알림 + 전체 진도율 표시
4. 인물별 진행률 / 출석·학습 연속일수 프로필 탭에서 갱신
5. 게이미피케이션(score/xp) 없음 — 완료 플래그만 기록 (ADR 참조)

### 5.4 알림 (Bell)

1. 상단 🔔 아이콘 클릭 → 드롭다운 오픈 (미독 최대 5개)
2. 알림 탭 → `mark_notification_read` RPC + deep link 라우팅
   (`/proposal/<id>`, `/event/<id>`, `/weekly` 중 하나)
3. 모바일/태블릿에서 제안 관련 알림 탭 → "컴퓨터에서 확인하세요" 다이얼로그
4. "전체 보기" → `NotificationHistoryScreen` (최근 30일, 읽은 것 포함)

## 6. 이미지 에셋 규격

| 에셋 | 원본 | 썸네일 | 형식 |
|------|------|--------|------|
| 인물 아바타 | `assets/avatars/` | `assets/avatars_thumbs/` | PNG |
| 장면 이미지 | `assets/story_images/` (4장/이벤트) | `assets/story_images_thumbs/` | PNG |
| UI 장식 | `assets/elements/` | — | PNG |
| 지도 | `assets/maps/` (GeoJSON) | — | GeoJSON |
