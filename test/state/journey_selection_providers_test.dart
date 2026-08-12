import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/daily_mission_provider.dart';
import 'package:story_bible/state/journey_selection_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/state/story_state.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _CatalogStoryController extends StoryController {
  @override
  StoryState build() => const StoryState(
    loading: true,
    eras: [
      Era(
        id: 'era-1',
        code: 'era_primeval',
        testament: 'old',
        name: '원역사',
        displayOrder: 1,
        startYear: null,
        endYear: null,
        mapCenterLat: null,
        mapCenterLng: null,
        mapZoom: null,
      ),
    ],
  );
}

class _EmptyCatalogStoryController extends StoryController {
  @override
  StoryState build() => const StoryState(loading: true);
}

void main() {
  test('시대가 준비되기 전에는 활성 인물 조회를 시작하지 않는다', () async {
    final repository = _MockStoryRepository();
    final container = ProviderContainer(
      overrides: [
        storyRepositoryProvider.overrideWithValue(repository),
        storyControllerProvider.overrideWith(_EmptyCatalogStoryController.new),
      ],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(journeyCatalogProvider.future);

    verifyNever(() => repository.fetchAllActiveCharacters());
    expect(catalog.eras, isEmpty);
    expect(catalog.events, isEmpty);
    expect(catalog.characters, isEmpty);
  });

  test('여정 카탈로그는 이야기와 인물 조회를 동시에 시작한다', () async {
    final repository = _MockStoryRepository();
    final pendingEvents = Completer<List<StoryEvent>>();
    final pendingCharacters = Completer<List<Character>>();
    when(
      () => repository.fetchAllActiveCharacters(),
    ).thenAnswer((_) => pendingCharacters.future);

    final container = ProviderContainer(
      overrides: [
        storyRepositoryProvider.overrideWithValue(repository),
        storyControllerProvider.overrideWith(_CatalogStoryController.new),
        dailyExplorationCatalogProvider.overrideWith(
          (ref) => pendingEvents.future,
        ),
      ],
    );
    addTearDown(container.dispose);

    final catalogFuture = container.read(journeyCatalogProvider.future);
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.fetchAllActiveCharacters()).called(1);

    pendingEvents.complete(const []);
    pendingCharacters.complete(const []);
    final catalog = await catalogFuture;
    expect(catalog.events, isEmpty);
    expect(catalog.characters, isEmpty);
  });
}
