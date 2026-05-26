import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_emotion_mark.dart';

void main() {
  group('EventEmotionMark', () {
    test('감정 선택지는 여덟 개이고 기타를 포함한다', () {
      expect(EventEmotionOption.options, hasLength(8));
      expect(EventEmotionOption.byKey('other')?.label, '기타');
      expect(EventEmotionOption.byKey('gratitude')?.emoji, '♥');
      expect(EventEmotionOption.byKey('comfort')?.emoji, '🌿');
      expect(EventEmotionOption.byKey('fear')?.emoji, '⚡');
    });

    test('fromMap은 Supabase row를 모델로 변환한다', () {
      final mark = EventEmotionMark.fromMap({
        'event_id': 'event-1',
        'emotion_key': 'joy',
        'emotion_label': '기쁨',
        'emotion_emoji': '😊',
        'note': '기쁨이 남았다.',
        'updated_at': '2026-05-25T12:00:00Z',
      });

      expect(mark.eventId, 'event-1');
      expect(mark.emotionLabel, '기쁨');
      expect(mark.emotionEmoji, '✨');
      expect(
        mark.updatedAt?.toUtc().toIso8601String(),
        '2026-05-25T12:00:00.000Z',
      );
    });

    test('toMap은 updated_at을 UTC ISO 문자열로 만든다', () {
      final mark = EventEmotionMark(
        eventId: 'event-1',
        emotionKey: 'comfort',
        emotionLabel: '위로',
        emotionEmoji: '🌿',
        note: '위로가 남았다.',
        updatedAt: DateTime.parse('2026-05-26T09:30:00+09:00'),
      );

      final map = mark.toMap(userId: 'user-1');

      expect(map['user_id'], 'user-1');
      expect(map['event_id'], 'event-1');
      expect(map['emotion_key'], 'comfort');
      expect(map['note'], '위로가 남았다.');
      expect(map['updated_at'], '2026-05-26T00:30:00.000Z');
    });
  });
}
