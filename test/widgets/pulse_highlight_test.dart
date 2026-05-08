import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/pulse_highlight.dart';

void main() {
  group('PulseHighlight dispose', () {
    testWidgets('active=false 인 채로 한 번도 활성화되지 않고 unmount 되어도 예외가 안 난다', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulseHighlight(
              active: false,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      // active 가 false 상태로 마운트만 됐다가, 트리에서 빼서 unmount.
      // 회귀 발생 조건: dispose 에서 처음으로 _controller 가 late-init 되면서
      // AnimationController(vsync: this) 가 deactivated context 에서
      // TickerMode 를 조회 → assert.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      // takeException 이 null 이어야 통과.
      expect(tester.takeException(), isNull);
    });

    testWidgets('active=true → false 전환 후 unmount 도 예외 없음', (tester) async {
      Widget tree(bool active) => MaterialApp(
        home: Scaffold(
          body: PulseHighlight(
            active: active,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );

      await tester.pumpWidget(tree(true));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(tree(false));
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
