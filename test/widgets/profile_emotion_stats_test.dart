import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/widgets/profile/profile_emotion_stats.dart';

EventEmotionMark _mark({required String eventId, required String emotionKey}) {
  final option = EventEmotionOption.byKey(emotionKey);
  return EventEmotionMark(
    eventId: eventId,
    emotionKey: emotionKey,
    emotionLabel: option?.label ?? '기타',
    emotionEmoji: option?.emoji ?? '·',
    note: '',
    updatedAt: DateTime.utc(2026, 6, 10),
  );
}

void main() {
  group('buildProfileEmotionStats', () {
    test('감정을 새긴 이야기 수와 감정별 개수를 누적한다', () {
      final stats = buildProfileEmotionStats({
        'event-1': _mark(eventId: 'event-1', emotionKey: 'joy'),
        'event-2': _mark(eventId: 'event-2', emotionKey: 'gratitude'),
        'event-3': _mark(eventId: 'event-3', emotionKey: 'joy'),
      });

      expect(stats.totalStories, 3);
      expect(stats.countFor('joy'), 2);
      expect(stats.countFor('gratitude'), 1);
      expect(stats.countFor('comfort'), 0);
      expect(stats.eventIdsFor('joy'), {'event-1', 'event-3'});
      expect(stats.eventIdsFor('gratitude'), {'event-2'});
    });

    test('알 수 없는 감정 key도 개수는 보존한다', () {
      final stats = buildProfileEmotionStats({
        'event-1': _mark(eventId: 'event-1', emotionKey: 'unknown'),
      });

      expect(stats.totalStories, 1);
      expect(stats.countFor('unknown'), 1);
      expect(stats.eventIdsFor('unknown'), {'event-1'});
    });
  });
}
