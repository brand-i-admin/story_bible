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

  testWidgets('제목 아래에 연도와 장소를, 요약 행에 등장인물 아바타를 표시한다', (tester) async {
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
    expect(find.text('요약 이야기'), findsOneWidget);
    expect(find.byType(CharacterAvatar), findsNWidgets(2));
    verify(() => storyRepository.fetchCharactersByEra('era-exodus')).called(1);
  });
}

StoryEvent _event() {
  return const StoryEvent(
    id: 'event-1',
    eraId: 'era-exodus',
    title: '시내산 도착',
    summary: '하나님은 백성에게 살아갈 길을 선포하신다.',
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
    characterCodes: ['moses', 'aaron'],
    bibleRefs: [],
  );
}
