import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/home/today_activity_header.dart';
import 'package:story_bible/widgets/home/today_home_page.dart';
import 'package:story_bible/widgets/v2/map_hint_overlay.dart';

void main() {
  testWidgets('오늘 할 일 가이드는 팔레트 패널과 지도 닫기 배지에 헤더 역할색을 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final palette in AppColorPalette.values) {
      final isDark = palette == AppColorPalette.blackMap;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(palette),
          theme: ThemeData(extensions: [AppPaletteTheme(palette)]),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(body: TodayTodoGuide()),
          ),
        ),
      );

      final guide = find.byKey(const ValueKey('today-todo-guide'));
      final content = find.byKey(const ValueKey('today-todo-guide-content'));
      expect(guide, findsOneWidget);
      expect(content, findsOneWidget);
      expect(find.byType(MapHintDismissBadge), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-guide-dismiss-badge')),
        findsOneWidget,
      );
      expect(find.text('화면 아무데나 누르면 사라집니다'), findsOneWidget);
      expect(find.text('매일 할 일:'), findsOneWidget);
      expect(find.text('이야기'), findsOneWidget);
      expect(find.text('다이어리'), findsOneWidget);
      expect(find.text('통독'), findsOneWidget);
      final reorderNote = find.text('(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)');
      expect(reorderNote, findsOneWidget);
      expect(tester.widget<Text>(reorderNote).textAlign, TextAlign.center);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byIcon(TodayActivityIcons.streak), findsOneWidget);
      expect(find.byIcon(TodayActivityIcons.story), findsOneWidget);
      expect(find.byIcon(TodayActivityIcons.diary), findsOneWidget);
      expect(find.byIcon(TodayActivityIcons.bible), findsOneWidget);

      for (final entry in <IconData, Color>{
        Icons.hourglass_top_rounded: Colors.white,
        TodayActivityIcons.streak: palette.currentAccentDeep,
        TodayActivityIcons.story: palette.regionAccent,
        TodayActivityIcons.diary: palette.successBottom,
        TodayActivityIcons.bible: palette.primary,
      }.entries) {
        expect(tester.widget<Icon>(find.byIcon(entry.key)).color, entry.value);
      }

      for (final entry in <String, Color>{
        '화면 아무데나 누르면 사라집니다': Colors.white,
        '매일 할 일:': isDark ? palette.text : AppColors.ink900,
        '이야기': palette.regionAccent,
        '다이어리': palette.successBottom,
        '통독': palette.primary,
        '(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)': isDark
            ? palette.mutedText
            : AppColors.ink500,
      }.entries) {
        expect(
          tester.widget<Text>(find.text(entry.key)).style?.color,
          entry.value,
        );
      }

      final guideContainer = tester.widget<Container>(guide);
      final guideDecoration = guideContainer.decoration! as BoxDecoration;
      expect(
        guideDecoration.color,
        Color.alphaBlend(
          palette.characterAccent.withValues(alpha: 0.28),
          palette.utilityBackground,
        ).withValues(alpha: 0.68),
      );

      final contentContainer = tester.widget<Container>(content);
      final contentDecoration = contentContainer.decoration! as BoxDecoration;
      final expectedContentColor = isDark
          ? Color.alphaBlend(
              palette.primary.withValues(alpha: 0.06),
              palette.cardSurface,
            ).withValues(alpha: 0.88)
          : Color.alphaBlend(
              palette.currentAccent.withValues(alpha: 0.035),
              AppColors.parchmentLight,
            ).withValues(alpha: 0.84);
      expect(contentDecoration.color, expectedContentColor);
      expect(guideDecoration.color!.a, closeTo(0.68, 0.001));
      expect(contentDecoration.color!.a, closeTo(isDark ? 0.88 : 0.84, 0.001));
      if (isDark) {
        expect(expectedContentColor.computeLuminance(), lessThan(0.1));
      } else {
        expect(
          expectedContentColor.computeLuminance(),
          greaterThan(guideDecoration.color!.computeLuminance()),
        );
      }
      final dismissBadge = find.byKey(
        const ValueKey('today-guide-dismiss-badge'),
      );
      final guideTop = tester.getTopLeft(guide).dy;
      final guideBottom = tester.getBottomLeft(guide).dy;
      final badgeTop = tester.getTopLeft(dismissBadge).dy;
      final badgeBottom = tester.getBottomLeft(dismissBadge).dy;
      final visibleTop = badgeTop < guideTop ? badgeTop : guideTop;
      final visibleBottom = badgeBottom > guideBottom
          ? badgeBottom
          : guideBottom;
      expect(
        (visibleTop + visibleBottom) / 2,
        closeTo(tester.getCenter(find.byType(TodayTodoGuide)).dy, 1),
      );
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  test('오늘 가이드는 헤더 하단과 시대 라벨 상단의 정중앙을 사용한다', () {
    const surfaceHeight = 760.0;

    for (final anchors in <(double, double)>[
      (118, 420),
      (142, 438),
      (176, 462),
    ]) {
      final insets = todayGuideInsets(
        surfaceHeight: surfaceHeight,
        headerBottom: anchors.$1,
        eraLabelTop: anchors.$2,
      );
      final availableCenter =
          insets.top + (surfaceHeight - insets.top - insets.bottom) / 2;

      expect(availableCenter, closeTo((anchors.$1 + anchors.$2) / 2, 0.001));
    }
  });

  test('오늘 가이드 영역은 화면 밖 앵커를 안전하게 보정한다', () {
    final insets = todayGuideInsets(
      surfaceHeight: 500,
      headerBottom: -20,
      eraLabelTop: 620,
    );

    expect(insets, EdgeInsets.zero);
  });
}
