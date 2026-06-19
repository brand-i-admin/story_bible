import 'package:latlong2/latlong.dart';

import 'bible_ref.dart';

/// 한 이야기(이벤트) 한 건. v2 위치 모델 — `landmarkId` 가 진실 소스이고,
/// `lat/lng/placeName` 은 events_ordered view 가 landmarks 와 JOIN 해서 derived
/// 로 노출하는 호환 필드. 클라이언트는 양쪽 다 사용 가능.
class StoryEvent {
  const StoryEvent({
    required this.id,
    required this.eraId,
    required this.title,
    required this.summary,
    this.backgroundContext,
    required this.storyScenes,
    this.sceneCaptions = const [],
    required this.sceneCharacters,
    required this.startYear,
    required this.endYear,
    required this.timePrecision,
    required this.storyIndex,
    this.unitCode = 'default',
    this.unitTitle = '전체 흐름',
    this.unitOrder = 1,
    required this.rankInEra,
    required this.globalRank,
    required this.landmarkId,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.characterCodes,
    required this.bibleRefs,
    this.sceneImagePaths = const [],
    this.landmarkKind,
    this.landmarkParentId,
  });

  factory StoryEvent.fromMap(Map<String, dynamic> row) {
    return StoryEvent(
      id: row['id'] as String,
      eraId: row['era_id'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String?,
      backgroundContext: row['background_context'] as String?,
      storyScenes: _stringList(row['story_scenes']),
      sceneCaptions: _stringList(row['scene_captions']),
      sceneCharacters: _stringListList(row['scene_characters']),
      startYear: row['start_year'] as int?,
      endYear: row['end_year'] as int?,
      timePrecision: (row['time_precision'] as String?) ?? 'approx',
      storyIndex: (row['story_index'] as num?)?.toInt() ?? 0,
      unitCode: (row['unit_code'] as String?)?.trim().isNotEmpty == true
          ? (row['unit_code'] as String).trim()
          : 'default',
      unitTitle: (row['unit_title'] as String?)?.trim().isNotEmpty == true
          ? (row['unit_title'] as String).trim()
          : '전체 흐름',
      unitOrder: (row['unit_order'] as num?)?.toInt() ?? 1,
      rankInEra: (row['rank_in_era'] as num?)?.toInt() ?? 0,
      globalRank: (row['global_rank'] as num?)?.toInt() ?? 0,
      landmarkId: row['landmark_id'] as String,
      placeName: row['place_name'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      characterCodes: _stringList(row['character_codes']),
      bibleRefs: BibleRef.fromList(row['bible_refs']),
      sceneImagePaths: _stringList(row['scene_image_paths']),
      landmarkKind: row['landmark_kind'] as String?,
      landmarkParentId: row['landmark_parent_id'] as String?,
    );
  }

  final String id;
  final String eraId;
  final String title;
  final String? summary;
  final String? backgroundContext;
  final List<String> storyScenes;
  final List<String> sceneCaptions;
  final List<List<String>> sceneCharacters;
  final int? startYear;
  final int? endYear;
  final String timePrecision;
  final int storyIndex;
  final String unitCode;
  final String unitTitle;
  final int unitOrder;
  final int rankInEra;
  final int globalRank;

  /// v2 위치 모델 — landmarks.id (region/anchor/minor) FK. 진실 소스.
  final String landmarkId;

  /// landmarks.name 의 derived. UI 표시용.
  final String? placeName;

  /// landmarks.lat/lng 의 derived. region 이면 anchor 좌표(라벨 위치).
  final double? lat;
  final double? lng;

  /// 'region' | 'point' (또는 v2 잔존 'anchor' | 'minor').
  final String? landmarkKind;
  final String? landmarkParentId;

  final List<String> characterCodes;
  final List<BibleRef> bibleRefs;

  final List<String> sceneImagePaths;

  String get shortSummary {
    final trimmed = summary?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return '요약 정보가 없습니다.';
  }

  String get detailText => shortSummary;

  String get backgroundText {
    final trimmed = backgroundContext?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return '이 이야기를 읽기 전, 앞뒤 흐름과 인물 관계를 떠올리면 본문을 더 쉽게 따라갈 수 있어요.';
  }

  bool get hasCoordinate => lat != null && lng != null;

  LatLng get latLng => LatLng(lat!, lng!);

  static List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item?.toString() ?? '').toList(growable: false);
    }
    return const <String>[];
  }

  static List<List<String>> _stringListList(dynamic raw) {
    if (raw is List) {
      return raw.map<List<String>>(_stringList).toList(growable: false);
    }
    return const <List<String>>[];
  }
}
