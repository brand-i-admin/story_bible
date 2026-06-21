import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/story_home_styles.dart';

void main() {
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
