/// 매일 퀴즈 한 문제. 4지선다 + 정답 + 해설.
class DailyQuiz {
  const DailyQuiz({
    required this.id,
    required this.question,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
    required this.createdAt,
  });

  final String id;
  final String question;

  /// 선택지 4개. 사용자에게 1..4 번으로 표시되지만 List index 는 0-based.
  final List<String> choices;

  /// 1-based 정답 번호 (DB 의 answer_index 와 동일).
  final int answerIndex;

  final String explanation;
  final DateTime createdAt;

  /// 0-based index 로 비교하기 위한 헬퍼.
  bool isCorrect(int selectedIndex0) => selectedIndex0 + 1 == answerIndex;

  factory DailyQuiz.fromMap(Map<String, dynamic> row) {
    return DailyQuiz(
      id: row['id'] as String,
      question: row['question'] as String,
      choices: [
        row['choice_1'] as String,
        row['choice_2'] as String,
        row['choice_3'] as String,
        row['choice_4'] as String,
      ],
      answerIndex: (row['answer_index'] as num).toInt(),
      explanation: row['explanation'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
