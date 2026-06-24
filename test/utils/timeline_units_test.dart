import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/utils/timeline_units.dart';

void main() {
  group('timelineUnitOptionsForEvents', () {
    test('groups events by unit code and sorts by curated order', () {
      final options = timelineUnitOptionsForEvents([
        _event(
          storyIndex: 4,
          unitCode: 'later',
          unitTitle: '나중 구간',
          unitOrder: 2,
        ),
        _event(
          storyIndex: 1,
          unitCode: 'first',
          unitTitle: '처음 구간',
          unitOrder: 1,
        ),
        _event(
          storyIndex: 2,
          unitCode: 'first',
          unitTitle: '처음 구간',
          unitOrder: 1,
        ),
      ]);

      expect(options.map((unit) => unit.code), ['first', 'later']);
      expect(options.first.title, '처음 구간');
      expect(options.first.eventCount, 2);
      expect(options.first.firstStoryIndex, 1);
    });

    test('normalizes empty unit fields to the default timeline unit', () {
      final options = timelineUnitOptionsForEvents([
        _event(storyIndex: 1, unitCode: '', unitTitle: '', unitOrder: 0),
      ]);

      expect(options, hasLength(1));
      expect(options.single.code, 'default');
      expect(options.single.title, '전체 흐름');
      expect(options.single.order, 1);
    });

    test('keeps an existing proposal unit that is not in published events', () {
      final options = timelineUnitOptionsForEvents(
        [
          _event(
            storyIndex: 1,
            unitCode: 'known',
            unitTitle: '기존 구간',
            unitOrder: 1,
          ),
        ],
        selectedFallback: const TimelineUnitOption(
          code: 'pending_only',
          title: '대기 중 구간',
          order: 2,
        ),
      );

      expect(options.map((unit) => unit.code), ['known', 'pending_only']);
      expect(options.last.eventCount, 0);
    });
  });
}

StoryEvent _event({
  required int storyIndex,
  required String unitCode,
  required String unitTitle,
  required int unitOrder,
}) {
  return StoryEvent(
    id: 'event_$storyIndex',
    eraId: 'era_test',
    title: '이야기 $storyIndex',
    summary: null,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    unitCode: unitCode,
    unitTitle: unitTitle,
    unitOrder: unitOrder,
    rankInEra: storyIndex,
    globalRank: storyIndex,
    landmarkId: 'landmark_test',
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const [],
    bibleRefs: const [],
  );
}
