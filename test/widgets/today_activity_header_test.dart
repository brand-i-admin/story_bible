import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/utils/today_activity_summary.dart';
import 'package:story_bible/widgets/home/today_activity_header.dart';

void main() {
  testWidgets('오늘 인사와 KST 일일 활동 라벨을 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TodayActivityHeader(nickname: '기도친구'),
              TodayActivityLabelRail(
                summary: TodayActivitySummary(
                  streakDays: 5,
                  explorationCount: 3,
                  hasDiary: true,
                  bibleChapterCount: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('오늘'), findsNothing);
    expect(find.byIcon(Icons.wb_sunny_rounded), findsNothing);
    expect(find.text('샬롬 👋 기도친구님,'), findsOneWidget);
    expect(find.text('오늘도 주님과 함께 걸어볼까요!'), findsOneWidget);
    expect(find.text('🔥 연속: 5일'), findsOneWidget);
    expect(find.text('🧭 탐험 3개'), findsOneWidget);
    expect(find.text('📝 다이어리 o'), findsOneWidget);
    expect(find.text('📖 통독 4장'), findsOneWidget);

    final headerRect = tester.getRect(
      find.byKey(const ValueKey('today-activity-header')),
    );
    for (final label in ['🔥 연속: 5일', '🧭 탐험 3개', '📝 다이어리 o', '📖 통독 4장']) {
      final labelRect = tester.getRect(find.text(label));
      expect(labelRect.left, greaterThanOrEqualTo(headerRect.left));
      expect(labelRect.right, lessThanOrEqualTo(headerRect.right));
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('today-activity-header')),
        matching: find.byKey(const ValueKey('today-activity-label-rail')),
      ),
      findsNothing,
    );

    final greeting = tester.widget<Text>(
      find.byKey(const ValueKey('today-activity-greeting-line')),
    );
    final greetingSpan = greeting.textSpan! as TextSpan;
    final nicknameSpan = greetingSpan.children![1] as TextSpan;
    final leadSpan = greetingSpan.children!.first as TextSpan;
    final invitation = tester.widget<Text>(
      find.byKey(const ValueKey('today-activity-invitation-line')),
    );
    expect(leadSpan.style!.fontSize, greaterThan(invitation.style!.fontSize!));
    expect(
      nicknameSpan.style!.fontSize,
      greaterThan(leadSpan.style!.fontSize!),
    );

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('today-activity-header')),
    );
    expect(header.color, AppColors.parchmentLight);
    expect(header.decoration, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('🔥 연속: 5일'));
    await tester.pumpAndSettle();

    expect(find.text('연속일은 이렇게 계산해요'), findsOneWidget);
    expect(find.text('탐험 완료 조건: 감정 새기기'), findsOneWidget);
    expect(find.text('다이어리 완료 조건: 작성 완료'), findsOneWidget);
    expect(find.text('통독 완료 조건: 1장 이상 읽음 처리'), findsOneWidget);
    expect(find.text('세 가지 중 1개 이상 완료한 날이 연속일에 카운팅됩니다.'), findsOneWidget);
  });

  testWidgets('비로그인 기본 이름과 초기화된 일일 활동을 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TodayActivityHeader(nickname: ''),
              TodayActivityLabelRail(summary: TodayActivitySummary.empty),
            ],
          ),
        ),
      ),
    );

    expect(find.text('샬롬 👋 사용자님,'), findsOneWidget);
    expect(find.text('오늘도 주님과 함께 걸어볼까요!'), findsOneWidget);
    expect(find.text('🔥 연속: 0일'), findsOneWidget);
    expect(find.text('🧭 탐험 0개'), findsOneWidget);
    expect(find.text('📝 다이어리 x'), findsOneWidget);
    expect(find.text('📖 통독 0장'), findsOneWidget);
  });
}
