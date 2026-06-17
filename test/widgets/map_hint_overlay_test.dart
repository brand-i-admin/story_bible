import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/v2/map_hint_overlay.dart';

void main() {
  testWidgets('MapHintOverlay는 상단 배지에 사라지는 조건을 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MapHintOverlay(message: '노란 지역을 눌러 그곳의 사건을 보세요.')),
      ),
    );

    expect(find.text('화면 아무데나 누르면 사라집니다'), findsOneWidget);
    expect(find.text('노란 지역을 눌러 그곳의 사건을 보세요.'), findsOneWidget);
    final guideText = tester.widget<Text>(find.text('노란 지역을 눌러 그곳의 사건을 보세요.'));
    expect(guideText.style?.fontSize, 12.4);
    expect(guideText.style?.height, 1.38);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
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
    final badgeBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('map-hint-dismiss-badge')))
        .dy;
    final messageTop = tester
        .getTopLeft(find.byKey(const ValueKey('map-hint-message-row')))
        .dy;
    expect(messageTop - badgeBottom, greaterThanOrEqualTo(18));
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
  });

  testWidgets('MapHintOverlay는 동그라미 숫자 단계 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapHintOverlay(
            message:
                '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.',
          ),
        ),
      ),
    );

    expect(find.text('오늘은 성경 어디를 여행해볼까요?'), findsOneWidget);
    expect(find.text('먼저 시대를 고르고'), findsOneWidget);
    expect(find.text('시간 순·인물·장소 중 선택해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-step-badge-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-hint-step-badge-2')), findsOneWidget);
  });

  testWidgets('첫 안내 문구는 좁은 폰에서도 한 줄 축소되고 검은 고스트 그림자가 없다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: MapHintOverlay(
              avatarSize: 70,
              message:
                  '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.',
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('오늘은 성경 어디를 여행해볼까요?'));
    expect(title.maxLines, 1);
    expect(title.style?.shadows, isEmpty);

    final step = tester.widget<Text>(find.text('시간 순·인물·장소 중 선택해 주세요.'));
    expect(step.maxLines, 1);
    expect(step.style?.shadows, isEmpty);
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
      '오늘은 성경 어디를 여행해볼까요?\n① 먼저 시대를 고르고\n② 시간 순·인물·장소 중 선택해 주세요.',
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
    expect(source, contains('① 먼저 시대를 고르고'));
    expect(source, contains('② 시간 순·인물·장소 중 선택'));
    expect(source, contains('노란 지역을 눌러'));
    expect(source, contains('아래 패널에서 인물을'));
    expect(source, contains('아래 패널에서 단위 카드를'));
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
