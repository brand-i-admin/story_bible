import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../models/user_companion_diary_entry.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/daily_exploration_selection.dart';
import '../../utils/scene_asset_loader.dart';
import '../../utils/today_activity_summary.dart';
import '../map/story_event_marker_presentation.dart';
import '../profile/companion_diary_entry_card.dart';
import '../story_map_panel.dart';
import '../web_pointer_interceptor.dart';
import 'home_journey_overlay.dart';
import 'story_root_navigation_bar.dart';
import 'today_activity_header.dart';

class TodayHomePage extends StatefulWidget {
  const TodayHomePage({
    super.key,
    required this.mapKey,
    required this.mapController,
    required this.events,
    required this.recommendedEventId,
    required this.eras,
    required this.charactersByCode,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.isAuthenticated,
    required this.todayDiary,
    required this.diaryLoading,
    required this.diaryError,
    required this.bibleTargetLabel,
    required this.nickname,
    required this.activitySummary,
    required this.colorForCharacter,
    required this.onOpenStory,
    required this.onSaveDiary,
    required this.onDeleteDiary,
    required this.onContinueBibleReading,
    required this.onOpenProfile,
    required this.onOpenFontSettings,
    required this.onOpenThemeSettings,
    required this.onOpenSearch,
  });

  final Key mapKey;
  final StoryMapPanelController mapController;
  final List<StoryEvent> events;
  final String? recommendedEventId;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final bool isAuthenticated;
  final UserCompanionDiaryEntry? todayDiary;
  final bool diaryLoading;
  final String? diaryError;
  final String bibleTargetLabel;
  final String nickname;
  final TodayActivitySummary activitySummary;
  final Color Function(String characterCode) colorForCharacter;
  final ValueChanged<StoryEvent> onOpenStory;
  final CompanionDiarySaveCallback? onSaveDiary;
  final CompanionDiaryDeleteCallback? onDeleteDiary;
  final VoidCallback onContinueBibleReading;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFontSettings;
  final VoidCallback onOpenThemeSettings;
  final VoidCallback onOpenSearch;

  @override
  State<TodayHomePage> createState() => _TodayHomePageState();
}

class _TodayHomePageState extends State<TodayHomePage> {
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  String? _currentEventId;
  String? _currentThumbnailEventId;
  String? _currentThumbnailUrl;
  int _thumbnailRequest = 0;

  @override
  void initState() {
    super.initState();
    _currentEventId = widget.recommendedEventId;
    unawaited(_loadCurrentThumbnail(_currentEventId));
  }

  @override
  void didUpdateWidget(covariant TodayHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendedEventId != widget.recommendedEventId) {
      _currentEventId = widget.recommendedEventId;
      unawaited(_loadCurrentThumbnail(_currentEventId));
    } else if (_currentEventId == null ||
        widget.events.every((event) => event.id != _currentEventId)) {
      _currentEventId = widget.recommendedEventId;
      unawaited(_loadCurrentThumbnail(_currentEventId));
    }
  }

  void _selectCurrentEvent(String eventId) {
    if (_currentEventId == eventId) return;
    setState(() => _currentEventId = eventId);
    unawaited(_loadCurrentThumbnail(eventId));
  }

  Future<void> _loadCurrentThumbnail(String? eventId) async {
    final request = ++_thumbnailRequest;
    if (eventId == null) {
      if (mounted) {
        setState(() {
          _currentThumbnailEventId = null;
          _currentThumbnailUrl = null;
        });
      }
      return;
    }
    final event = widget.events.where((item) => item.id == eventId).firstOrNull;
    if (event == null) return;
    final imageUrl = await _sceneAssetLoader.loadThumbnailDataUrlForEvent(
      event,
    );
    if (!mounted || request != _thumbnailRequest) return;
    setState(() {
      _currentThumbnailEventId = eventId;
      _currentThumbnailUrl = imageUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mapSelection = explorationMapSelectionFor(
      events: widget.events,
      eras: widget.eras,
      currentEventId: _currentEventId ?? widget.recommendedEventId,
    );
    final currentEvent = mapSelection.position?.current;
    final currentEventId = currentEvent?.id;
    final thumbnailUrls = <String, String>{};
    if (_currentThumbnailEventId == currentEventId &&
        _currentThumbnailUrl != null &&
        currentEventId != null) {
      thumbnailUrls[currentEventId] = _currentThumbnailUrl!;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = media.textScaler.scale(1);
        final floatingOverlayExtent =
            304.0 + ((textScale - 1) * 185).clamp(0.0, 76.0);
        final topObscured =
            media.padding.top + TodayActivityHeader.mapObscuredExtent + 8;
        final bottomObscuredFraction = constraints.maxHeight <= 0
            ? 0.48
            : (floatingOverlayExtent / constraints.maxHeight).clamp(0.0, 0.68);
        return Stack(
          children: [
            Positioned.fill(
              child: StoryMapPanel(
                key: widget.mapKey,
                controller: widget.mapController,
                events: mapSelection.events,
                selectedEventId: currentEventId,
                onSelectEvent: _selectCurrentEvent,
                onCloseSelectedCallout: () {},
                onOpenDetail: (eventId) {
                  final event = widget.events
                      .where((entry) => entry.id == eventId)
                      .firstOrNull;
                  if (event != null) {
                    widget.onOpenStory(event);
                  }
                },
                colorForCharacter: widget.colorForCharacter,
                selectedCharacterCodes: const <String>{},
                eventEmotionMarks: widget.eventEmotionMarks,
                markerPresentation: StoryEventMarkerPresentation.dailyJourney(
                  roles: mapSelection.markerRoles,
                  thumbnailUrls: thumbnailUrls,
                ),
                mapGesturesEnabled: true,
                decorate: false,
                showSelectedCallout: false,
                animateReveal: false,
                fitEventIds: mapSelection.fitEventIds,
                fitAllZoomAdjust: 0.0,
                fitTightClusterMaxZoom: 9.0,
                showEventPath: true,
                topObscuredPixels: topObscured,
                bottomObscuredFraction: bottomObscuredFraction,
                showCharacterLegend: false,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: WebPointerInterceptor(
                child: TodayActivityHeader(
                  nickname: widget.nickname,
                  summary: widget.activitySummary,
                  actions: _TodayHeaderActions(
                    onOpenFontSettings: widget.onOpenFontSettings,
                    onOpenThemeSettings: widget.onOpenThemeSettings,
                    onOpenSearch: widget.onOpenSearch,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  widget.mapController.suppressMapTaps(
                    const Duration(milliseconds: 1200),
                  );
                  widget.mapController.suspendMapGestures();
                },
                onPointerMove: (_) {
                  widget.mapController.suppressMapTaps();
                  widget.mapController.suspendMapGestures();
                },
                onPointerUp: (_) {
                  widget.mapController.suppressMapTaps(
                    const Duration(milliseconds: 1200),
                  );
                  widget.mapController.clearMapGestureSuspension();
                },
                onPointerCancel: (_) {
                  widget.mapController.suppressMapTaps(
                    const Duration(milliseconds: 1200),
                  );
                  widget.mapController.clearMapGestureSuspension();
                },
                onPointerSignal: (_) => widget.mapController.suppressMapTaps(),
                child: WebPointerInterceptor(
                  child: HomeJourneyOverlay(
                    events: widget.events,
                    recommendedEventId: widget.recommendedEventId,
                    currentEventId: currentEventId,
                    eras: widget.eras,
                    charactersByCode: widget.charactersByCode,
                    eventEmotionMarks: widget.eventEmotionMarks,
                    quizAttemptSummaries: widget.quizAttemptSummaries,
                    isAuthenticated: widget.isAuthenticated,
                    todayDiary: widget.todayDiary,
                    diaryLoading: widget.diaryLoading,
                    diaryError: widget.diaryError,
                    bibleTargetLabel: widget.bibleTargetLabel,
                    todayStoryCompleted:
                        widget.activitySummary.explorationCount > 0,
                    bibleReadingCompleted:
                        widget.activitySummary.bibleChapterCount > 0,
                    onOpenStory: widget.onOpenStory,
                    onCurrentStoryChanged: (event) {
                      _selectCurrentEvent(event.id);
                    },
                    onSaveDiary: widget.onSaveDiary,
                    onDeleteDiary: widget.onDeleteDiary,
                    onContinueBibleReading: widget.onContinueBibleReading,
                    onOpenProfile: widget.onOpenProfile,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TodayHeaderActions extends StatelessWidget {
  const _TodayHeaderActions({
    required this.onOpenFontSettings,
    required this.onOpenThemeSettings,
    required this.onOpenSearch,
  });

  final VoidCallback onOpenFontSettings;
  final VoidCallback onOpenThemeSettings;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _TodayHeaderAction(
          label: '찾기',
          onTap: onOpenSearch,
          child: const Icon(
            Icons.search_rounded,
            size: _TodayHeaderAction.iconSize,
          ),
        ),
        const SizedBox(width: 6),
        _TodayHeaderAction(
          label: '큰글자',
          onTap: onOpenFontSettings,
          child: const Text('Aa'),
        ),
        const SizedBox(width: 6),
        _TodayHeaderAction(
          label: '테마',
          onTap: onOpenThemeSettings,
          child: const Icon(
            Icons.palette_outlined,
            size: _TodayHeaderAction.iconSize,
          ),
        ),
      ],
    );
  }
}

class _TodayHeaderAction extends StatelessWidget {
  const _TodayHeaderAction({
    required this.label,
    required this.onTap,
    required this.child,
  });

  static const double extent = 40;
  static const double iconSize = 17;

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final foreground = palette.primaryDeep;
    final navigationSurface = storyRootNavigationSurfaceColor(palette);
    final background = Color.alphaBlend(
      palette.primary.withValues(alpha: 0.10),
      navigationSurface,
    );
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: palette.primary.withValues(alpha: 0.20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: SizedBox(
          width: extent,
          height: extent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 18,
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(color: foreground, size: iconSize),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 9.2,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
