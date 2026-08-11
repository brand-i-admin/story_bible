import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/utils/today_activity_summary.dart';
import 'package:story_bible/widgets/home/story_root_navigation_bar.dart';
import 'package:story_bible/widgets/home/today_activity_header.dart';

void main() {
  testWidgets('오늘 인사와 KST 일일 활동 라벨을 분리해 표시한다', (tester) async {
    final dialogVisibilityChanges = <bool>[];
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TodayActivityHeader(nickname: '기도친구'),
              TodayActivityLabelRail(
                summary: const TodayActivitySummary(
                  streakDays: 5,
                  explorationCount: 3,
                  hasDiary: true,
                  bibleChapterCount: 4,
                ),
                onStreakDialogVisibilityChanged: dialogVisibilityChanges.add,
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
    expect(find.text('연속: 5일'), findsOneWidget);
    expect(find.text('이야기: 3개'), findsOneWidget);
    expect(find.text('다이어리: o'), findsOneWidget);
    expect(find.text('통독: 4장'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today-streak-fire-celebration')),
      findsOneWidget,
    );
    final fadedStreakContent = tester.widget<Opacity>(
      find.byKey(const ValueKey('today-streak-label-content')),
    );
    expect(fadedStreakContent.opacity, lessThanOrEqualTo(0.2));
    final activeFire = tester.widget<Icon>(
      find.byKey(const ValueKey('today-streak-fire-icon')),
    );
    expect(activeFire.size, greaterThanOrEqualTo(27));
    final glow = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('today-streak-fire-glow')),
    );
    final glowDecoration = glow.decoration as BoxDecoration;
    expect(glowDecoration.boxShadow, isNotEmpty);
    for (var index = 0; index < 4; index++) {
      expect(
        find.byKey(ValueKey('today-streak-fire-sparkle-$index')),
        findsOneWidget,
      );
    }
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNWidgets(4));
    final initialSparkleOpacity = tester
        .widget<Opacity>(
          find.byKey(const ValueKey('today-streak-fire-sparkle-0')),
        )
        .opacity;

    await tester.pump(const Duration(milliseconds: 600));
    final scaledFire = tester.widget<Transform>(
      find.byKey(const ValueKey('today-streak-fire-scale')),
    );
    expect(scaledFire.transform.getMaxScaleOnAxis(), greaterThan(1.13));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('today-streak-fire-sparkle-0')),
          )
          .opacity,
      isNot(initialSparkleOpacity),
    );
    expect(
      find.byKey(const ValueKey('today-story-completion-mark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('today-diary-completion-mark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('today-bible-completion-mark')),
      findsOneWidget,
    );

    final railRect = tester.getRect(
      find.byKey(const ValueKey('today-activity-label-rail')),
    );
    for (final label in ['연속: 5일', '이야기: 3개', '다이어리: o', '통독: 4장']) {
      final labelRect = tester.getRect(find.text(label));
      expect(labelRect.left, greaterThanOrEqualTo(railRect.left));
      expect(labelRect.right, lessThanOrEqualTo(railRect.right));
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
    expect(leadSpan.style!.fontSize, invitation.style!.fontSize);
    expect(
      nicknameSpan.style!.fontSize,
      greaterThan(invitation.style!.fontSize!),
    );

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('today-activity-header')),
    );
    expect(
      header.color,
      storyRootNavigationSurfaceColor(AppColorPalette.classic),
    );
    expect(header.decoration, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.ancestor(of: find.text('연속: 5일'), matching: find.byType(InkWell)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(dialogVisibilityChanges, [true]);
    expect(find.text('연속일은 이렇게 계산해요'), findsOneWidget);
    expect(find.text('탐험 완료 조건: 감정 새기기'), findsOneWidget);
    expect(find.text('다이어리 완료 조건: 작성 완료'), findsOneWidget);
    expect(find.text('통독 완료 조건: 1장 이상 읽음 처리'), findsOneWidget);
    expect(find.text('세 가지 중 1개 이상 완료한 날이 연속일에 카운팅됩니다.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(dialogVisibilityChanges, [true, false]);
  });

  testWidgets('연속 반짝임은 밝은 팔레트에서 진한 역할색, 다크에서 금빛을 사용한다', (tester) async {
    Future<Color?> sparkleColorFor(AppColorPalette palette) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppPaletteTheme(palette)]),
          home: const Scaffold(
            body: TodayActivityLabelRail(
              summary: TodayActivitySummary(
                streakDays: 5,
                explorationCount: 1,
                hasDiary: false,
                bibleChapterCount: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final firstSparkle = find.descendant(
        of: find.byKey(const ValueKey('today-streak-fire-sparkle-0')),
        matching: find.byIcon(Icons.auto_awesome_rounded),
      );
      return tester.widget<Icon>(firstSparkle).color;
    }

    for (final palette in AppColorPalette.values.where(
      (palette) => palette != AppColorPalette.blackMap,
    )) {
      expect(await sparkleColorFor(palette), palette.primaryDeep);
    }
    expect(await sparkleColorFor(AppColorPalette.blackMap), AppColors.goldHi);
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
    expect(find.text('연속: 0일'), findsOneWidget);
    expect(find.text('이야기: 0개'), findsOneWidget);
    expect(find.text('다이어리: x'), findsOneWidget);
    expect(find.text('통독: 0장'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today-streak-fire-celebration')),
      findsNothing,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });
}
