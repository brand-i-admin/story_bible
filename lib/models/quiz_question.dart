class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
    required this.displayOrder,
  });

  final String id;
  final String question;
  final List<String> choices;
  final int answerIndex;
  final String? explanation;
  final int displayOrder;
}
