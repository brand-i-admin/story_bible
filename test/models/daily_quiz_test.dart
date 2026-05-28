import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/daily_quiz.dart';

void main() {
  group('DailyQuiz.fromMap', () {
    test('가변 선택지 jsonb 배열을 파싱한다', () {
      final quiz = DailyQuiz.fromMap({
        'id': 'daily-1',
        'question': '포로 및 포로 후기 시대에서 페르시아 지역 사건은?',
        'choices': ['에스더: 왕후가 되다', '성벽 재건: 밤의 조사와 한 손엔 무기', '마른 뼈: 숨이 들어오다'],
        'answer_index': 1,
        'explanation': '페르시아 지역에서 볼 수 있는 사건입니다.',
        'created_at': '2026-05-27T00:00:00Z',
      });

      expect(quiz.choices, hasLength(3));
      expect(quiz.answerIndex, 1);
      expect(quiz.isCorrect(0), isTrue);
      expect(quiz.isCorrect(1), isFalse);
    });
  });
}
