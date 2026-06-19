import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/character_avatar.dart';
import 'package:story_bible/widgets/event_detail_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

void main() {
  late _MockStoryRepository storyRepository;

  setUp(() {
    storyRepository = _MockStoryRepository();
    when(() => storyRepository.fetchCharactersByEra('era-exodus')).thenAnswer(
      (_) async => const [
        Character(
          id: 'c-moses',
          code: 'moses',
          name: '모세',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 1,
        ),
        Character(
          id: 'c-aaron',
          code: 'aaron',
          name: '아론',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 2,
        ),
      ],
    );
  });

  testWidgets('배경 지식 제목 옆에 등장인물 아바타와 인라인 요약을 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(),
            sceneAssetsFuture: Future.value(const []),
            onOpenBibleReader: (_) async => false,
            onStartQuiz: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('시내산 도착'), findsOneWidget);
    expect(find.text('B.C. 1446년경 · 시내산(전승)'), findsOneWidget);
    expect(find.text('배경 지식'), findsOneWidget);
    expect(find.text('출애굽 여정의 배경을 먼저 떠올립니다.'), findsOneWidget);
    expect(find.text('요약 이야기'), findsNothing);
    expect(_summaryFinder(), findsOneWidget);
    expect(find.byType(CharacterAvatar), findsNWidgets(2));
    expect(find.text('모세'), findsOneWidget);
    expect(find.text('아론'), findsOneWidget);
    expect(tester.getSize(find.byType(CharacterAvatar).first).width, 31);
    expect(_avatarNames(tester), ['모세', '아론']);
    _expectAvatarsBesideBackgroundTitle(tester);
    _expectAvatarsDoNotOverlap(tester);
    verify(() => storyRepository.fetchCharactersByEra('era-exodus')).called(1);
  });

  testWidgets('DB 목록에 없는 등장인물 코드도 한글 fallback으로 모두 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(characterCodes: const ['god', 'moses', 'cain']),
            sceneAssetsFuture: Future.value(const []),
            onOpenBibleReader: (_) async => false,
            onStartQuiz: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CharacterAvatar), findsNWidgets(3));
    expect(find.text('하나님'), findsOneWidget);
    expect(find.text('모세'), findsOneWidget);
    expect(find.text('가인'), findsOneWidget);
    expect(find.text('god'), findsNothing);
    expect(find.text('cain'), findsNothing);
    expect(_avatarNames(tester), ['하나님', '가인', '모세']);
    _expectAvatarsBesideBackgroundTitle(tester);
    _expectAvatarsDoNotOverlap(tester);
  });
}

List<String> _avatarNames(WidgetTester tester) {
  return tester
      .widgetList<CharacterAvatar>(find.byType(CharacterAvatar))
      .map((avatar) => avatar.character.name)
      .toList(growable: false);
}

void _expectAvatarsDoNotOverlap(WidgetTester tester) {
  final rects = find
      .byType(CharacterAvatar)
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)))
      .toList(growable: false);

  for (var index = 1; index < rects.length; index++) {
    expect(rects[index].left, greaterThanOrEqualTo(rects[index - 1].right));
  }
}

void _expectAvatarsBesideBackgroundTitle(WidgetTester tester) {
  final titleRect = tester.getRect(find.text('배경 지식'));
  final avatarRect = tester.getRect(find.byType(CharacterAvatar).first);
  final summaryRect = tester.getRect(_summaryFinder());

  expect(avatarRect.center.dy, closeTo(titleRect.center.dy, 12));
  expect(avatarRect.top, lessThan(summaryRect.top));
}

Finder _summaryFinder() {
  return find.text('요약: 하나님은 백성에게 살아갈 길을 선포하신다.', findRichText: true);
}

StoryEvent _event({List<String> characterCodes = const ['aaron', 'moses']}) {
  return StoryEvent(
    id: 'event-1',
    eraId: 'era-exodus',
    title: '시내산 도착',
    summary: '하나님은 백성에게 살아갈 길을 선포하신다.',
    backgroundContext: '출애굽 여정의 배경을 먼저 떠올립니다.',
    storyScenes: [],
    sceneCharacters: [],
    startYear: -1446,
    endYear: -1446,
    timePrecision: 'approx',
    storyIndex: 1,
    rankInEra: 1,
    globalRank: 1,
    landmarkId: 'lm-sinai',
    placeName: '시내산(전승)',
    lat: 28.5392,
    lng: 33.9756,
    characterCodes: characterCodes,
    bibleRefs: const [],
  );
}
