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

  group('eventFitTopPadding', () {
    test('상단 툴바 가림 영역과 기본 여백을 보존한다', () {
      final padding = eventFitTopPadding(
        topObscuredPixels: 96,
        bottomPadding: 80,
      );

      expect(padding, 104);
    });

    test('하단 시트가 커지면 사건 묶음이 너무 위로 몰리지 않게 상단 여백을 늘린다', () {
      final padding = eventFitTopPadding(
        topObscuredPixels: 96,
        bottomPadding: 420,
      );

      expect(padding, greaterThan(220));
      expect(padding, lessThan(260));
    });

    test('큰 하단 시트에서도 상단 보정은 상한을 둔다', () {
      final padding = eventFitTopPadding(
        topObscuredPixels: 140,
        bottomPadding: 640,
      );

      expect(padding, closeTo(328, 0.001));
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
        landmarkId: 'lm_test',
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
          landmarkId: 'lm_test',
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

  group('buildRankedEventPointMap', () {
    test('같은 위치의 전체 사건 묶음 기준으로 번호 핀 좌표를 분산한다', () {
      final events = [
        _rankedEvent('1', 1, 31.7, 35.2),
        _rankedEvent('2', 2, 31.7, 35.2),
        _rankedEvent('3', 3, 31.7, 35.2),
      ];

      final allPoints = buildRankedEventPointMap(events);
      final pairOnlyPoints = spreadColocatedPoints({
        '1': events[0].latLng,
        '2': events[1].latLng,
      });

      expect(allPoints.keys, containsAll(['1', '2', '3']));
      expect(allPoints['1'], isNot(pairOnlyPoints['1']));
      expect(allPoints['2'], isNot(pairOnlyPoints['2']));
    });

    test('visibleCount가 있으면 현재 reveal 된 사건까지만 포함한다', () {
      final events = [
        _rankedEvent('1', 3, 31.7, 35.2),
        _rankedEvent('2', 1, 31.7, 35.2),
        _rankedEvent('3', 2, 31.7, 35.2),
      ];

      final points = buildRankedEventPointMap(events, visibleCount: 2);

      expect(points.keys, containsAll(['2', '3']));
      expect(points.containsKey('1'), isFalse);
    });

    test('custom radius로 같은 위치 번호 핀 분산 폭을 줄일 수 있다', () {
      final events = [
        _rankedEvent('1', 1, 31.7, 35.2),
        _rankedEvent('2', 2, 31.7, 35.2),
      ];

      final compact = buildRankedEventPointMap(events, radiusDeg: 0.018);
      final wide = buildRankedEventPointMap(events, radiusDeg: 0.045);

      final compactDelta = (compact['1']!.longitude - 35.2).abs();
      final wideDelta = (wide['1']!.longitude - 35.2).abs();

      expect(compactDelta, lessThan(wideDelta));
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

  group('convexHull', () {
    test('점이 3개 미만이면 입력 그대로 반환', () {
      final r0 = convexHull(const []);
      expect(r0, isEmpty);
      final r1 = convexHull([const LatLng(1, 1)]);
      expect(r1, hasLength(1));
      final r2 = convexHull([const LatLng(1, 1), const LatLng(2, 2)]);
      expect(r2, hasLength(2));
    });

    test('동일 좌표 다수 → 1개로 collapse 후 hull 못 만듦', () {
      final hull = convexHull([
        const LatLng(31.7, 35.2),
        const LatLng(31.7, 35.2),
        const LatLng(31.7, 35.2),
      ]);
      expect(hull.length, lessThanOrEqualTo(2));
    });

    test('일직선 점들 — 중간 점은 hull 에서 제외', () {
      final hull = convexHull([
        const LatLng(0, 0),
        const LatLng(0, 1),
        const LatLng(0, 2),
        const LatLng(0, 3),
      ]);
      // 일직선이라 area 0 → 거의 collapse 됨. 양 끝만 남거나 빈 리스트.
      expect(hull.length, lessThanOrEqualTo(2));
    });

    test('정사각 4점 hull — 4점 모두 hull 정점', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 1),
        const LatLng(1, 0),
        const LatLng(1, 1),
      ];
      final hull = convexHull(pts);
      expect(hull, hasLength(4));
    });

    test('내부 점은 hull 에서 제외 (외곽 4점만)', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(10, 0),
        const LatLng(10, 10),
        const LatLng(5, 5), // 내부 점
        const LatLng(3, 7), // 내부 점
      ];
      final hull = convexHull(pts);
      expect(hull, hasLength(4));
      for (final inner in [const LatLng(5, 5), const LatLng(3, 7)]) {
        expect(hull, isNot(contains(inner)));
      }
    });

    test('실제 사용 — 메소포타미아 + 가나안 + 이집트 hull', () {
      final pts = [
        const LatLng(30.96, 46.10), // 우르
        const LatLng(36.86, 39.03), // 하란
        const LatLng(31.53, 35.10), // 헤브론
        const LatLng(30.78, 31.36), // 고센
        const LatLng(32.5, 39.0), // 내부 점 (확실히 안)
      ];
      final hull = convexHull(pts);
      // 내부 점은 반드시 빠짐. 외곽 점 중 일부가 변 위에 있을 수 있어
      // 정점 수는 3 ~ 4 사이.
      expect(hull.length, inInclusiveRange(3, 4));
      expect(
        hull.contains(const LatLng(32.5, 39.0)),
        isFalse,
        reason: '내부 점은 hull 에서 제외',
      );
    });
  });

  group('bufferedHull', () {
    test('빈 입력 → 빈 리스트', () {
      expect(bufferedHull(const []), isEmpty);
    });

    test('단일 점 → 8각형 buffer', () {
      final hull = bufferedHull([const LatLng(31.7, 35.2)], bufferDeg: 0.5);
      // 8 방향 점 → convex hull 은 보통 8각형 (또는 그 미만).
      expect(hull.length, greaterThanOrEqualTo(4));
      // buffer 가 충분히 커서 모든 정점이 원래 좌표에서 떨어져 있어야 한다.
      for (final p in hull) {
        final dLat = (p.latitude - 31.7).abs();
        final dLng = (p.longitude - 35.2).abs();
        expect(dLat + dLng, greaterThan(0.3));
      }
    });

    test('두 점 → 둘러싸는 capsule 모양', () {
      final hull = bufferedHull([
        const LatLng(0, 0),
        const LatLng(0, 5),
      ], bufferDeg: 0.5);
      expect(hull.length, greaterThanOrEqualTo(4));
    });
  });
}

StoryEvent _rankedEvent(String id, int globalRank, double lat, double lng) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_test',
    eraId: 'e',
    title: id,
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: globalRank,
    rankInEra: globalRank,
    globalRank: globalRank,
    placeName: null,
    lat: lat,
    lng: lng,
    characterCodes: const [],
    bibleRefs: const [],
  );
}

StoryEvent _bareEvent(String id) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_test',
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
