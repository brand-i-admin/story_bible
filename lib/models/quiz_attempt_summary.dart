class QuizAttemptSummary {
  const QuizAttemptSummary({
    required this.eventId,
    required this.correctCount,
    required this.totalCount,
    required this.wrongCount,
    required this.confusedCount,
    required this.selectedAnswers,
    required this.updatedAt,
  });

  final String eventId;
  final int correctCount;
  final int totalCount;
  final int wrongCount;
  final int confusedCount;
  final List<int?> selectedAnswers;
  final DateTime? updatedAt;

  bool get needsReview =>
      totalCount > 0 && (wrongCount > 0 || confusedCount > 0);

  Map<String, dynamic> toMap({required String userId}) {
    final timestamp = (updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    return {
      'user_id': userId,
      'event_id': eventId,
      'correct_count': correctCount,
      'total_count': totalCount,
      'wrong_count': wrongCount,
      'confused_count': confusedCount,
      'selected_answers': selectedAnswers,
      'updated_at': timestamp,
    };
  }

  factory QuizAttemptSummary.fromMap(Map<String, dynamic> map) {
    final rawAnswers = map['selected_answers'];
    final selectedAnswers = rawAnswers is List
        ? rawAnswers
              .map<int?>((value) => value is num ? value.toInt() : null)
              .toList(growable: false)
        : const <int?>[];
    final updatedAtText = map['updated_at'] as String?;
    return QuizAttemptSummary(
      eventId: map['event_id'] as String,
      correctCount: (map['correct_count'] as num?)?.toInt() ?? 0,
      totalCount: (map['total_count'] as num?)?.toInt() ?? 0,
      wrongCount: (map['wrong_count'] as num?)?.toInt() ?? 0,
      confusedCount: (map['confused_count'] as num?)?.toInt() ?? 0,
      selectedAnswers: selectedAnswers,
      updatedAt: updatedAtText == null
          ? null
          : DateTime.tryParse(updatedAtText),
    );
  }
}
