import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
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
    this.mainAxisExtent = 226,
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
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    final sortedEvents = sortEventsByEraThenIndex(events, eras);
    if (sortedEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink300,
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

    return Padding(
      padding: padding,
      child: CustomScrollView(
        slivers: [
          for (final entry in eventsByEra.entries) ...[
            SliverToBoxAdapter(
              child: _ProfileEventEraDivider(
                label: eraById[entry.key]?.name ?? '시대 미상',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 14),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: mainAxisExtent,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final event = entry.value[index];
                  return StoryEventThumbCard(
                    event: event,
                    era: eraById[event.eraId],
                    charactersByCode: charactersByCode,
                    selected: false,
                    completed: completedEventIds.contains(event.id),
                    emotionKey: eventEmotionMarks[event.id]?.emotionKey,
                    attemptSummary: quizAttemptSummaries[event.id],
                    orderNumber: event.storyIndex,
                    loader: loader,
                    onTap: () => onOpenEventDetail(event),
                  );
                }, childCount: entry.value.length),
              ),
            ),
          ],
        ],
      ),
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

class _ProfileEventEraDivider extends StatelessWidget {
  const _ProfileEventEraDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0x668E6F48), height: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5BF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x998E6F48), width: 0.9),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF5A4326),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0x668E6F48), height: 1)),
        ],
      ),
    );
  }
}
