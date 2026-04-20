import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/person.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

Era _era({
  required String id,
  required String code,
  String testament = 'old',
  String name = '테스트',
  int displayOrder = 0,
}) {
  return Era(
    id: id,
    code: code,
    testament: testament,
    name: name,
    displayOrder: displayOrder,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  );
}

Person _person({
  required String id,
  required String name,
  int displayOrder = 0,
}) {
  return Person(
    id: id,
    code: id,
    name: name,
    tagline: null,
    description: null,
    avatarUrl: null,
    avatarThumbUrl: null,
    displayOrder: displayOrder,
  );
}

StoryEvent _event({
  required String id,
  required String eraId,
  required List<String> personIds,
  int timeSortKey = 0,
}) {
  return StoryEvent(
    id: id,
    code: id,
    displayNumber: '001',
    eraId: eraId,
    title: '사건 $id',
    summary: null,
    story: null,
    shortStory: null,
    storyScenes: null,
    timelineRank: 1.0,
    startYear: null,
    endYear: null,
    timeSortKey: timeSortKey,
    placeName: null,
    lat: null,
    lng: null,
    personIds: personIds,
    bibleRefs: const [],
    thumbUrl: null,
    storyAssetDir: null,
    storyThumbnailDir: null,
    storySceneCount: 0,
  );
}

void main() {
  late _MockStoryRepository mockRepo;
  late _MockUserRepository mockUserRepo;
  late _MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;

  setUp(() {
    mockRepo = _MockStoryRepository();
    mockUserRepo = _MockUserRepository();
    mockClient = _MockSupabaseClient();
    mockAuth = _MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(null);
  });

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        storyRepositoryProvider.overrideWithValue(mockRepo),
        userRepositoryProvider.overrideWithValue(mockUserRepo),
        supabaseClientProvider.overrideWithValue(mockClient),
      ],
    );
  }

  group('StoryController.initialize', () {
    test('eras 로드 성공 시 첫 구약 시대를 기본 testament로 설정', () async {
      final eras = [
        _era(id: 'era1', code: 'era_primeval', testament: 'old'),
        _era(
          id: 'era2',
          code: 'era_nt_gospels',
          testament: 'new',
          displayOrder: 1,
        ),
      ];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.eras, hasLength(2));
      expect(state.selectedTestament, 'old');
      expect(state.error, isNull);
    });

    test('eras가 비어있으면 에러 메시지 설정', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, '시대 데이터가 없습니다.');
    });

    test('fetchEras 실패 시 에러 메시지 포함한 상태로 전환', () async {
      when(() => mockRepo.fetchEras()).thenThrow(Exception('network down'));

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, contains('초기 데이터를 불러오지 못했습니다'));
    });

    test('구약이 없고 신약만 있으면 신약을 기본 testament로 선택', () async {
      final eras = [_era(id: 'era1', code: 'era_nt_test', testament: 'new')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
    });
  });

  group('StoryController.selectEra', () {
    setUp(() {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'era1', code: 'era_primeval')]);
    });

    test('persons와 events를 로드하고 selectedEraId를 설정', () async {
      when(
        () => mockRepo.fetchPersonsByEra('era1'),
      ).thenAnswer((_) async => [_person(id: 'p1', name: '아담')]);
      when(() => mockRepo.fetchEventsByEra('era1')).thenAnswer(
        (_) async => [
          _event(id: 'e1', eraId: 'era1', personIds: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');

      final state = container.read(storyControllerProvider);
      expect(state.selectedEraId, 'era1');
      expect(state.persons, hasLength(1));
      expect(state.events, hasLength(1));
      expect(state.loading, isFalse);
    });

    test('실패 시 error 메시지 설정', () async {
      when(
        () => mockRepo.fetchPersonsByEra('era1'),
      ).thenThrow(Exception('boom'));

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');

      final state = container.read(storyControllerProvider);
      expect(state.error, contains('시대 변경 중'));
    });
  });

  group('StoryController.togglePerson', () {
    test('비어있는 set에 id 추가', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.togglePerson('p1');

      expect(
        container.read(storyControllerProvider).selectedPersonIds,
        containsAll(['p1']),
      );
    });

    test('이미 있는 id는 제거', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.togglePerson('p1');
      controller.togglePerson('p1');

      expect(
        container.read(storyControllerProvider).selectedPersonIds,
        isEmpty,
      );
    });

    test('색상 팔레트가 선택 순서대로 할당', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.togglePerson('p1');
      controller.togglePerson('p2');

      final colors = container
          .read(storyControllerProvider)
          .selectedPersonColors;
      expect(colors['p1'], isNotNull);
      expect(colors['p2'], isNotNull);
      expect(colors['p1'], isNot(equals(colors['p2'])));
    });
  });

  group('StoryController.selectEvent', () {
    test('null 전달 시 selectedEventId 클리어', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.selectEvent('e1');
      expect(container.read(storyControllerProvider).selectedEventId, 'e1');

      controller.selectEvent(null);
      expect(container.read(storyControllerProvider).selectedEventId, isNull);
    });
  });

  group('StoryController.colorForPerson', () {
    test('미선택 인물은 기본 색상 반환', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      final color = controller.colorForPerson('unknown');
      expect(color, const Color(0xFF8E7B61));
    });
  });

  group('StoryController.mergedTimeline', () {
    test('선택된 인물의 이벤트만 time_sort_key 오름차순으로 반환', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'era1', code: 'era_primeval')]);
      when(() => mockRepo.fetchPersonsByEra('era1')).thenAnswer(
        (_) async => [
          _person(id: 'p1', name: '아담'),
          _person(id: 'p2', name: '이브', displayOrder: 1),
        ],
      );
      when(() => mockRepo.fetchEventsByEra('era1')).thenAnswer(
        (_) async => [
          _event(id: 'e1', eraId: 'era1', personIds: ['p1'], timeSortKey: 20),
          _event(id: 'e2', eraId: 'era1', personIds: ['p2'], timeSortKey: 10),
          _event(id: 'e3', eraId: 'era1', personIds: ['p1'], timeSortKey: 5),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');
      controller.setSelectedPersons({'p1'});

      final timeline = controller.mergedTimeline();
      expect(timeline.map((e) => e.id), orderedEquals(['e3', 'e1']));
    });
  });

  group('StoryController.selectTestament', () {
    test('구약 → 신약 전환 시 해당 testament의 첫 시대를 선택', () async {
      final eras = [
        _era(id: 'e1', code: 'old1', testament: 'old'),
        _era(id: 'e2', code: 'new1', testament: 'new', displayOrder: 0),
        _era(id: 'e3', code: 'new2', testament: 'new', displayOrder: 1),
      ];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchPersonsByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      await controller.selectTestament('new');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
      // 첫 번째 신약 시대 선택
      expect(state.selectedEraId, 'e2');
    });

    test('이미 같은 testament이고 시대도 일치하면 아무 동작 없음', () async {
      final eras = [_era(id: 'e1', code: 'old1', testament: 'old')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchPersonsByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      // 같은 testament 다시 호출 — selectEra가 추가 호출되지 않아야 함
      await controller.selectTestament('old');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'old');
      expect(state.selectedEraId, 'e1');
    });

    test('해당 testament에 시대가 없으면 선택 초기화', () async {
      final eras = [_era(id: 'e1', code: 'old1', testament: 'old')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      await controller.selectTestament('new');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
      expect(state.selectedEraId, isNull);
      expect(state.persons, isEmpty);
      expect(state.events, isEmpty);
    });
  });

  group('StoryController.toggleEra', () {
    test('선택된 시대를 다시 토글하면 선택 해제', () async {
      final eras = [_era(id: 'e1', code: 'old1')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchPersonsByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      expect(container.read(storyControllerProvider).selectedEraId, 'e1');

      await controller.toggleEra('e1');
      expect(container.read(storyControllerProvider).selectedEraId, isNull);
    });

    test('다른 시대를 토글하면 해당 시대를 선택', () async {
      final eras = [_era(id: 'e1', code: 'old1'), _era(id: 'e2', code: 'old2')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchPersonsByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      await controller.toggleEra('e2');
      expect(container.read(storyControllerProvider).selectedEraId, 'e2');
    });
  });

  group('StoryController.clearEraSelection', () {
    test('모든 선택 상태를 초기화', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(
        () => mockRepo.fetchPersonsByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', personIds: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      controller.togglePerson('p1');
      controller.selectEvent('ev1');

      controller.clearEraSelection();
      final state = container.read(storyControllerProvider);
      expect(state.selectedEraId, isNull);
      expect(state.selectedEventId, isNull);
      expect(state.selectedPersonIds, isEmpty);
      expect(state.persons, isEmpty);
      expect(state.events, isEmpty);
      expect(state.searchQuery, '');
    });
  });

  group('StoryController.setSelectedPersons', () {
    test('persons에 없는 id는 필터링된다', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(() => mockRepo.fetchPersonsByEra(any())).thenAnswer(
        (_) async => [
          _person(id: 'p1', name: 'A'),
          _person(id: 'p2', name: 'B'),
        ],
      );
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      controller.setSelectedPersons({'p1', 'p999'});
      final state = container.read(storyControllerProvider);
      expect(state.selectedPersonIds, {'p1'});
      expect(state.selectedPersonColors.containsKey('p1'), true);
      expect(state.selectedPersonColors.containsKey('p999'), false);
    });
  });

  group('StoryController.setSearchQuery', () {
    test('빈 쿼리면 검색 결과 초기화', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('모세');
      controller.setSearchQuery('');
      final state = container.read(storyControllerProvider);
      expect(state.searchQuery, '');
      expect(state.isSearching, false);
      expect(state.searchResults, isEmpty);
    });

    test('공백만 있는 쿼리도 빈 쿼리 처리', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('   ');
      final state = container.read(storyControllerProvider);
      expect(state.isSearching, false);
    });

    test('유효한 쿼리면 isSearching을 true로 설정', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('모세');
      final state = container.read(storyControllerProvider);
      expect(state.searchQuery, '모세');
      expect(state.isSearching, true);
    });
  });
}
