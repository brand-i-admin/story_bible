import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/utils/daily_exploration_selection.dart';

void main() {
  group('dailyExplorationKeyForKst', () {
    test('UTC 오후가 KST 다음날이면 다음 날짜 키를 쓴다', () {
      final key = dailyExplorationKeyForKst(
        DateTime.parse('2026-06-22T15:30:00Z'),
      );

      expect(key, '2026-6-23');
    });
  });

  group('pickDailyExplorationEvent', () {
    test('같은 날짜 키는 같은 사건을 고른다', () {
      final events = [
        _event(id: 'b', globalRank: 2),
        _event(id: 'a', globalRank: 1),
        _event(id: 'c', globalRank: 3),
      ];

      final first = pickDailyExplorationEvent(
        events: events,
        dayKey: '2026-6-23',
      );
      final second = pickDailyExplorationEvent(
        events: events.reversed.toList(),
        dayKey: '2026-6-23',
      );

      expect(first?.id, second?.id);
    });

    test('사건이 없으면 null을 반환한다', () {
      expect(
        pickDailyExplorationEvent(events: const [], dayKey: '2026-6-23'),
        isNull,
      );
    });
  });

  group('pickDailyExplorationJourney', () {
    test('추천 사건을 가운데 두고 이전과 이후 사건을 함께 반환한다', () {
      final events = [
        _event(id: 'a', globalRank: 1),
        _event(id: 'b', globalRank: 2),
        _event(id: 'c', globalRank: 3),
        _event(id: 'd', globalRank: 4),
      ];
      final recommended = pickDailyExplorationEvent(
        events: events,
        dayKey: '2026-6-23',
      )!;

      final journey = pickDailyExplorationJourney(
        events: events,
        dayKey: '2026-6-23',
      );

      expect(journey, hasLength(3));
      expect(journey[1].id, recommended.id);
      expect(journey.map((event) => event.id).toSet(), hasLength(3));
    });

    test('첫 사건이 추천되면 마지막 사건을 이전 이야기로 순환한다', () {
      final events = [
        _event(id: 'a', globalRank: 1),
        _event(id: 'b', globalRank: 2),
        _event(id: 'c', globalRank: 3),
      ];
      var matchingDayKey = '';
      for (var day = 1; day <= 100; day += 1) {
        final candidate = '2026-7-$day';
        if (pickDailyExplorationEvent(events: events, dayKey: candidate)?.id ==
            'a') {
          matchingDayKey = candidate;
          break;
        }
      }
      expect(matchingDayKey, isNotEmpty);

      final journey = pickDailyExplorationJourney(
        events: events,
        dayKey: matchingDayKey,
      );

      expect(journey.map((event) => event.id), ['c', 'a', 'b']);
    });

    test('사건이 두 개뿐이면 중복 없이 두 사건만 반환한다', () {
      final journey = pickDailyExplorationJourney(
        events: [
          _event(id: 'a', globalRank: 1),
          _event(id: 'b', globalRank: 2),
        ],
        dayKey: '2026-6-23',
      );

      expect(journey, hasLength(2));
      expect(journey.map((event) => event.id).toSet(), {'a', 'b'});
    });
  });

  group('explorationJourneyAround', () {
    final events = [
      _event(id: 'a', globalRank: 1),
      _event(id: 'b', globalRank: 2),
      _event(id: 'c', globalRank: 3),
      _event(id: 'd', globalRank: 4),
    ];

    test('선택한 이야기를 가운데 두고 이전과 다음 이야기를 반환한다', () {
      final journey = explorationJourneyAround(
        events: events,
        currentEventId: 'b',
      );

      expect(journey.map((event) => event.id), ['a', 'b', 'c']);
    });

    test('마지막 이야기 다음에는 첫 이야기로 순환한다', () {
      final journey = explorationJourneyAround(
        events: events,
        currentEventId: 'd',
      );

      expect(journey.map((event) => event.id), ['c', 'd', 'a']);
    });
  });

  group('pickExplorationResumeEvent', () {
    final events = [
      _event(id: 'a', globalRank: 1),
      _event(id: 'b', globalRank: 2),
      _event(id: 'c', globalRank: 3),
      _event(id: 'd', globalRank: 4),
    ];

    test('감정 새기기가 없으면 전체 첫 이야기를 추천한다', () {
      final current = pickExplorationResumeEvent(
        events: events,
        eras: const [_defaultEra],
        emotionUpdatedAtByEventId: const {},
      );

      expect(current?.id, 'a');
    });

    test('가장 최근 감정 새기기 다음 이야기를 추천한다', () {
      final current = pickExplorationResumeEvent(
        events: events,
        eras: const [_defaultEra],
        emotionUpdatedAtByEventId: {
          'a': DateTime.parse('2026-07-13T09:00:00Z'),
          'c': DateTime.parse('2026-07-14T09:00:00Z'),
        },
      );

      expect(current?.id, 'd');
    });

    test('마지막 이야기가 가장 최근 기록이면 마지막 이야기를 유지한다', () {
      final current = pickExplorationResumeEvent(
        events: events,
        eras: const [_defaultEra],
        emotionUpdatedAtByEventId: {
          'd': DateTime.parse('2026-07-14T09:00:00Z'),
        },
      );

      expect(current?.id, 'd');
    });
  });

  group('explorationPositionFor', () {
    final events = [
      _event(id: 'a', globalRank: 1, eraId: 'primeval'),
      _event(id: 'b', globalRank: 2, eraId: 'patriarch'),
      _event(id: 'c', globalRank: 3, eraId: 'patriarch'),
    ];

    test('전체 첫 이야기는 이전 이야기 없이 시작한다', () {
      final position = explorationPositionFor(
        events: events,
        eras: const [_primevalEra, _patriarchEra],
        currentEventId: 'a',
      );

      expect(position?.previous, isNull);
      expect(position?.current.id, 'a');
      expect(position?.next?.id, 'b');
    });

    test('시대가 달라도 전체 시간순 이전 이야기를 유지한다', () {
      final position = explorationPositionFor(
        events: events,
        eras: const [_primevalEra, _patriarchEra],
        currentEventId: 'b',
      );

      expect(position?.previous?.id, 'a');
      expect(position?.previous?.eraId, 'primeval');
      expect(position?.next?.id, 'c');
    });

    test('전체 마지막 이야기는 다음 이야기가 없다', () {
      final position = explorationPositionFor(
        events: events,
        eras: const [_primevalEra, _patriarchEra],
        currentEventId: 'c',
      );

      expect(position?.previous?.id, 'b');
      expect(position?.next, isNull);
    });
  });

  group('explorationMapSelectionFor', () {
    final events = [
      _event(id: 'a', globalRank: 1, eraId: 'primeval'),
      _event(id: 'b', globalRank: 2, eraId: 'patriarch'),
      _event(id: 'c', globalRank: 3, eraId: 'patriarch'),
      _event(id: 'd', globalRank: 4, eraId: 'patriarch'),
    ];

    test('현재 시대 모든 사건을 표시하고 다른 시대의 이전 핀은 제외한다', () {
      final selection = explorationMapSelectionFor(
        events: events,
        eras: const [_primevalEra, _patriarchEra],
        currentEventId: 'b',
      );

      expect(selection.events.map((event) => event.id), ['b', 'c', 'd']);
      expect(selection.markerRoles, {'b': 'current', 'c': 'next'});
      expect(selection.fitEventIds, ['b', 'c']);
    });

    test('같은 시대의 이전 현재 다음만 카메라 기준과 역할 핀으로 고른다', () {
      final selection = explorationMapSelectionFor(
        events: events,
        eras: const [_primevalEra, _patriarchEra],
        currentEventId: 'c',
      );

      expect(selection.events.map((event) => event.id), ['b', 'c', 'd']);
      expect(selection.markerRoles, {
        'b': 'previous',
        'c': 'current',
        'd': 'next',
      });
      expect(selection.fitEventIds, ['b', 'c', 'd']);
    });
  });

  group('orderedExplorationEventsByEra', () {
    final events = [
      _event(id: 'jesus-middle', eraId: 'jesus', globalRank: 1, rankInEra: 2),
      _event(
        id: 'primeval-second',
        eraId: 'primeval',
        globalRank: 900,
        rankInEra: 2,
      ),
      _event(id: 'exile-last', eraId: 'exile', globalRank: 500, rankInEra: 16),
      _event(id: 'jesus-first', eraId: 'jesus', globalRank: 2, rankInEra: 1),
      _event(
        id: 'primeval-first',
        eraId: 'primeval',
        globalRank: 700,
        rankInEra: 1,
      ),
    ];

    test('globalRank가 뒤섞여도 시대와 시대 내 사건 순서로 정렬한다', () {
      final ordered = orderedExplorationEventsByEra(
        events: events,
        eras: _canonicalEras,
      );

      expect(ordered.map((event) => event.id), [
        'primeval-first',
        'primeval-second',
        'exile-last',
        'jesus-first',
        'jesus-middle',
      ]);
    });

    test('구약 7시대 다음에 신약 3시대를 고정 순서로 이어 붙인다', () {
      const eraCodes = <String>[
        'era_primeval',
        'era_patriarch',
        'era_exodus',
        'era_judges',
        'era_monarchy',
        'era_divided_kingdom',
        'era_exile_return',
        'era_nt_public_ministry',
        'era_nt_apostolic',
        'era_nt_post_apostolic',
      ];
      final eras = <Era>[
        for (var index = 0; index < eraCodes.length; index += 1)
          Era(
            id: 'era-$index',
            code: eraCodes[index],
            testament: index < 7 ? 'old' : 'new',
            name: eraCodes[index],
            displayOrder: index < 7 ? index + 1 : index - 6,
            startYear: null,
            endYear: null,
            mapCenterLat: null,
            mapCenterLng: null,
            mapZoom: null,
          ),
      ];
      final unorderedEvents = <StoryEvent>[
        for (var index = eraCodes.length - 1; index >= 0; index -= 1)
          _event(
            id: 'event-$index',
            eraId: 'era-$index',
            globalRank: eraCodes.length - index,
          ),
      ];

      final ordered = orderedExplorationEventsByEra(
        events: unorderedEvents,
        eras: eras,
      );

      expect(ordered.map((event) => event.eraId), [
        for (var index = 0; index < eraCodes.length; index += 1) 'era-$index',
      ]);
    });

    test('공생애 중간 이야기는 같은 시대 직전 이야기를 이전으로 쓴다', () {
      final position = explorationPositionFor(
        events: events,
        eras: _canonicalEras,
        currentEventId: 'jesus-middle',
      );

      expect(position?.previous?.id, 'jesus-first');
      expect(position?.previous?.eraId, 'jesus');
    });

    test('공생애 첫 이야기는 포로 및 포로 후기 마지막 이야기에 이어진다', () {
      final position = explorationPositionFor(
        events: events,
        eras: _canonicalEras,
        currentEventId: 'jesus-first',
      );

      expect(position?.previous?.id, 'exile-last');
      expect(position?.previous?.eraId, 'exile');
    });

    test('최근 감정 다음 추천도 같은 고정 순서를 사용한다', () {
      final current = pickExplorationResumeEvent(
        events: events,
        eras: _canonicalEras,
        emotionUpdatedAtByEventId: {
          'jesus-first': DateTime.parse('2026-07-14T09:00:00Z'),
        },
      );

      expect(current?.id, 'jesus-middle');
    });
  });
}

StoryEvent _event({
  required String id,
  required int globalRank,
  String eraId = 'era',
  int? rankInEra,
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_$id',
    eraId: eraId,
    title: '사건 $id',
    summary: null,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: globalRank,
    rankInEra: rankInEra ?? globalRank,
    globalRank: globalRank,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const [],
    bibleRefs: const [],
  );
}

const _defaultEra = Era(
  id: 'era',
  code: 'era_primeval',
  testament: 'old',
  name: '원역사',
  displayOrder: 1,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _primevalEra = Era(
  id: 'primeval',
  code: 'era_primeval',
  testament: 'old',
  name: '원역사',
  displayOrder: 1,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _patriarchEra = Era(
  id: 'patriarch',
  code: 'era_patriarch',
  testament: 'old',
  name: '족장',
  displayOrder: 2,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _canonicalEras = <Era>[
  _primevalEra,
  Era(
    id: 'patriarch',
    code: 'era_patriarch',
    testament: 'old',
    name: '족장',
    displayOrder: 2,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  ),
  Era(
    id: 'exile',
    code: 'era_exile_return',
    testament: 'old',
    name: '포로 및 포로 후기',
    displayOrder: 7,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  ),
  Era(
    id: 'jesus',
    code: 'era_nt_public_ministry',
    testament: 'new',
    name: '예수님의 공생애',
    displayOrder: 1,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  ),
];
