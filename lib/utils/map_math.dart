import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

import 'package:latlong2/latlong.dart';

import '../models/story_event.dart';

/// 지도 패널에서 사용하는 순수 수학/지오메트리 함수 모음.
///
/// 모두 부수효과 없이 입력 → 출력만 수행하므로 단위 테스트 가능하다.
/// 원래 `_StoryMapPanelState` 내부의 private 메소드들이었다.

/// `t`(0.0~1.0)에 대한 4차 ease-in-out 보간값.
double easeInOut(double t) {
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
}

/// 이벤트 리스트의 ID들을 `|`로 join한 시그니처.
/// `didUpdateWidget`에서 변경 감지용으로 사용.
String eventListSignature(List<StoryEvent> events) {
  return events.map((event) => event.id).join('|');
}

/// 위도를 Web Mercator Y 좌표(0~1)로 투영.
/// 극단값 클램프 적용 (-85.051 ~ 85.051).
double mercatorY(double latitude) {
  final clampedLatitude = latitude.clamp(-85.05112878, 85.05112878);
  final sinValue = math.sin(clampedLatitude * math.pi / 180.0);
  return 0.5 - math.log((1 + sinValue) / (1 - sinValue)) / (4 * math.pi);
}

/// 두 경도(west, east) 사이의 짧은 호 거리(°).
/// 180° 초과 시 반대 방향으로 보정.
double normalizedLongitudeDelta(double west, double east) {
  final delta = (east - west).abs();
  if (delta <= 180.0) {
    return delta;
  }
  return 360.0 - delta;
}

/// 사건/지역 fitBounds 에서 사용할 상단 padding.
///
/// 하단 선택 시트가 높아질수록 MapLibre fitBounds 가 가시 영역을 위쪽으로 잡기
/// 때문에 사건/지역 묶음이 화면 상단 필터 뒤로 몰릴 수 있다. 하단 padding 의
/// 초과분을 상단에도 충분히 나눠 주어 북쪽 지도 여백과 탭 가능한 영역을 확보한다.
double eventFitTopPadding({
  required double topObscuredPixels,
  required double bottomPadding,
  double minPadding = 16.0,
  double baseGap = 8.0,
}) {
  final safeTopPadding = math.max(minPadding, topObscuredPixels + baseGap);
  final excessBottomPadding = math.max(0.0, bottomPadding - safeTopPadding);
  return safeTopPadding + math.min(180.0, excessBottomPadding * 0.45);
}

/// "예루살렘 → 다메섹" 같은 다중 장소 표기인지 판정.
bool hasMultiPlacePin(String placeName) {
  return placeName.contains('→') || placeName.contains('->');
}

/// "예루살렘 → 다메섹"을 (출발, 도착)으로 분리. 분리 불가 시 동일 값 반환.
(String, String) splitPlaceParts(String placeName) {
  final arrow = placeName.contains('→') ? '→' : '->';
  final parts = placeName
      .split(arrow)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) {
    return (parts.first, parts.last);
  }
  return (placeName, placeName);
}

/// 다중 장소 핀의 출발/도착 좌표 한 쌍을 계산.
/// basePoint를 출발점으로, 약간 동남쪽 오프셋을 도착점으로.
(LatLng, LatLng) buildSplitPinPoints(LatLng basePoint) {
  const radiusDeg = 0.038;
  final cosLat = math
      .cos(basePoint.latitude * math.pi / 180)
      .abs()
      .clamp(0.3, 1.0);
  final dLng = (radiusDeg / cosLat) * 0.75;
  const dLat = radiusDeg * 0.30;
  return (
    basePoint,
    LatLng(basePoint.latitude - dLat, basePoint.longitude + dLng),
  );
}

/// 가까운 좌표(소수점 2자리 동일)를 가진 이벤트들을 원형으로 분산 배치.
/// 같은 위치에 여러 핀이 겹치는 것을 방지하기 위해 사용.
Map<String, LatLng> buildAdjustedPoints(List<StoryEvent> visible) {
  final grouped = <String, List<StoryEvent>>{};
  for (final event in visible) {
    if (event.lat == null || event.lng == null) continue;
    final key =
        '${event.lat!.toStringAsFixed(2)}:${event.lng!.toStringAsFixed(2)}';
    grouped.putIfAbsent(key, () => []).add(event);
  }

  final adjusted = <String, LatLng>{};
  for (final group in grouped.values) {
    if (group.length == 1) {
      final event = group.first;
      adjusted[event.id] = event.latLng;
      continue;
    }

    final radiusDeg = group.length > 6 ? 0.10 : 0.065;
    final baseLat = group.first.lat!;
    final cosLat = math.cos(baseLat * math.pi / 180).abs().clamp(0.3, 1.0);
    for (var i = 0; i < group.length; i++) {
      final angle = (2 * math.pi * i) / group.length;
      final dLat = radiusDeg * math.sin(angle);
      final dLng = (radiusDeg * math.cos(angle)) / cosLat;
      final event = group[i];
      adjusted[event.id] = LatLng(event.lat! + dLat, event.lng! + dLng);
    }
  }
  return adjusted;
}

/// 시간순 번호 핀에서 사용하는 사건 좌표 맵.
///
/// [visibleCount]가 있으면 현재 reveal 된 사건까지만 포함한다. 같은 장소의
/// 사건들은 [spreadColocatedPoints]로 분산해 실제 번호 핀 중심과 path/glow
/// 중심이 같은 좌표계를 공유하게 한다.
Map<String, LatLng> buildRankedEventPointMap(
  List<StoryEvent> events, {
  int? visibleCount,
  double radiusDeg = 0.045,
  double thresholdDeg = 0.04,
}) {
  final ordered = events.where((event) => event.hasCoordinate).toList()
    ..sort((a, b) => a.globalRank.compareTo(b.globalRank));
  final visible = visibleCount == null
      ? ordered
      : ordered.take(math.max(0, visibleCount)).toList(growable: false);
  final input = <String, LatLng>{
    for (final event in visible) event.id: event.latLng,
  };
  return spreadColocatedPoints(
    input,
    radiusDeg: radiusDeg,
    thresholdDeg: thresholdDeg,
  );
}

/// 거리 기반으로 가까운 점들을 묶어 원형 분산. [thresholdDeg] 이내 거리의 점들을
/// 한 그룹으로 (transitive) 묶어 [radiusDeg] 반경의 원에 분산.
///
/// 격자 키 방식(소수점 2자리 동일)은 31.55 vs 31.53 처럼 같은 셀 경계 양쪽에
/// 걸친 점을 못 묶는 문제가 있어, 거리 직접 비교로 변경. region(영역) 핀은
/// 폴리곤 중심 근처에 한 개라 겹칠 일이 없으므로 호출 측에서 non-region
/// landmark 만 골라 넘기는 것을 권장.
Map<String, LatLng> spreadColocatedPoints(
  Map<String, LatLng> input, {
  double radiusDeg = 0.05,
  double thresholdDeg = 0.04,
}) {
  final entries = input.entries.toList(growable: false);
  final visited = List<bool>.filled(entries.length, false);
  final adjusted = <String, LatLng>{};

  for (var i = 0; i < entries.length; i++) {
    if (visited[i]) continue;
    visited[i] = true;
    final group = <MapEntry<String, LatLng>>[entries[i]];
    final base = entries[i].value;
    for (var j = i + 1; j < entries.length; j++) {
      if (visited[j]) continue;
      final p = entries[j].value;
      final d = math.sqrt(
        math.pow(p.latitude - base.latitude, 2) +
            math.pow(p.longitude - base.longitude, 2),
      );
      if (d < thresholdDeg) {
        visited[j] = true;
        group.add(entries[j]);
      }
    }

    if (group.length == 1) {
      adjusted[group.first.key] = group.first.value;
      continue;
    }
    final r = group.length > 6 ? radiusDeg * 1.5 : radiusDeg;
    final cosLat = math
        .cos(base.latitude * math.pi / 180)
        .abs()
        .clamp(0.3, 1.0);
    for (var k = 0; k < group.length; k++) {
      final angle = (2 * math.pi * k) / group.length;
      final dLat = r * math.sin(angle);
      final dLng = (r * math.cos(angle)) / cosLat;
      final entry = group[k];
      adjusted[entry.key] = LatLng(
        entry.value.latitude + dLat,
        entry.value.longitude + dLng,
      );
    }
  }
  return adjusted;
}

/// 화면 좌표 오프셋을 `radians`만큼 회전.
/// 카메라 회전(rotationRad) 보정에 사용.
Offset rotateOffset(Offset value, double radians) {
  final cosTheta = math.cos(radians);
  final sinTheta = math.sin(radians);
  return Offset(
    value.dx * cosTheta - value.dy * sinTheta,
    value.dx * sinTheta + value.dy * cosTheta,
  );
}

/// 입력 점들의 convex hull (최소 볼록 다각형) 정점 리스트를 반환.
/// Andrew's monotone chain 알고리즘 — O(n log n).
///
/// 시대 폴리곤을 그 시대의 사건/랜드마크 좌표 기반으로 동적 계산할 때 사용.
/// 점이 3개 미만이면 입력 그대로 반환 (다각형 못 만듦).
List<LatLng> convexHull(List<LatLng> points) {
  if (points.length < 3) {
    return List<LatLng>.from(points);
  }
  final unique = <String, LatLng>{};
  for (final p in points) {
    unique['${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}'] =
        p;
  }
  final sorted = unique.values.toList()
    ..sort((a, b) {
      if (a.longitude != b.longitude) {
        return a.longitude.compareTo(b.longitude);
      }
      return a.latitude.compareTo(b.latitude);
    });
  if (sorted.length < 3) {
    return sorted;
  }

  double cross(LatLng o, LatLng a, LatLng b) {
    return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);
  }

  final lower = <LatLng>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }

  final upper = <LatLng>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }

  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1),
  ];
}

/// 점 집합을 8 방향으로 [bufferDeg] 만큼 확장 후 convex hull. 사건이 적거나
/// 한 점에 모여 있어도 자연스러운 영역으로 보이도록 padding 추가.
/// bufferDeg 0.4 ≈ 약 40km (lat 32°N 기준).
List<LatLng> bufferedHull(List<LatLng> points, {double bufferDeg = 0.4}) {
  if (points.isEmpty) return const [];
  final expanded = <LatLng>[];
  for (final p in points) {
    expanded.add(LatLng(p.latitude + bufferDeg, p.longitude));
    expanded.add(LatLng(p.latitude - bufferDeg, p.longitude));
    expanded.add(LatLng(p.latitude, p.longitude + bufferDeg));
    expanded.add(LatLng(p.latitude, p.longitude - bufferDeg));
    final diag = bufferDeg * 0.7071;
    expanded.add(LatLng(p.latitude + diag, p.longitude + diag));
    expanded.add(LatLng(p.latitude + diag, p.longitude - diag));
    expanded.add(LatLng(p.latitude - diag, p.longitude + diag));
    expanded.add(LatLng(p.latitude - diag, p.longitude - diag));
  }
  return convexHull(expanded);
}
