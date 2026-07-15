import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/screens/bible_progress_screen.dart';
import 'package:story_bible/theme/app_theme.dart';

void main() {
  testWidgets('통독 진행률은 팝업이 아닌 페이지에서 권별 장 표를 보여준다', (tester) async {
    int? openedBookNo;
    int? openedChapterNo;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BibleProgressScreen(
          completedChapterKeys: const {'43:3'},
          initialBookNo: 43,
          onOpenChapter: ({required bookNo, required chapterNo}) async {
            openedBookNo = bookNo;
            openedChapterNo = chapterNo;
          },
        ),
      ),
    );

    expect(find.text('통독 진행률'), findsOneWidget);
    expect(find.text('신약'), findsOneWidget);
    expect(find.text('요한복음'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bible-progress-chapter-21')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byKey(const ValueKey('bible-progress-chapter-2')));
    await tester.pumpAndSettle();

    expect(openedBookNo, 43);
    expect(openedChapterNo, 2);
  });
}
