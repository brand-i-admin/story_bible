import 'package:latlong2/latlong.dart';

import 'bible_ref.dart';

/// 한 이야기(이벤트) 한 건. `events_ordered` view 결과를 그대로 매핑한다.
///
/// 정렬 컬럼은 두 가지: era 내부에서는 [rankInEra], 전체 타임라인에서는
/// [globalRank]. 수동으로 부여하는 [storyIndex]는 era 내 unique 정수이며
/// 새 이야기를 끼워 넣을 때 RPC가 시프트해 준다.
class StoryEvent {
  const StoryEvent({
    required this.id,
    required this.eraId,
    required this.title,
    required this.summary,
    required this.storyScenes,
    required this.scenePersons,
    required this.startYear,
    required this.endYear,
    required this.timePrecision,
    required this.storyIndex,
    required this.rankInEra,
    required this.globalRank,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.personCodes,
    required this.bibleRefs,
  });

  factory StoryEvent.fromMap(Map<String, dynamic> row) {
    return StoryEvent(
      id: row['id'] as String,
      eraId: row['era_id'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String?,
      storyScenes: _stringList(row['story_scenes']),
      scenePersons: _stringListList(row['scene_persons']),
      startYear: row['start_year'] as int?,
      endYear: row['end_year'] as int?,
      timePrecision: (row['time_precision'] as String?) ?? 'approx',
      storyIndex: (row['story_index'] as num?)?.toInt() ?? 0,
      rankInEra: (row['rank_in_era'] as num?)?.toInt() ?? 0,
      globalRank: (row['global_rank'] as num?)?.toInt() ?? 0,
      placeName: row['place_name'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      personCodes: _stringList(row['person_codes']),
      bibleRefs: BibleRef.fromList(row['bible_refs']),
    );
  }

  final String id;
  final String eraId;
  final String title;
  final String? summary;
  final List<String> storyScenes;
  final List<List<String>> scenePersons;
  final int? startYear;
  final int? endYear;
  final String timePrecision;
  final int storyIndex;
  final int rankInEra;
  final int globalRank;
  final String? placeName;
  final double? lat;
  final double? lng;
  final List<String> personCodes;
  final List<BibleRef> bibleRefs;

  String get shortSummary {
    final trimmed = summary?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return '요약 정보가 없습니다.';
  }

  String get detailText => shortSummary;

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
