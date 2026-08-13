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
import '../v2/map_hint_overlay.dart';
import '../web_pointer_interceptor.dart';
import 'home_journey_overlay.dart';
import 'story_root_navigation_bar.dart';
import 'today_activity_header.dart';

/// 오늘 가이드가 헤더 하단과 현재 이야기의 시대 라벨 상단 사이를
/// 정확히 채우도록 화면 상단·하단 여백을 계산한다.
EdgeInsets todayGuideInsets({
  required double surfaceHeight,
  required double headerBottom,
  required double eraLabelTop,
}) {
  if (!surfaceHeight.isFinite ||
      !headerBottom.isFinite ||
      !eraLabelTop.isFinite ||
      surfaceHeight <= 0) {
    return EdgeInsets.zero;
  }
  final top = headerBottom.clamp(0.0, surfaceHeight).toDouble();
  final bottomEdge = eraLabelTop.clamp(top, surfaceHeight).toDouble();
  return EdgeInsets.only(top: top, bottom: surfaceHeight - bottomEdge);
}

class TodayTodoGuide extends StatelessWidget {
  const TodayTodoGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final isDark = palette == AppColorPalette.blackMap;
    final outerBackground = Color.alphaBlend(
      palette.characterAccent.withValues(alpha: 0.28),
      palette.utilityBackground,
    ).withValues(alpha: 0.68);
    final contentBackground = isDark
        ? Color.alphaBlend(
            palette.primary.withValues(alpha: 0.06),
            palette.cardSurface,
          ).withValues(alpha: 0.88)
        : Color.alphaBlend(
            palette.currentAccent.withValues(alpha: 0.035),
            AppColors.parchmentLight,
          ).withValues(alpha: 0.84);
    final guideTextColor = palette.primaryDeep;
    final stepAccentColor = palette.currentAccentDeep;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - AppSpacing.x10)
                  .clamp(1.0, 410.0)
                  .toDouble()
            : 410.0;
        return Center(
          child: FittedBox(
            key: const ValueKey('today-todo-guide-scale-to-fit'),
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: contentWidth,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: -MapHintDismissBadge.overlapTop,
                    ),
                    child: Container(
                      key: const ValueKey('today-todo-guide'),
                      padding: const EdgeInsets.all(AppSpacing.x4),
                      decoration: BoxDecoration(
                        color: outerBackground,
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        border: Border.all(
                          color: palette.utilityBorder.withValues(alpha: 0.42),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryDeep.withValues(alpha: 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Container(
                        key: const ValueKey('today-todo-guide-content'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x7,
                          vertical: AppSpacing.x5,
                        ),
                        decoration: BoxDecoration(
                          color: contentBackground,
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                          border: Border.all(
                            color: palette.currentAccent.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TodayGuideStep(
                              number: 1,
                              message: '아래 이야기 카드를 좌우 넘기기 혹은 클릭',
                              accentColor: stepAccentColor,
                              textColor: guideTextColor,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _TodayGuideStep(
                              number: 2,
                              message: "화면 위 '여정 선택'에서 나열될 이야기 카드 변경",
                              accentColor: stepAccentColor,
                              textColor: guideTextColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    child: MapHintDismissBadge(
                      badgeKey: ValueKey('today-guide-dismiss-badge'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TodayGuideStep extends StatelessWidget {
  const _TodayGuideStep({
    required this.number,
    required this.message,
    required this.accentColor,
    required this.textColor,
  });

  final int number;
  final String message;
  final Color accentColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '$number단계',
          child: ExcludeSemantics(
            child: Container(
              key: ValueKey('today-guide-step-$number-badge'),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 1.5),
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  color: accentColor,
                  fontSize: MapHintDismissBadge.messageFontSize,
                  fontWeight: MapHintDismissBadge.messageFontWeight,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Flexible(
          child: Text(
            message,
            key: ValueKey('today-guide-step-$number-message'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: textColor,
              fontSize: MapHintDismissBadge.messageFontSize,
              fontWeight: FontWeight.w700,
              height: MapHintDismissBadge.messageLineHeight,
            ),
          ),
        ),
      ],
    );
  }
}

class TodayHomePage extends StatefulWidget {
  const TodayHomePage({
    super.key,
    required this.mapKey,
    required this.mapController,
    required this.mapGesturesEnabled,
    required this.events,
    this.journeyLoading = false,
    required this.recommendedEventId,
    this.currentEventOverrideId,
    required this.eras,
    required this.charactersByCode,
    required this.journeySelectionLabel,
    required this.journeyBoundaryLabel,
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
    required this.onOpenJourneySelection,
    required this.onOpenFontSettings,
    required this.onOpenThemeSettings,
    required this.onOpenSearch,
  });

  final Key mapKey;
  final StoryMapPanelController mapController;
  final bool mapGesturesEnabled;
  final List<StoryEvent> events;
  final bool journeyLoading;
  final String? recommendedEventId;
  final String? currentEventOverrideId;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final String journeySelectionLabel;
  final String journeyBoundaryLabel;
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
  final VoidCallback onOpenJourneySelection;
  final VoidCallback onOpenFontSettings;
  final VoidCallback onOpenThemeSettings;
  final VoidCallback onOpenSearch;

  @override
  State<TodayHomePage> createState() => _TodayHomePageState();
}

class _TodayHomePageState extends State<TodayHomePage> {
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'today-stack');
  final GlobalKey _headerAnchorKey = GlobalKey(
    debugLabel: 'today-header-anchor',
  );
  final GlobalKey _journeyAnchorKey = GlobalKey(
    debugLabel: 'today-journey-anchor',
  );
  final GlobalKey _journeySelectionAnchorKey = GlobalKey(
    debugLabel: 'today-journey-selection-anchor',
  );
  final GlobalKey _eraDividerAnchorKey = GlobalKey(
    debugLabel: 'today-era-divider-anchor',
  );
  String? _currentEventId;
  String? _currentThumbnailEventId;
  String? _currentThumbnailUrl;
  int _thumbnailRequest = 0;
  bool _todayGuideDismissed = false;
  double? _renderedHeaderBottom;
  double? _renderedEraLabelTop;

  @override
  void initState() {
    super.initState();
    _currentEventId = widget.recommendedEventId;
    unawaited(
      _loadCurrentThumbnail(widget.currentEventOverrideId ?? _currentEventId),
    );
  }

  @override
  void didUpdateWidget(covariant TodayHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAuthenticated && !widget.isAuthenticated) {
      _todayGuideDismissed = false;
    }
    if (!oldWidget.mapGesturesEnabled && widget.mapGesturesEnabled) {
      _todayGuideDismissed = false;
    }
    var selectionChanged = false;
    if (oldWidget.recommendedEventId != widget.recommendedEventId) {
      _currentEventId = widget.recommendedEventId;
      selectionChanged = true;
    } else if (_currentEventId == null ||
        widget.events.every((event) => event.id != _currentEventId)) {
      _currentEventId = widget.recommendedEventId;
      selectionChanged = true;
    }
    if (selectionChanged ||
        oldWidget.currentEventOverrideId != widget.currentEventOverrideId) {
      unawaited(
        _loadCurrentThumbnail(widget.currentEventOverrideId ?? _currentEventId),
      );
    }
  }

  void _selectCurrentEvent(String eventId) {
    if (_currentEventId == eventId) return;
    setState(() => _currentEventId = eventId);
    unawaited(_loadCurrentThumbnail(eventId));
  }

  void _dismissTodayGuide() {
    if (_todayGuideDismissed) return;
    widget.mapController.suppressMapTaps(const Duration(milliseconds: 650));
    setState(() => _todayGuideDismissed = true);
  }

  void _scheduleGuideAnchorMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _todayGuideDismissed) return;
      final stackBox = _stackKey.currentContext?.findRenderObject();
      final headerBox = _journeySelectionAnchorKey.currentContext
          ?.findRenderObject();
      final eraDividerBox = _eraDividerAnchorKey.currentContext
          ?.findRenderObject();
      final journeyBox = _journeyAnchorKey.currentContext?.findRenderObject();
      if (stackBox is! RenderBox ||
          headerBox is! RenderBox ||
          !stackBox.hasSize ||
          !headerBox.hasSize) {
        return;
      }
      final lowerAnchorBox = eraDividerBox is RenderBox
          ? eraDividerBox
          : journeyBox is RenderBox
          ? journeyBox
          : null;
      if (lowerAnchorBox == null || !lowerAnchorBox.hasSize) return;

      final headerBottom = headerBox
          .localToGlobal(Offset(0, headerBox.size.height), ancestor: stackBox)
          .dy;
      final eraLabelTop = lowerAnchorBox
          .localToGlobal(Offset.zero, ancestor: stackBox)
          .dy;
      if (eraLabelTop < headerBottom) return;
      final unchanged =
          (_renderedHeaderBottom == null ||
              (_renderedHeaderBottom! - headerBottom).abs() < 0.5) &&
          (_renderedEraLabelTop == null ||
              (_renderedEraLabelTop! - eraLabelTop).abs() < 0.5);
      if (unchanged &&
          _renderedHeaderBottom != null &&
          _renderedEraLabelTop != null) {
        return;
      }
      setState(() {
        _renderedHeaderBottom = headerBottom;
        _renderedEraLabelTop = eraLabelTop;
      });
    });
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
      currentEventId:
          widget.currentEventOverrideId ??
          _currentEventId ??
          widget.recommendedEventId,
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
            296.0 + ((textScale - 1) * 150).clamp(0.0, 60.0);
        final topObscured =
            media.padding.top + TodayActivityHeader.mapObscuredExtent + 78;
        final bottomObscuredFraction = constraints.maxHeight <= 0
            ? 0.48
            : (floatingOverlayExtent / constraints.maxHeight).clamp(0.0, 0.68);
        if (!widget.isAuthenticated && !_todayGuideDismissed) {
          _scheduleGuideAnchorMeasurement();
        }
        final fallbackEraLabelTop =
            (constraints.maxHeight - floatingOverlayExtent - 12)
                .clamp(topObscured, constraints.maxHeight)
                .toDouble();
        final guideInsets = todayGuideInsets(
          surfaceHeight: constraints.maxHeight,
          headerBottom: _renderedHeaderBottom ?? topObscured,
          eraLabelTop: _renderedEraLabelTop ?? fallbackEraLabelTop,
        );
        return Stack(
          key: _stackKey,
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
                  orderNumberByEventId: mapSelection.orderNumberByEventId,
                ),
                mapGesturesEnabled: widget.mapGesturesEnabled,
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
              child: Listener(
                key: const ValueKey('today-header-map-input-blocker'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  widget.mapController.suppressMapTaps(
                    const Duration(milliseconds: 1200),
                  );
                  widget.mapController.suspendMapGestures(
                    const Duration(milliseconds: 1200),
                  );
                },
                onPointerMove: (_) {
                  widget.mapController.suppressMapTaps();
                  widget.mapController.suspendMapGestures(
                    const Duration(milliseconds: 1200),
                  );
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
                onPointerSignal: (_) {
                  widget.mapController.suppressMapTaps(
                    const Duration(milliseconds: 1200),
                  );
                  widget.mapController.suspendMapGestures(
                    const Duration(milliseconds: 1200),
                  );
                },
                child: WebPointerInterceptor(
                  child: TodayActivityHeader(
                    key: _headerAnchorKey,
                    nickname: widget.nickname,
                    actions: _TodayHeaderActions(
                      onOpenFontSettings: widget.onOpenFontSettings,
                      onOpenThemeSettings: widget.onOpenThemeSettings,
                      onOpenSearch: widget.onOpenSearch,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top:
                  media.padding.top + TodayActivityHeader.mapObscuredExtent + 6,
              left: AppSpacing.x5,
              right: AppSpacing.x5,
              child: WebPointerInterceptor(
                child: TodayJourneySelectionBar(
                  key: _journeySelectionAnchorKey,
                  currentLabel: widget.journeySelectionLabel,
                  completedCount: widget.events
                      .where(
                        (event) =>
                            widget.eventEmotionMarks.containsKey(event.id),
                      )
                      .length,
                  totalCount: widget.events.length,
                  loading: widget.journeyLoading,
                  onTap: widget.onOpenJourneySelection,
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
                    key: _journeyAnchorKey,
                    currentEraDividerAnchorKey: _eraDividerAnchorKey,
                    events: widget.events,
                    loading: widget.journeyLoading,
                    recommendedEventId: widget.recommendedEventId,
                    currentEventId: currentEventId,
                    eras: widget.eras,
                    charactersByCode: widget.charactersByCode,
                    journeyBoundaryLabel: widget.journeyBoundaryLabel,
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
            if (!widget.isAuthenticated && !_todayGuideDismissed)
              Positioned.fill(
                child: WebPointerInterceptor(
                  child: Listener(
                    key: const ValueKey('today-guide-dismiss-layer'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _dismissTodayGuide(),
                    child: Padding(
                      padding: guideInsets,
                      child: const TodayTodoGuide(),
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

class TodayJourneySelectionBar extends StatelessWidget {
  const TodayJourneySelectionBar({
    super.key,
    required this.currentLabel,
    required this.completedCount,
    required this.totalCount,
    this.loading = false,
    required this.onTap,
  });

  final String currentLabel;
  final int completedCount;
  final int totalCount;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final safeTotal = totalCount < 0 ? 0 : totalCount;
    final safeCompleted = completedCount.clamp(0, safeTotal).toInt();
    final progress = safeTotal == 0 ? 0.0 : safeCompleted / safeTotal;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const ValueKey('today-open-journey-selection'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          key: const ValueKey('today-journey-selection-surface'),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(
            10,
            AppSpacing.x1,
            9,
            AppSpacing.x1,
          ),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              palette.currentAccent.withValues(alpha: 0.055),
              palette.cardSurface,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.currentAccent.withValues(alpha: 0.36),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.primaryDeep.withValues(alpha: 0.13),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                key: const ValueKey('today-journey-selection-leading-icon'),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.currentAccent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.route_rounded,
                  size: 18,
                  color: palette.currentAccentDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '여정 선택',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: AppFontSizes.base,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x2),
                        Text(
                          '·',
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: AppFontSizes.base,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x2),
                        Flexible(
                          child: Text(
                            currentLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.currentAccentDeep,
                              fontSize: AppFontSizes.xs,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _TodayJourneyProgressIndicator(
                      palette: palette,
                      progress: progress,
                      completedCount: safeCompleted,
                      totalCount: safeTotal,
                      loading: loading,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Semantics(
                button: true,
                label: '여정 선택 화면 열기',
                child: Container(
                  key: const ValueKey('today-journey-selection-arrow'),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.cardSurface.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.currentAccent.withValues(alpha: 0.32),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: palette.currentAccentDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayJourneyProgressIndicator extends StatelessWidget {
  const _TodayJourneyProgressIndicator({
    required this.palette,
    required this.progress,
    required this.completedCount,
    required this.totalCount,
    required this.loading,
  });

  static const _height = 14.0;
  static const _trackHeight = 14.0;
  static const _flameExtent = 13.0;

  final AppColorPalette palette;
  final double progress;
  final int completedCount;
  final int totalCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final flameLeft =
              (constraints.maxWidth - _flameExtent) * progress.clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _trackHeight,
                child: Container(
                  key: const ValueKey('today-journey-selection-progress-track'),
                  decoration: BoxDecoration(
                    color: palette.currentFill,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(
                      color: palette.currentAccentDeep.withValues(alpha: 0.48),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      LinearProgressIndicator(
                        key: const ValueKey('today-journey-selection-progress'),
                        value: loading ? null : progress,
                        minHeight: _trackHeight,
                        backgroundColor: Colors.transparent,
                        color: palette.currentAccentDeep,
                      ),
                      Center(
                        child: Text(
                          loading ? '불러오는 중' : '$completedCount/$totalCount',
                          key: const ValueKey('today-journey-selection-count'),
                          maxLines: 1,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: progress >= 0.5
                                ? AppColors.fgOnDark
                                : palette.currentAccentDeep,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            shadows: [
                              Shadow(
                                color: progress >= 0.5
                                    ? Colors.black38
                                    : palette.cardSurface,
                                blurRadius: 1.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!loading)
                Positioned(
                  left: flameLeft,
                  top: (_trackHeight - _flameExtent) / 2,
                  width: _flameExtent,
                  height: _flameExtent,
                  child: Semantics(
                    label: '현재 여정 진행 위치',
                    excludeSemantics: true,
                    child: const SizedBox(
                      key: ValueKey('today-journey-selection-progress-flame'),
                      width: _flameExtent,
                      height: _flameExtent,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(
                          '🔥',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(fontSize: 14, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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
