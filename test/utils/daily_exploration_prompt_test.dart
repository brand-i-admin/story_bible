import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/utils/daily_exploration_prompt.dart';

void main() {
  group('dailyExplorationCardNoteFor', () {
    test('감정 기록이 없으면 문구를 표시하지 않는다', () {
      final note = dailyExplorationCardNoteFor(
        mark: null,
        now: DateTime.parse('2026-06-23T01:00:00Z'),
      );

      expect(note, isNull);
    });

    test('KST 기준 오늘 새긴 감정이면 축복 문구를 표시한다', () {
      final note = dailyExplorationCardNoteFor(
        mark: _mark(updatedAt: DateTime.parse('2026-06-22T16:30:00Z')),
        now: DateTime.parse('2026-06-23T01:00:00Z'),
      );

      expect(note?.kind, DailyExplorationCardNoteKind.blessing);
      expect(note?.message, dailyExplorationBlessingMessage);
    });

    test('이전 날짜 감정이면 재탐험 문구를 표시한다', () {
      final note = dailyExplorationCardNoteFor(
        mark: _mark(updatedAt: DateTime.parse('2026-06-21T16:30:00Z')),
        now: DateTime.parse('2026-06-23T01:00:00Z'),
      );

      expect(note?.kind, DailyExplorationCardNoteKind.revisit);
      expect(note?.message, dailyExplorationRevisitMessage);
    });
  });
}

EventEmotionMark _mark({required DateTime updatedAt}) {
  return EventEmotionMark(
    eventId: 'event_1',
    emotionKey: 'joy',
    emotionLabel: '기쁨',
    emotionEmoji: '🌟',
    note: '',
    updatedAt: updatedAt,
  );
}
