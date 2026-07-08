import 'package:flutter/material.dart';

import '../../models/event_emotion_mark.dart';
import '../../theme/app_color_palette.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey('profile-emotion-stats-row'),
          children: [
            for (var i = 0; i < sortedOptions.length; i++) ...[
              Expanded(
                child: _ProfileEmotionStatChip(
                  option: sortedOptions[i],
                  count: stats.countFor(sortedOptions[i].key),
                  onTap: () => onTapEmotion(sortedOptions[i]),
                ),
              ),
              if (i != sortedOptions.length - 1) const SizedBox(width: 2),
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
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: largeText ? 30 : 27,
              height: largeText ? 30 : 27,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: count > 0 ? palette.currentFill : palette.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: count > 0
                      ? palette.currentAccentDeep.withValues(alpha: 0.44)
                      : palette.subtleBorder,
                  width: 0.8,
                ),
              ),
              child: EmotionBadgeIcon(
                emotionKey: option.key,
                size: largeText ? 23 : 21,
                iconSize: largeText ? 14 : 12.5,
                elevation: false,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${option.label} $count',
                maxLines: 1,
                style: TextStyle(
                  color: count > 0 ? palette.text : palette.mutedText,
                  fontSize: largeText ? 8.8 : 9.2,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
