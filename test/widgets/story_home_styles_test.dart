import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/story_home_styles.dart';

void main() {
  group('large text accessibility', () {
    testWidgets('공통 채움 버튼은 아주 큰 글자에서도 라벨을 말줄임하지 않는다', (tester) async {
      await tester.pumpWidget(
        _largeTextHarness(
          Center(
            child: SizedBox(
              width: 118,
              child: filledActionButton(
                label: '지도 위에 새기기',
                onTap: () {},
                minWidth: 0,
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('지도 위에 새기기'));
      expect(text.maxLines, isNot(1));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });

    testWidgets('홈 상단 텍스트 버튼은 아주 큰 글자에서도 라벨을 말줄임하지 않는다', (tester) async {
      await tester.pumpWidget(
        _largeTextHarness(
          Center(
            child: topUtilityButton(label: '프로필', onTap: () {}),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('프로필'));
      expect(text.maxLines, isNot(1));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });

    testWidgets('홈 상단 글자 버튼은 아주 큰 글자에서도 라벨을 말줄임하지 않는다', (tester) async {
      await tester.pumpWidget(
        _largeTextHarness(Center(child: topFontScaleButton(onTap: () {}))),
      );

      final text = tester.widget<Text>(find.text('글자'));
      expect(text.maxLines, isNot(1));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });

    testWidgets('장면 앞면 캡션은 아주 큰 글자에서도 말줄임하지 않는다', (tester) async {
      const caption = '아브라함이 밤하늘의 별을 바라보며 하나님이 주신 약속을 마음에 새깁니다.';

      await tester.pumpWidget(
        _largeTextHarness(
          SizedBox(
            width: 220,
            height: 260,
            child: storySceneRow(
              const ['assets/missing_scene_for_test.png'],
              sceneCaptions: const [caption],
            ),
          ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text(caption));
      expect(text.maxLines, anyOf(isNull, greaterThanOrEqualTo(2)));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });
  });

  group('topMissionButton', () {
    testWidgets('완료 전 매일 미션 버튼은 노란색 클릭 유도 상태를 보여준다', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: topMissionButton(
                onTap: () => tapped = true,
                dailyCompleted: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('미션'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('top-mission-button')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(_missionButtonUsesColor(homeStepperDoneColor), findsOneWidget);
      expect(tester.widget<Text>(find.text('미션')).style?.color, Colors.white);
      expect(
        tester.getSize(find.byKey(const ValueKey('top-mission-button'))).width,
        lessThanOrEqualTo(54),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('top-mission-button'))).height,
        36,
      );

      await tester.tap(find.byKey(const ValueKey('top-mission-button')));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('완료한 매일 미션 버튼은 초록색 고정 상태를 보여준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: topMissionButton(onTap: () {}, dailyCompleted: true),
            ),
          ),
        ),
      );

      expect(find.text('미션'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('top-mission-button')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(_missionButtonUsesColor(homeStepperActiveColor), findsOneWidget);
      expect(tester.widget<Text>(find.text('미션')).style?.color, Colors.white);
      expect(
        tester.getSize(find.byKey(const ValueKey('top-mission-button'))).height,
        36,
      );
    });
  });

  group('topFontScaleButton', () {
    testWidgets('홈 상단 글자 크기 버튼은 한글 라벨을 사용한다', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: topFontScaleButton(onTap: () => tapped = true)),
          ),
        ),
      );

      expect(find.text('글자'), findsOneWidget);
      expect(find.text('Tt'), findsNothing);
      expect(find.text('Aa'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('top-font-scale-button')));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('홈 상단 글자 크기 버튼은 전역 글자 배율을 따른다', (tester) async {
      Future<double> pumpAndMeasure(double textScale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: Center(child: topFontScaleButton(onTap: () {})),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.text('글자')).height;
      }

      final normalHeight = await pumpAndMeasure(1.0);
      final veryLargeHeight = await pumpAndMeasure(1.4);

      expect(veryLargeHeight, greaterThan(normalHeight));
    });
  });
}

Widget _largeTextHarness(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
      child: Scaffold(body: child),
    ),
  );
}

Finder _missionButtonUsesColor(Color color) {
  return find.descendant(
    of: find.byKey(const ValueKey('top-mission-button')),
    matching: find.byWidgetPredicate((widget) {
      final decoration = widget is Container ? widget.decoration : null;
      return decoration is BoxDecoration && decoration.color == color;
    }),
  );
}
