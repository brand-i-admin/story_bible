import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/v2/map_hint_overlay.dart';

void main() {
  testWidgets('MapHintOverlay는 상단 배지에 사라지는 조건을 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapHintOverlay(
            message: '노란 지역을 눌러 그곳의 사건을 보세요.',
            icon: Icons.touch_app_rounded,
          ),
        ),
      ),
    );

    expect(find.text('화면 아무데나 누르면 사라집니다'), findsOneWidget);
    expect(find.text('노란 지역을 눌러 그곳의 사건을 보세요.'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byIcon(Icons.touch_app_outlined), findsNothing);
  });
}
