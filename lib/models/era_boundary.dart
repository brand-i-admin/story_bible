import 'package:flutter/painting.dart';

import 'package:latlong2/latlong.dart';

/// 시대(era)의 거친 지리 영역. 지도 위 반투명 폴리곤으로 그려져 사용자가
/// "이 시대의 이야기는 대략 이 영역에서 일어났다"는 지리적 감각을 잡게 한다.
///
/// 한 시대가 분리된 지역(예: 메소포타미아 + 가나안)을 포함하면 같은 era_id 로
/// 여러 행이 들어온다. 클라이언트는 era_id 로 필터해서 각 행을 별도 폴리곤으로
/// 렌더한다.
class EraBoundary {
  const EraBoundary({
    required this.id,
    required this.eraId,
    required this.polygonIndex,
    required this.polygon,
    required this.color,
    required this.fillOpacity,
    required this.displayOrder,
  });

  factory EraBoundary.fromMap(Map<String, dynamic> row) {
    return EraBoundary(
      id: row['id'] as String,
      eraId: row['era_id'] as String,
      polygonIndex: (row['polygon_index'] as num?)?.toInt() ?? 0,
      polygon: _parsePolygon(row['polygon']),
      color: _parseHexColor(row['color'] as String?),
      fillOpacity: (row['fill_opacity'] as num?)?.toDouble() ?? 0.18,
      displayOrder: (row['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String eraId;
  final int polygonIndex;

  /// 폴리곤 정점 좌표. 시계/반시계 방향 무관 (flutter_map 이 알아서 채움).
  final List<LatLng> polygon;

  /// 외곽선 + 채움 색.
  final Color color;

  /// 채움 알파 (0.0 ~ 1.0). 외곽선은 보통 1.0 으로 고정.
  final double fillOpacity;

  final int displayOrder;
}

List<LatLng> _parsePolygon(Object? raw) {
  if (raw is! List) {
    return const <LatLng>[];
  }
  final result = <LatLng>[];
  for (final pair in raw) {
    if (pair is! List || pair.length < 2) {
      continue;
    }
    final lat = pair[0];
    final lng = pair[1];
    if (lat is num && lng is num) {
      result.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
  }
  return result;
}

Color _parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) {
    return const Color(0xFFFF8800);
  }
  var s = hex.trim();
  if (s.startsWith('#')) {
    s = s.substring(1);
  }
  if (s.length == 6) {
    s = 'FF$s';
  }
  final value = int.tryParse(s, radix: 16);
  if (value == null) {
    return const Color(0xFFFF8800);
  }
  return Color(value);
}
