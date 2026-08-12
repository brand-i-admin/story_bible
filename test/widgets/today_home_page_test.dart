import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/home/today_home_page.dart';
import 'package:story_bible/widgets/v2/map_hint_overlay.dart';

void main() {
  test('여정 선택은 헤더 아래에 있고 안내 오버레이는 비로그인 상태에만 연다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("key: const ValueKey('today-open-journey-selection')"),
    );
    expect(
      source,
      contains('if (!widget.isAuthenticated && !_todayGuideDismissed)'),
    );
  });

  testWidgets('여정 선택 화살표는 오른쪽 끝의 원형 버튼으로 표시한다', (tester) async {
    var tapped = false;
    await tester.binding.setSurfaceSize(const Size(390, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: TodayJourneySelectionBar(
                currentLabel: '신명기 · 시대 구간',
                completedCount: 3,
                totalCount: 12,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    final bar = find.byKey(const ValueKey('today-open-journey-selection'));
    final surface = find.byKey(
      const ValueKey('today-journey-selection-surface'),
    );
    final leadingIcon = find.byKey(
      const ValueKey('today-journey-selection-leading-icon'),
    );
    final arrow = find.byKey(const ValueKey('today-journey-selection-arrow'));
    final barRect = tester.getRect(bar);
    final arrowRect = tester.getRect(arrow);
    expect(arrowRect.width, closeTo(30, 0.1));
    expect(arrowRect.height, closeTo(30, 0.1));
    expect(barRect.right - arrowRect.right, lessThanOrEqualTo(10));
    expect(tester.getSize(leadingIcon), const Size(34, 34));

    final surfaceDecoration =
        tester.widget<Container>(surface).decoration! as BoxDecoration;
    expect(surfaceDecoration.borderRadius, BorderRadius.circular(20));
    expect(surfaceDecoration.boxShadow, isNotEmpty);
    expect(find.text('진행률'), findsOneWidget);
    final titleRect = tester.getRect(find.text('여정 선택'));
    final currentLabelRect = tester.getRect(find.text('신명기 · 시대 구간'));
    expect(titleRect.right, lessThan(currentLabelRect.left));
    expect(titleRect.center.dy, closeTo(currentLabelRect.center.dy, 1));

    final arrowDecoration =
        tester.widget<Container>(arrow).decoration! as BoxDecoration;
    expect(arrowDecoration.shape, BoxShape.circle);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('today-journey-selection-progress')),
    );
    expect(progress.value, 0.25);
    expect(find.text('3/12'), findsOneWidget);
    final progressTrack = find.byKey(
      const ValueKey('today-journey-selection-progress-track'),
    );
    final progressCount = find.byKey(
      const ValueKey('today-journey-selection-count'),
    );
    final trackRect = tester.getRect(progressTrack);
    final countRect = tester.getRect(progressCount);
    expect(trackRect.height, closeTo(14, 0.1));
    expect(countRect.center.dx, closeTo(trackRect.center.dx, 0.5));
    expect(countRect.center.dy, closeTo(trackRect.center.dy, 0.5));
    expect(trackRect.contains(countRect.topLeft), isTrue);
    expect(trackRect.contains(countRect.bottomRight), isTrue);

    await tester.tap(arrow);
    expect(tapped, isTrue);
  });

  testWidgets('네이비 테마의 0퍼센트 여정도 진행률 트랙 윤곽을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [AppPaletteTheme(AppColorPalette.atlasNavy)],
        ),
        home: Scaffold(
          body: TodayJourneySelectionBar(
            currentLabel: '전체 순서',
            completedCount: 0,
            totalCount: 299,
            onTap: () {},
          ),
        ),
      ),
    );

    final track = tester.widget<Container>(
      find.byKey(const ValueKey('today-journey-selection-progress-track')),
    );
    final decoration = track.decoration! as BoxDecoration;
    final foregroundDecoration = track.foregroundDecoration! as BoxDecoration;
    expect(decoration.color, AppColorPalette.atlasNavy.currentFill);
    expect(foregroundDecoration.border, isNotNull);
    expect(find.text('0/299'), findsOneWidget);
  });

  testWidgets('비로그인 여정 가이드는 카드 스크롤 안내와 닫기 배지를 표시한다', (tester) async {
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
      final journeyGuide = find.text(
        '아래 이야기 카드를 스크롤 해보세요.\n'
        '나열되는 이야기 카드들은 위 여정 선택을 기준으로 표시됩니다.',
      );
      expect(journeyGuide, findsOneWidget);
      expect(tester.widget<Text>(journeyGuide).textAlign, TextAlign.center);
      expect(find.text('매일 할 일:'), findsNothing);
      expect(find.text('(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)'), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

      for (final entry in <IconData, Color>{
        Icons.hourglass_top_rounded: Colors.white,
      }.entries) {
        expect(tester.widget<Icon>(find.byIcon(entry.key)).color, entry.value);
      }

      for (final entry in <String, Color>{
        '화면 아무데나 누르면 사라집니다': Colors.white,
        '아래 이야기 카드를 스크롤 해보세요.\n'
            '나열되는 이야기 카드들은 위 여정 선택을 기준으로 표시됩니다.': isDark
            ? palette.text
            : AppColors.ink900,
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
