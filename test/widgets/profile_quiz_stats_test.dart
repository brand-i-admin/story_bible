import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/quiz_attempt_summary.dart';
import 'package:story_bible/widgets/profile/profile_quiz_stats.dart';

QuizAttemptSummary _attempt({
  required String eventId,
  required int correct,
  required int wrong,
  required int confused,
}) {
  return QuizAttemptSummary(
    eventId: eventId,
    correctCount: correct,
    totalCount: correct + wrong + confused,
    wrongCount: wrong,
    confusedCount: confused,
    selectedAnswers: const [],
    updatedAt: null,
  );
}

void main() {
  group('buildProfileQuizStats', () {
    test('이야기 개수가 아니라 각 퀴즈 문항 결과를 누적한다', () {
      final stats = buildProfileQuizStats({
        'event-1': _attempt(
          eventId: 'event-1',
          correct: 2,
          wrong: 1,
          confused: 0,
        ),
        'event-2': _attempt(
          eventId: 'event-2',
          correct: 1,
          wrong: 0,
          confused: 2,
        ),
      });

      expect(stats.correct, 3);
      expect(stats.wrong, 1);
      expect(stats.confused, 2);
      expect(stats.total, 6);
      expect(stats.correctEventCount, 2);
      expect(stats.wrongEventCount, 1);
      expect(stats.confusedEventCount, 1);
      expect(stats.percentFor(stats.correct), 50);
    });

    test('오답과 헷갈림이 함께 있으면 양쪽 복습 목록에 같은 이야기를 포함한다', () {
      final stats = buildProfileQuizStats({
        'event-1': _attempt(
          eventId: 'event-1',
          correct: 1,
          wrong: 1,
          confused: 1,
        ),
      });

      expect(stats.wrongEventIds, {'event-1'});
      expect(stats.confusedEventIds, {'event-1'});
    });

    test('퀴즈와 이야기 개수를 함께 표시할 라벨을 만든다', () {
      expect(profileQuizCountLabel(quizCount: 6, storyCount: 2), '6문항 · 2이야기');
    });
  });
}
