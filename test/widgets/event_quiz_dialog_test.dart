import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/quiz_question.dart';
import 'package:story_bible/widgets/event_quiz_dialog.dart';

void main() {
  group('EventQuizDialog', () {
    testWidgets('문항마다 정답 확인 후 해설을 보고 다음 문항으로 이동한다', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _QuizDialogHost()));

      await tester.tap(find.text('퀴즈 시작'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('바다가 갈라진 사건을 기억해요.'), findsNothing);
      expect(find.text('다음'), findsNothing);

      await tester.tap(find.text('비가 멈춤'));
      await tester.pump();
      expect(find.text('정답 확인'), findsOneWidget);

      await tester.tap(find.text('정답 확인'));
      await tester.pumpAndSettle();

      expect(find.text('오답이에요'), findsOneWidget);
      expect(find.text('정답: 2번 물이 갈라짐'), findsOneWidget);
      expect(find.text('바다가 갈라진 사건을 기억해요.'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('누가 이스라엘 백성을 이끌었나요?'), findsOneWidget);
      expect(find.text('바다가 갈라진 사건을 기억해요.'), findsNothing);

      await tester.tap(find.text('모세'));
      await tester.pump();
      await tester.tap(find.text('정답 확인'));
      await tester.pumpAndSettle();

      expect(find.text('정답입니다!'), findsOneWidget);
      expect(find.text('모세가 백성을 이끌었어요.'), findsOneWidget);
      expect(find.text('결과 보기'), findsOneWidget);

      await tester.tap(find.text('결과 보기'));
      await tester.pumpAndSettle();

      expect(find.text('결과 확인'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Q2'), findsOneWidget);
      expect(find.text('바다가 갈라진 사건을 기억해요.'), findsOneWidget);
      expect(find.text('모세가 백성을 이끌었어요.'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('저장: 1/2/0'), findsOneWidget);
    });
  });
}

class _QuizDialogHost extends StatefulWidget {
  const _QuizDialogHost();

  @override
  State<_QuizDialogHost> createState() => _QuizDialogHostState();
}

class _QuizDialogHostState extends State<_QuizDialogHost> {
  EventQuizResult? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                final result = await showDialog<EventQuizResult>(
                  context: context,
                  builder: (_) => const EventQuizDialog(
                    title: '홍해를 건너다',
                    questions: _questions,
                  ),
                );
                if (!mounted || result == null) {
                  return;
                }
                setState(() => _result = result);
              },
              child: const Text('퀴즈 시작'),
            ),
            if (_result != null)
              Text(
                '저장: ${_result!.score}/${_result!.selectedAnswers.length}/${_result!.confusedCount}',
              ),
          ],
        ),
      ),
    );
  }
}

const _questions = [
  QuizQuestion(
    id: 'q1',
    question: '홍해에서 어떤 일이 일어났나요?',
    choices: ['비가 멈춤', '물이 갈라짐', QuizQuestion.confusedChoiceLabel],
    answerIndex: 1,
    explanation: '바다가 갈라진 사건을 기억해요.',
    displayOrder: 1,
  ),
  QuizQuestion(
    id: 'q2',
    question: '누가 이스라엘 백성을 이끌었나요?',
    choices: ['모세', '요나', QuizQuestion.confusedChoiceLabel],
    answerIndex: 0,
    explanation: '모세가 백성을 이끌었어요.',
    displayOrder: 2,
  ),
];
