import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/story_controller.dart';

StoryEvent _makeEvent({
  required String id,
  required double? lat,
  required double? lng,
}) {
  return StoryEvent(
    id: id,
    eraId: 'era-1',
    title: id,
    summary: null,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 0,
    rankInEra: 0,
    globalRank: 0,
    placeName: null,
    lat: lat,
    lng: lng,
    characterCodes: const [],
    bibleRefs: const <BibleRef>[],
  );
}

void main() {
  group('filterEventsByLatLngBox', () {
    final inside = _makeEvent(id: 'inside', lat: 31.5, lng: 35.0);
    final boundary = _makeEvent(id: 'boundary', lat: 32.0, lng: 36.0);
    final outsideLat = _makeEvent(id: 'outside_lat', lat: 33.0, lng: 35.0);
    final outsideLng = _makeEvent(id: 'outside_lng', lat: 31.0, lng: 38.0);
    final missing = _makeEvent(id: 'missing', lat: null, lng: null);

    test('박스 내부 사건만 통과시킨다', () {
      final hits = filterEventsByLatLngBox(
        events: [inside, outsideLat, outsideLng, missing],
        minLat: 30.0,
        maxLat: 32.0,
        minLng: 34.0,
        maxLng: 36.0,
      );

      expect(hits.map((e) => e.id), ['inside']);
    });

    test('박스 경계는 포함된다 (inclusive)', () {
      final hits = filterEventsByLatLngBox(
        events: [boundary],
        minLat: 30.0,
        maxLat: 32.0,
        minLng: 34.0,
        maxLng: 36.0,
      );

      expect(hits, hasLength(1));
    });

    test('좌표가 null 인 사건은 제외된다', () {
      final hits = filterEventsByLatLngBox(
        events: [missing],
        minLat: -90.0,
        maxLat: 90.0,
        minLng: -180.0,
        maxLng: 180.0,
      );

      expect(hits, isEmpty);
    });

    test('min/max 가 뒤집혀 들어와도 같은 결과를 낸다', () {
      final hits = filterEventsByLatLngBox(
        events: [inside],
        minLat: 32.0,
        maxLat: 30.0,
        minLng: 36.0,
        maxLng: 34.0,
      );

      expect(hits.map((e) => e.id), ['inside']);
    });
  });
}
