import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
import '../profile/companion_diary_entry_card.dart';
import '../profile/profile_event_review_grid.dart';
import '../pulse_highlight.dart';

import '../v2/region_event_list.dart'
    show StoryEventCardPresentation, StoryEventThumbCard;

const _homeJourneyViewportFraction = 0.34;
const _homeJourneyCurrentWidthScale = 1.85;
const _homeJourneyAdjacentHeightFraction = 0.60;
const _homeJourneyBaseDeckHeight = 250.0;
const _homeJourneyCurrentCardTopInset = 20.0;

double _homeJourneyAdjacentTopInset(double height) =>
    height -
    (height - _homeJourneyCurrentCardTopInset) *
        _homeJourneyAdjacentHeightFraction;

class HomeJourneyOverlay extends StatelessWidget {
  const HomeJourneyOverlay({
    super.key,
    required this.events,
    this.loading = false,
    required this.recommendedEventId,
    required this.currentEventId,
    this.currentEraDividerAnchorKey,
    required this.eras,
    required this.charactersByCode,
    this.journeyBoundaryLabel = '선택된 여정',
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.isAuthenticated,
    required this.todayDiary,
    required this.diaryLoading,
    required this.diaryError,
    required this.bibleTargetLabel,
    this.todayStoryCompleted = false,
    this.bibleReadingCompleted = false,
    required this.onOpenStory,
    required this.onCurrentStoryChanged,
    required this.onSaveDiary,
    required this.onDeleteDiary,
    required this.onContinueBibleReading,
    required this.onOpenProfile,
  });

  final List<StoryEvent> events;
  final bool loading;
  final String? recommendedEventId;
  final String? currentEventId;
  final Key? currentEraDividerAnchorKey;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final String journeyBoundaryLabel;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final bool isAuthenticated;
  final UserCompanionDiaryEntry? todayDiary;
  final bool diaryLoading;
  final String? diaryError;
  final String bibleTargetLabel;
  final bool todayStoryCompleted;
  final bool bibleReadingCompleted;
  final ValueChanged<StoryEvent> onOpenStory;
  final ValueChanged<StoryEvent> onCurrentStoryChanged;
  final CompanionDiarySaveCallback? onSaveDiary;
  final CompanionDiaryDeleteCallback? onDeleteDiary;
  final VoidCallback onContinueBibleReading;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-journey-overlay'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeStoryJourneyDeck(
          key: ValueKey(
            'home-story-deck-${events.map((event) => event.id).join('-')}',
          ),
          events: events,
          loading: loading,
          recommendedEventId: recommendedEventId,
          currentEventId: currentEventId,
          currentEraDividerAnchorKey: currentEraDividerAnchorKey,
          eras: eras,
          charactersByCode: charactersByCode,
          journeyBoundaryLabel: journeyBoundaryLabel,
          eventEmotionMarks: eventEmotionMarks,
          quizAttemptSummaries: quizAttemptSummaries,
          todayStoryCompleted: todayStoryCompleted,
          onOpenStory: onOpenStory,
          onCurrentStoryChanged: onCurrentStoryChanged,
        ),
      ],
    );
  }
}

class _HomeStoryJourneyDeck extends StatefulWidget {
  const _HomeStoryJourneyDeck({
    super.key,
    required this.events,
    required this.loading,
    required this.recommendedEventId,
    required this.currentEventId,
    this.currentEraDividerAnchorKey,
    required this.eras,
    required this.charactersByCode,
    required this.journeyBoundaryLabel,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.todayStoryCompleted,
    required this.onOpenStory,
    required this.onCurrentStoryChanged,
  });

  final List<StoryEvent> events;
  final bool loading;
  final String? recommendedEventId;
  final String? currentEventId;
  final Key? currentEraDividerAnchorKey;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final String journeyBoundaryLabel;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final bool todayStoryCompleted;
  final ValueChanged<StoryEvent> onOpenStory;
  final ValueChanged<StoryEvent> onCurrentStoryChanged;

  @override
  State<_HomeStoryJourneyDeck> createState() => _HomeStoryJourneyDeckState();
}

class _HomeStoryJourneyDeckState extends State<_HomeStoryJourneyDeck> {
  late final PageController _pageController;
  late int _currentPage;
  String? _measuredCurrentEventId;
  double? _measuredTextScale;
  double? _measuredCurrentCardHeight;

  @override
  void initState() {
    super.initState();
    _currentPage = _initialPage();
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: _homeJourneyViewportFraction,
    );
  }

  @override
  void didUpdateWidget(covariant _HomeStoryJourneyDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = _orderedEvents();
    if (events.isEmpty || widget.currentEventId == null) return;
    final showingBoundaryHint =
        _currentPage == 0 || _currentPage == events.length + 1;
    if (showingBoundaryHint &&
        oldWidget.currentEventId == widget.currentEventId) {
      return;
    }
    final visibleEventIndex = _currentPage - 1;
    if (visibleEventIndex >= 0 &&
        visibleEventIndex < events.length &&
        events[visibleEventIndex].id == widget.currentEventId) {
      return;
    }
    final targetIndex = events.indexWhere(
      (event) => event.id == widget.currentEventId,
    );
    if (targetIndex < 0) return;
    final nextPage = targetIndex + 1;
    _currentPage = nextPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(nextPage);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final ordered = _orderedEvents();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final measuredCurrentCardHeight = _measuredTextScale == textScale
        ? _measuredCurrentCardHeight
        : null;
    final deckHeight = measuredCurrentCardHeight == null
        ? _homeJourneyBaseDeckHeight + ((textScale - 1) * 90).clamp(0.0, 32.0)
        : _homeJourneyCurrentCardTopInset + measuredCurrentCardHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ordered.isEmpty)
          Container(
            height: deckHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.subtleBorder),
            ),
            child: widget.loading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: palette.currentAccentDeep,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      Text(
                        '이야기를 불러오고 있어요.',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '선택한 여정에 연결된 이야기가 없어요.',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          )
        else
          SizedBox(
            height: deckHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final eraById = {for (final era in widget.eras) era.id: era};
                final currentEventIndex = _currentPage - 1;
                String? leftBoundaryLabel;
                String? rightBoundaryLabel;
                if (currentEventIndex >= 0 &&
                    currentEventIndex < ordered.length) {
                  final currentEvent = ordered[currentEventIndex];
                  leftBoundaryLabel = _boundaryLabel(
                    adjacent: currentEventIndex > 0
                        ? ordered[currentEventIndex - 1]
                        : null,
                    current: currentEvent,
                    eraById: eraById,
                    missingLabel: '여정\n처음',
                  );
                  rightBoundaryLabel = _boundaryLabel(
                    adjacent: currentEventIndex + 1 < ordered.length
                        ? ordered[currentEventIndex + 1]
                        : null,
                    current: currentEvent,
                    eraById: eraById,
                    missingLabel: '여정\n끝',
                  );
                }
                final boundaryInset = (constraints.maxWidth * 0.26 - 26.5)
                    .clamp(0.0, double.infinity)
                    .toDouble();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: PageView.builder(
                        key: const ValueKey('home-story-page-view'),
                        controller: _pageController,
                        physics: const PageScrollPhysics(),
                        clipBehavior: Clip.none,
                        itemCount: ordered.length + 2,
                        onPageChanged: (page) {
                          final nextPage = page.clamp(
                            (_currentPage - 1).clamp(0, ordered.length + 1),
                            (_currentPage + 1).clamp(0, ordered.length + 1),
                          );
                          setState(() => _currentPage = nextPage);
                          if (nextPage != page) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _pageController.hasClients) {
                                _pageController.jumpToPage(nextPage);
                              }
                            });
                          }
                          final eventIndex = nextPage - 1;
                          if (eventIndex >= 0 && eventIndex < ordered.length) {
                            widget.onCurrentStoryChanged(ordered[eventIndex]);
                          }
                        },
                        itemBuilder: (context, page) {
                          if (page == 0 || page == ordered.length + 1) {
                            return _buildBoundaryPage(page: page);
                          }
                          final eventIndex = page - 1;
                          return _buildCard(
                            context: context,
                            events: ordered,
                            eventIndex: eventIndex,
                            page: page,
                          );
                        },
                      ),
                    ),
                    if (leftBoundaryLabel != null)
                      Positioned(
                        key: const ValueKey(
                          'home-journey-left-boundary-overlay',
                        ),
                        left: boundaryInset,
                        top: (deckHeight - 38) / 2,
                        child: _HomeJourneyBoundaryBadge(
                          label: leftBoundaryLabel,
                        ),
                      ),
                    if (rightBoundaryLabel != null)
                      Positioned(
                        key: const ValueKey(
                          'home-journey-right-boundary-overlay',
                        ),
                        right: boundaryInset,
                        top: (deckHeight - 38) / 2,
                        child: _HomeJourneyBoundaryBadge(
                          label: rightBoundaryLabel,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  List<StoryEvent> _orderedEvents() {
    return orderedExplorationEventsByEra(
      events: <String, StoryEvent>{
        for (final event in widget.events) event.id: event,
      }.values.toList(growable: false),
      eras: widget.eras,
    );
  }

  int _initialPage() {
    final events = _orderedEvents();
    if (events.isEmpty) return 0;
    final currentIndex = events.indexWhere(
      (event) => event.id == widget.currentEventId,
    );
    final index = currentIndex < 0 ? 0 : currentIndex;
    return index + 1;
  }

  void _reportCurrentCardSize({
    required String eventId,
    required double textScale,
    required Size size,
  }) {
    if (!mounted) return;
    final events = _orderedEvents();
    final currentEventIndex = _currentPage - 1;
    if (currentEventIndex < 0 ||
        currentEventIndex >= events.length ||
        events[currentEventIndex].id != eventId ||
        MediaQuery.textScalerOf(context).scale(1) != textScale) {
      return;
    }
    if (_measuredCurrentEventId == eventId &&
        _measuredTextScale == textScale &&
        _measuredCurrentCardHeight != null &&
        (_measuredCurrentCardHeight! - size.height).abs() < 0.1) {
      return;
    }
    setState(() {
      _measuredCurrentEventId = eventId;
      _measuredTextScale = textScale;
      _measuredCurrentCardHeight = size.height;
    });
  }

  Widget _buildBoundaryPage({required int page}) {
    final isCurrent = page == _currentPage;
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = constraints.maxWidth;
        final expandedWidth =
            ((baseWidth - 10) * _homeJourneyCurrentWidthScale) + 10;
        final horizontalShift = isCurrent
            ? 0.0
            : ((expandedWidth - baseWidth) / 2 - 10.5) *
                  (page < _currentPage ? -1 : 1);
        final frameWidth = isCurrent ? expandedWidth : baseWidth;
        return Transform.translate(
          offset: Offset(horizontalShift, 0),
          child: OverflowBox(
            minWidth: frameWidth,
            maxWidth: frameWidth,
            minHeight: constraints.maxHeight,
            maxHeight: constraints.maxHeight,
            alignment: Alignment.center,
            child: SizedBox(
              width: frameWidth,
              height: constraints.maxHeight,
              child: _HomeJourneyBoundaryCard(
                isCurrent: isCurrent,
                journeyLabel: widget.journeyBoundaryLabel,
                isStart: page == 0,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required List<StoryEvent> events,
    required int eventIndex,
    required int page,
  }) {
    final event = events[eventIndex];
    final isCurrent = page == _currentPage;
    final isRecommended = event.id == widget.recommendedEventId;
    final label = page < _currentPage ? '이전 이야기' : '다음 이야기';
    final palette = AppPaletteTheme.of(context);
    final eraById = {for (final era in widget.eras) era.id: era};
    final card = StoryEventThumbCard(
      event: event,
      era: eraById[event.eraId],
      charactersByCode: widget.charactersByCode,
      selected: isCurrent,
      completed: widget.eventEmotionMarks.containsKey(event.id),
      emotionKey: widget.eventEmotionMarks[event.id]?.emotionKey,
      attemptSummary: widget.quizAttemptSummaries[event.id],
      orderNumber: eventIndex + 1,
      presentation: isCurrent
          ? StoryEventCardPresentation.todayCurrent
          : StoryEventCardPresentation.todayAdjacent,
      showSummary: isCurrent,
      showCharacterPills: false,
      expandSurface: !isCurrent,
      surfaceColorOverride: palette.cardSurface,
      loader: SceneAssetLoader(),
      onTap: () {
        if (isCurrent) {
          widget.onOpenStory(event);
        } else {
          _pageController.animateToPage(
            page,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
      },
    );
    final highlightedCard = PulseHighlight(
      key: ValueKey('home-story-task-highlight-${event.id}'),
      active: isRecommended && !widget.todayStoryCompleted,
      pulseCount: null,
      duration: const Duration(milliseconds: 1800),
      borderRadius: BorderRadius.circular(15),
      color: AppColors.goldLight,
      child: card,
    );
    final cardFrame = LayoutBuilder(
      builder: (context, frameConstraints) {
        final adjacentTopInset = _homeJourneyAdjacentTopInset(
          frameConstraints.maxHeight,
        );
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final cardContents = isCurrent
            ? highlightedCard
            : Stack(
                fit: StackFit.expand,
                children: [
                  highlightedCard,
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 8,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.cardSurface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: palette.currentAccent.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: palette.currentAccentDeep,
                            fontSize: 9.8,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
        final decoratedCard = DecoratedBox(
          key: ValueKey('home-journey-card-surface-frame-${event.id}'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: palette.currentAccent.withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: cardContents,
        );
        return Stack(
          key: ValueKey('home-journey-card-${event.id}-$page'),
          clipBehavior: Clip.none,
          children: [
            if (isCurrent)
              Positioned(
                left: 5,
                right: 5,
                bottom: 0,
                child: _HomeJourneySizeReporter(
                  key: ValueKey(
                    'home-current-card-size-${event.id}-$textScale',
                  ),
                  onSizeChanged: (size) => _reportCurrentCardSize(
                    eventId: event.id,
                    textScale: textScale,
                    size: size,
                  ),
                  child: decoratedCard,
                ),
              )
            else
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, adjacentTopInset, 10, 0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: 0.72,
                    child: decoratedCard,
                  ),
                ),
              ),
            if (isCurrent)
              Positioned(
                left: 12,
                right: 12,
                top: _homeJourneyCurrentCardTopInset - 30,
                child: SizedBox(
                  key: widget.currentEraDividerAnchorKey,
                  child: ProfileEventEraDivider(
                    key: ValueKey('home-current-era-divider-${event.eraId}'),
                    eraId: event.eraId,
                    label: eraById[event.eraId]?.name ?? '시대 미상',
                  ),
                ),
              ),
          ],
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = constraints.maxWidth;
        final expandedWidth =
            ((baseWidth - 10) * _homeJourneyCurrentWidthScale) + 10;
        final horizontalShift = isCurrent
            ? 0.0
            : ((expandedWidth - baseWidth) / 2 - 10.5) *
                  (page < _currentPage ? -1 : 1);
        final frameWidth = isCurrent ? expandedWidth : baseWidth;
        return Transform.translate(
          offset: Offset(horizontalShift, 0),
          child: OverflowBox(
            minWidth: frameWidth,
            maxWidth: frameWidth,
            minHeight: constraints.maxHeight,
            maxHeight: constraints.maxHeight,
            alignment: Alignment.center,
            child: SizedBox(
              width: frameWidth,
              height: constraints.maxHeight,
              child: cardFrame,
            ),
          ),
        );
      },
    );
  }

  String? _boundaryLabel({
    required StoryEvent? adjacent,
    required StoryEvent current,
    required Map<String, Era> eraById,
    required String missingLabel,
  }) {
    if (adjacent == null) return missingLabel;
    if (adjacent.eraId == current.eraId) return null;
    final eraName = eraById[adjacent.eraId]?.name.trim();
    final shortName = eraName == null || eraName.isEmpty
        ? '다른 시대'
        : eraName.replaceFirst(RegExp(r'\s*시대$'), '');
    return '$shortName\n이동';
  }
}

class _HomeJourneySizeReporter extends SingleChildRenderObjectWidget {
  const _HomeJourneySizeReporter({
    super.key,
    required this.onSizeChanged,
    required super.child,
  });

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _HomeJourneySizeReporterRenderObject(onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _HomeJourneySizeReporterRenderObject renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _HomeJourneySizeReporterRenderObject extends RenderProxyBox {
  _HomeJourneySizeReporterRenderObject(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _lastReportedSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastReportedSize == size) return;
    final reportedSize = size;
    _lastReportedSize = reportedSize;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => onSizeChanged(reportedSize),
    );
  }
}

class _HomeJourneyBoundaryBadge extends StatelessWidget {
  const _HomeJourneyBoundaryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: label.startsWith('여정')
          ? const ValueKey('home-journey-missing-boundary-badge')
          : const ValueKey('home-journey-era-boundary-badge'),
      width: 64,
      constraints: const BoxConstraints(minHeight: 38),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: palette.utilitySelectedBackground.withValues(alpha: 1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: palette.currentAccent.withValues(alpha: 0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.currentAccent.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.fgOnDark,
          fontSize: label.contains('\n') ? 9.2 : 8.4,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
      ),
    );
  }
}

class _HomeJourneyBoundaryCard extends StatelessWidget {
  const _HomeJourneyBoundaryCard({
    required this.isCurrent,
    required this.journeyLabel,
    required this.isStart,
  });

  final bool isCurrent;
  final String journeyLabel;
  final bool isStart;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        key: isCurrent ? const ValueKey('home-journey-boundary-current') : null,
        padding: EdgeInsets.fromLTRB(
          isCurrent ? 5 : 10,
          isCurrent ? 0 : _homeJourneyAdjacentTopInset(constraints.maxHeight),
          isCurrent ? 5 : 10,
          0,
        ),
        child: Container(
          key: ValueKey(
            isStart ? 'home-journey-start-card' : 'home-journey-end-card',
          ),
          padding: EdgeInsets.symmetric(
            horizontal: largeText ? 8 : 14,
            vertical: largeText ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              palette.currentAccent.withValues(alpha: 0.08),
              palette.cardSurface,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: palette.currentAccent.withValues(alpha: 0.32),
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: palette.currentAccent.withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              key: const ValueKey('home-journey-boundary-fit'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isStart ? Icons.first_page_rounded : Icons.flag_rounded,
                      color: palette.currentAccentDeep,
                      size: largeText ? 20 : 24,
                    ),
                    SizedBox(height: largeText ? 4 : 8),
                    Text(
                      isStart ? '여정의 시작' : '여정의 끝',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: largeText ? 11 : 12.5,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: largeText ? 3 : 6),
                    Text(
                      '$journeyLabel의\n${isStart ? '첫' : '마지막'} 이야기입니다.',
                      key: const ValueKey('home-journey-boundary-body'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: largeText ? 9.4 : 10.5,
                        fontWeight: FontWeight.w800,
                        height: largeText ? 1.28 : 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
