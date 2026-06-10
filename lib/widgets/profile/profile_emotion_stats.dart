import '../../models/event_emotion_mark.dart';

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
