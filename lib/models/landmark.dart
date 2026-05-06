import 'package:latlong2/latlong.dart';

/// 위치 모델 v3 — 단일 [Landmark] 모델로 region 폴리곤 + 점 마커를 모두 표현.
///
/// - **region**: kind='region'. polygon 으로 영역 표시. parentLandmarkId 없음.
///   anchor_lat/lng = lat/lng 은 region 라벨 위치(중심 근사).
/// - **point** (kind != 'region'): mountain / city / sea / river / island /
///   palace / wilderness / holy_site / campsite 등. lat/lng 정확한 좌표.
///   parentLandmarkId = 자기가 속한 region 의 id.
///
/// alias_group 기능은 v3 에서 제거. 같은 좌표를 시대마다 다른 이름으로 부르는
/// 케이스는 별개 landmark 두 개의 era_codes 로 자연 분리한다.
class Landmark {
  const Landmark({
    required this.id,
    required this.code,
    required this.name,
    required this.emoji,
    required this.lat,
    required this.lng,
    required this.displayPriority,
    required this.eraCodes,
    required this.relatedEventCodes,
    required this.kind,
    this.polygon = const [],
    this.parentLandmarkId,
    this.description,
    this.category,
  });

  factory Landmark.fromMap(Map<String, dynamic> row) {
    return Landmark(
      id: row['id'] as String,
      code: row['code'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      emoji: (row['emoji'] as String?) ?? '📍',
      category: row['category'] as String?,
      // v3 — lat/lng nullable (비지리적 region). null 이면 0 으로 폴백.
      lat: (row['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (row['lng'] as num?)?.toDouble() ?? 0.0,
      displayPriority: (row['display_priority'] as num?)?.toInt() ?? 0,
      eraCodes: _stringList(row['era_codes']),
      relatedEventCodes: _stringList(row['related_event_codes']),
      kind: (row['kind'] as String?) ?? 'point',
      polygon: _parsePolygon(row['polygon']),
      parentLandmarkId: row['parent_landmark_id'] as String?,
    );
  }

  final String id;
  final String code;
  final String name;
  final String? description;
  final String emoji;
  final String? category;
  final double lat;
  final double lng;
  final int displayPriority;

  /// 'region' | 'point' (또는 v2 잔존: 'anchor' | 'minor').
  final String kind;

  /// kind='region' 일 때만 채워짐. 폴리곤 정점 [lat, lng] 시퀀스.
  final List<LatLng> polygon;

  /// non-region 마커 → 자기가 속한 region 의 landmark id. region 자체는 null.
  final String? parentLandmarkId;

  final List<String> eraCodes;
  final List<String> relatedEventCodes;

  bool get isRegion => kind == 'region';
  bool get isAnchor => kind == 'anchor'; // v2 호환 — v3 에서는 'point' 권장
  bool get isMinor => kind == 'minor'; // v2 호환

  LatLng get latLng => LatLng(lat, lng);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.whereType<String>().toList(growable: false);
}

List<LatLng> _parsePolygon(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final result = <LatLng>[];
  for (final pair in raw) {
    if (pair is! List || pair.length < 2) continue;
    final lat = pair[0];
    final lng = pair[1];
    if (lat is num && lng is num) {
      result.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
  }
  return result;
}
