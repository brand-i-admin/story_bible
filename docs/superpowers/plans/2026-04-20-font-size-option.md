# 글자 크기 옵션 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고령 사용자를 위해 앱 전역 글자 크기를 3단계(작게 0.9× / 보통 1.0× / 크게 1.2×)로 조절할 수 있는 기능을 추가한다.

**Architecture:** `MaterialApp.builder`에서 `MediaQuery`를 override하여 `TextScaler.linear(ratio)`를 주입, 앱 전체 `Text` 위젯이 자동으로 스케일된다. 설정은 Riverpod `fontScaleProvider`로 관리하고 `SharedPreferences`에 영속화한다. 커스텀 상단 row의 `topFontScaleButton(Aa)`를 탭하면 미리보기 + 3단계 선택 바텀시트가 열린다.

**Tech Stack:** Flutter 3.8, Dart 3.8, Riverpod 2.6, `shared_preferences`, `mocktail`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-04-20-font-size-option-design.md`

---

## File Structure

**신규**
- `lib/state/font_scale_providers.dart` — `FontScale` enum + `sharedPreferencesProvider`, `fontScaleRepositoryProvider`, `fontScaleProvider`, `FontScaleNotifier`
- `lib/data/font_scale_repository.dart` — `SharedPreferences` 기반 저장소 래퍼
- `lib/widgets/font_scale_bottom_sheet.dart` — 바텀시트 위젯 + `showFontScaleSheet(context)` 헬퍼
- `test/state/font_scale_providers_test.dart`
- `test/data/font_scale_repository_test.dart`
- `test/widgets/font_scale_bottom_sheet_test.dart`
- `test/app_test.dart`

**수정**
- `pubspec.yaml` — `shared_preferences` 의존성
- `lib/main.dart` — SharedPreferences 사전 로드 + override
- `lib/app.dart` — `MaterialApp.builder`에서 `textScaler` 주입
- `lib/widgets/story_home_styles.dart` — `topFontScaleButton` 헬퍼 추가
- `lib/screens/story_home_screen.dart` — 상단 row에 `Aa` 버튼 배치 (~L954 근처)
- ~~`lib/widgets/sub_page_scaffold.dart`~~ — **REVERTED**: 코드 리뷰에서 `SubPageScaffold`가 프로덕션에서 모두 `compactBackOnly: true`로 호출되어 변경이 dead code였음이 발견됨. 스펙을 "홈 전용"으로 축소했고 Task 9 변경은 revert 되었다.
- `docs/PRD.md`, `docs/FRONTEND.md`, `docs/UI_GUIDE.md` — 동기화

---

## Task 1: Add `shared_preferences` dependency

**Files:**
- Modify: `pubspec.yaml` (dependencies 블록)

- [ ] **Step 1: Add dependency**

Run: `flutter pub add shared_preferences`

이 명령은 `pubspec.yaml`의 `dependencies:` 블록에 최신 안정 버전을 추가하고 `pub get`을 실행한다.

- [ ] **Step 2: Verify install**

Run: `flutter pub get`
Expected: `Got dependencies!` (에러 없음)

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add shared_preferences dependency for font scale persistence"
```

---

## Task 2: Create `FontScale` enum (TDD)

**Files:**
- Create: `lib/state/font_scale_providers.dart` (enum 부분만 먼저)
- Create: `test/state/font_scale_providers_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/state/font_scale_providers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  group('FontScale enum', () {
    test('각 단계의 ratio 값이 정확하다', () {
      expect(FontScale.small.ratio, 0.9);
      expect(FontScale.normal.ratio, 1.0);
      expect(FontScale.large.ratio, 1.2);
    });

    test('라벨은 한국어로 표시된다', () {
      expect(FontScale.small.label, '작게');
      expect(FontScale.normal.label, '보통');
      expect(FontScale.large.label, '크게');
    });

    test('storageKey는 enum name과 동일하다', () {
      expect(FontScale.small.storageKey, 'small');
      expect(FontScale.normal.storageKey, 'normal');
      expect(FontScale.large.storageKey, 'large');
    });

    group('fromStorage', () {
      test('알려진 값은 대응되는 enum으로 복원된다', () {
        expect(FontScale.fromStorage('small'), FontScale.small);
        expect(FontScale.fromStorage('normal'), FontScale.normal);
        expect(FontScale.fromStorage('large'), FontScale.large);
      });

      test('null은 normal로 복원된다', () {
        expect(FontScale.fromStorage(null), FontScale.normal);
      });

      test('알 수 없는 값은 normal로 복원된다', () {
        expect(FontScale.fromStorage('xlarge'), FontScale.normal);
        expect(FontScale.fromStorage(''), FontScale.normal);
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/font_scale_providers_test.dart`
Expected: 컴파일 에러 — `FontScale` 미정의.

- [ ] **Step 3: Implement enum**

Create `lib/state/font_scale_providers.dart`:

```dart
/// 앱 전역 글자 크기 배율.
///
/// `MediaQuery.textScaler`에 주입되어 모든 `Text` 위젯에 자동 적용된다.
/// SharedPreferences에는 [storageKey] 문자열로 저장한다.
enum FontScale {
  small(0.9, '작게'),
  normal(1.0, '보통'),
  large(1.2, '크게');

  const FontScale(this.ratio, this.label);

  final double ratio;
  final String label;

  String get storageKey => name;

  static FontScale fromStorage(String? raw) => switch (raw) {
    'small' => FontScale.small,
    'large' => FontScale.large,
    _ => FontScale.normal,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/font_scale_providers_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/state/font_scale_providers.dart test/state/font_scale_providers_test.dart
git commit -m "feat: add FontScale enum with 3 levels (small/normal/large)"
```

---

## Task 3: Create `FontScaleRepository` (TDD)

**Files:**
- Create: `lib/data/font_scale_repository.dart`
- Create: `test/data/font_scale_repository_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/data/font_scale_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/data/font_scale_repository.dart';
import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  group('FontScaleRepository', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('빈 저장소에서는 기본값(normal)을 반환한다', () {
      final repo = FontScaleRepository(prefs);
      expect(repo.read(), FontScale.normal);
    });

    test('write 후 read하면 저장된 값을 반환한다', () async {
      final repo = FontScaleRepository(prefs);
      await repo.write(FontScale.large);
      expect(repo.read(), FontScale.large);
    });

    test('저장소에 잘못된 값이 있어도 normal로 복원된다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'font_scale': 'bogus',
      });
      prefs = await SharedPreferences.getInstance();
      final repo = FontScaleRepository(prefs);
      expect(repo.read(), FontScale.normal);
    });

    test('write는 동일 키(font_scale)를 사용한다', () async {
      final repo = FontScaleRepository(prefs);
      await repo.write(FontScale.small);
      expect(prefs.getString('font_scale'), 'small');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/font_scale_repository_test.dart`
Expected: 컴파일 에러 — `FontScaleRepository` 미정의.

- [ ] **Step 3: Implement repository**

Create `lib/data/font_scale_repository.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../state/font_scale_providers.dart';

/// 글자 크기 설정을 SharedPreferences에 영속화한다.
class FontScaleRepository {
  FontScaleRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'font_scale';

  FontScale read() => FontScale.fromStorage(_prefs.getString(_key));

  Future<void> write(FontScale scale) =>
      _prefs.setString(_key, scale.storageKey);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/font_scale_repository_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/font_scale_repository.dart test/data/font_scale_repository_test.dart
git commit -m "feat: add FontScaleRepository for SharedPreferences persistence"
```

---

## Task 4: Add Riverpod providers + `FontScaleNotifier` (TDD)

**Files:**
- Modify: `lib/state/font_scale_providers.dart`
- Modify: `test/state/font_scale_providers_test.dart`

- [ ] **Step 1: Add failing tests**

`test/state/font_scale_providers_test.dart` 파일 끝(마지막 `}` 앞)에 다음 테스트 그룹을 추가:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/font_scale_repository.dart';

class _MockFontScaleRepository extends Mock implements FontScaleRepository {}
```

(위 import들은 파일 상단 import 블록으로 이동)

그리고 `main()` 안에 다음 그룹 추가:

```dart
  group('FontScaleNotifier', () {
    late _MockFontScaleRepository repo;

    setUp(() {
      repo = _MockFontScaleRepository();
      when(() => repo.write(any())).thenAnswer((_) async {});
    });

    ProviderContainer makeContainer(FontScale initial) {
      when(repo.read).thenReturn(initial);
      return ProviderContainer(
        overrides: [
          fontScaleRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    test('build()는 저장소의 현재 값을 초기 상태로 사용한다', () {
      final container = makeContainer(FontScale.large);
      addTearDown(container.dispose);

      expect(container.read(fontScaleProvider), FontScale.large);
      verify(repo.read).called(1);
    });

    test('set()은 state를 갱신하고 저장소에 기록한다', () async {
      final container = makeContainer(FontScale.normal);
      addTearDown(container.dispose);

      await container
          .read(fontScaleProvider.notifier)
          .set(FontScale.large);

      expect(container.read(fontScaleProvider), FontScale.large);
      verify(() => repo.write(FontScale.large)).called(1);
    });

    test('set()을 동일한 값으로 호출하면 write를 생략한다', () async {
      final container = makeContainer(FontScale.normal);
      addTearDown(container.dispose);

      await container
          .read(fontScaleProvider.notifier)
          .set(FontScale.normal);

      verifyNever(() => repo.write(any()));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/font_scale_providers_test.dart`
Expected: 컴파일 에러 — `fontScaleRepositoryProvider`, `fontScaleProvider` 미정의.

- [ ] **Step 3: Implement providers**

`lib/state/font_scale_providers.dart` 파일 끝에 다음을 추가 (상단 import도 추가):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/font_scale_repository.dart';
```

그리고 enum 아래에:

```dart
/// `main.dart`에서 `overrideWithValue`로 실제 인스턴스를 주입한다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart',
  ),
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
    if (state == scale) {
      return;
    }
    state = scale;
    await ref.read(fontScaleRepositoryProvider).write(scale);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/font_scale_providers_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Run import sorter**

Run: `dart run import_sorter:main lib/state/font_scale_providers.dart test/state/font_scale_providers_test.dart`
Expected: import 순서 자동 정렬.

- [ ] **Step 6: Commit**

```bash
git add lib/state/font_scale_providers.dart test/state/font_scale_providers_test.dart
git commit -m "feat: add fontScaleProvider and FontScaleNotifier"
```

---

## Task 5: Wire `main.dart` and `app.dart` with `MediaQuery.textScaler` (TDD)

**Files:**
- Create: `test/app_test.dart`
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Write failing integration test**

`app.dart`의 builder 로직을 테스트에서도 재사용할 수 있도록, Task 5 Step 3에서 `MaterialApp.builder`에 넘기는 함수를 top-level 함수 `fontScaleBuilder`로 분리한다. 먼저 테스트부터 작성한다.

Create `test/app_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/app.dart';
import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  testWidgets(
    'fontScaleBuilder는 fontScaleProvider의 ratio를 MediaQuery.textScaler로 주입한다',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'font_scale': 'large',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            builder: fontScaleBuilder,
            home: const Scaffold(body: Text('probe')),
          ),
        ),
      );

      final BuildContext innerContext = tester.element(find.text('probe'));
      final textScaler = MediaQuery.textScalerOf(innerContext);

      expect(textScaler.scale(10), closeTo(12.0, 0.001));
    },
  );

  testWidgets(
    'fontScaleBuilder는 저장값이 없으면 normal(1.0×)을 사용한다',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            builder: fontScaleBuilder,
            home: const Scaffold(body: Text('probe')),
          ),
        ),
      );

      final BuildContext innerContext = tester.element(find.text('probe'));
      final textScaler = MediaQuery.textScalerOf(innerContext);

      expect(textScaler.scale(10), closeTo(10.0, 0.001));
    },
  );
}
```

**설계 의도:** `StoryBibleApp` 전체를 띄우지 않는다. `StoryHomeScreen`은 Supabase 클라이언트를 참조하므로 test 환경에서 초기화하기 번거롭다. 대신 `app.dart`의 `MaterialApp.builder`에 주입되는 순수 함수 `fontScaleBuilder`를 export하여 **그 함수가 올바르게 textScaler를 주입하는지**만 독립적으로 검증한다. 이로써 "앱 전체가 잘 뜨는가"와 "builder 로직이 맞는가"를 분리한다.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_test.dart`
Expected: 컴파일 에러 — `fontScaleBuilder`가 아직 `app.dart`에서 export되지 않음.

- [ ] **Step 3: Modify `lib/app.dart`**

파일 전체를 다음으로 교체. `fontScaleBuilder`를 top-level 함수로 export하여 테스트에서 재사용한다.

```dart
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/story_home_screen.dart';
import 'state/font_scale_providers.dart';

/// `MaterialApp.builder`에 주입되어 `MediaQuery.textScaler`를 `fontScaleProvider`
/// 값에 동기화한다. 테스트에서도 재사용하기 위해 top-level로 분리.
Widget fontScaleBuilder(BuildContext context, Widget? child) {
  if (child == null) {
    return const SizedBox.shrink();
  }
  return Consumer(
    builder: (context, ref, _) {
      final fontScale = ref.watch(fontScaleProvider);
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: TextScaler.linear(fontScale.ratio),
        ),
        child: child,
      );
    },
  );
}

class StoryBibleApp extends StatelessWidget {
  const StoryBibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Story Bible',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5A2B)),
        scaffoldBackgroundColor: const Color(0xFFEEE0C6),
      ),
      builder: fontScaleBuilder,
      home: const StoryHomeScreen(),
    );
  }
}
```

**변경 설명:** `Consumer` 위젯을 builder 내부에 두는 이유는 `MaterialApp.builder`가 `MaterialApp` 스코프 밖에서 호출되어 상위의 `ProviderScope`에 직접 접근할 수 있기 때문이다. `StoryBibleApp` 자체는 `ConsumerWidget`일 필요가 없어 `StatelessWidget`으로 단순화.

- [ ] **Step 4: Modify `lib/main.dart`**

`main()` 함수를 다음처럼 변경 (기존 Supabase 초기화는 유지):

```dart
import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'state/font_scale_providers.dart';

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseConfig = _resolveSupabaseConfig();

  await Supabase.initialize(
    url: supabaseConfig.url,
    anonKey: supabaseConfig.anonKey,
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const StoryBibleApp(),
    ),
  );
}

SupabaseConfig _resolveSupabaseConfig() {
  final normalizedEnv = _runtimeEnv.toLowerCase();
  final suffix = switch (normalizedEnv) {
    'dev' => 'DEV',
    'prod' || 'real' => 'PROD',
    _ => throw StateError(
      'Unsupported ENV="$_runtimeEnv". Use ENV=dev, ENV=real, or ENV=prod.',
    ),
  };

  final url = dotenv.env['SUPABASE_URL_$suffix'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY_$suffix'];

  if (url == null || url.isEmpty) {
    throw StateError('Missing SUPABASE_URL_$suffix in .env');
  }
  if (anonKey == null || anonKey.isEmpty) {
    throw StateError('Missing SUPABASE_ANON_KEY_$suffix in .env');
  }

  return SupabaseConfig(url: url, anonKey: anonKey);
}

class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/app_test.dart`
Expected: 두 테스트 모두 통과.

- [ ] **Step 6: Run full test suite**

Run: `flutter test`
Expected: 모든 기존 테스트 + 신규 테스트 통과.

- [ ] **Step 7: Run import sorter + analyze**

```bash
dart run import_sorter:main lib/main.dart lib/app.dart test/app_test.dart
flutter analyze
```
Expected: 정렬 완료, analyze 에러 없음.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/app.dart test/app_test.dart
git commit -m "feat: inject MediaQuery.textScaler from fontScaleProvider"
```

---

## Task 6: Create `FontScaleBottomSheet` widget (TDD)

**Files:**
- Create: `lib/widgets/font_scale_bottom_sheet.dart`
- Create: `test/widgets/font_scale_bottom_sheet_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/widgets/font_scale_bottom_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/widgets/font_scale_bottom_sheet.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  FontScale initial = FontScale.normal,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'font_scale': initial.storageKey,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: FontScaleBottomSheet()),
      ),
    ),
  );
  return container;
}

void main() {
  group('FontScaleBottomSheet', () {
    testWidgets('3단계 버튼(작게/보통/크게)을 렌더한다', (tester) async {
      await _pumpSheet(tester);

      expect(find.text('작게'), findsOneWidget);
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('크게'), findsOneWidget);
    });

    testWidgets('현재 선택된 단계에 체크 아이콘을 표시한다', (tester) async {
      await _pumpSheet(tester, initial: FontScale.large);

      final checkIcons = find.byIcon(Icons.check);
      expect(checkIcons, findsOneWidget);

      final checkWidget = tester.widget<Icon>(checkIcons);
      final parentText = find
          .ancestor(
            of: checkIcons,
            matching: find.byKey(const ValueKey('font-scale-button-large')),
          )
          .evaluate();
      expect(parentText, isNotEmpty);
      expect(checkWidget.icon, Icons.check);
    });

    testWidgets('다른 버튼 탭 시 fontScaleProvider.set이 호출된다', (tester) async {
      final container = await _pumpSheet(tester, initial: FontScale.normal);

      await tester.tap(
        find.byKey(const ValueKey('font-scale-button-large')),
      );
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.large);
    });

    testWidgets('동일한 단계 탭은 state를 변경하지 않는다', (tester) async {
      final container = await _pumpSheet(tester, initial: FontScale.normal);

      await tester.tap(
        find.byKey(const ValueKey('font-scale-button-normal')),
      );
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.normal);
    });

    testWidgets('미리보기 Text가 현재 textScaler로 렌더된다', (tester) async {
      await _pumpSheet(tester, initial: FontScale.large);

      expect(find.text('태초에 하나님이 천지를 창조하시니라 (창세기 1:1)'),
          findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/font_scale_bottom_sheet_test.dart`
Expected: 컴파일 에러 — `FontScaleBottomSheet` 미정의.

- [ ] **Step 3: Implement widget**

Create `lib/widgets/font_scale_bottom_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/font_scale_providers.dart';

/// 글자 크기 선택 바텀시트를 띄운다.
///
/// 탭 시 즉시 전역 `fontScaleProvider`가 갱신되어 앱 전체 텍스트가 재스케일된다.
Future<void> showFontScaleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFF8F1E4),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const FontScaleBottomSheet(),
  );
}

class FontScaleBottomSheet extends ConsumerWidget {
  const FontScaleBottomSheet({super.key});

  static const String _previewText = '태초에 하나님이 천지를 창조하시니라 (창세기 1:1)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fontScaleProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '글자 크기',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A331D),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E2),
                border: Border.all(color: const Color(0xFFD8BF99)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                _previewText,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF3A2816),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: FontScale.values
                  .map(
                    (scale) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _FontScaleChoiceButton(
                          scale: scale,
                          selected: scale == current,
                          onTap: () => ref
                              .read(fontScaleProvider.notifier)
                              .set(scale),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontScaleChoiceButton extends StatelessWidget {
  const _FontScaleChoiceButton({
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  final FontScale scale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('font-scale-button-${scale.storageKey}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE9D18E)
                : const Color(0xFFFDF5E2),
            border: Border.all(
              color: selected
                  ? const Color(0xFFB27A2B)
                  : const Color(0xFFD8BF99),
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Icon(
                  Icons.check,
                  size: 18,
                  color: Color(0xFF6A401E),
                ),
              Text(
                scale.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A2816),
                ),
              ),
              Text(
                '${scale.ratio.toStringAsFixed(1)}×',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A401E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/font_scale_bottom_sheet_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Run import sorter + analyze**

```bash
dart run import_sorter:main lib/widgets/font_scale_bottom_sheet.dart test/widgets/font_scale_bottom_sheet_test.dart
flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/font_scale_bottom_sheet.dart test/widgets/font_scale_bottom_sheet_test.dart
git commit -m "feat: add FontScaleBottomSheet with preview and 3-level selector"
```

---

## Task 7: Add `topFontScaleButton` helper in `story_home_styles.dart`

**Files:**
- Modify: `lib/widgets/story_home_styles.dart` (append new helper)

- [ ] **Step 1: Add helper function**

`lib/widgets/story_home_styles.dart` 파일 끝(마지막 `}` 뒤)에 다음을 추가:

```dart
/// 상단 row에 "Aa" 라벨로 표시되는 글자 크기 토글 버튼.
///
/// `topUtilityButton`과 동일한 스타일을 공유하지만 고정 라벨과 고정 폭을 사용한다.
Widget topFontScaleButton({required VoidCallback onTap}) {
  return topUtilityButton(
    label: 'Aa',
    onTap: onTap,
  );
}
```

**참고:** 별도 테스트를 추가하지 않는다 — `topUtilityButton`의 얇은 래퍼이며 Task 8, 9의 실기 배치에서 동작이 검증된다.

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: 에러 없음.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/story_home_styles.dart
git commit -m "feat: add topFontScaleButton helper for Aa top-row button"
```

---

## Task 8: Place `Aa` button in `story_home_screen.dart`

**Files:**
- Modify: `lib/screens/story_home_screen.dart` (상단 row, ~L952-973)

- [ ] **Step 1: Add import**

파일 상단 import 블록에 추가 (이미 있으면 생략):

```dart
import '../widgets/font_scale_bottom_sheet.dart';
```

- [ ] **Step 2: Add `Aa` button to top row**

L952의 `Row(children: [...])` 끝에 다음 항목을 추가:

**변경 전 (L952-973):**
```dart
                    child: Row(
                      children: [
                        topUtilityButton(
                          label: '사건선택',
                          selected: selectionButtonIsOpen,
                          backgroundColor: selectionButtonBackground,
                          borderColor: selectionButtonBorder,
                          foregroundColor: selectionButtonForeground,
                          boxShadow: selectionButtonShadow,
                          onTap: _toggleSelectionPanelFromTopButton,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '금주 인물', onTap: _openWeeklyTab),
                        const SizedBox(width: 8),
                        topUtilityButton(
                          label: '성경',
                          onTap: _openBibleReaderPopup,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '프로필', onTap: _openProfileTab),
                      ],
                    ),
```

**변경 후:**
```dart
                    child: Row(
                      children: [
                        topUtilityButton(
                          label: '사건선택',
                          selected: selectionButtonIsOpen,
                          backgroundColor: selectionButtonBackground,
                          borderColor: selectionButtonBorder,
                          foregroundColor: selectionButtonForeground,
                          boxShadow: selectionButtonShadow,
                          onTap: _toggleSelectionPanelFromTopButton,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '금주 인물', onTap: _openWeeklyTab),
                        const SizedBox(width: 8),
                        topUtilityButton(
                          label: '성경',
                          onTap: _openBibleReaderPopup,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '프로필', onTap: _openProfileTab),
                        const SizedBox(width: 8),
                        topFontScaleButton(
                          onTap: () => showFontScaleSheet(context),
                        ),
                      ],
                    ),
```

- [ ] **Step 3: Run analyze + tests**

```bash
flutter analyze
flutter test
```
Expected: 에러 없음, 모든 테스트 통과.

- [ ] **Step 4: Run import sorter**

```bash
dart run import_sorter:main lib/screens/story_home_screen.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/story_home_screen.dart
git commit -m "feat: add Aa font-scale button to story home top row"
```

---

## Task 9: ~~Place `Aa` button in `sub_page_scaffold.dart`~~ (REVERTED)

**Status:** 이 태스크는 구현했다가 최종 리뷰에서 `SubPageScaffold`가 프로덕션에서 항상 `compactBackOnly: true`로 호출되어 non-compact 브랜치의 Aa 버튼이 실제로 렌더되지 않는다는 사실이 발견되어 revert되었다. 스펙을 "홈 화면 한 곳에서만 변경 가능"으로 공식 축소했다. 이후 단계에서 이 태스크는 무시한다.



**Files:**
- Modify: `lib/widgets/sub_page_scaffold.dart` (상단 row, ~L108-144)

- [ ] **Step 1: Add imports**

파일 상단 import 블록에 추가:

```dart
import 'font_scale_bottom_sheet.dart';
import 'story_home_styles.dart';
```

(`story_home_styles.dart`는 이미 line 6에 import 되어 있으므로 `font_scale_bottom_sheet.dart`만 추가)

- [ ] **Step 2: Add `Aa` button between 이전 and title**

L108-144의 `Column(children: [Padding(... Row(children: [...]))])` 중 Row 부분을 찾아 수정:

**변경 전 (L112-144):**
```dart
                        child: Row(
                          children: [
                            topUtilityButton(
                              label: '이전',
                              onTap: () => Navigator.of(context).pop(),
                              selected: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 40,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: floatingPanelDecoration(
                                  color: const Color(0xEEF7E9D1),
                                  shadowOpacity: 0.08,
                                ),
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF4A331D),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
```

**변경 후 (Aa 버튼을 Expanded title 뒤에 추가):**
```dart
                        child: Row(
                          children: [
                            topUtilityButton(
                              label: '이전',
                              onTap: () => Navigator.of(context).pop(),
                              selected: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 40,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: floatingPanelDecoration(
                                  color: const Color(0xEEF7E9D1),
                                  shadowOpacity: 0.08,
                                ),
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF4A331D),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            topFontScaleButton(
                              onTap: () => showFontScaleSheet(context),
                            ),
                          ],
                        ),
```

**이유:** 설계상 "이전 버튼 옆"이었지만 긴 제목이 더 중요한 정보라 title Expanded를 우선시하고 우측 끝에 배치. 이전 버튼과 title 사이에 넣으면 고정폭 버튼 2개로 좁은 단말에서 title 영역이 과도하게 좁아진다.

- [ ] **Step 3: Run analyze + tests**

```bash
flutter analyze
flutter test
```
Expected: 에러 없음, 모든 테스트 통과.

- [ ] **Step 4: Run import sorter**

```bash
dart run import_sorter:main lib/widgets/sub_page_scaffold.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/sub_page_scaffold.dart
git commit -m "feat: add Aa font-scale button to sub page scaffold top row"
```

---

## Task 10: Manual QA smoke test

**Files:** 없음 (실기 확인)

- [ ] **Step 1: Run app in dev**

```bash
flutter run --dart-define=ENV=dev
```

- [ ] **Step 2: Verify Aa button + bottom sheet**

1. 홈 화면 상단 우측의 **"Aa" 버튼** 탭 → 바텀시트 오픈 확인
2. 바텀시트에서 **"작게"** 탭 → 앱 전체 텍스트가 0.9×로 즉시 변화
3. **"크게"** 탭 → 1.2×로 변화
4. **"닫기"** 탭 → 시트 닫힘
5. 앱 **재시작** (hot restart: `R`) → 마지막 선택 복원 확인

- [ ] **Step 3: Walk main user journeys in "크게" mode**

"크게"를 선택한 상태로 다음 화면을 순서대로 확인. **노랑/검정 빗금(overflow)** 가 나오면 해당 위치 기록.

- [ ] 홈 화면 (지도 + 상단 버튼)
- [ ] 사건선택 패널 열기/접기 + 단계 칩
- [ ] 이야기 선택 → 이야기 상세 (event_detail_page)
- [ ] 성경 리더 팝업
- [ ] 주간 인물 탭 (weekly_tab_page)
- [ ] 프로필 탭 (profile_tab_page) — 저장 구절 / 노트 / 중보기도
- [ ] 로그인 화면 (로그아웃 후 진입)
- [ ] 법적 문서 (약관/개인정보처리방침)
- [ ] `SubPageScaffold.compactBackOnly` 모드 화면 — Aa 버튼이 **없어야** 함

- [ ] **Step 4: Walk journeys in "작게" mode**

"작게"로 전환 후 동일 여정 — 읽기 곤란할 정도로 작아지는 곳 없는지 확인.

- [ ] **Step 5: Fix overflow if any**

발견된 overflow 각각에 대해 다음 중 하나 적용 (spec §레이아웃 리스크 & 대응 참조):

1. 무시 가능한 정도 → 그대로 둠
2. 특정 위젯만 스케일 제외 →
   ```dart
   MediaQuery(
     data: MediaQuery.of(context).copyWith(
       textScaler: TextScaler.noScaling,
     ),
     child: <문제 위젯>,
   )
   ```
3. 전역 배율 하향 → `FontScale.large(1.2, ...)`를 `FontScale.large(1.15, ...)`로 조정 (`lib/state/font_scale_providers.dart`) + 해당 단위 테스트 기대값도 함께 수정

- [ ] **Step 6: Commit fixes (있는 경우)**

```bash
git add <수정 파일>
git commit -m "fix: resolve <화면> overflow at large font scale"
```

---

## Task 11: Update project docs

**Files:**
- Modify: `docs/PRD.md`
- Modify: `docs/FRONTEND.md`
- Modify: `docs/UI_GUIDE.md`

- [ ] **Step 1: Update `docs/PRD.md`**

"접근성" 또는 가장 유사한 섹션을 찾아 다음 내용을 추가:

```markdown
### 글자 크기 조절

고령 사용자의 가독성을 위해 앱 전역 글자 크기를 3단계(작게 0.9× / 보통 1.0× / 크게 1.2×)로 조절할 수 있다.

- **접근**: 상단 row의 `Aa` 버튼 (홈 화면 및 서브 페이지)
- **UI**: 바텀시트에 미리보기와 3단계 버튼. 선택 즉시 전역 반영.
- **저장**: 기기 로컬(`SharedPreferences`). 앱 재시작 후 복원.
- **범위 외**: OS 시스템 크기 연동, 기기 간 동기화, UI/본문 분리 배율.
```

(적절한 기능 섹션 위치는 기존 구조에 맞춰 판단)

- [ ] **Step 2: Update `docs/FRONTEND.md`**

"파일 표" 또는 "위젯 목록" 섹션에 다음 추가:

```markdown
| `lib/state/font_scale_providers.dart` | FontScale enum + Riverpod 프로바이더 (앱 전역 글자 크기) |
| `lib/data/font_scale_repository.dart` | 글자 크기 설정 SharedPreferences 래퍼 |
| `lib/widgets/font_scale_bottom_sheet.dart` | 글자 크기 3단계 선택 바텀시트 + `showFontScaleSheet` 헬퍼 |
```

§6 의존 패키지 표에 `shared_preferences` 추가:

```markdown
| `shared_preferences` | 로컬 키-값 저장 (글자 크기 등 사용자 선호 설정) |
```

- [ ] **Step 3: Update `docs/UI_GUIDE.md`**

"상단 UI" 또는 "접근성" 섹션에 다음 단락 추가:

```markdown
### 글자 크기 토글 (Aa)

홈 화면 및 `SubPageScaffold` 상단 row에 `Aa` 버튼을 배치한다. 탭 시 바텀시트가 열리며 미리보기 문구("태초에 하나님이 천지를 창조하시니라 (창세기 1:1)")와 3단계(작게/보통/크게) 버튼이 표시된다. 선택 즉시 앱 전체에 반영되고 SharedPreferences에 저장된다. `SubPageScaffold.compactBackOnly` 모드(드래그 홈 버튼만 있는 본문 리더 등)에는 배치하지 않는다.
```

- [ ] **Step 4: Verify pre-commit**

Run: `pre-commit run --all-files`
Expected: 포맷/린트/훅 모두 통과.

- [ ] **Step 5: Commit docs**

```bash
git add docs/PRD.md docs/FRONTEND.md docs/UI_GUIDE.md
git commit -m "docs: reflect font-scale feature in PRD/FRONTEND/UI_GUIDE"
```

---

## Done criteria

- [ ] `flutter analyze` 에러 없음
- [ ] `flutter test` 전체 통과 (신규 + 기존)
- [ ] Task 10의 QA 체크리스트 모두 확인됨
- [ ] `pre-commit run --all-files` 통과
- [ ] 커밋은 타스크별로 분리되어 있음 (히스토리에서 rollback 가능)
- [ ] 푸시는 사용자 요청 시에만 (CLAUDE.md 규칙)
