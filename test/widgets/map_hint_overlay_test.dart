import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/v2/map_hint_overlay.dart';

void main() {
  testWidgets('MapHintOverlay는 바깥 프레임 상단에 닫힘 안내를 겹쳐 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MapHintOverlay(message: '노란 지역을 눌러 그곳의 사건을 보세요.')),
      ),
    );

    expect(find.text('화면 아무데나 누르면 사라집니다'), findsOneWidget);
    expect(find.text('노란 지역을 눌러 그곳의 사건을 보세요.'), findsOneWidget);
    final guideText = tester.widget<Text>(find.text('노란 지역을 눌러 그곳의 사건을 보세요.'));
    expect(guideText.style?.color, Colors.white);
    expect(guideText.style?.fontSize, 12.4);
    expect(guideText.style?.height, 1.38);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    final dismissIcon = tester.widget<Icon>(
      find.byIcon(Icons.hourglass_top_rounded),
    );
    expect(dismissIcon.color, Colors.white);
    final dismissText = tester.widget<Text>(find.text('화면 아무데나 누르면 사라집니다'));
    expect(dismissText.style?.color, Colors.white);
    final avatarSize = tester.getSize(
      find.byKey(const ValueKey('map-hint-avatar')),
    );
    expect(avatarSize, const Size.square(48));
    expect(find.byKey(const ValueKey('map-hint-avatar-image')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map-hint-avatar-face-crop')),
      findsNothing,
    );
    final avatar = tester.widget<Image>(
      find.byKey(const ValueKey('map-hint-avatar-image')),
    );
    expect(
      (avatar.image as AssetImage).assetName,
      'assets/avatars_thumbs/guide.png',
    );
    expect(avatar.fit, BoxFit.cover);
    expect(avatar.alignment, Alignment.center);
    final imageScale = tester.widget<Transform>(
      find.byKey(const ValueKey('map-hint-avatar-image-scale')),
    );
    expect(imageScale.transform.getMaxScaleOnAxis(), closeTo(1.13, 0.001));
    expect(
      find.byKey(const ValueKey('map-hint-speech-bubble')),
      findsOneWidget,
    );
    expect(find.byType(ClipPath), findsNothing);
    final badgeCenter = tester.getCenter(
      find.byKey(const ValueKey('map-hint-dismiss-badge')),
    );
    final overlayCenter = tester.getCenter(find.byType(MapHintOverlay));
    expect((badgeCenter.dx - overlayCenter.dx).abs(), lessThan(1));
    final outerTop = tester
        .getTopLeft(find.byKey(const ValueKey('map-hint-container')))
        .dy;
    final badgeTop = tester
        .getTopLeft(find.byKey(const ValueKey('map-hint-dismiss-badge')))
        .dy;
    final badgeBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('map-hint-dismiss-badge')))
        .dy;
    expect(badgeTop, lessThan(outerTop));
    expect(badgeBottom, greaterThan(outerTop));
    expect(badgeBottom - outerTop, lessThanOrEqualTo(4));
    expect(outerTop - badgeTop, greaterThanOrEqualTo(19.5));
    final outerContainer = tester.widget<Container>(
      find.byKey(const ValueKey('map-hint-container')),
    );
    final outerPadding = outerContainer.padding! as EdgeInsets;
    expect(outerPadding.top, 12);
    expect(outerPadding.bottom, 8);
    expect(outerContainer.transform?.getTranslation().y, -2);

    final outerHeight = tester
        .getSize(find.byKey(const ValueKey('map-hint-container')))
        .height;
    final messageHeight = tester
        .getSize(find.byKey(const ValueKey('map-hint-message-row')))
        .height;
    expect(outerHeight - messageHeight, closeTo(22, 0.01));
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
  });

  testWidgets('MapHintOverlay는 현재 팔레트의 역할색으로 표면을 나눈다', (tester) async {
    const palette = AppColorPalette.colorfulMap;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPaletteTheme(palette)]),
        home: const Scaffold(body: MapHintOverlay(message: '시대를 골라보세요.')),
      ),
    );

    BoxDecoration decorationFor(String key) {
      final container = tester.widget<Container>(find.byKey(ValueKey(key)));
      return container.decoration as BoxDecoration;
    }

    final outerColor = decorationFor('map-hint-container').color;
    final dismissBadgeColor = decorationFor('map-hint-dismiss-badge').color;
    final speechBubbleColor = decorationFor('map-hint-speech-bubble').color;
    expect(outerColor, palette.utilityBackground.withValues(alpha: 0.64));
    expect(
      dismissBadgeColor,
      Color.alphaBlend(
        palette.currentAccentDeep.withValues(alpha: 0.82),
        palette.utilityBackground,
      ).withValues(alpha: 0.78),
    );
    expect(
      speechBubbleColor,
      Color.alphaBlend(
        palette.characterAccent.withValues(alpha: 0.68),
        palette.utilityBackground,
      ).withValues(alpha: 0.72),
    );
    expect(dismissBadgeColor, isNot(outerColor));
    expect(speechBubbleColor, isNot(outerColor));
    expect(speechBubbleColor, isNot(dismissBadgeColor));
  });

  testWidgets('MapHintOverlay는 동그라미 숫자 단계 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapHintOverlay(
            message:
                '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.\n(성경 구절 검색은 상단 🔍 클릭)',
          ),
        ),
      ),
    );

    expect(find.text('오늘은 성경 어디를 여행해볼까요?'), findsOneWidget);
    expect(find.text('(성경 구절 검색은 상단 🔍 클릭)'), findsOneWidget);
    expect(find.text('먼저 시대를 고르고'), findsOneWidget);
    expect(find.text('시간 순·인물·장소 중 선택해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-step-badge-0')), findsNothing);
    expect(find.byKey(const ValueKey('map-hint-step-badge-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-step-badge-2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map-hint-aside-line-(성경 구절 검색은 상단 🔍 클릭)')),
      findsOneWidget,
    );
    final aside = tester.widget<Text>(find.text('(성경 구절 검색은 상단 🔍 클릭)'));
    final firstStep = tester.widget<Text>(find.text('먼저 시대를 고르고'));
    final secondStep = tester.widget<Text>(find.text('시간 순·인물·장소 중 선택해 주세요.'));
    expect(aside.style?.fontSize, lessThan(firstStep.style?.fontSize ?? 0));
    expect(firstStep.style?.fontSize, secondStep.style?.fontSize);
  });

  testWidgets('시대 선택 가이드는 두 불릿과 짧은 다른 시대 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapHintOverlay(
            showAvatar: false,
            message:
                '• 출애굽 시대 - 출애굽기, 민수기, 신명기, 여호수아\n'
                '• 선택된 시대를 보는 방법을 선택하세요\n'
                '다른 시대를 선택하려면',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('map-hint-bullet-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-bullet-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-avatar')), findsNothing);
    expect(find.byKey(const ValueKey('map-hint-avatar-image')), findsNothing);
    expect(find.text('출애굽 시대 - 출애굽기, 민수기, 신명기, 여호수아'), findsOneWidget);
    expect(find.text('선택된 시대를 보는 방법을 선택하세요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map-hint-era-back-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-hint-era-home-icon')),
      findsOneWidget,
    );
    for (final (ringKey, iconKey) in [
      ('map-hint-era-back-icon-ring', 'map-hint-era-back-icon'),
      ('map-hint-era-home-icon-ring', 'map-hint-era-home-icon'),
    ]) {
      final ringFinder = find.byKey(ValueKey(ringKey));
      expect(ringFinder, findsOneWidget);
      final ring = tester.widget<Container>(ringFinder);
      final decoration = ring.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(tester.getSize(ringFinder), const Size.square(16));
      final iconFinder = find.descendant(
        of: ringFinder,
        matching: find.byKey(ValueKey(iconKey)),
      );
      expect(iconFinder, findsOneWidget);
      expect(tester.widget<Icon>(iconFinder).size, 10);
    }
    expect(
      find.byKey(const ValueKey('map-hint-era-navigation-aside')),
      findsOneWidget,
    );
    final navigationTitle = tester.widget<Text>(
      find.byKey(const ValueKey('map-hint-era-navigation-title')),
    );
    final eraSummary = tester.widget<Text>(
      find.text('출애굽 시대 - 출애굽기, 민수기, 신명기, 여호수아'),
    );
    final methodPrompt = tester.widget<Text>(find.text('선택된 시대를 보는 방법을 선택하세요'));
    expect(navigationTitle.data, '다른 시대를 선택하려면');
    expect(navigationTitle.textAlign, TextAlign.center);
    expect(navigationTitle.style?.fontSize, AppFontSizes.xs);
    expect(navigationTitle.style?.fontWeight, FontWeight.w600);
    expect(
      navigationTitle.style?.fontSize,
      lessThan(eraSummary.style?.fontSize ?? 0),
    );
    expect(
      navigationTitle.style?.fontSize,
      lessThan(methodPrompt.style?.fontSize ?? 0),
    );
    final navigationActions = tester.widget<Wrap>(
      find.byKey(const ValueKey('map-hint-era-navigation-actions')),
    );
    expect(navigationActions.alignment, WrapAlignment.center);
    expect(find.text('시대 다시 선택'), findsOneWidget);
    expect(find.text('또는'), findsOneWidget);
    expect(find.text('시대/방법'), findsOneWidget);
    expect(find.textContaining('('), findsNothing);
    final containerRect = tester.getRect(
      find.byKey(const ValueKey('map-hint-container')),
    );
    final bubbleRect = tester.getRect(
      find.byKey(const ValueKey('map-hint-speech-bubble')),
    );
    expect(bubbleRect.left, closeTo(containerRect.left + 16, 0.1));
    expect(bubbleRect.right, closeTo(containerRect.right - 16, 0.1));
  });

  testWidgets('시대 선택 가이드는 모든 글자 크기에서 중앙 안내가 자연스럽게 맞는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final scale in [1.0, 1.2, 1.4]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SizedBox(
                width: 390,
                height: 320,
                child: MapHintOverlay(
                  showAvatar: false,
                  message:
                      '• 출애굽 시대 - 출애굽기, 민수기, 신명기, 여호수아\n'
                      '• 선택된 시대를 보는 방법을 선택하세요\n'
                      '다른 시대를 선택하려면',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(
        find.byKey(const ValueKey('map-hint-era-navigation-title')),
      );
      final actionsRect = tester.getRect(
        find.byKey(const ValueKey('map-hint-era-navigation-actions')),
      );
      final bubbleRect = tester.getRect(
        find.byKey(const ValueKey('map-hint-speech-bubble')),
      );
      expect(titleRect.center.dx, closeTo(bubbleRect.center.dx, 0.5));
      expect(actionsRect.center.dx, closeTo(bubbleRect.center.dx, 0.5));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('오늘 환영 가이드는 세 가지 동행 항목과 두 참고 문구를 간결하게 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapHintOverlay(
            message:
                '환영합니다! 매일 3가지로 주님과 동행해요!\n'
                '① 이야기 탐험\n'
                '(최근 감정을 새긴 다음 이야기가 추천되요)\n'
                '② 신앙 다이어리\n'
                '③ 통독\n'
                "(기록은 '내정보'에 쌓여요)",
            checklistStates: {'1': true, '2': false, '3': true},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('map-hint-check-1-completed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-hint-check-2-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-hint-check-3-completed')),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('이야기 탐험'), findsOneWidget);
    expect(find.text('신앙 다이어리'), findsOneWidget);
    expect(find.text('통독'), findsOneWidget);
    expect(find.text('(최근 감정을 새긴 다음 이야기가 추천되요)'), findsOneWidget);
    expect(find.text("(기록은 '내정보'에 쌓여요)"), findsOneWidget);
  });

  testWidgets('오늘 환영 가이드는 낮은 지도 가시 영역에서도 overflow 없이 맞춰진다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: ValueKey('welcome-guide-available-area'),
              width: 360,
              height: 210,
              child: MapHintOverlay(
                avatarSize: 58,
                message:
                    '환영합니다! 매일 3가지로 주님과 동행해요!\n'
                    '① 이야기 탐험\n'
                    '(최근 감정을 새긴 다음 이야기가 추천되요)\n'
                    '② 신앙 다이어리\n'
                    '③ 통독\n'
                    "(기록은 '내정보'에 쌓여요)",
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-hint-scale-to-fit')), findsOneWidget);
    final availableBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('welcome-guide-available-area')),
        )
        .dy;
    final guideBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('map-hint-container')))
        .dy;
    expect(guideBottom, lessThanOrEqualTo(availableBottom + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('권 목록이 가장 긴 후기 사도 가이드도 좁은 지도 영역에 맞춰진다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const message =
        '선택된 후기 사도 시대에는 로마서, 고린도전서, 고린도후서, 갈라디아서, '
        '에베소서, 빌립보서, 골로새서, 데살로니가전서, 디모데전서, 디모데후서, '
        '야고보서, 베드로전서, 베드로후서, 요한일서, 요한계시록의 이야기들이 등장합니다.\n'
        '해당 시대를 볼 방법을 선택하세요.\n'
        "(다른 시대를 선택하려면 '시대 다시 선택' 이나 '시대/방법' 버튼을 선택하세요)";
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: ValueKey('long-era-guide-available-area'),
              width: 390,
              height: 312,
              child: MapHintOverlay(message: message, avatarSize: 70),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final availableRect = tester.getRect(
      find.byKey(const ValueKey('long-era-guide-available-area')),
    );
    final guideRect = tester.getRect(
      find.byKey(const ValueKey('map-hint-container')),
    );
    expect(guideRect.top, greaterThanOrEqualTo(availableRect.top - 0.5));
    expect(guideRect.bottom, lessThanOrEqualTo(availableRect.bottom + 0.5));
    expect(find.text(message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('첫 안내 문구는 좁은 폰에서도 단계 줄 글자 크기를 맞춘다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: MapHintOverlay(
              avatarSize: 70,
              message:
                  '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.\n(성경 구절 검색은 상단 🔍 클릭)',
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('오늘은 성경 어디를 여행해볼까요?'));
    expect(title.maxLines, 1);
    expect(title.style?.shadows, isEmpty);

    final aside = tester.widget<Text>(find.text('(성경 구절 검색은 상단 🔍 클릭)'));
    final firstStep = tester.widget<Text>(find.text('먼저 시대를 고르고'));
    final secondStep = tester.widget<Text>(find.text('시간 순·인물·장소 중 선택해 주세요.'));
    expect(aside.maxLines, 1);
    expect(firstStep.maxLines, 2);
    expect(secondStep.maxLines, 2);
    expect(aside.style?.fontSize, lessThan(firstStep.style?.fontSize ?? 0));
    expect(firstStep.style?.fontSize, secondStep.style?.fontSize);
    expect(aside.style?.shadows, isEmpty);
    expect(firstStep.style?.shadows, isEmpty);
    expect(secondStep.style?.shadows, isEmpty);
    expect(
      find.byKey(const ValueKey('map-hint-scaled-line-오늘은 성경 어디를 여행해볼까요?')),
      findsOneWidget,
    );
  });

  testWidgets('MapHintOverlay는 기본 크기와 홈 전용 큰 크기를 구분한다', (tester) async {
    Future<double> pumpAndAvatarSize(String message, double? avatarSize) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: avatarSize == null
                  ? MapHintOverlay(message: message)
                  : MapHintOverlay(message: message, avatarSize: avatarSize),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .getSize(find.byKey(const ValueKey('map-hint-avatar')))
          .width;
    }

    final twoLineSize = await pumpAndAvatarSize(
      '아래 패널에서 인물을 한 명 이상 골라주세요.\n좌측 상단의 초록 「다음」 버튼을 눌러주세요.',
      null,
    );
    final introSize = await pumpAndAvatarSize(
      '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.\n(성경 구절 검색은 오늘 탭의 🔍 클릭)',
      70,
    );

    expect(twoLineSize, 48);
    expect(introSize, 70);
  });

  test('mode entry keeps the hint visible through the triggering tap', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(source, contains('DateTime? _mapHintDismissIgnoredUntil;'));
    expect(
      source,
      contains(
        'if (ignoredUntil != null && DateTime.now().isBefore(ignoredUntil))',
      ),
    );
    expect(source, contains('const Duration(milliseconds: 650)'));
    expect(source, contains('_resetMapHint();'));
    expect(source, contains('_mode == null && _selectionStep == 1'));
    expect(source, contains('오늘은 성경 어디를 여행해볼까요?'));
    expect(source, contains('avatarSize: 70'));
    expect(source, contains('avatarSize: mapHint.avatarSize ?? 48'));
    expect(source, contains('showAvatar: false'));
    expect(source, contains('showAvatar: mapHint.showAvatar'));
    expect(source, contains('① 먼저 시대를 고르고'));
    expect(source, contains('② 시간 순·인물·장소 중 선택'));
    expect(source, contains('(성경 구절 검색은 오늘 탭의 🔍 클릭)'));
    expect(source, isNot(contains('⓪')));
    expect(
      source,
      contains('_selectedEraIntroHintMessage(selectedEra, state.events)'),
    );
    expect(source, contains('canonicalBibleBookNames('));
    expect(source, contains('• \$eraName - \$bookList'));
    expect(source, contains('• 선택된 시대를 보는 방법을 선택하세요'));
    expect(source, contains('다른 시대를 선택하려면'));
    expect(source, isNot(contains('(다른 시대 선택은')));
    expect(source, isNot(contains('이야기들이 등장합니다.')));
    expect(source, isNot(contains('창조부터 바벨까지')));
    expect(source, contains('노란 지역을 눌러'));
    expect(source, contains('아래 패널에서 인물을'));
    expect(source, contains('아래 패널에서 구간 카드를'));
    expect(source, isNot(contains('👋 오늘은 성경')));
    expect(source, isNot(contains('🧭 먼저 시대를')));
    expect(source, isNot(contains('👥 아래 패널')));
    expect(source, isNot(contains('🗂️ 아래 패널')));
  });

  test('tapping era method step shows the intro hint again', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    final eraStepStart = source.indexOf('if (step == 1) {');
    final eraStepEnd = source.indexOf(
      '_animateSelectionPanelToStage(StorySelectionPanelStage.expanded);',
      eraStepStart,
    );
    final eraStepBranch = source.substring(eraStepStart, eraStepEnd);

    expect(eraStepBranch, contains('_mode = null;'));
    expect(eraStepBranch, contains('_selectionStep = 1;'));
    expect(eraStepBranch, contains('_resetMapHint();'));
    expect(eraStepBranch, isNot(contains('_mapHintDismissed = true')));
  });
}
