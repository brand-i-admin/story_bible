import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/screens/companion_diary_editor_screen.dart';
import 'package:story_bible/theme/app_theme.dart';

void main() {
  testWidgets('신앙 다이어리는 말씀 연결 없이 새 페이지에서 작성한다', (tester) async {
    CompanionDiaryDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await openCompanionDiaryEditorPage(
                    context,
                    entryDate: DateTime(2026, 7, 14),
                  );
                },
                child: const Text('작성'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('작성'));
    await tester.pumpAndSettle();

    expect(find.text('다이어리 작성'), findsOneWidget);
    expect(find.text('2026년 7월 14일 화요일'), findsOneWidget);
    expect(find.text('제목 (선택)'), findsOneWidget);
    expect(find.text('기록을 돕는 질문'), findsOneWidget);
    expect(find.text('오늘 감사한 일'), findsOneWidget);
    expect(find.text('기도한 내용'), findsOneWidget);
    expect(find.text('말씀을 통해 떠오른 생각'), findsOneWidget);
    expect(find.text('오늘의 하루 돌아보기'), findsOneWidget);
    expect(find.text('오늘의 말씀 연결'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('이 다이어리는 나만 볼 수 있어요.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('companion-diary-body-field')),
      '하나님과 함께한 순간을 기록합니다.',
    );
    await tester.pump();
    await tester.tap(find.text('기록 저장'));
    await tester.pumpAndSettle();

    expect(result?.title, '제목 없는 다이어리');
    expect(result?.body, '하나님과 함께한 순간을 기록합니다.');
  });
}
