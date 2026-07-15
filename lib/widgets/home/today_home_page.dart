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
import '../map/story_event_marker_presentation.dart';
import '../profile/companion_diary_entry_card.dart';
import '../story_bottom_panel_style.dart';
import '../story_map_panel.dart';
import '../v2/map_hint_overlay.dart';
import '../web_pointer_interceptor.dart';
import 'home_journey_overlay.dart';

class TodayHomePageController {
  _TodayHomePageState? _state;

  void showWelcomeGuide() => _state?._showWelcomeGuideAgain();

  void _bind(_TodayHomePageState state) => _state = state;

  void _unbind(_TodayHomePageState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

class TodayHomePage extends StatefulWidget {
  const TodayHomePage({
    super.key,
    this.controller,
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
    required this.todayStoryCompleted,
    required this.bibleReadingCompleted,
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

  final TodayHomePageController? controller;
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
  final bool todayStoryCompleted;
  final bool bibleReadingCompleted;
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
  static const double _todayPanelCollapsedHeight = 64;
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  String? _currentEventId;
  String? _currentThumbnailEventId;
  String? _currentThumbnailUrl;
  int _thumbnailRequest = 0;
  bool _panelExpanded = true;
  bool _showWelcomeGuide = true;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _currentEventId = widget.recommendedEventId;
    unawaited(_loadCurrentThumbnail(_currentEventId));
  }

  @override
  void didUpdateWidget(covariant TodayHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind(this);
      widget.controller?._bind(this);
    }
    if (oldWidget.recommendedEventId != widget.recommendedEventId) {
      _currentEventId = widget.recommendedEventId;
      unawaited(_loadCurrentThumbnail(_currentEventId));
    } else if (_currentEventId == null ||
        widget.events.every((event) => event.id != _currentEventId)) {
      _currentEventId = widget.recommendedEventId;
      unawaited(_loadCurrentThumbnail(_currentEventId));
    }
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    super.dispose();
  }

  void _selectCurrentEvent(String eventId) {
    if (_currentEventId == eventId) return;
    setState(() => _currentEventId = eventId);
    unawaited(_loadCurrentThumbnail(eventId));
  }

  void _togglePanel() {
    setState(() => _panelExpanded = !_panelExpanded);
  }

  void _dismissWelcomeGuide() {
    if (!_showWelcomeGuide) return;
    setState(() => _showWelcomeGuide = false);
  }

  void _showWelcomeGuideAgain() {
    if (_showWelcomeGuide || !mounted) return;
    setState(() => _showWelcomeGuide = true);
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
        final overlayHeight = (constraints.maxHeight * 0.48)
            .clamp(330.0, 445.0)
            .toDouble();
        final panelHeight = _panelExpanded
            ? overlayHeight
            : _todayPanelCollapsedHeight;
        final topObscured = media.padding.top + _TodayHeaderAction.extent + 14;
        final bottomObscuredFraction = constraints.maxHeight <= 0
            ? 0.48
            : (panelHeight / constraints.maxHeight).clamp(0.0, 0.75);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _dismissWelcomeGuide(),
          child: Stack(
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
              if (_showWelcomeGuide)
                Positioned(
                  top: media.padding.top + _TodayHeaderAction.extent + 14,
                  left: 0,
                  right: 0,
                  bottom: panelHeight + 18,
                  child: const IgnorePointer(
                    child: MapHintOverlay(
                      message:
                          '환영합니다! 매일 3가지로 주님과 동행해요!\n'
                          '① 이야기 탐험\n'
                          '(최근 감정을 새긴 다음 이야기가 추천되요)\n'
                          '② 신앙 다이어리\n'
                          '③ 통독\n'
                          "(기록은 '내정보'에 쌓여요)",
                      avatarSize: 58,
                    ),
                  ),
                ),
              Positioned(
                top: media.padding.top + 8,
                left: 12,
                right: 12,
                child: WebPointerInterceptor(
                  child: _TodayHeaderActions(
                    onOpenFontSettings: widget.onOpenFontSettings,
                    onOpenThemeSettings: widget.onOpenThemeSettings,
                    onOpenSearch: widget.onOpenSearch,
                  ),
                ),
              ),
              Positioned(
                left: storyBottomPanelHorizontalMargin(constraints.maxWidth),
                right: storyBottomPanelHorizontalMargin(constraints.maxWidth),
                bottom: 0,
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
                  onPointerSignal: (_) =>
                      widget.mapController.suppressMapTaps(),
                  child: WebPointerInterceptor(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: panelHeight,
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
                        todayStoryCompleted: widget.todayStoryCompleted,
                        bibleReadingCompleted: widget.bibleReadingCompleted,
                        panelExpanded: _panelExpanded,
                        onTogglePanel: _togglePanel,
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
              ),
            ],
          ),
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
            color: Colors.white,
            size: _TodayHeaderAction.iconSize,
          ),
        ),
        const SizedBox(width: 6),
        _TodayHeaderAction(
          label: '큰글자',
          onTap: onOpenFontSettings,
          child: const Text('Aa', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 6),
        _TodayHeaderAction(
          label: '테마',
          onTap: onOpenThemeSettings,
          child: const Icon(
            Icons.palette_outlined,
            color: Colors.white,
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

  static const double extent = 48;
  static const double iconSize = 20;

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: palette.primaryDeep.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: SizedBox(
          width: extent,
          height: extent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 21,
                child: Center(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                    child: child,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
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
