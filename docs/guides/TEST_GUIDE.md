# 테스트 가이드 — Story Bible

이 문서는 `test/` 디렉토리에 있는 모든 테스트가 **무엇을 검증하는지** 한눈에 볼 수 있도록 정리한 카탈로그다. 코드 변경 시 어느 테스트가 영향받는지, 새 기능에 어떤 테스트를 추가해야 하는지 판단하는 출발점.

총 **240개+ 테스트** (2026-05-25 기준), `flutter test` 실행 시간 약 10초.

---

## 0. 한 장 요약

| 디렉토리 | 파일 수 | 테스트 수 (대략) | 주된 검증 대상 |
|----------|--------|------------------|----------------|
| `test/models/` | 16 | 100+ | DB row → Dart 객체 변환, getter / equality / 직렬화 |
| `test/data/` | 2 | 20+ | repository helper 함수 (검색 점수, 일별 streak 계산 등) |
| `test/state/` | 2 | 30+ | Riverpod controller 의 상태 전이 (mocktail) |
| `test/utils/` | 4 | 50+ | 순수 함수 (지도 좌표 보정, 성경 책 메타, 주차 계산, 자산 경로 정규화) |
| `test/widgets/` | 3 | 14 | Flutter 위젯 렌더링 + 인터랙션 (`testWidgets`) |
| `test/widget_test.dart` | 1 | 1 | 기본 sanity (앱이 빌드되는지) |

테스트 전략 요약:
- **순수 데이터/계산 로직** 은 unit test (mock 불필요)
- **Repository / Controller** 는 `mocktail` 로 Supabase 클라이언트 mock
- **위젯** 은 `testWidgets` + Riverpod `ProviderScope` overrides
- **Supabase 통합 테스트는 없음** — RPC/RLS 는 `db_init.sql` + 수동 검증으로 보증
- **golden test 없음** — `flutter_test_config.dart` 에 `loadAppFonts()` 만 활성화 (golden 시 폰트 일관성 위해 준비됨, 현재 미사용)

CI 에서는 `.github/workflows/flutter_ci.yml` 이 `flutter test --coverage` 로 매 push/PR 마다 실행. pre-push hook (`.pre-commit-config.yaml`) 도 동일 명령으로 가드.

---

## 1. 모델 테스트 (`test/models/`)

DB row → Dart 객체 변환의 정확성을 보장하는 핵심 보호막. 대부분 `fromMap()` 팩토리에 다양한 입력을 넣고 결과 필드를 검증하는 패턴.

### 1.1 [character_test.dart](../../test/models/character_test.dart) — 캐릭터 모델

**무엇을 검증**: `Character.avatarAssetPath` getter 와 `hasLocalAvatar` getter 의 contract.

| 그룹 | 테스트 | 무엇을 보장 |
|------|--------|------------|
| `Character.avatarAssetPath` | avatarUrl 이 null 이면 빈 문자열 반환 | storage fallback 신호 — 호출처(CharacterAvatar)가 isEmpty 체크로 storage 분기 진입 |
| | avatarUrl 이 빈 문자열이면 빈 문자열 | 동일 |
| | `assets/avatars/` → `assets/avatars_thumbs/` 로 경로 교체 | 캐논 캐릭터의 썸네일 자동 매핑 |
| | `assets/` 가 아닌 경로(http URL 등)는 빈 문자열 | 로컬 자산이 아니므로 storage 분기로 빠지게 |
| | 앞뒤 공백 trim | 데이터 정리 |
| `Character.hasLocalAvatar` | null/빈 → false | storage fallback 결정 분기 |
| | `assets/avatars/`, `assets/avatars_thumbs/` 시작 → true | 로컬 번들 보유 신호 |
| | http(s) URL, `proposal-characters/...` 같은 storage 경로 → false | 로컬이 아님 |

**왜 중요**: 테스터 아바타가 안 보이던 버그(존재하지 않는 `_placeholder.png` 를 반환해 errorBuilder 가 storage fallback 진입을 막음)를 막는 회귀 방지 테스트.

### 1.2 [event_proposal_test.dart](../../test/models/event_proposal_test.dart) — 제안 모델

| 그룹 | 검증 |
|------|------|
| `QuizDraft.isValid` | 유효한 작성 선택지 3개 퀴즈는 true; 선택지 개수 ≠3 / 빈 선택지 / answer_index 범위 초과 / 빈 해설은 false |
| `QuizDraft.fromMap`/`toMap` | 왕복 직렬화 정합 |
| `EventProposal.fromMap` | proposal_type 기본값 'new', delete 타입은 target_event_id + 빈 quiz_questions, quiz_questions jsonb 가 QuizDraft 리스트로 파싱, isPending/isApproved/isRejected/isNewProposal/isDeleteProposal getter 정합 |

**커버 안 됨**: `positionInvalidatedAt` / `needsPositionRevision` 신규 필드 — TODO (충돌→재제출 라이프사이클의 핵심 contract)

### 1.3 [story_event_test.dart](../../test/models/story_event_test.dart) — 이야기 이벤트

| 그룹 | 검증 |
|------|------|
| `shortSummary` | summary 가 있으면 그대로, 없으면 기본 메시지 |
| `hasCoordinate` / `latLng` | lat/lng 모두 있을 때만 true |
| `fromMap` | events_ordered view 행을 모두 파싱(rank_in_era, global_rank, character_codes, story_scenes, scene_image_paths, bible_refs jsonb 포함), character_codes null → 빈 리스트, int 좌표 → double 변환 |

### 1.4 [era_test.dart](../../test/models/era_test.dart) — 시대 모델

| 검증 |
|------|
| 모든 필드 파싱, testament null 시 'old' 기본값, 선택적 필드 null 허용, num→double 좌표 변환 |

### 1.5 [bible_ref_test.dart](../../test/models/bible_ref_test.dart) — 성경 참조

| 검증 |
|------|
| 단일 절 displayText (from만), 범위 displayText (from-to), fromMap 누락 키 처리, fromList 의 jsonb 배열 파싱 / null / non-dict 항목 무시 |

### 1.6 [bible_verse_test.dart](../../test/models/bible_verse_test.dart) — 성경 구절

| 검증 |
|------|
| 모든 필드 파싱, const 생성자 사용 가능 |

### 1.7 [saved_bible_verse_test.dart](../../test/models/saved_bible_verse_test.dart) — 저장된 구절

| 검증 |
|------|
| fromMap 모든 필드, `referenceText` 형식 (`bookName chapter:verse`), `key` 형식 (`translation:bookNo:chapterNo:verseNo`), 정적 `buildVerseKey` 동일 형식 |

### 1.8 [user_note_test.dart](../../test/models/user_note_test.dart) — 사용자 노트

| 검증 |
|------|
| fromMap 모든 필드, `previewLine` (72자 이하 그대로 / 초과 시 잘리고 ... / 정확히 72자 / 빈 content) |

### 1.9 [character_study_progress_test.dart](../../test/models/character_study_progress_test.dart) — 인물 학습 진도

| 검증 |
|------|
| `fraction` getter — totalCount=0 / 음수 → 0.0, 일부/전부/미완료 비율 정확 |

### 1.10 [intercessory_prayer_item_test.dart](../../test/models/intercessory_prayer_item_test.dart) — 중보기도 항목

| 검증 |
|------|
| fromMap 모든 필드, nickname null/빈 → "사용자" 기본값, share_id null → 빈 문자열, photo_url/prayer_request null 유지 |

### 1.11 [app_user_profile_test.dart](../../test/models/app_user_profile_test.dart) — 사용자 프로필

| 검증 |
|------|
| fromMap 모든 필드, nickname 처리 (null/공백/trim), share_id null, photo_url/prayer_request null 유지 |

### 1.12 [app_notification_test.dart](../../test/models/app_notification_test.dart) — 알림 모델

| 그룹 | 검증 |
|------|------|
| `AppNotificationType.fromWire` | 알려진 타입 문자열 → enum 매핑, 알 수 없는 값 → unknown |
| `isProposalRelated` | 제안 관련 5종 → true (모바일/태블릿 다이얼로그 분기용), 무관 타입 → false |
| `AppNotification.fromMap` | personal source 전체 필드, broadcast source + is_read 기본값 false, source 누락 시 personal 폴백, payload Map<dynamic,dynamic> → Map<String,dynamic> 정규화 |
| `copyWith` | isRead 만 바꿔 새 객체 |

### 1.13 [quiz_attempt_summary_test.dart](../../test/models/quiz_attempt_summary_test.dart) — 이야기 퀴즈 풀이 요약

| 검증 |
|------|
| 오답/헷갈림이 있으면 복습 대상, 모두 정답이면 복습 대상 아님, selected_answers jsonb 와 updated_at 파싱 |

### 1.14 [event_emotion_mark_test.dart](../../test/models/event_emotion_mark_test.dart) — 지도 위 감정 새김

| 검증 |
|------|
| 감정 선택지 8개와 기타/감사 이모지, Supabase row → 모델 변환, upsert payload 생성 |

---

## 2. Data 레이어 테스트 (`test/data/`)

Repository 의 **순수 헬퍼 함수** 만 테스트 (Supabase 통합은 mocktail 없이 직접 호출하지 않음).

### 2.1 [story_repository_test.dart](../../test/data/story_repository_test.dart) — 검색 점수

`scoreEventMatch` 함수의 가중치 정합 — 검색 결과 정렬을 결정하는 로직.

| 매치 종류 | 점수 |
|----------|------|
| title 완전 일치 | 130 + 토큰 25 + 보너스 40 = **195** |
| summary 매치 | 120 + 토큰 18 = **138** |
| storyScenes 합본 매치 | 100 + 토큰 15 = **115** |
| 인물명 매치 | 80 + 토큰 18 = **98** |
| 장소명 매치 | 30 + 토큰 5 = **35** |
| 매치 없음 | 0 |
| 대소문자 무시 | (소문자 가정) |

### 2.2 [user_repository_test.dart](../../test/data/user_repository_test.dart) — 유틸 함수

| 그룹 | 검증 |
|------|------|
| `cleanNullableText` | null 유지, 빈/공백 → null, 유효 텍스트 trim |
| `normalizeImageExtension` | jpg/jpeg/JPG → jpg, webp/png 그대로, 미지원 → png 폴백 |
| `contentTypeForImageExtension` | jpg→image/jpeg, webp→image/webp, 그 외→image/png |
| `dateOnly` | 시/분/초 0 정규화 |
| `computeDailyStreak` | 빈 rows → 0, 오늘+어제 없음 → 0, 오늘 포함 연속 N일, 어제 시작 연속 (오늘 미출석), 중간 결손 시 오늘부터 연속만, 중복 날짜 1회 |

---

## 3. State 테스트 (`test/state/`)

Riverpod controller 의 상태 전이를 mocktail 로 검증.

### 3.1 [story_state_test.dart](../../test/state/story_state_test.dart) — 불변 상태 객체

`StoryState.copyWith` 의 정합성:

| 그룹 | 검증 |
|------|------|
| 기본값 | 모든 필드 초기값 |
| copyWith | 전달 필드만 변경 / 미전달 시 원래 값 유지 |
| `clearError=true` | error → null (전달과 동시면 clearError 우선) |
| `clearSelectedEra=true` / `clearSelectedEvent=true` | 해당 id null |
| Set/Map/List 교체 | selectedCharacterCodes / selectedCharacterColors / completedEventIds / eras / displayedEventIds 모두 새 컬렉션으로 교체 |

### 3.2 [story_controller_test.dart](../../test/state/story_controller_test.dart) — 컨트롤러 액션

mocktail 로 `StoryRepository`, `UserRepository`, `SupabaseClient`, `GoTrueClient` 를 mock 후 행동 검증.

| 그룹 | 검증 |
|------|------|
| `initialize` | eras 로드 성공 시 첫 구약 시대를 기본 testament 로 / eras 비면 에러 메시지 / fetchEras 실패 시 에러 / 구약 없고 신약만 있으면 신약 기본 |
| `selectEra` | characters + events 로드 후 selectedEraId 세팅 / 실패 시 error |
| `toggleCharacter` | 빈 set 추가, 이미 있는 id 제거, 색상 팔레트 선택 순서대로 할당 |
| `selectEvent` | null 전달 시 selectedEventId 클리어 |
| `colorForCharacter` | 미선택 인물은 기본 색상 |
| `mergedTimeline` | 선택된 인물의 이벤트만 time_sort_key 오름차순 |
| `selectTestament` | 구약↔신약 전환 시 첫 시대 자동 선택, 같은 testament면 no-op, 시대 없으면 초기화 |
| `toggleEra` | 같은 시대 토글 시 해제, 다른 시대 토글 시 선택 |
| `clearEraSelection` | 모든 선택 초기화 |
| `setSelectedCharacters` | characters 에 없는 id 필터링 |
| `setSearchQuery` | 빈/공백 쿼리 → 검색 결과 초기화, 유효 쿼리 → isSearching=true |
| `setDisplayedEvents` | state.events 에 있는 id 만 저장 / 빈 Set 클리어 |
| `displayedEventIds 리셋 조건` | setSelectedCharacters / toggleCharacter 호출 시 자동 초기화 |

---

## 4. Utils 테스트 (`test/utils/`)

순수 함수 — mock 없이 입출력만 검증.

### 4.1 [bible_book_meta_test.dart](../../test/utils/bible_book_meta_test.dart) — 성경 책 메타

| 그룹 | 검증 |
|------|------|
| `bibleBooks` | 66권 정의, 창세기 50장 / 요한계시록 22장 / 시편 150장 |
| `bibleRefAliasBookLookup` | 66권 한글 약자 모두 정의, 창→1, 계→66 |
| `parseBibleNavigationTarget` | null/빈 → null, 약자/풀네임 참조 파싱 (창 1:1, 창세기 1:1, 마 5장 3), 잘못된 책 이름 → null, 장 수 초과 시 최대 장 보정, 전각 콜론 처리 |
| `normalizeBibleBookKey` | 공백/대소문자 정규화 |

### 4.2 [map_math_test.dart](../../test/utils/map_math_test.dart) — 지도 수학

| 그룹 | 검증 |
|------|------|
| `easeInOut` | 0/1 경계, 중간값 0.5, 단조 증가 |
| `mercatorY` | 적도≈0.5, 북극→0 / 남극→1, ±90° 클램프 |
| `normalizedLongitudeDelta` | 단순 차이, 180° 초과 시 반대 방향 보정, order 무관 (절대값) |
| `hasMultiPlacePin` | 한글/ASCII 화살표 인식, 단일 장소 → false |
| `splitPlaceParts` | 한글 화살표로 분리, 공백 trim, 분리 불가 시 동일 값 |
| `buildSplitPinPoints` | 출발점 = base, 도착점은 동남쪽 오프셋 (위도 더 작고 경도 더 큼) |
| `buildAdjustedPoints` | 단일 이벤트 원본 유지, 같은 좌표 그룹 분산 배치, 좌표 없는 이벤트 제외 |
| `rotateOffset` | 0 라디안 무회전, π/2 = 90° 시계방향, 거리 보존 |
| `eventListSignature` | 빈 리스트 → 빈 문자열, id 를 \| 로 join, 순서 변경 시 시그니처 다름 |

### 4.3 [scene_asset_loader_test.dart](../../test/utils/scene_asset_loader_test.dart) — 장면 자산 경로

| 그룹 | 검증 |
|------|------|
| `sceneDirectoryNameForTitle` | 일반 제목 그대로, 잘못된 문자(`\/:*?"<>|`) → `_`, 앞뒤 점 제거, 연속 공백 단일화, 빈 문자열 → `untitled_event`, 특수문자만 → 치환 결과 |
| `normalizeSceneLookupKey` | 소문자 변환 + 구분자 제거, 한글 보존, 콜론/쉼표/괄호 제거 |
| `stripSceneDirectoryPrefix` | 숫자 접두사 제거, 숫자 없으면 그대로, 숫자만 있으면 빈 문자열 |
| `scenePrefixForTitle` | 제목 앞 숫자 3자리 패딩, 1자리도 3자리, 숫자 없으면 null, 빈 문자열 null, trim |

### 4.4 [weekly_selection_test.dart](../../test/utils/weekly_selection_test.dart) — 주간 선택

| 그룹 | 검증 |
|------|------|
| `weekStartMonday` | 월요일 그대로 (시간 0 정규화), 일요일 6일 전 월요일, 수요일 2일 전, 월 경계 처리 |
| `weeklyKeyFor` | YYYY-M-D 형식, 패딩 없음 |
| `seedFromKey` | 같은 키 → 같은 시드 / 다른 키 → 다른 시드 / 항상 양의 32-bit / 빈 문자열 → 0 |

---

## 5. Widget 테스트 (`test/widgets/`)

`testWidgets` 로 실제 위젯을 트리에 그려 인터랙션을 시뮬레이션. `Image.network` 호출은 `HttpOverrides.runZoned` 로 mock.

### 5.1 [character_avatar_test.dart](../../test/widgets/character_avatar_test.dart) — 아바타 위젯

| 검증 |
|------|
| 이미지 로드 실패 시 이름 첫 글자 fallback |
| 이름이 빈 문자열이면 ? fallback |
| 이름이 공백만 있어도 ? fallback |
| size 인자가 Container 에 반영 |
| 기본 크기 32 |
| 원형 모양 (BoxShape.circle) 유지 |

**커버 안 됨**: storage fallback (`avatarStoragePath` 분기), 줌 1.5×, hover 효과 — TODO

### 5.2 [proposal_quiz_editor_test.dart](../../test/widgets/proposal_quiz_editor_test.dart) — 퀴즈 편집기

| 검증 |
|------|
| 초기 비어있으면 기본 빈 퀴즈 1개 렌더링 |
| 추가 버튼 누르면 최대 3개까지 늘어남 |
| 퀴즈 1개만 남을 때 삭제 아이콘 미표시 |
| 2개 이상일 때 삭제 아이콘 표시 + 클릭 시 감소 |
| 초기 퀴즈 데이터 편집기에 반영 |
| onChanged 가 편집 시마다 호출되고 최신 drafts 방출 |

### 5.3 [notification_deep_link_test.dart](../../test/widgets/notification_deep_link_test.dart) — 알림 딥링크

`NotificationDeepLink.parse` 의 라우팅:

| 입력 | target / id |
|------|------------|
| `/proposal/<id>` | proposal + id |
| `/event/<id>` | event + id |
| `/weekly` | weekly, id 없음 |
| `/weekly/extra` | weekly (하위 무시) |
| null / 빈 문자열 / 알 수 없는 prefix | unknown |
| 선두 `/` 없어도 파싱 |
| `/proposal` (id 누락) | target=proposal, id=null |

---

## 6. 전체 sanity (`test/widget_test.dart`)

기본 `basic sanity` 테스트 1개 — 앱이 빌드 가능한 상태인지 최소 확인.

---

## 7. 테스트 인프라

### 7.1 의존성 (pubspec.yaml dev_dependencies)

| 패키지 | 용도 |
|--------|------|
| `flutter_test` | Dart/Flutter 표준 테스트 프레임워크 |
| `mocktail` | Supabase 클라이언트/repository mock |
| `golden_toolkit` | golden 테스트 폰트 로딩 (현재는 폰트만 사용) |

### 7.2 [flutter_test_config.dart](../../test/flutter_test_config.dart)

```dart
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  return testMain();
}
```

전역 setup — golden 테스트가 도입되면 폰트 일관성 보장. 현재는 모든 테스트 시작 전 한 번만 실행.

### 7.3 mock 전략

- **Repository 계층**: `class _MockStoryRepository extends Mock implements StoryRepository {}` 패턴. `when(() => repo.fetchEras()).thenAnswer((_) async => [...])` 로 응답 stub.
- **Supabase 클라이언트**: `_MockSupabaseClient extends Mock implements SupabaseClient {}` — Riverpod `supabaseClientProvider.overrideWithValue(mock)` 로 주입.
- **위젯**: `ProviderScope(overrides: [...], child: MaterialApp(home: ...))` 로 감싸 의존성 주입. `Image.network` 는 `HttpOverrides` 로 빈 응답 반환.

---

## 8. 실행 / CI

### 8.1 로컬

```bash
flutter test                          # 전체
flutter test test/models/             # 디렉토리만
flutter test test/widgets/character_avatar_test.dart  # 단일 파일
flutter test --plain-name '아바타'    # 이름 매치
flutter test --coverage              # coverage/lcov.info 생성
```

### 8.2 pre-push hook (`.pre-commit-config.yaml`)

`git push` 전 자동 실행:
- `flutter analyze` (정적 분석)
- `flutter test` (전체 테스트)
- `tools/app/verify_asset_paths.py` (pubspec.yaml 자산 경로 검증)
- `tools/lint/check_code_metrics.py` (파일 ≤1500줄, 메소드 ≤200줄)
- `tools/run_unit_tests.py` (Python 도구 단위 테스트)

### 8.3 GitHub Actions (`.github/workflows/flutter_ci.yml`)

push/PR 시 cloud 실행:
- `flutter test --coverage --reporter expanded` → coverage artifact 업로드
- forbidden patterns 검증 (시크릿, `print(` 차단)
- code metrics 검증

---

## 9. 커버리지 빈 곳 (TODO)

추적 가치 있는 미커버 영역:

| 영역 | 누락 contract |
|------|--------------|
| `EventProposal` | `positionInvalidatedAt`, `positionInvalidationReason`, `needsPositionRevision` 신규 필드 |
| `CharacterAvatar` widget | storage fallback 분기 (`avatarStoragePath`), 1.5× 줌 (Imagen 비율 가공) |
| `ProposalRepository` | `revisePosition`, `approveDelete` 의 새 jsonb 반환 shape 소비 |
| `RevisePositionDialog` | 위치 라디오 + 연도 검증 다이얼로그 (`prev.endYear ≤ start ≤ end ≤ next.startYear`) |
| Sync 스크립트 | Python 측은 `flutter test` 범위 밖 — `pytest` 도입 시 추가 가능 |
| RPC | Supabase 통합 테스트 부재 — `db_init.sql` 의 `approve_event_proposal` 셔플, 충돌 감지, hard delete 동작은 수동 검증으로만 보증 |

---

## 10. 새 테스트를 추가할 때

1. 해당 영역의 디렉토리(`test/models/`, `test/widgets/` 등)에 파일 생성 — `lib/` 미러링.
2. `flutter_test` import + 필요시 `mocktail`.
3. 기존 같은 영역 파일을 참고해 group/test 명을 한국어로 자연스럽게 작성.
4. 기존 테스트 **수정/삭제** 는 `AGENTS.md` 의 TDD 규칙에 따라 사유를 명확히 하고 범위를 작게 유지.
5. `flutter test` 로 그린 확인 → commit.

자세한 TDD 규칙은 [WORKFLOW_GUIDE.md §5](WORKFLOW_GUIDE.md) 와 [AGENTS.md](../../AGENTS.md) 의 "TDD And Tests" 섹션 참조.
