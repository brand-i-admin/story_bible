import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/scene_asset_loader.dart';
import '../v2/region_event_list.dart' show StoryEventThumbCard;

class ProfileEventReviewGrid extends StatelessWidget {
  const ProfileEventReviewGrid({
    super.key,
    required this.events,
    required this.eras,
    required this.charactersByCode,
    required this.completedEventIds,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.onOpenEventDetail,
    this.emptyText = '보여줄 이야기가 없습니다.',
    this.padding = const EdgeInsets.fromLTRB(2, 0, 2, 12),
    this.crossAxisCount = 3,
    this.scrollable = true,
  });

  final List<StoryEvent> events;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Set<String> completedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final String emptyText;
  final EdgeInsetsGeometry padding;
  final int crossAxisCount;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final sortedEvents = sortEventsByEraThenIndex(events, eras);
    if (sortedEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    final eraById = {for (final era in eras) era.id: era};
    final loader = SceneAssetLoader();
    final eventsByEra = <String, List<StoryEvent>>{};
    for (final event in sortedEvents) {
      eventsByEra.putIfAbsent(event.eraId, () => <StoryEvent>[]).add(event);
    }

    if (!scrollable) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in eventsByEra.entries) ...[
              ProfileEventEraDivider(
                eraId: entry.key,
                label: eraById[entry.key]?.name ?? '시대 미상',
              ),
              _ProfileEventWrap(
                events: entry.value,
                eraById: eraById,
                charactersByCode: charactersByCode,
                completedEventIds: completedEventIds,
                eventEmotionMarks: eventEmotionMarks,
                quizAttemptSummaries: quizAttemptSummaries,
                crossAxisCount: crossAxisCount,
                loader: loader,
                onOpenEventDetail: onOpenEventDetail,
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: padding,
      children: [
        for (final entry in eventsByEra.entries) ...[
          ProfileEventEraDivider(
            eraId: entry.key,
            label: eraById[entry.key]?.name ?? '시대 미상',
          ),
          _ProfileEventWrap(
            events: entry.value,
            eraById: eraById,
            charactersByCode: charactersByCode,
            completedEventIds: completedEventIds,
            eventEmotionMarks: eventEmotionMarks,
            quizAttemptSummaries: quizAttemptSummaries,
            crossAxisCount: crossAxisCount,
            loader: loader,
            onOpenEventDetail: onOpenEventDetail,
          ),
        ],
      ],
    );
  }

  static List<StoryEvent> sortEventsByEraThenIndex(
    List<StoryEvent> events,
    List<Era> eras,
  ) {
    final orderByEraId = <String, int>{
      for (final era in eras) era.id: era.displayOrder,
    };
    final sorted = [...events];
    sorted.sort((a, b) {
      final eraOrder = (orderByEraId[a.eraId] ?? 1 << 30).compareTo(
        orderByEraId[b.eraId] ?? 1 << 30,
      );
      if (eraOrder != 0) {
        return eraOrder;
      }
      final storyOrder = a.storyIndex.compareTo(b.storyIndex);
      if (storyOrder != 0) {
        return storyOrder;
      }
      return a.globalRank.compareTo(b.globalRank);
    });
    return sorted;
  }
}

class _ProfileEventWrap extends StatelessWidget {
  const _ProfileEventWrap({
    required this.events,
    required this.eraById,
    required this.charactersByCode,
    required this.completedEventIds,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.crossAxisCount,
    required this.loader,
    required this.onOpenEventDetail,
  });

  final List<StoryEvent> events;
  final Map<String, Era> eraById;
  final Map<String, Character> charactersByCode;
  final Set<String> completedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final int crossAxisCount;
  final SceneAssetLoader loader;
  final ValueChanged<StoryEvent> onOpenEventDetail;

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 5, 2, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final event in events)
                SizedBox(
                  width: width,
                  child: StoryEventThumbCard(
                    event: event,
                    era: eraById[event.eraId],
                    charactersByCode: charactersByCode,
                    selected: false,
                    completed: completedEventIds.contains(event.id),
                    emotionKey: eventEmotionMarks[event.id]?.emotionKey,
                    attemptSummary: quizAttemptSummaries[event.id],
                    orderNumber: event.storyIndex,
                    showSummary: false,
                    loader: loader,
                    onTap: () => onOpenEventDetail(event),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ProfileEventEraDivider extends StatelessWidget {
  const ProfileEventEraDivider({
    super.key,
    required this.eraId,
    required this.label,
  });

  final String eraId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Padding(
      key: key == null ? ValueKey('profile-event-era-divider-$eraId') : null,
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Expanded(child: Divider(color: palette.subtleBorder, height: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.currentFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.subtleBorder, width: 0.9),
            ),
            child: Text(
              label,
              maxLines: largeText ? 2 : 1,
              overflow: largeText
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                color: palette.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: AppColors.borderCard.withValues(alpha: 0.58),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
