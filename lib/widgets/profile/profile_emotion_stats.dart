import 'package:flutter/material.dart';

import '../../models/event_emotion_mark.dart';
import '../../theme/tokens.dart';
import '../emotion_badge_icon.dart';

class ProfileEmotionStats {
  const ProfileEmotionStats({
    required this.totalStories,
    required this.countsByEmotionKey,
    required this.eventIdsByEmotionKey,
  });

  final int totalStories;
  final Map<String, int> countsByEmotionKey;
  final Map<String, Set<String>> eventIdsByEmotionKey;

  int countFor(String emotionKey) => countsByEmotionKey[emotionKey] ?? 0;

  Set<String> eventIdsFor(String emotionKey) =>
      eventIdsByEmotionKey[emotionKey] ?? const <String>{};
}

ProfileEmotionStats buildProfileEmotionStats(
  Map<String, EventEmotionMark> marks,
) {
  final storyIds = <String>{};
  final counts = {
    for (final option in EventEmotionOption.options) option.key: 0,
  };
  final eventIds = {
    for (final option in EventEmotionOption.options) option.key: <String>{},
  };

  for (final mark in marks.values) {
    storyIds.add(mark.eventId);
    counts[mark.emotionKey] = (counts[mark.emotionKey] ?? 0) + 1;
    (eventIds[mark.emotionKey] ??= <String>{}).add(mark.eventId);
  }

  return ProfileEmotionStats(
    totalStories: storyIds.length,
    countsByEmotionKey: Map.unmodifiable(counts),
    eventIdsByEmotionKey: Map.unmodifiable({
      for (final entry in eventIds.entries)
        entry.key: Set.unmodifiable(entry.value),
    }),
  );
}

class ProfileEmotionStatsRows extends StatelessWidget {
  const ProfileEmotionStatsRows({
    super.key,
    required this.stats,
    required this.onTapEmotion,
  });

  final ProfileEmotionStats stats;
  final ValueChanged<EventEmotionOption> onTapEmotion;

  @override
  Widget build(BuildContext context) {
    final sortedOptions = [...EventEmotionOption.options]
      ..sort((a, b) {
        final countCompare = stats
            .countFor(b.key)
            .compareTo(stats.countFor(a.key));
        if (countCompare != 0) {
          return countCompare;
        }
        return EventEmotionOption.options
            .indexOf(a)
            .compareTo(EventEmotionOption.options.indexOf(b));
      });
    final firstRow = sortedOptions.take(4).toList();
    final secondRow = sortedOptions.skip(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < firstRow.length; i++) ...[
              Expanded(
                child: _ProfileEmotionStatChip(
                  option: firstRow[i],
                  count: stats.countFor(firstRow[i].key),
                  onTap: () => onTapEmotion(firstRow[i]),
                ),
              ),
              if (i != firstRow.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (var i = 0; i < secondRow.length; i++) ...[
              Expanded(
                child: _ProfileEmotionStatChip(
                  option: secondRow[i],
                  count: stats.countFor(secondRow[i].key),
                  onTap: () => onTapEmotion(secondRow[i]),
                ),
              ),
              if (i != secondRow.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }
}

class _ProfileEmotionStatChip extends StatelessWidget {
  const _ProfileEmotionStatChip({
    required this.option,
    required this.count,
    required this.onTap,
  });

  final EventEmotionOption option;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: count > 0
                ? AppColors.parchmentCream
                : AppColors.parchmentCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: count > 0 ? AppColors.goldDeep : const Color(0x66A8834D),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              EmotionBadgeIcon(
                emotionKey: option.key,
                size: 15,
                iconSize: 9,
                elevation: false,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${option.label} $count',
                    maxLines: 1,
                    style: TextStyle(
                      color: count > 0 ? AppColors.ink700 : AppColors.ink200,
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
    );
  }
}
