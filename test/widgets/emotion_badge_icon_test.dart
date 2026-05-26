import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/emotion_badge_icon.dart';

void main() {
  testWidgets('EmotionBadgeIcon은 고정 크기 배지 중앙에 아이콘을 배치한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: EmotionBadgeIcon(
            emotionKey: 'joy',
            size: 24,
            iconSize: 14,
            elevation: false,
          ),
        ),
      ),
    );

    final badgeCenter = tester.getCenter(find.byType(EmotionBadgeIcon));
    final iconCenter = tester.getCenter(find.byIcon(Icons.auto_awesome));

    expect((badgeCenter.dx - iconCenter.dx).abs(), lessThan(0.01));
    expect((badgeCenter.dy - iconCenter.dy).abs(), lessThan(0.01));
  });
}
