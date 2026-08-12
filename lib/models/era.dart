class Era {
  const Era({
    required this.id,
    required this.code,
    required this.testament,
    required this.name,
    required this.displayOrder,
    required this.startYear,
    required this.endYear,
    required this.mapCenterLat,
    required this.mapCenterLng,
    required this.mapZoom,
  });

  final String id;
  final String code;
  final String testament;
  final String name;
  final int displayOrder;
  final int? startYear;
  final int? endYear;
  final double? mapCenterLat;
  final double? mapCenterLng;
  final double? mapZoom;

  factory Era.fromMap(Map<String, dynamic> map) {
    return Era(
      id: map['id'] as String,
      code: map['code'] as String,
      testament: (map['testament'] as String?) ?? 'old',
      name: map['name'] as String,
      displayOrder: map['display_order'] as int,
      startYear: map['start_year'] as int?,
      endYear: map['end_year'] as int?,
      mapCenterLat: (map['map_center_lat'] as num?)?.toDouble(),
      mapCenterLng: (map['map_center_lng'] as num?)?.toDouble(),
      mapZoom: (map['map_zoom'] as num?)?.toDouble(),
    );
  }
}

/// 아직 공개하지 않는 마지막 시대는 DB 상태와 별개로 앱에서도 방어적으로 숨긴다.
const hiddenEraCodes = <String>{'era_nt_consummation'};

bool isHiddenEraCode(String code) => hiddenEraCodes.contains(code);
