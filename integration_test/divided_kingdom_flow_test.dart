import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/app.dart';
import 'package:story_bible/screens/story_home_screen.dart';
import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/state/story_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('분열왕국 시대의 남유다/북이스라엘 장소 흐름이 연결되어 있다', (tester) async {
    await _startTestApp();
    await tester.pump(const Duration(seconds: 1));

    await _selectDividedKingdomEra(tester);

    await _tapFinder(
      tester,
      find.byKey(const ValueKey('home-mode-region')),
      description: '장소에서 시작하기 카드',
    );
    await _pumpUntil(
      tester,
      () =>
          _storyState(tester).selectionMode == SelectionMode.region &&
          find.text('남유다').evaluate().isNotEmpty &&
          find.text('북이스라엘').evaluate().isNotEmpty,
      description: '분열왕국 지역 선택 카드 표시',
    );

    await _tapText(tester, '남유다');
    await _pumpUntil(tester, () {
      final state = _storyState(tester);
      return state.landmarkById(state.selectedLandmarkId)?.name == '남유다' &&
          state.displayedEventIds.length == _southJudahTitles.length;
    }, description: '남유다 사건 표시');
    _expectDisplayedTitles(tester, _southJudahTitles);

    await _tapText(tester, '장소 다시 선택');
    await _pumpUntil(
      tester,
      () =>
          _storyState(tester).selectedLandmarkId == null &&
          find.text('북이스라엘').evaluate().isNotEmpty,
      description: '지역 선택으로 복귀',
    );

    await _tapText(tester, '북이스라엘');
    await _pumpUntil(tester, () {
      final state = _storyState(tester);
      return state.landmarkById(state.selectedLandmarkId)?.name == '북이스라엘' &&
          state.displayedEventIds.length == _northIsraelTitles.length;
    }, description: '북이스라엘 사건 표시');
    _expectDisplayedTitles(tester, _northIsraelTitles);
  });

  testWidgets('분열왕국 시대의 인물과 걷기 순서가 첫 등장 이야기 순서다', (tester) async {
    await _startTestApp();
    await tester.pump(const Duration(seconds: 1));

    await _selectDividedKingdomEra(tester);
    _expectCharacterOrder(tester, _dividedKingdomCharacterCodes);

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
    _expectCharacterOrder(tester, _dividedKingdomCharacterCodes);
    expect(find.text('솔로몬').evaluate(), isNotEmpty);
    expect(find.text('여로보암').evaluate(), isNotEmpty);
    expect(find.text('르호보암').evaluate(), isNotEmpty);
    expect(find.text('아합').evaluate(), isNotEmpty);
  });
}

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
bool _supabaseInitialized = false;

Future<void> _startTestApp() async {
  await dotenv.load(fileName: '.env');

  final suffix = switch (_runtimeEnv.toLowerCase()) {
    'dev' => 'DEV',
    'prod' || 'real' => 'PROD',
    _ => throw StateError('Unsupported ENV="$_runtimeEnv".'),
  };
  final url = dotenv.env['SUPABASE_URL_$suffix'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY_$suffix'];
  if (url == null || url.isEmpty) {
    throw StateError('Missing SUPABASE_URL_$suffix in .env');
  }
  if (anonKey == null || anonKey.isEmpty) {
    throw StateError('Missing SUPABASE_ANON_KEY_$suffix in .env');
  }

  if (!_supabaseInitialized) {
    await Supabase.initialize(url: url, anonKey: anonKey);
    _supabaseInitialized = true;
  }
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const StoryBibleApp(),
    ),
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
        state.events.length == 23 &&
        state.characters.any((c) => c.code == 'elijah') &&
        state.characters.any((c) => c.code == 'jeremiah');
  }, description: '분열왕국 사건과 인물 로드');
}

final _southJudahTitles = <String>[
  '르호보암의 남유다: 우상과 약탈',
  '이사야의 소명: 거룩한 보좌의 환상',
  '아하스와 임마누엘: 믿음의 징조',
  '히스기야와 산헤립: 두려움의 편지',
  '히스기야의 병과 바벨론 사신',
  '요시야의 개혁: 율법책을 찾다',
  '예레미야의 경고: 칠십 년의 포로',
  '새 언약의 약속: 마음에 새기다',
  '불태워진 두루마리: 말씀을 거부하다',
  '토굴의 예레미야: 왕에게 전하다',
  '예루살렘 포위: 왕의 몰락',
];

final _northIsraelTitles = <String>[
  '왕국의 균열: 찢어진 옷',
  '왕국 분열: 무거운 멍에와 금송아지',
  '여로보암의 집: 아히야의 경고',
  '아합과 엘리야: 가뭄의 시작',
  '엘리야와 갈멜: 불의 응답',
  '엘리야 승천: 겉옷의 계승',
  '엘리사의 첫 표징: 물과 경고',
  '엘리사의 기적들: 기름과 생명과 양식',
  '나아만: 요단의 일곱 번',
  '도단의 불 말과 불 전차: 눈이 열리다',
  '호세아의 몰락: 사마리아가 함락되다',
];

final _dividedKingdomCharacterCodes = <String>[
  'solomon',
  'jeroboam',
  'rehoboam',
  'ahab',
  'elijah',
  'elisha',
  'naaman',
  'isaiah',
  'ahaz',
  'hoshea_king',
  'hezekiah',
  'josiah',
  'jeremiah',
  'jehoiakim',
  'zedekiah',
];

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
