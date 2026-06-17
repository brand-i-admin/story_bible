import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/story_home_styles.dart';

Widget _harness(Widget child, {double width = 320}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: 320, child: child),
      ),
    ),
  );
}

void main() {
  group('StorySceneRow nudge', () {
    testWidgets('4장이 viewport 보다 길면 등장 시 0 → 60 → 0 으로 한 번 들썩인다', (
      tester,
    ) async {
      // 의도적으로 존재하지 않는 path 4개. _hybridSceneImage 의 errorBuilder
      // 가 placeholder 로 떨어져서 layout 은 정상 진행된다.
      const assets = [
        'assets/scene_a.png',
        'assets/scene_b.png',
        'assets/scene_c.png',
        'assets/scene_d.png',
      ];

      await tester.pumpWidget(
        _harness(const StorySceneRow(sceneAssets: assets), width: 320),
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(60));

      var maxObserved = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        if (scrollable.position.pixels > maxObserved) {
          maxObserved = scrollable.position.pixels;
        }
      }
      expect(
        maxObserved,
        greaterThan(50),
        reason: 'peak 60 근처까지 도달해야 한다 (max=$maxObserved)',
      );

      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        lessThan(1),
        reason: 'nudge 종료 후 다시 0 근처로 복귀',
      );
    });

    testWidgets('1장만 있으면 (overflow 없음) nudge 가 일어나지 않고 offset 0 유지', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const StorySceneRow(sceneAssets: ['assets/scene_solo.png']),
          width: 600,
        ),
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(scrollable.position.pixels, 0);
      }
    });

    testWidgets('장면 캡션은 앞면 한 줄, 탭 후 뒷면 전체 설명으로 표시한다', (tester) async {
      const caption = '하나님의 빛이 어둠 위에 비치며 창조의 첫 질서가 드러납니다';
      await tester.pumpWidget(
        _harness(
          const StorySceneRow(
            sceneAssets: ['assets/scene_solo.png'],
            sceneCaptions: [caption],
          ),
          width: 600,
        ),
      );

      final front = find.byKey(const ValueKey('story-scene-caption-front-0'));
      expect(front, findsOneWidget);
      final frontText = tester.widget<Text>(
        find.descendant(of: front, matching: find.text(caption)),
      );
      expect(frontText.maxLines, 1);

      await tester.tap(find.byKey(const ValueKey('story-scene-tile-0')));
      await tester.pump();
      await tester.pumpAndSettle();

      final back = find.byKey(const ValueKey('story-scene-caption-back-0'));
      expect(back, findsOneWidget);
      final backText = tester.widget<Text>(
        find.descendant(of: back, matching: find.text(caption)),
      );
      expect(backText.maxLines, isNull);
    });
  });
}
