enum StoryEventMarkerPresentationMode { mapTimeline, dailyJourney }

/// 같은 사건 핀 렌더러에 화면별 표현 차이만 전달하는 불변 설정.
///
/// `mapTimeline`은 감정을 주 표식으로 두고 이야기 번호를 작은 배지로 보이며,
/// `dailyJourney`는 이전·현재·다음 역할과 현재 썸네일을 더하고 감정은 보조
/// 배지로 표시한다.
class StoryEventMarkerPresentation {
  const StoryEventMarkerPresentation.mapTimeline()
    : mode = StoryEventMarkerPresentationMode.mapTimeline,
      roles = const {},
      thumbnailUrls = const {};

  const StoryEventMarkerPresentation.dailyJourney({
    required this.roles,
    this.thumbnailUrls = const {},
  }) : mode = StoryEventMarkerPresentationMode.dailyJourney;

  final StoryEventMarkerPresentationMode mode;
  final Map<String, String> roles;
  final Map<String, String> thumbnailUrls;

  bool get isDailyJourney =>
      mode == StoryEventMarkerPresentationMode.dailyJourney;

  String roleFor(String eventId) => roles[eventId] ?? '';

  String thumbnailUrlFor(String eventId) => thumbnailUrls[eventId] ?? '';
}
