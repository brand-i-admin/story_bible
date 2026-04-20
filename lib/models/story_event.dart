import 'package:latlong2/latlong.dart';

class StoryEvent {
  const StoryEvent({
    required this.id,
    required this.code,
    required this.displayNumber,
    required this.eraId,
    required this.title,
    required this.summary,
    required this.story,
    required this.shortStory,
    required this.storyScenes,
    required this.timelineRank,
    required this.startYear,
    required this.endYear,
    required this.timeSortKey,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.personIds,
    required this.bibleRefs,
    required this.thumbUrl,
    required this.storyAssetDir,
    required this.storyThumbnailDir,
    required this.storySceneCount,
  });

  final String id;
  final String code;
  final String? displayNumber;
  final String eraId;
  final String title;
  final String? summary;
  final String? story;
  final String? shortStory;
  final String? storyScenes;
  final double timelineRank;
  final int? startYear;
  final int? endYear;
  final int timeSortKey;
  final String? placeName;
  final double? lat;
  final double? lng;
  final List<String> personIds;
  final List<String> bibleRefs;
  final String? thumbUrl;
  final String? storyAssetDir;
  final String? storyThumbnailDir;
  final int storySceneCount;

  String get shortSummary =>
      (shortStory ?? story ?? summary)?.trim().isNotEmpty == true
      ? (shortStory ?? story ?? summary)!
      : (summary ?? '요약 정보가 없습니다.');

  String get detailText =>
      (shortStory ?? story ?? summary ?? '').trim().isNotEmpty == true
      ? (shortStory ?? story ?? summary)!
      : '요약 정보가 없습니다.';

  bool get hasCoordinate => lat != null && lng != null;

  LatLng get latLng => LatLng(lat!, lng!);

  int compareTimelineTo(StoryEvent other) {
    final byRank = timelineRank.compareTo(other.timelineRank);
    if (byRank != 0) {
      return byRank;
    }
    final byTimeSortKey = timeSortKey.compareTo(other.timeSortKey);
    if (byTimeSortKey != 0) {
      return byTimeSortKey;
    }
    return id.compareTo(other.id);
  }
}
