import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/utils/map_math.dart';

void main() {
  group('easeInOut', () {
    test('0과 1에서 경계값을 반환', () {
      expect(easeInOut(0), closeTo(0, 1e-9));
      expect(easeInOut(1), closeTo(1, 1e-9));
    });

    test('중간값 0.5에서 정확히 0.5', () {
      expect(easeInOut(0.5), closeTo(0.5, 1e-9));
    });

    test('단조 증가', () {
      var prev = -1.0;
      for (var i = 0; i <= 20; i++) {
        final curr = easeInOut(i / 20);
        expect(curr, greaterThan(prev));
        prev = curr;
      }
    });
  });

  group('mercatorY', () {
    test('적도(0°)는 0.5 근처', () {
      expect(mercatorY(0), closeTo(0.5, 1e-9));
    });

    test('북극에 가까울수록 0에 수렴', () {
      expect(mercatorY(85), lessThan(0.05));
    });

    test('남극에 가까울수록 1에 수렴', () {
      expect(mercatorY(-85), greaterThan(0.95));
    });

    test('극단값 클램프 (±90° → 약 0/1)', () {
      expect(mercatorY(90), lessThan(0.05));
      expect(mercatorY(-90), greaterThan(0.95));
    });
  });

  group('normalizedLongitudeDelta', () {
    test('단순 차이는 그대로', () {
      expect(normalizedLongitudeDelta(0, 90), 90);
      expect(normalizedLongitudeDelta(-30, 30), 60);
    });

    test('180° 초과는 반대 방향으로 보정', () {
      expect(normalizedLongitudeDelta(-170, 170), 20);
    });

    test('order 무관 (절대값)', () {
      expect(normalizedLongitudeDelta(170, -170), 20);
    });
  });

  group('hasMultiPlacePin', () {
    test('한글 화살표 → 인식', () {
      expect(hasMultiPlacePin('예루살렘 → 다메섹'), true);
    });

    test('ASCII 화살표 -> 인식', () {
      expect(hasMultiPlacePin('Jerusalem -> Damascus'), true);
    });

    test('단일 장소면 false', () {
      expect(hasMultiPlacePin('가나안'), false);
      expect(hasMultiPlacePin(''), false);
    });
  });

  group('splitPlaceParts', () {
    test('한글 화살표로 분리', () {
      final (from, to) = splitPlaceParts('예루살렘 → 다메섹');
      expect(from, '예루살렘');
      expect(to, '다메섹');
    });

    test('공백 trim', () {
      final (from, to) = splitPlaceParts(' A → B ');
      expect(from, 'A');
      expect(to, 'B');
    });

    test('분리 불가 시 동일 값 반환', () {
      final (from, to) = splitPlaceParts('단일');
      expect(from, '단일');
      expect(to, '단일');
    });
  });

  group('buildSplitPinPoints', () {
    test('출발점은 base와 동일', () {
      const base = LatLng(31.7, 35.2);
      final (start, _) = buildSplitPinPoints(base);
      expect(start, base);
    });

    test('도착점은 동남쪽 오프셋 (위도 더 작고 경도 더 큼)', () {
      const base = LatLng(31.7, 35.2);
      final (_, end) = buildSplitPinPoints(base);
      expect(end.latitude, lessThan(base.latitude));
      expect(end.longitude, greaterThan(base.longitude));
    });
  });

  group('buildAdjustedPoints', () {
    StoryEvent event(String id, double lat, double lng) {
      return StoryEvent(
        id: id,
        eraId: 'e',
        title: id,
        summary: null,
        storyScenes: const <String>[],
        sceneCharacters: const <List<String>>[],
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
        bibleRefs: const [],
      );
    }

    test('단일 이벤트는 원본 좌표 유지', () {
      final result = buildAdjustedPoints([event('1', 31.7, 35.2)]);
      expect(result['1'], const LatLng(31.7, 35.2));
    });

    test('같은 좌표 그룹은 분산 배치', () {
      final result = buildAdjustedPoints([
        event('1', 31.7, 35.2),
        event('2', 31.7, 35.2),
        event('3', 31.7, 35.2),
      ]);
      expect(result.length, 3);
      // 모두 다른 좌표여야 함
      final coords = result.values.toSet();
      expect(coords.length, 3);
    });

    test('좌표가 없는 이벤트는 결과에서 제외', () {
      final result = buildAdjustedPoints([
        event('a', 31.7, 35.2),
        const StoryEvent(
          id: 'b',
          eraId: 'e',
          title: 'noCoord',
          summary: null,
          storyScenes: <String>[],
          sceneCharacters: <List<String>>[],
          startYear: null,
          endYear: null,
          timePrecision: 'approx',
          storyIndex: 0,
          rankInEra: 0,
          globalRank: 0,
          placeName: null,
          lat: null,
          lng: null,
          characterCodes: [],
          bibleRefs: [],
        ),
      ]);
      expect(result.containsKey('a'), true);
      expect(result.containsKey('b'), false);
    });
  });

  group('rotateOffset', () {
    test('0 라디안은 무회전', () {
      const o = Offset(3, 4);
      final r = rotateOffset(o, 0);
      expect(r.dx, closeTo(3, 1e-9));
      expect(r.dy, closeTo(4, 1e-9));
    });

    test('π/2 라디안은 90° 시계방향 회전', () {
      const o = Offset(1, 0);
      final r = rotateOffset(o, 1.5707963267948966); // π/2
      expect(r.dx, closeTo(0, 1e-9));
      expect(r.dy, closeTo(1, 1e-9));
    });

    test('회전은 거리 보존', () {
      const o = Offset(3, 4);
      final r = rotateOffset(o, 1.234);
      final originalDist = (o.dx * o.dx + o.dy * o.dy);
      final rotatedDist = (r.dx * r.dx + r.dy * r.dy);
      expect(rotatedDist, closeTo(originalDist, 1e-9));
    });
  });

  group('eventListSignature', () {
    test('빈 리스트는 빈 문자열', () {
      expect(eventListSignature([]), '');
    });

    test('id를 |로 join', () {
      expect(eventListSignature([_bareEvent('a'), _bareEvent('b')]), 'a|b');
    });

    test('순서 변경 시 시그니처도 다름', () {
      final s1 = eventListSignature([_bareEvent('a'), _bareEvent('b')]);
      final s2 = eventListSignature([_bareEvent('b'), _bareEvent('a')]);
      expect(s1, isNot(s2));
    });
  });
}

StoryEvent _bareEvent(String id) {
  return StoryEvent(
    id: id,
    eraId: 'e',
    title: id,
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 0,
    rankInEra: 0,
    globalRank: 0,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const [],
    bibleRefs: const [],
  );
}
