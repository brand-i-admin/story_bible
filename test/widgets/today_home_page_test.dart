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

  testWidgets('여정 선택은 경로 아이콘과 붙은 2행 정보, 오른쪽 화살표로 낮게 표시한다', (tester) async {
    var tapped = false;
    await tester.binding.setSurfaceSize(const Size(360, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 336,
                child: TodayJourneySelectionBar(
                  currentLabel: '아브라함 이야기만',
                  completedCount: 3,
                  totalCount: 12,
                  onTap: () => tapped = true,
                ),
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
    expect(barRect.height, lessThan(60));
    expect(tester.getSize(leadingIcon), const Size(34, 34));
    expect(
      find.descendant(
        of: leadingIcon,
        matching: find.byIcon(Icons.route_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('🧭'), findsNothing);

    final surfaceDecoration =
        tester.widget<Container>(surface).decoration! as BoxDecoration;
    expect(surfaceDecoration.borderRadius, BorderRadius.circular(20));
    expect(surfaceDecoration.boxShadow, isNotEmpty);
    expect(find.text('진행률'), findsNothing);
    final titleRect = tester.getRect(find.text('여정 선택'));
    final currentLabelRect = tester.getRect(find.text('아브라함 이야기만'));
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
    final leadingRect = tester.getRect(leadingIcon);
    expect(trackRect.height, closeTo(14, 0.1));
    expect(trackRect.top - titleRect.bottom, closeTo(0, 0.1));
    expect(trackRect.left, greaterThan(leadingRect.right));
    expect(trackRect.right, lessThan(arrowRect.left));
    expect(countRect.center.dx, closeTo(trackRect.center.dx, 0.5));
    expect(countRect.center.dy, closeTo(trackRect.center.dy, 0.5));
    expect(trackRect.contains(countRect.topLeft), isTrue);
    expect(trackRect.contains(countRect.bottomRight), isTrue);

    await tester.tap(arrow);
    expect(tapped, isTrue);
  });

  testWidgets('여정 진행 불꽃은 0퍼센트에서 왼쪽, 50퍼센트에서 중앙에 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpProgress(int completedCount) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 336,
                child: TodayJourneySelectionBar(
                  currentLabel: '아브라함 이야기만',
                  completedCount: completedCount,
                  totalCount: 10,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpProgress(0);
    final track = find.byKey(
      const ValueKey('today-journey-selection-progress-track'),
    );
    final flame = find.byKey(
      const ValueKey('today-journey-selection-progress-flame'),
    );
    var trackRect = tester.getRect(track);
    var flameRect = tester.getRect(flame);
    expect(flameRect.left, closeTo(trackRect.left, 0.5));
    expect(flameRect.center.dy, closeTo(trackRect.center.dy, 0.5));

    await pumpProgress(5);
    trackRect = tester.getRect(track);
    flameRect = tester.getRect(flame);
    expect(flameRect.center.dx, closeTo(trackRect.center.dx, 0.5));
    expect(find.text('5/10'), findsOneWidget);

    await pumpProgress(10);
    trackRect = tester.getRect(track);
    flameRect = tester.getRect(flame);
    expect(flameRect.right, closeTo(trackRect.right, 0.5));
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

  testWidgets('여정 카탈로그 로딩 중에는 0/0 대신 불러오는 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayJourneySelectionBar(
            currentLabel: '전체 순서',
            completedCount: 0,
            totalCount: 0,
            loading: true,
            onTap: () {},
          ),
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('today-journey-selection-progress')),
    );
    expect(progress.value, isNull);
    expect(find.text('불러오는 중'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(
      find.byKey(const ValueKey('today-journey-selection-progress-flame')),
      findsNothing,
    );
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
      final firstStepBadge = find.byKey(
        const ValueKey('today-guide-step-1-badge'),
      );
      final secondStepBadge = find.byKey(
        const ValueKey('today-guide-step-2-badge'),
      );
      final firstStepMessage = find.byKey(
        const ValueKey('today-guide-step-1-message'),
      );
      final secondStepMessage = find.byKey(
        const ValueKey('today-guide-step-2-message'),
      );
      expect(firstStepBadge, findsOneWidget);
      expect(secondStepBadge, findsOneWidget);
      expect(firstStepMessage, findsOneWidget);
      expect(secondStepMessage, findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(
        tester.widget<Text>(firstStepMessage).data,
        '아래 이야기 카드를 좌우 넘기기 혹은 클릭',
      );
      expect(
        tester.widget<Text>(secondStepMessage).data,
        "화면 위 '여정 선택'에서 나열될 이야기 카드 변경",
      );
      final storyTitleStyle = ThemeData().textTheme.titleSmall;
      for (final message in [firstStepMessage, secondStepMessage]) {
        final text = tester.widget<Text>(message);
        expect(text.textAlign, TextAlign.center);
        expect(text.style?.color, palette.primaryDeep);
        expect(text.style?.fontSize, MapHintDismissBadge.messageFontSize);
        expect(text.style?.fontWeight, FontWeight.w700);
        expect(text.style?.height, MapHintDismissBadge.messageLineHeight);
        expect(text.style?.fontFamily, storyTitleStyle?.fontFamily);
      }
      for (final badge in [firstStepBadge, secondStepBadge]) {
        final decoration = tester.widget<Container>(badge).decoration!;
        expect(decoration, isA<BoxDecoration>());
        final boxDecoration = decoration as BoxDecoration;
        expect(boxDecoration.shape, BoxShape.circle);
        expect(boxDecoration.border?.top.color, palette.currentAccentDeep);
      }
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
