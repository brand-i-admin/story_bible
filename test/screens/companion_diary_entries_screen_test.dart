import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/screens/companion_diary_entries_screen.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/widgets/profile/companion_diary_entry_card.dart';

void main() {
  testWidgets('신앙 다이어리 목록은 이번 달 기록일과 연속일, 전체·이번달 필터를 보여준다', (tester) async {
    final entries = [
      _entry('july-14', DateTime(2026, 7, 14), '7월 14일 기록'),
      _entry('july-13', DateTime(2026, 7, 13), '7월 13일 기록'),
      _entry('july-12', DateTime(2026, 7, 12), '7월 12일 기록'),
      _entry('june-30', DateTime(2026, 6, 30), '6월 기록'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CompanionDiaryEntriesScreen(
          entries: entries,
          now: DateTime(2026, 7, 14),
        ),
      ),
    );

    expect(find.text('이번 달'), findsWidgets);
    expect(find.text('3일 기록'), findsOneWidget);
    expect(find.text('연속'), findsOneWidget);
    expect(find.text('3일'), findsOneWidget);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('최근'), findsNothing);
    expect(find.text('북마크'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.scrollUntilVisible(find.text('6월 기록'), 200);
    expect(find.text('6월 기록'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('companion-diary-filter-this-month')),
      -200,
    );

    await tester.tap(
      find.byKey(const ValueKey('companion-diary-filter-this-month')),
    );
    await tester.pumpAndSettle();

    expect(find.text('7월 14일 기록'), findsOneWidget);
    expect(find.text('7월 13일 기록'), findsOneWidget);
    expect(find.text('7월 12일 기록'), findsOneWidget);
    expect(find.text('6월 기록'), findsNothing);
  });

  testWidgets('날짜와 KST 시간을 카드 안 제목 오른쪽에 표시한다', (tester) async {
    final entry = UserCompanionDiaryEntry(
      id: 'kst-entry',
      userId: 'user-1',
      entryDate: DateTime(2026, 7, 14),
      title: '새벽 기도',
      body: '기도 내용',
      createdAt: DateTime.utc(2026, 7, 14, 16, 30),
      updatedAt: DateTime.utc(2026, 7, 14, 16, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CompanionDiaryEntriesScreen(
          entries: [entry],
          now: DateTime.utc(2026, 7, 15),
        ),
      ),
    );

    final card = find.byType(CompanionDiaryEntryPreviewCard);
    final timestamp = find.text('7월 14일 화요일 · 오전 1:30');
    expect(timestamp, findsOneWidget);
    expect(find.ancestor(of: timestamp, matching: card), findsOneWidget);
    expect(
      (tester.getCenter(timestamp).dy - tester.getCenter(find.text('새벽 기도')).dy)
          .abs(),
      lessThan(12),
    );
  });
}

UserCompanionDiaryEntry _entry(String id, DateTime date, String title) {
  return UserCompanionDiaryEntry(
    id: id,
    userId: 'user-1',
    entryDate: date,
    title: title,
    body: '$title 본문입니다.',
    createdAt: date,
    updatedAt: date,
  );
}
