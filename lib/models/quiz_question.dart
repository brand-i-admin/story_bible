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

  static const confusedChoiceLabel = '헷갈렸어요';

  bool isConfusedChoiceIndex(int? index) {
    if (index == null || index < 0 || index >= choices.length) {
      return false;
    }
    return choices[index].trim() == confusedChoiceLabel;
  }
}
