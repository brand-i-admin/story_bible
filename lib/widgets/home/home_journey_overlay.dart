import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../models/user_companion_diary_entry.dart';
import '../../screens/companion_diary_editor_screen.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/daily_exploration_selection.dart';
import '../../utils/scene_asset_loader.dart';
import '../login_required_dialog.dart';
import '../profile/companion_diary_entry_card.dart';
import '../pulse_highlight.dart';

import '../v2/region_event_list.dart'
    show StoryEventCardPresentation, StoryEventThumbCard;

class HomeJourneyOverlay extends StatelessWidget {
  const HomeJourneyOverlay({
    super.key,
    required this.events,
    required this.recommendedEventId,
    required this.currentEventId,
    required this.eras,
    required this.charactersByCode,
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
  final String? recommendedEventId;
  final String? currentEventId;
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
          recommendedEventId: recommendedEventId,
          currentEventId: currentEventId,
          eras: eras,
          charactersByCode: charactersByCode,
          eventEmotionMarks: eventEmotionMarks,
          quizAttemptSummaries: quizAttemptSummaries,
          todayStoryCompleted: todayStoryCompleted,
          onOpenStory: onOpenStory,
          onCurrentStoryChanged: onCurrentStoryChanged,
        ),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _HomeQuickActions(
            isAuthenticated: isAuthenticated,
            todayDiary: todayDiary,
            diaryLoading: diaryLoading,
            diaryError: diaryError,
            bibleTargetLabel: bibleTargetLabel,
            bibleReadingCompleted: bibleReadingCompleted,
            onSaveDiary: onSaveDiary,
            onDeleteDiary: onDeleteDiary,
            onContinueBibleReading: onContinueBibleReading,
            onOpenProfile: onOpenProfile,
          ),
        ),
      ],
    );
  }
}

class _HomeStoryJourneyDeck extends StatefulWidget {
  const _HomeStoryJourneyDeck({
    super.key,
    required this.events,
    required this.recommendedEventId,
    required this.currentEventId,
    required this.eras,
    required this.charactersByCode,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.todayStoryCompleted,
    required this.onOpenStory,
    required this.onCurrentStoryChanged,
  });

  final List<StoryEvent> events;
  final String? recommendedEventId;
  final String? currentEventId;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
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

  @override
  void initState() {
    super.initState();
    _currentPage = _initialPage();
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.32,
    );
  }

  @override
  void didUpdateWidget(covariant _HomeStoryJourneyDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = _orderedEvents();
    if (events.isEmpty || widget.currentEventId == null) return;
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
    final deckHeight = 186.0 + ((textScale - 1) * 80).clamp(0.0, 40.0);
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
            child: Text(
              '추천 이야기를 불러오는 중이에요.',
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
                  return const _HomeExplorationSortHintCard();
                }
                final eventIndex = page - 1;
                return _buildCard(
                  context: context,
                  events: ordered,
                  eventIndex: eventIndex,
                  page: page,
                  deckHeight: deckHeight,
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

  Widget _buildCard({
    required BuildContext context,
    required List<StoryEvent> events,
    required int eventIndex,
    required int page,
    required double deckHeight,
  }) {
    final event = events[eventIndex];
    final isCurrent = page == _currentPage;
    final isRecommended = event.id == widget.recommendedEventId;
    final label = isCurrent
        ? (isRecommended ? '오늘의 이야기' : '현재 이야기')
        : page < _currentPage
        ? '이전 이야기'
        : '다음 이야기';
    final palette = AppPaletteTheme.of(context);
    final eraById = {for (final era in widget.eras) era.id: era};
    final previous = eventIndex > 0 ? events[eventIndex - 1] : null;
    final next = eventIndex + 1 < events.length ? events[eventIndex + 1] : null;
    final leftBoundaryLabel = isCurrent
        ? _boundaryLabel(
            adjacent: previous,
            current: event,
            eraById: eraById,
            missingLabel: '이전 이야기 없음',
          )
        : null;
    final rightBoundaryLabel = isCurrent
        ? _boundaryLabel(
            adjacent: next,
            current: event,
            eraById: eraById,
            missingLabel: '다음 이야기 없음',
          )
        : null;
    final card = StoryEventThumbCard(
      event: event,
      era: eraById[event.eraId],
      charactersByCode: widget.charactersByCode,
      selected: isCurrent,
      completed: widget.eventEmotionMarks.containsKey(event.id),
      emotionKey: widget.eventEmotionMarks[event.id]?.emotionKey,
      attemptSummary: widget.quizAttemptSummaries[event.id],
      orderNumber: event.storyIndex,
      presentation: isCurrent
          ? StoryEventCardPresentation.todayCurrent
          : StoryEventCardPresentation.todayAdjacent,
      showSummary: false,
      showCharacterPills: true,
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
    final cardFrame = Stack(
      key: ValueKey('home-journey-card-${event.id}-$page'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              5,
              isCurrent ? 0 : 14,
              5,
              isCurrent ? 0 : 14,
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: isCurrent ? 1 : 0.72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: palette.currentAccent.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    highlightedCard,
                    if (!isCurrent || isRecommended)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? palette.currentAccentDeep
                                : palette.cardSurface.withValues(alpha: 0.94),
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
                              color: isCurrent
                                  ? AppColors.fgOnDark
                                  : palette.currentAccentDeep,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (leftBoundaryLabel != null)
          Positioned(
            left: -29,
            top: (deckHeight - 38) / 2,
            child: _HomeJourneyBoundaryBadge(label: leftBoundaryLabel),
          ),
        if (rightBoundaryLabel != null)
          Positioned(
            right: -29,
            top: (deckHeight - 38) / 2,
            child: _HomeJourneyBoundaryBadge(label: rightBoundaryLabel),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = constraints.maxWidth;
        final expandedWidth = ((baseWidth - 10) * 1.5) + 10;
        final horizontalShift = isCurrent
            ? 0.0
            : ((expandedWidth - baseWidth) / 2 - 6) *
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

class _HomeJourneyBoundaryBadge extends StatelessWidget {
  const _HomeJourneyBoundaryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      width: 64,
      constraints: const BoxConstraints(minHeight: 38),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: palette.panelSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.currentAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: palette.primaryDeep.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.text,
          fontSize: label.contains('\n') ? 9.2 : 8.4,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
      ),
    );
  }
}

class _HomeExplorationSortHintCard extends StatelessWidget {
  const _HomeExplorationSortHintCard();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 12, 5, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.regionAccent.withValues(alpha: 0.10),
            palette.cardSurface,
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: palette.regionAccent.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_location_alt_rounded, color: palette.regionAccent),
            const SizedBox(height: 8),
            Text(
              '탐험 정렬 안내',
              style: TextStyle(
                color: palette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '지도 탭에서 사건에 직접 감정을 새기면\n그 사건 기준으로 탐험 정렬이 바뀌어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.isAuthenticated,
    required this.todayDiary,
    required this.diaryLoading,
    required this.diaryError,
    required this.bibleTargetLabel,
    required this.bibleReadingCompleted,
    required this.onSaveDiary,
    required this.onDeleteDiary,
    required this.onContinueBibleReading,
    required this.onOpenProfile,
  });

  final bool isAuthenticated;
  final UserCompanionDiaryEntry? todayDiary;
  final bool diaryLoading;
  final String? diaryError;
  final String bibleTargetLabel;
  final bool bibleReadingCompleted;
  final CompanionDiarySaveCallback? onSaveDiary;
  final CompanionDiaryDeleteCallback? onDeleteDiary;
  final VoidCallback onContinueBibleReading;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _HomeQuickActionCard(
              key: const ValueKey('home-diary-quick-action'),
              effectId: 'diary',
              icon: Icons.edit_note_rounded,
              title: '신앙 다이어리',
              subtitle: diaryError ?? _diaryPreviewText(todayDiary),
              subtitleMaxLines: todayDiary == null ? 2 : 3,
              actionLabel: !diaryLoading && todayDiary == null
                  ? '+ 기록하기'
                  : null,
              actionEffectActive: !diaryLoading && todayDiary == null,
              accent: palette.successBottom,
              onTap: diaryLoading ? null : () => _handleDiaryTap(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _HomeQuickActionCard(
              key: const ValueKey('home-bible-quick-action'),
              effectId: 'bible',
              icon: Icons.menu_book_rounded,
              title: '통독 이어읽기',
              subtitle: bibleTargetLabel,
              subtitleMaxLines: 2,
              actionLabel: '→ 이어읽기',
              actionEffectActive: !bibleReadingCompleted,
              accent: palette.primary,
              onTap: () => _handleBibleTap(context),
            ),
          ),
        ],
      ),
    );
  }

  String _diaryPreviewText(UserCompanionDiaryEntry? entry) {
    if (diaryLoading) {
      return '오늘 기록을 불러오는 중이에요.';
    }
    if (entry == null) {
      return '오늘의 동행을 기록해 보세요.';
    }
    return '${entry.title}\n${entry.body}';
  }

  Future<void> _handleDiaryTap(BuildContext context) async {
    if (!isAuthenticated) {
      await _showLoginRequiredDialog(context, featureName: '신앙 다이어리');
      return;
    }
    final entry = todayDiary;
    if (entry == null) {
      await _openDiaryEditor(context, null);
      return;
    }
    final action = await showDialog<CompanionDiaryDetailAction>(
      context: context,
      builder: (dialogContext) => CompanionDiaryEntryDetailDialog(
        entry: entry,
        onEdit: onSaveDiary == null
            ? null
            : () => Navigator.of(
                dialogContext,
              ).pop(CompanionDiaryDetailAction.edit),
        onDelete: onDeleteDiary == null
            ? null
            : () => Navigator.of(
                dialogContext,
              ).pop(CompanionDiaryDetailAction.delete),
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (action == CompanionDiaryDetailAction.edit) {
      await _openDiaryEditor(context, entry);
    } else if (action == CompanionDiaryDetailAction.delete) {
      await _deleteDiary(context, entry);
    }
  }

  Future<void> _openDiaryEditor(
    BuildContext context,
    UserCompanionDiaryEntry? initialEntry,
  ) async {
    final save = onSaveDiary;
    if (save == null) {
      return;
    }
    final draft = await openCompanionDiaryEditorPage(
      context,
      entryDate: initialEntry?.entryDate ?? DateTime.now(),
      initialEntry: initialEntry,
    );
    if (draft == null) {
      return;
    }
    try {
      await save(
        entryDate: initialEntry?.entryDate ?? DateTime.now(),
        title: draft.title,
        body: draft.body,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initialEntry == null ? '신앙 다이어리를 남겼어요.' : '신앙 다이어리를 수정했어요.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('신앙 다이어리를 저장하지 못했습니다.\n$error')));
    }
  }

  Future<void> _deleteDiary(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final delete = onDeleteDiary;
    if (delete == null) {
      return;
    }
    final confirmed = await showCompanionDiaryDeleteConfirmDialog(
      context,
      entry,
    );
    if (!confirmed) {
      return;
    }
    try {
      await delete(entry);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신앙 다이어리를 삭제했어요.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다.\n$error')));
    }
  }

  Future<void> _handleBibleTap(BuildContext context) async {
    if (!isAuthenticated) {
      await _showLoginRequiredDialog(context, featureName: '통독 이어읽기');
      return;
    }
    onContinueBibleReading();
  }

  Future<void> _showLoginRequiredDialog(
    BuildContext context, {
    required String featureName,
  }) async {
    await showLoginRequiredDialog(
      context: context,
      message: '$featureName은 로그인 후 사용할 수 있어요.',
      onOpenMyInfo: onOpenProfile,
    );
  }
}

class _HomeQuickActionCard extends StatelessWidget {
  const _HomeQuickActionCard({
    super.key,
    required this.effectId,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.actionLabel,
    this.actionEffectActive = false,
    this.subtitleMaxLines = 1,
  });

  final String effectId;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final String? actionLabel;
  final bool actionEffectActive;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final darkSurface = palette == AppColorPalette.blackMap;
    final surface = Color.alphaBlend(
      accent.withValues(alpha: darkSurface ? 0.18 : 0.10),
      palette.cardSurface,
    );
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: accent.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: largeText
                          ? subtitleMaxLines + 2
                          : subtitleMaxLines,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 11.4,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 6),
                      _HomeQuickActionCta(
                        effectId: effectId,
                        label: actionLabel!,
                        accent: accent,
                        active: actionEffectActive,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeQuickActionCta extends StatelessWidget {
  const _HomeQuickActionCta({
    required this.effectId,
    required this.label,
    required this.accent,
    required this.active,
  });

  final String effectId;
  final String label;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: PulseHighlight(
        key: ValueKey('home-$effectId-quick-action-cta-glow'),
        active: active,
        pulseCount: null,
        duration: const Duration(milliseconds: 1900),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        color: accent,
        child: Container(
          key: ValueKey('home-$effectId-quick-action-cta'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.13),
              palette.cardSurface,
            ),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: accent.withValues(alpha: 0.42)),
          ),
          child: _HomeQuickActionRipple(
            effectId: effectId,
            label: label,
            accent: accent,
            active: active,
          ),
        ),
      ),
    );
  }
}

class _HomeQuickActionRipple extends StatefulWidget {
  const _HomeQuickActionRipple({
    required this.effectId,
    required this.label,
    required this.accent,
    required this.active,
  });

  final String effectId;
  final String label;
  final Color accent;
  final bool active;

  @override
  State<_HomeQuickActionRipple> createState() => _HomeQuickActionRippleState();
}

class _HomeQuickActionRippleState extends State<_HomeQuickActionRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeQuickActionRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      widget.label,
      key: ValueKey(
        'home-quick-action-label-${widget.label.replaceAll(' ', '-')}',
      ),
      maxLines: 1,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: widget.accent,
        fontSize: 11.6,
        fontWeight: FontWeight.w900,
        height: 1.1,
      ),
    );
    if (!widget.active) return label;
    return AnimatedBuilder(
      animation: _controller,
      child: label,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: -8,
              top: -8,
              bottom: -8,
              width: 32,
              child: IgnorePointer(
                child: CustomPaint(
                  key: ValueKey('home-${widget.effectId}-quick-action-ripple'),
                  painter: _HomeQuickActionRipplePainter(
                    progress: _controller.value,
                    color: widget.accent,
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}

class _HomeQuickActionRipplePainter extends CustomPainter {
  const _HomeQuickActionRipplePainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    void paintRipple(double phase) {
      final curved = Curves.easeOutCubic.transform(phase);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = color.withValues(alpha: (1 - phase) * 0.58);
      canvas.drawCircle(
        size.center(Offset.zero),
        4 + (size.shortestSide * 0.38 * curved),
        paint,
      );
    }

    paintRipple(progress);
    paintRipple((progress + 0.5) % 1);
  }

  @override
  bool shouldRepaint(covariant _HomeQuickActionRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
