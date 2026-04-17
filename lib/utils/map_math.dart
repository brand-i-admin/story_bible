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
