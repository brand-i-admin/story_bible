import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/home/today_activity_header.dart';
import 'package:story_bible/widgets/home/today_home_page.dart';

void main() {
  testWidgets('오늘 할 일 가이드는 헤더와 같은 단색 아이콘을 단일 컨테이너에 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(body: TodayTodoGuide()),
        ),
      ),
    );

    final guide = find.byKey(const ValueKey('today-todo-guide'));
    expect(guide, findsOneWidget);
    expect(find.text('매일 할 일:'), findsOneWidget);
    expect(find.text('이야기'), findsOneWidget);
    expect(find.text('다이어리'), findsOneWidget);
    expect(find.text('통독'), findsOneWidget);
    final reorderNote = find.text('(아래 이야기 카드는 감정을 새길 때마다 재정렬 됩니다)');
    expect(reorderNote, findsOneWidget);
    expect(tester.widget<Text>(reorderNote).textAlign, TextAlign.center);
    expect(find.byIcon(TodayActivityIcons.story), findsOneWidget);
    expect(find.byIcon(TodayActivityIcons.diary), findsOneWidget);
    expect(find.byIcon(TodayActivityIcons.bible), findsOneWidget);
    expect(
      find.descendant(of: guide, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: guide, matching: find.byType(Container)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
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
