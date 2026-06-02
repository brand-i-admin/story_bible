import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/daily_quiz.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/quiz/daily_quiz_section.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

void main() {
  group('DailyQuizSection', () {
    late _MockStoryRepository storyRepository;

    setUp(() {
      storyRepository = _MockStoryRepository();
      when(
        () => storyRepository.fetchLatestDailyQuiz(),
      ).thenAnswer((_) async => _dailyQuiz());
    });

    testWidgets('비로그인 상태에서는 선택지를 고르면 로그인 유도를 요청한다', (tester) async {
      var loginPromptCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(null),
            storyRepositoryProvider.overrideWithValue(storyRepository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DailyQuizSection(
                onLoginRequired: (_) {
                  loginPromptCount += 1;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('첫째 보기'));
      await tester.pump();

      expect(loginPromptCount, 1);
      expect(find.text('정답입니다!'), findsNothing);
      expect(find.text('아쉬워요'), findsNothing);
    });
  });
}

DailyQuiz _dailyQuiz() {
  return DailyQuiz(
    id: 'daily-1',
    question: '오늘의 질문은 무엇인가요?',
    choices: const ['첫째 보기', '둘째 보기'],
    answerIndex: 1,
    explanation: '테스트 해설입니다.',
    createdAt: DateTime.parse('2026-06-02T00:00:00Z'),
  );
}
