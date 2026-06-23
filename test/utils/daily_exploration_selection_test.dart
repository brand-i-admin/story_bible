import 'package:flutter_test/flutter_test.dart';

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
}

StoryEvent _event({required String id, required int globalRank}) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_$id',
    eraId: 'era',
    title: '사건 $id',
    summary: null,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: globalRank,
    rankInEra: globalRank,
    globalRank: globalRank,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const [],
    bibleRefs: const [],
  );
}
