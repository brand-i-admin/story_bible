import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/app.dart';
import 'package:story_bible/data/color_palette_repository.dart';
import 'package:story_bible/data/font_scale_repository.dart';
import 'package:story_bible/screens/story_home_screen.dart';
import 'package:story_bible/state/color_palette_providers.dart';
import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/theme/app_color_palette.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('새 설치는 오늘 탭, 보통 글자, 네이비 테마로 시작한다', (tester) async {
    await _startTestApp();
    await _pumpUntil(
      tester,
      () =>
          find.byType(StoryHomeScreen).evaluate().isNotEmpty &&
          find
              .byKey(const ValueKey('root-navigation-today-selected'))
              .evaluate()
              .isNotEmpty &&
          _maybeStoryState(tester)?.loading == false &&
          _storyState(tester).eras.isNotEmpty &&
          _storyState(tester).landmarks.isNotEmpty,
      description: '오늘 탭 기본 화면',
    );

    final context = tester.element(find.byType(StoryHomeScreen));
    final container = _container(tester);

    expect(container.read(fontScaleProvider), FontScale.large);
    expect(FontScale.large.label, '보통');
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(12, 0.001));
    expect(container.read(colorPaletteProvider), AppColorPalette.atlasNavy);
    expect(
      Theme.of(context).extension<AppPaletteTheme>()?.palette,
      AppColorPalette.atlasNavy,
    );
  });

  testWidgets('분열왕국 시대의 남유다/북이스라엘 장소 흐름이 연결되어 있다', (tester) async {
    await _startTestApp();
    await _openMapTab(tester);

    await _selectDividedKingdomEra(tester);

    await _tapText(tester, '장소로 시작');
    await _pumpUntil(
      tester,
      () => _storyState(tester).selectionMode == SelectionMode.region,
      description: '분열왕국 장소 모드 진입',
    );
    await _tapFinder(
      tester,
      find.byIcon(Icons.keyboard_arrow_up),
      description: '장소 선택 패널 펼치기',
    );
    await _pumpUntil(
      tester,
      () =>
          find.text('남유다').hitTestable().evaluate().isNotEmpty &&
          find.text('북이스라엘').evaluate().isNotEmpty,
      description: '분열왕국 지역 선택 카드 표시',
    );

    final southJudahTitles = _expectedRegionTitles(tester, '남유다');
    await _tapText(tester, '남유다');
    await _pumpUntil(tester, () {
      final state = _storyState(tester);
      return state.landmarkById(state.selectedLandmarkId)?.name == '남유다' &&
          state.displayedEventIds.length == southJudahTitles.length;
    }, description: '남유다 사건 표시');
    _expectDisplayedTitles(tester, southJudahTitles);
    expect(
      southJudahTitles,
      containsAll(<String>['르호보암의 남유다: 우상과 약탈', '예루살렘 포위: 왕의 몰락']),
    );

    await _tapFinder(
      tester,
      find.byTooltip('장소 선택 단계로 돌아가기'),
      description: '장소 선택 단계 스테퍼',
    );
    await _pumpUntil(
      tester,
      () =>
          _storyState(tester).selectionMode == SelectionMode.region &&
          _storyState(tester).selectedLandmarkId == null,
      description: '지역 선택으로 복귀',
    );
    await _tapFinder(
      tester,
      find.byIcon(Icons.keyboard_arrow_up),
      description: '지역 선택 패널 다시 펼치기',
    );
    await _pumpUntil(
      tester,
      () => find.text('북이스라엘').hitTestable().evaluate().isNotEmpty,
      description: '북이스라엘 지역 카드 표시',
    );

    final northIsraelTitles = _expectedRegionTitles(tester, '북이스라엘');
    await _tapText(tester, '북이스라엘');
    await _pumpUntil(tester, () {
      final state = _storyState(tester);
      return state.landmarkById(state.selectedLandmarkId)?.name == '북이스라엘' &&
          state.displayedEventIds.length == northIsraelTitles.length;
    }, description: '북이스라엘 사건 표시');
    _expectDisplayedTitles(tester, northIsraelTitles);
    expect(
      northIsraelTitles,
      containsAll(<String>['아합과 엘리야: 가뭄의 시작', '호세아의 몰락: 사마리아가 함락되다']),
    );
  });

  testWidgets('분열왕국 시대의 인물과 걷기 순서가 첫 등장 이야기 순서다', (tester) async {
    await _startTestApp();
    await _openMapTab(tester);

    await _selectDividedKingdomEra(tester);
    final expectedCharacterCodes = _firstAppearanceCharacterCodes(tester);
    expect(expectedCharacterCodes.length, greaterThan(20));
    expect(
      expectedCharacterCodes,
      containsAll(<String>[
        'solomon',
        'jeroboam',
        'rehoboam',
        'elijah',
        'isaiah',
        'jeremiah',
        'daniel',
        'ezekiel',
      ]),
    );
    _expectCharacterOrder(tester, expectedCharacterCodes);

    await tester.pump(const Duration(seconds: 1));
    await _tapText(tester, '인물과 걷기');
    await _pumpUntil(
      tester,
      () =>
          _storyState(tester).selectionMode == SelectionMode.character &&
          find.text('솔로몬').evaluate().isNotEmpty &&
          _storyState(tester).characters.any((c) => c.code == 'elijah') &&
          _storyState(tester).characters.any((c) => c.code == 'isaiah') &&
          _storyState(tester).characters.any((c) => c.code == 'jeremiah'),
      description: '분열왕국 인물 선택 표시',
    );
    _expectCharacterOrder(tester, expectedCharacterCodes);
    expect(find.text('솔로몬').evaluate(), isNotEmpty);
    expect(find.text('여로보암').evaluate(), isNotEmpty);
    expect(find.text('르호보암').evaluate(), isNotEmpty);
    expect(find.text('아합').evaluate(), isNotEmpty);
  });
}

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);
bool _supabaseInitialized = false;

Future<void> _startTestApp() async {
  switch (_runtimeEnv.toLowerCase()) {
    case 'dev':
    case 'prod':
    case 'real':
      break;
    default:
      throw StateError('Unsupported ENV="$_runtimeEnv".');
  }
  final url = _supabaseUrl.trim();
  final anonKey = _supabaseAnonKey.trim();
  if (url.isEmpty) {
    throw StateError('Missing --dart-define=SUPABASE_URL.');
  }
  if (anonKey.isEmpty) {
    throw StateError('Missing --dart-define=SUPABASE_ANON_KEY.');
  }

  if (!_supabaseInitialized) {
    await Supabase.initialize(url: url, anonKey: anonKey);
    _supabaseInitialized = true;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(FontScaleRepository.key);
  await prefs.remove(ColorPaletteRepository.key);

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const StoryBibleApp(),
    ),
  );
}

Future<void> _openMapTab(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(StoryHomeScreen).evaluate().isNotEmpty,
    description: '앱 홈 화면',
  );
  await _tapText(tester, '지도');
  await _pumpUntil(
    tester,
    () =>
        find
            .byKey(const ValueKey('root-navigation-map-selected'))
            .evaluate()
            .isNotEmpty &&
        _maybeStoryState(tester) != null,
    description: '지도 탭',
  );
}

Future<void> _selectDividedKingdomEra(WidgetTester tester) async {
  await _pumpUntil(tester, () {
    final state = _maybeStoryState(tester);
    return state != null &&
        !state.loading &&
        state.eras.any((era) => era.code == 'era_divided_kingdom');
  }, description: '분열왕국 시대 로드');

  final dividedEra = _storyState(
    tester,
  ).eras.firstWhere((era) => era.code == 'era_divided_kingdom');
  await _tapText(tester, dividedEra.name);

  await _pumpUntil(tester, () {
    final state = _storyState(tester);
    return !state.loading &&
        state.selectedEraId == dividedEra.id &&
        state.events.length >= 52 &&
        state.events.any((event) => event.title == '왕국의 균열: 찢어진 옷') &&
        state.events.any((event) => event.title == '예루살렘 포위: 왕의 몰락') &&
        state.characters.any((c) => c.code == 'elijah') &&
        state.characters.any((c) => c.code == 'jeremiah');
  }, description: '분열왕국 사건과 인물 로드');
}

List<String> _expectedRegionTitles(WidgetTester tester, String regionName) {
  final state = _storyState(tester);
  final region = state.landmarks.firstWhere(
    (landmark) => landmark.isRegion && landmark.name == regionName,
  );
  final landmarkIds = <String>{
    region.id,
    for (final landmark in state.landmarks)
      if (landmark.parentLandmarkId == region.id) landmark.id,
  };
  final events =
      state.events
          .where((event) => landmarkIds.contains(event.landmarkId))
          .toList()
        ..sort((a, b) => a.storyIndex.compareTo(b.storyIndex));
  return events.map((event) => event.title).toList(growable: false);
}

List<String> _firstAppearanceCharacterCodes(WidgetTester tester) {
  final state = _storyState(tester);
  final loadedCodes = state.characters
      .map((character) => character.code)
      .toSet();
  final events = [...state.events]
    ..sort((a, b) => a.storyIndex.compareTo(b.storyIndex));
  final codes = <String>[];
  final seen = <String>{};

  for (final event in events) {
    for (final code in event.characterCodes) {
      if (loadedCodes.contains(code) && seen.add(code)) {
        codes.add(code);
      }
    }
  }
  return codes;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (predicate()) return;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('Timed out waiting for $description. Last error: $lastError');
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await _tapFinder(tester, find.text(text), description: '"$text" 텍스트');
}

Future<void> _tapFinder(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    description: '$description 표시',
  );

  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 100));
  }
  final target = finder.hitTestable().evaluate().isNotEmpty
      ? finder.hitTestable().first
      : finder.first;
  await tester.tap(target, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
}

StoryState? _maybeStoryState(WidgetTester tester) {
  if (find.byType(StoryHomeScreen).evaluate().isEmpty) {
    return null;
  }
  return _storyState(tester);
}

StoryState _storyState(WidgetTester tester) {
  return _container(tester).read(storyControllerProvider);
}

ProviderContainer _container(WidgetTester tester) {
  final context = tester.element(find.byType(StoryHomeScreen));
  return ProviderScope.containerOf(context, listen: false);
}

void _expectDisplayedTitles(WidgetTester tester, List<String> expectedTitles) {
  final state = _storyState(tester);
  final displayed =
      state.events
          .where((event) => state.displayedEventIds.contains(event.id))
          .toList()
        ..sort((a, b) => a.storyIndex.compareTo(b.storyIndex));

  expect(displayed.map((event) => event.title), orderedEquals(expectedTitles));
}

void _expectCharacterOrder(
  WidgetTester tester,
  List<String> expectedCharacterCodes,
) {
  final actualCodes = _storyState(
    tester,
  ).characters.map((character) => character.code);
  expect(actualCodes, orderedEquals(expectedCharacterCodes));
}
