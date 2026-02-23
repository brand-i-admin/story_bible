import 'package:latlong2/latlong.dart';

class StoryEvent {
  const StoryEvent({
    required this.id,
    required this.code,
    required this.eraId,
    required this.title,
    required this.summary,
    required this.story,
    required this.shortStory,
    required this.shortText,
    required this.startYear,
    required this.endYear,
    required this.timeSortKey,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.searchText,
    required this.personIds,
    required this.bibleRefs,
  });

  final String id;
  final String code;
  final String eraId;
  final String title;
  final String? summary;
  final String? story;
  final String? shortStory;
  final String? shortText;
  final int? startYear;
  final int? endYear;
  final int timeSortKey;
  final String? placeName;
  final double? lat;
  final double? lng;
  final String? searchText;
  final List<String> personIds;
  final List<String> bibleRefs;

  String get shortSummary =>
      (shortStory ?? shortText ?? story ?? summary)?.trim().isNotEmpty == true
          ? (shortStory ?? shortText ?? story ?? summary)!
          : (summary ?? '요약 정보가 없습니다.');

  String get detailText =>
      (shortStory ?? story ?? summary ?? '').trim().isNotEmpty == true
          ? (shortStory ?? story ?? summary)!
          : '요약 정보가 없습니다.';

  bool get hasCoordinate => lat != null && lng != null;

  LatLng get latLng => LatLng(lat!, lng!);
}
