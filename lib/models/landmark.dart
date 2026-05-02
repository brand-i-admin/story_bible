import 'package:latlong2/latlong.dart';

/// 시대별로 지도 위에 표시되는 성경 랜드마크 (예루살렘 성전, 시내산, 떨기나무 등).
///
/// 사용자가 시대를 선택하면 [eraCodes] 배열에 해당 시대 코드를 가진 랜드마크만
/// 지도에 노출되어 시대별 무대 감각을 잡아 준다. 한 랜드마크가 여러 시대에 걸쳐
/// 의미를 가지면(예: 예루살렘 성전 = 왕정 + 포로/귀환 + 예수 사역) 배열에 여러
/// era code 를 둔다.
///
/// 시드 파이프라인: `assets/landmarks/landmarks.json` →
/// `tools/seed/build_landmarks_seed_sql.py` →
/// `supabase/200_stories/landmarks_seed.sql`.
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
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      displayPriority: (row['display_priority'] as num?)?.toInt() ?? 0,
      eraCodes: _stringList(row['era_codes']),
      relatedEventCodes: _stringList(row['related_event_codes']),
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

  /// 이 랜드마크가 노출되는 시대 코드 배열 (eras.code 기준).
  /// 비어 있으면 어떤 시대에서도 노출되지 않는다.
  final List<String> eraCodes;

  final List<String> relatedEventCodes;

  LatLng get latLng => LatLng(lat, lng);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.whereType<String>().toList(growable: false);
}
