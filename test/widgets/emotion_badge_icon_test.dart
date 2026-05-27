import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/emotion_badge_icon.dart';

void main() {
  testWidgets('EmotionBadgeIcon은 고정 크기 배지 중앙에 컬러 이모지를 배치한다', (tester) async {
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
    final emojiCenter = tester.getCenter(find.text('🌟'));

    expect(find.byType(Icon), findsNothing);
    expect((badgeCenter.dx - emojiCenter.dx).abs(), lessThan(0.01));
    expect((badgeCenter.dy - emojiCenter.dy).abs(), lessThan(0.01));
  });
}
