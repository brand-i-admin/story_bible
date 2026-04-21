import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible_admin/widgets/scene_persons_grid.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('ScenePersonsGrid', () {
    testWidgets('persons 가 비어 있으면 안내 텍스트 표시', (tester) async {
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: const [],
            sceneCount: 4,
            initial: const [],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.textContaining('인물 코드를 먼저 추가'), findsOneWidget);
    });

    testWidgets('체크박스 grid 가 sceneCount × personCodes 만큼 그려진다', (tester) async {
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: const ['peter', 'paul'],
            sceneCount: 4,
            initial: const [],
            onChanged: (_) {},
          ),
        ),
      );
      // 4 scene × 2 person = 8 체크박스
      expect(find.byType(Checkbox), findsNWidgets(8));
      // 'peter'/'paul' 라벨은 각 장면마다 1번씩 = 4번 등장
      expect(find.text('peter'), findsNWidgets(4));
      expect(find.text('paul'), findsNWidgets(4));
      expect(find.text('장면 1'), findsOneWidget);
      expect(find.text('장면 4'), findsOneWidget);
    });

    testWidgets('초기 selection 이 체크박스에 반영된다', (tester) async {
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: const ['peter', 'paul'],
            sceneCount: 2,
            initial: const [
              ['peter'], // 장면 1
              ['peter', 'paul'], // 장면 2
            ],
            onChanged: (_) {},
          ),
        ),
      );
      final cells = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      // 장면 1: peter true, paul false
      expect(cells[0].value, isTrue);
      expect(cells[1].value, isFalse);
      // 장면 2: peter true, paul true
      expect(cells[2].value, isTrue);
      expect(cells[3].value, isTrue);
    });

    testWidgets('체크박스 토글하면 onChanged 가 갱신된 행렬로 호출', (tester) async {
      List<List<String>>? captured;
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: const ['peter', 'paul'],
            sceneCount: 2,
            initial: const [],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      // 장면 1, peter 체크
      await tester.tap(find.byKey(const ValueKey('scene_chk_0_peter')));
      await tester.pump();
      expect(captured, isNotNull);
      expect(captured![0], ['peter']);
      expect(captured![1], isEmpty);

      // 장면 2, paul 체크
      await tester.tap(find.byKey(const ValueKey('scene_chk_1_paul')));
      await tester.pump();
      expect(captured![1], ['paul']);
    });

    testWidgets('personCodes 가 변경되면 grid 가 자동 재구성', (tester) async {
      var personCodes = ['peter'];
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: personCodes,
            sceneCount: 2,
            initial: const [
              ['peter'],
            ],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byType(Checkbox), findsNWidgets(2)); // 2 scene × 1

      personCodes = ['peter', 'paul'];
      await tester.pumpWidget(
        host(
          ScenePersonsGrid(
            personCodes: personCodes,
            sceneCount: 2,
            initial: const [
              ['peter'],
            ],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byType(Checkbox), findsNWidgets(4)); // 2 scene × 2
    });
  });
}
