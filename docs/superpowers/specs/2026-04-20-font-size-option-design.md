# 글자 크기 옵션 설계

고령 사용자를 위한 앱 전역 글자 크기 조절 기능.

## 목표

- 고령 사용자가 앱 내 텍스트(성경 본문, 이야기, UI 라벨 전체)를 읽기 편한 크기로 조절할 수 있게 한다.
- 설정은 한 번 선택하면 앱 재시작 후에도 유지된다.
- 어디서든 상단 `Aa` 토글로 접근 가능해야 한다.

## 범위

**포함**
- 앱 전체 동일 배율 3단계: 작게 (0.9×) / 보통 (1.0×, 기본값) / 크게 (1.2×)
- **홈 화면 상단 row의 `Aa` 토글 버튼** 단 한 곳에서만 변경 가능 → 바텀시트(미리보기 + 3버튼) 오픈
- 선택 즉시 앱 전체 텍스트 스케일 반영 (홈에서 변경해도 모든 화면에 적용됨)
- 로컬 저장 (`SharedPreferences`)

**접근성 결정 — 홈 전용 (home-only)**
- Aa 버튼은 `StoryHomeScreen` 상단 row에만 배치한다.
- 서브 페이지(`SubPageScaffold`, `ParchmentPageScaffold`)에는 배치하지 않는다.
- **근거**: `SubPageScaffold`의 모든 프로덕션 호출(`bible_reader_page`, `event_detail_page`, `weekly_tab_page`, `profile_tab_page`)이 `compactBackOnly: true`로 상단 영역을 드래그 가능한 홈 버튼에 양보한다. 즉 상단 공간이 없어서 Aa 버튼을 둘 곳이 없다. `ParchmentPageScaffold`(saved_verses, profile_notes 등)도 UX 일관성을 위해 동일 정책.
- `TextScaler`는 전역에 적용되므로 **홈에서 한 번 설정하면 모든 서브 화면에 즉시 반영**된다. 설정 변경 자체가 빈번하지 않아 "매 화면에서 변경"이 필수 요구사항은 아님.

**제외 (필요 시 후속 스펙)**
- Supabase 동기화 (다른 기기 동일 설정)
- OS 시스템 글자 크기 연동 ("기기 설정 따르기" 옵션)
- UI와 본문 분리 배율
- 슬라이더/연속값 조절
- 커스텀 폰트 가족 선택
- 서브 페이지 내 Aa 버튼 (본 스펙에서는 홈 전용)

## 접근 방식

### 선택한 접근 — Flutter 표준 `MediaQuery.textScaler`

`MaterialApp.builder`에서 `MediaQuery`를 override 하여 `TextScaler.linear(ratio)`를 주입한다.
현재 코드베이스의 `fontSize: N` 하드코딩 위치(150곳 / 29개 파일)는 코드 수정 없이 자동 스케일된다.

**검토했지만 선택하지 않은 대안**
- `ThemeData.textTheme` 기반 스케일 — 코드가 `textTheme`을 거의 쓰지 않고 위젯마다 `fontSize:`를 직접 쓰는 구조라 효과가 없음.
- 커스텀 `ScaledText` 래퍼 — 150곳을 전부 수정해야 하며 Flutter 표준을 재발명.

## 아키텍처

```
main.dart
  ├─ SharedPreferences.getInstance()      ← 첫 프레임 깜빡임 방지용 사전 로드
  └─ runApp(ProviderScope(overrides: [
       sharedPreferencesProvider.overrideWithValue(prefs),
     ]))

StoryBibleApp (app.dart)
  ├─ ref.watch(fontScaleProvider)        → FontScale (0.9 | 1.0 | 1.2)
  └─ MaterialApp(
       builder: (context, child) => MediaQuery(
         data: MediaQuery.of(context).copyWith(
           textScaler: TextScaler.linear(scale.ratio),
         ),
         child: child!,
       ),
     )

story_home_styles.dart
  └─ 신규: topFontScaleButton(...)       ← topUtilityButton 스타일 재사용, "Aa" 라벨

story_home_screen.dart 상단 row (~L954)
  └─ 기존 "금주 인물"/"프로필" 버튼 근처 우측에 topFontScaleButton 배치
       → onTap: showFontScaleSheet(context)
```

서브 페이지(`SubPageScaffold`, `ParchmentPageScaffold`)에는 Aa 버튼을 배치하지 않는다 — 「접근성 결정」 섹션 참조.

## 상태 모델

### FontScale enum

```dart
// lib/state/font_scale_providers.dart
enum FontScale {
  small(0.9, '작게'),
  normal(1.0, '보통'),
  large(1.2, '크게');

  const FontScale(this.ratio, this.label);
  final double ratio;
  final String label;

  static FontScale fromStorage(String? raw) => switch (raw) {
    'small' => small,
    'large' => large,
    _ => normal, // null 또는 unknown 값은 기본값으로 복원
  };

  String get storageKey => name;
}
```

### 저장소

```dart
// lib/data/font_scale_repository.dart
class FontScaleRepository {
  FontScaleRepository(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'font_scale';

  FontScale read() => FontScale.fromStorage(_prefs.getString(_key));
  Future<void> write(FontScale scale) =>
      _prefs.setString(_key, scale.storageKey);
}
```

### Riverpod 프로바이더

```dart
// lib/state/font_scale_providers.dart
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(), // main.dart에서 override
);

final fontScaleRepositoryProvider = Provider<FontScaleRepository>(
  (ref) => FontScaleRepository(ref.watch(sharedPreferencesProvider)),
);

final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, FontScale>(FontScaleNotifier.new);

class FontScaleNotifier extends Notifier<FontScale> {
  @override
  FontScale build() => ref.read(fontScaleRepositoryProvider).read();

  Future<void> set(FontScale scale) async {
    if (state == scale) return;
    state = scale;
    await ref.read(fontScaleRepositoryProvider).write(scale);
  }
}
```

## 데이터 흐름

```
[앱 시작]
  main()
    ├─ SharedPreferences.getInstance()  (await)
    └─ runApp(ProviderScope(overrides: [sharedPreferencesProvider=prefs]))

[초기 렌더]
  FontScaleNotifier.build() → repository.read() → FontScale (동기)
  StoryBibleApp.build → ref.watch(fontScaleProvider)
                      → MaterialApp.builder에서 textScaler 주입
  → 첫 프레임부터 저장된 배율 적용 (깜빡임 없음)

[사용자가 Aa 탭 → 바텀시트 → "크게" 탭]
  FontScaleNotifier.set(FontScale.large)
    ├─ state = large             (동기, 즉시)
    │   → fontScaleProvider 구독자 리빌드
    │   → 앱 전체 텍스트 1.2× 즉시 반영
    │   → 바텀시트 내 미리보기도 실시간 갱신
    └─ repository.write(large)   (비동기, await)
```

## UI 동작

### Aa 토글 버튼

- 기존 `topUtilityButton` 스타일 재사용. "Aa" 라벨.
- 배치: `story_home_screen.dart` 상단 row 우측 **한 곳에만**.
- 서브 페이지(`SubPageScaffold`, `ParchmentPageScaffold`)에는 배치하지 않음 — 「접근성 결정」 섹션 참조.

### 바텀시트

```
┌──────────────────────────────────────────────┐
│   글자 크기                                   │
│                                              │
│   ┌──────────────────────────────────────┐  │
│   │ 미리보기                               │  │
│   │ 태초에 하나님이 천지를 창조하시니라    │  │
│   │ (창세기 1:1)                          │  │
│   └──────────────────────────────────────┘  │
│                                              │
│   ┌────────┐  ┌────────┐  ┌────────┐        │
│   │  작게   │  │ ✓ 보통  │  │  크게   │       │
│   │  0.9×  │  │  1.0×   │  │  1.2×  │       │
│   └────────┘  └────────┘  └────────┘        │
│                                              │
│   [ 닫기 ]                                    │
└──────────────────────────────────────────────┘
```

**상호작용**
- 3버튼 중 하나 탭 → `fontScaleProvider.set(...)` → 전역 반영 + 시트 내 미리보기 실시간 변화 (시트 유지)
- 현재 선택된 단계는 selected 스타일 + 체크 아이콘 (색각이상 고려해 색 + 아이콘 **둘 다**)
- "닫기" 또는 바깥 탭 → `Navigator.pop`
- 별도 "저장" 버튼 없음 — 탭 시점에 자동 저장
- 미리보기 샘플: "태초에 하나님이 천지를 창조하시니라 (창세기 1:1)" (고정)

**접근성**
- 버튼 최소 터치 영역 48×48 확보
- 선택 상태는 색상 + 체크 아이콘 둘 다로 표시

## 레이아웃 리스크 & 대응

`TextScaler.linear(1.2)` 주입 시 고정 높이 컨테이너 안의 텍스트가 잘릴 가능성.

### 주의 지점 (검증 대상)
- `topUtilityButton` — `height: 40`, `fontSize: 13.4`, `maxLines: 1`, `overflow: ellipsis` (`story_home_styles.dart:310,329`)
- `sub_page_scaffold.dart` 제목 박스 — `height: 40`
- `selection/step_chip.dart`, `selection/selection_cards.dart` 고정 높이 영역
- `weekly_tab_page.dart`, `profile_tab_page.dart` 고정 크기 배지/라벨
- `parchment_dialog.dart`, `shared/event_short_popup.dart` 고정 너비

### 대응 (Cascading)
1. **1차 — 그대로 진행 + 실기 테스트**: 1.2× 정도면 `ellipsis` 설정이 있는 대부분의 버튼/라벨은 자연스럽게 흡수됨. "크게" 모드로 주요 화면 눈으로 확인.
2. **2차 — 스케일 제외 (opt-out)**: 깨지는 소수 위젯은 주변을 `MediaQuery(data: copyWith(textScaler: TextScaler.noScaling), child: ...)`로 덮어써서 스케일 제외.
3. **3차 — 고정 height 완화**: 위 두 방법으로 해결 불가한 경우에만 `height: 40` → `IntrinsicHeight` 등으로 완화.

### 롤백
- 문제 규모가 크면 "크게" 배율을 1.2 → 1.15 또는 1.1로 한 줄만 변경해 전역 완화 가능.

### OS 설정과의 상호작용
- 이번 기능은 **앱 내 설정만** 반영. OS 시스템 글자 크기는 `TextScaler.linear(ratio)`로 override 되어 무시됨 (복수 설정 곱셈 혼란 방지).

## QA 체크리스트

`flutter run` 후:

- [ ] 홈 화면 Aa 버튼 → 바텀시트 오픈
- [ ] "작게"/"보통"/"크게" 각각 선택 시 앱 전체 텍스트 즉시 변화
- [ ] 시트 닫고 앱 재시작 → 마지막 선택 복원
- [ ] 주요 여정 모두 "크게" 모드로 확인: 홈 → 이야기 선택 → 성경 리더 → 이야기 상세 → 주간 탭 → 프로필 탭 → 저장 구절 → 로그인 → 법적 문서
- [ ] 위 여정에서 디버그 오버플로 표시(노랑/검정 빗금) 없음
- [ ] "작게" 모드에서 너무 작아 읽기 힘든 곳 없음
- [ ] Aa 버튼은 홈 화면 상단 row 한 곳에서만 표시됨 (서브 페이지에는 없음)
- [ ] 홈에서 변경한 배율이 서브 페이지(성경 리더 등)에서도 동일하게 적용됨

## 테스트 계획 (TDD)

CLAUDE.md §TDD 규칙에 따라 **Red → Green → Refactor** 순서로 4개 테스트 파일을 신규 추가한다.

### 1. `test/state/font_scale_providers_test.dart` (단위)
- `FontScale.fromStorage('small')` → `FontScale.small`
- `FontScale.fromStorage(null)` → `FontScale.normal`
- `FontScale.fromStorage('unknown')` → `FontScale.normal`
- 각 단계 ratio 값: 0.9 / 1.0 / 1.2
- `FontScaleNotifier.build()` 초기값이 저장소 값 반영 (mocktail로 repository mock)
- `set(large)` 호출 시 state 갱신 + `repository.write` 호출
- 동일 값 `set` 호출 시 write 생략

### 2. `test/data/font_scale_repository_test.dart` (단위)
- `SharedPreferences.setMockInitialValues({})` 사용
- 빈 저장소 read → `FontScale.normal`
- `write(large)` 후 `read()` → `FontScale.large`
- 저장소에 잘못된 값이 있을 때 `read()` → `FontScale.normal`

### 3. `test/widgets/font_scale_bottom_sheet_test.dart` (위젯)
- 3개 버튼 렌더 + 라벨 "작게"/"보통"/"크게"
- 현재 선택된 단계에 체크 아이콘 표시
- 다른 버튼 탭 시 `fontScaleProvider.set(...)` 호출
- 미리보기 `Text`가 선택 변경에 따라 `MediaQuery.textScalerOf` 변화를 따라감

### 4. `test/app_test.dart` (통합, 신규)
- `fontScaleProvider`를 `overrideWith`로 `FontScale.large` 상태로 고정
- `StoryBibleApp`을 `ProviderScope`로 감싸 렌더
- 렌더 후 내부 `BuildContext`에서 `MediaQuery.of(ctx).textScaler.scale(10) == 12.0` 검증

## 문서 동기화

CLAUDE.md §문서 동기화 규칙 준수:

| 문서 | 업데이트 내용 |
|------|--------------|
| `docs/PRD.md` | "글자 크기 조절" 기능 추가 (고령 사용자 접근성) |
| `docs/FRONTEND.md` | 새 파일 4개 반영 (표), §6 의존 패키지에 `shared_preferences` 추가 |
| `docs/UI_GUIDE.md` | Aa 토글 + 바텀시트 UX 패턴 한 문단 |
| `pubspec.yaml` | `shared_preferences` 추가 (버전은 `flutter pub add shared_preferences`로 최신 안정 버전 사용) |

`docs/ADR.md`는 기존 결정을 뒤집는 변경이 아니므로 추가하지 않는다.

## 파일 구조

**신규 파일**
- `lib/state/font_scale_providers.dart`
- `lib/data/font_scale_repository.dart`
- `lib/widgets/font_scale_bottom_sheet.dart`
- `test/state/font_scale_providers_test.dart`
- `test/data/font_scale_repository_test.dart`
- `test/widgets/font_scale_bottom_sheet_test.dart`

**수정 파일**
- `pubspec.yaml` — `shared_preferences` 의존성 (`flutter pub add shared_preferences`로 버전 자동 선택)
- `lib/main.dart` — `SharedPreferences.getInstance()` 사전 로드 + override
- `lib/app.dart` — `MaterialApp.builder`에서 `textScaler` 주입
- `lib/widgets/story_home_styles.dart` — `topFontScaleButton(onTap:)` 헬퍼 추가
- `lib/screens/story_home_screen.dart` — 상단 row에 `Aa` 버튼 배치
- `docs/PRD.md`, `docs/FRONTEND.md`, `docs/UI_GUIDE.md` — 동기화

## 커밋/푸시 정책

CLAUDE.md §Git 훅 & CI 규칙 준수:
- 커밋·푸시는 사용자의 명시적 지시가 있을 때만 수행
- `pre-commit` 훅 통과: `dart format`, `flutter analyze`, `flutter test`, import_sorter, forbidden pattern, 에셋 경로 검증
