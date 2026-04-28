import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_proposal.dart';
import 'package:story_bible/widgets/proposal/proposal_quiz_editor.dart';

/// 퀴즈 카드 3장이 들어가도 overflow 가 안 나도록 surface 를 크게 잡는다.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1200, 4000));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('ProposalQuizEditor', () {
    testWidgets('초기 비어있으면 기본 빈 퀴즈 1개가 렌더링된다', (tester) async {
      await _pump(
        tester,
        ProposalQuizEditor(initial: const [], onChanged: (_) {}),
      );

      expect(find.text('퀴즈 1'), findsOneWidget);
      expect(find.text('퀴즈 2'), findsNothing);
    });

    testWidgets('퀴즈 추가 버튼을 누르면 최대 3개까지 늘어난다', (tester) async {
      await _pump(
        tester,
        ProposalQuizEditor(initial: const [], onChanged: (_) {}),
      );

      Future<void> tapAdd() async {
        await tester.tap(find.textContaining('퀴즈 추가'));
        await tester.pump();
      }

      await tapAdd();
      expect(find.text('퀴즈 2'), findsOneWidget);

      await tapAdd();
      expect(find.text('퀴즈 3'), findsOneWidget);

      // 3개 도달 시 추가 버튼이 사라진다.
      expect(find.textContaining('퀴즈 추가'), findsNothing);
    });

    testWidgets('퀴즈 1개만 남을 때는 삭제 아이콘이 안 보인다', (tester) async {
      await _pump(
        tester,
        ProposalQuizEditor(initial: const [], onChanged: (_) {}),
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('2개 이상일 때 삭제 아이콘이 나오고 클릭 시 개수가 줄어든다', (tester) async {
      await _pump(
        tester,
        ProposalQuizEditor(
          initial: const [QuizDraft.empty, QuizDraft.empty],
          onChanged: (_) {},
        ),
      );
      expect(find.text('퀴즈 2'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();

      expect(find.text('퀴즈 2'), findsNothing);
    });

    testWidgets('초기 퀴즈 데이터를 편집기에 반영한다', (tester) async {
      final initial = [
        const QuizDraft(
          question: '첫 번째 문제',
          choices: ['가', '나', '다', '라'],
          answerIndex: 2,
          explanation: '해설-X',
        ),
      ];
      await _pump(
        tester,
        ProposalQuizEditor(initial: initial, onChanged: (_) {}),
      );

      expect(find.text('첫 번째 문제'), findsOneWidget);
      expect(find.text('해설-X'), findsOneWidget);
    });

    testWidgets('onChanged 는 편집 시마다 호출되고 최신 drafts 를 방출한다', (tester) async {
      final events = <List<QuizDraft>>[];
      await _pump(
        tester,
        ProposalQuizEditor(
          initial: const [QuizDraft.empty],
          onChanged: (v) => events.add(v),
        ),
      );

      await tester.tap(find.textContaining('퀴즈 추가'));
      await tester.pump();

      expect(events.isNotEmpty, isTrue);
      expect(events.last.length, 2);
    });
  });
}
