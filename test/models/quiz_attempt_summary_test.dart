import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/quiz_attempt_summary.dart';

void main() {
  group('QuizAttemptSummary', () {
    test('오답이나 헷갈림이 있으면 복습 대상이다', () {
      const attempt = QuizAttemptSummary(
        eventId: 'event-1',
        correctCount: 2,
        totalCount: 3,
        wrongCount: 0,
        confusedCount: 1,
        selectedAnswers: [0, 3, 1],
        updatedAt: null,
      );

      expect(attempt.needsReview, isTrue);
    });

    test('모두 맞히면 복습 대상이 아니다', () {
      const attempt = QuizAttemptSummary(
        eventId: 'event-1',
        correctCount: 3,
        totalCount: 3,
        wrongCount: 0,
        confusedCount: 0,
        selectedAnswers: [0, 1, 2],
        updatedAt: null,
      );

      expect(attempt.needsReview, isFalse);
    });

    test('fromMap은 Supabase row를 모델로 변환한다', () {
      final attempt = QuizAttemptSummary.fromMap({
        'event_id': 'event-1',
        'correct_count': 1,
        'total_count': 3,
        'wrong_count': 1,
        'confused_count': 1,
        'selected_answers': [0, 2, null],
        'updated_at': '2026-05-25T12:00:00Z',
      });

      expect(attempt.eventId, 'event-1');
      expect(attempt.selectedAnswers, [0, 2, null]);
      expect(
        attempt.updatedAt?.toUtc().toIso8601String(),
        '2026-05-25T12:00:00.000Z',
      );
    });

    test('toMap은 updated_at을 UTC ISO 문자열로 만든다', () {
      final attempt = QuizAttemptSummary(
        eventId: 'event-1',
        correctCount: 2,
        totalCount: 3,
        wrongCount: 1,
        confusedCount: 0,
        selectedAnswers: const [0, 1, null],
        updatedAt: DateTime.parse('2026-05-26T23:10:00+09:00'),
      );

      final map = attempt.toMap(userId: 'user-1');

      expect(map['user_id'], 'user-1');
      expect(map['event_id'], 'event-1');
      expect(map['updated_at'], '2026-05-26T14:10:00.000Z');
    });
  });
}
