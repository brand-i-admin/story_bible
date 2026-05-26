import '../../models/quiz_attempt_summary.dart';

class ProfileQuizStats {
  const ProfileQuizStats({
    required this.correct,
    required this.wrong,
    required this.confused,
    required this.correctEventIds,
    required this.wrongEventIds,
    required this.confusedEventIds,
  });

  final int correct;
  final int wrong;
  final int confused;
  final Set<String> correctEventIds;
  final Set<String> wrongEventIds;
  final Set<String> confusedEventIds;

  int get total => correct + wrong + confused;

  int percentFor(int value) {
    if (total == 0) {
      return 0;
    }
    return ((value / total) * 100).round();
  }
}

ProfileQuizStats buildProfileQuizStats(
  Map<String, QuizAttemptSummary> summaries,
) {
  var correct = 0;
  var wrong = 0;
  var confused = 0;
  final correctIds = <String>{};
  final wrongIds = <String>{};
  final confusedIds = <String>{};

  for (final entry in summaries.entries) {
    final attempt = entry.value;
    if (attempt.totalCount <= 0) {
      continue;
    }

    final correctCount = _nonNegative(attempt.correctCount);
    final wrongCount = _nonNegative(attempt.wrongCount);
    final confusedCount = _nonNegative(attempt.confusedCount);

    correct += correctCount;
    wrong += wrongCount;
    confused += confusedCount;

    if (correctCount > 0) {
      correctIds.add(entry.key);
    }
    if (wrongCount > 0) {
      wrongIds.add(entry.key);
    }
    if (confusedCount > 0) {
      confusedIds.add(entry.key);
    }
  }

  return ProfileQuizStats(
    correct: correct,
    wrong: wrong,
    confused: confused,
    correctEventIds: correctIds,
    wrongEventIds: wrongIds,
    confusedEventIds: confusedIds,
  );
}

int _nonNegative(int value) => value < 0 ? 0 : value;
