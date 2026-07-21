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
    final primaryTextColor = isDark ? palette.text : AppColors.ink900;
    final secondaryTextColor = isDark ? palette.mutedText : AppColors.ink500;
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
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    TodayActivityIcons.streak,
                                    size: 15,
                                    color: palette.currentAccentDeep,
                                  ),
                                  const SizedBox(width: AppSpacing.x2),
                                  Text(
                                    '매일 할 일:',
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: primaryTextColor,
                                      fontSize: 13.2,
                                      fontWeight: FontWeight.w900,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.x4),
                                  _TodayTodoItem(
                                    icon: TodayActivityIcons.story,
                                    label: '이야기',
                                    color: palette.regionAccent,
                                  ),
                                  _TodayTodoSeparator(
                                    color: secondaryTextColor,
                                  ),
                                  _TodayTodoItem(
                                    icon: TodayActivityIcons.diary,
                                    label: '다이어리',
                                    color: palette.successBottom,
                                  ),
                                  _TodayTodoSeparator(
                                    color: secondaryTextColor,
                                  ),
                                  _TodayTodoItem(
                                    icon: TodayActivityIcons.bible,
                                    label: '통독',
                                    color: palette.primary,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)',
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
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

class _TodayTodoItem extends StatelessWidget {
  const _TodayTodoItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: AppSpacing.x1),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 12.8,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _TodayTodoSeparator extends StatelessWidget {
  const _TodayTodoSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      ', ',
      style: TextStyle(
        color: color,
        fontSize: 12.8,
        fontWeight: FontWeight.w800,
      ),
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
    required this.recommendedEventId,
    this.currentEventOverrideId,
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
  final bool mapGesturesEnabled;
  final List<StoryEvent> events;
  final String? recommendedEventId;
  final String? currentEventOverrideId;
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
  static const Duration _modalMapInputLockDuration = Duration(hours: 1);
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'today-stack');
  final GlobalKey _headerAnchorKey = GlobalKey(
    debugLabel: 'today-header-anchor',
  );
  final GlobalKey _journeyAnchorKey = GlobalKey(
    debugLabel: 'today-journey-anchor',
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
      final headerBox = _headerAnchorKey.currentContext?.findRenderObject();
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

  void _setStreakDialogMapInputBlocked(bool blocked) {
    if (blocked) {
      widget.mapController.suppressMapTaps(_modalMapInputLockDuration);
      widget.mapController.suspendMapGestures(_modalMapInputLockDuration);
      return;
    }
    widget.mapController.clearMapTapSuppression();
    widget.mapController.suppressMapTaps(const Duration(milliseconds: 1200));
    widget.mapController.clearMapGestureSuspension();
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
            304.0 + ((textScale - 1) * 185).clamp(0.0, 76.0);
        final topObscured =
            media.padding.top + TodayActivityHeader.mapObscuredExtent + 8;
        final bottomObscuredFraction = constraints.maxHeight <= 0
            ? 0.48
            : (floatingOverlayExtent / constraints.maxHeight).clamp(0.0, 0.68);
        if (!_todayGuideDismissed) {
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
                    summary: widget.activitySummary,
                    onStreakDialogVisibilityChanged:
                        _setStreakDialogMapInputBlocked,
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
            if (!_todayGuideDismissed)
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
