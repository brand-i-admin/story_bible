import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible_admin/widgets/bible_refs_picker.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('BibleRefsPicker', () {
    testWidgets('초기 ref 가 카드로 표시된다', (tester) async {
      List<Map<String, String>>? captured;
      await tester.pumpWidget(
        host(
          BibleRefsPicker(
            initial: const [
              {'book': '창', 'from': '1:1', 'to': '2:3'},
            ],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      expect(find.text('창 1:1-2:3'), findsOneWidget);
      expect(captured, isNull); // 초기엔 onChanged 안 불림
    });

    testWidgets('"추가" 버튼으로 새 ref 가 빈 상태로 추가된다', (tester) async {
      List<Map<String, String>>? captured;
      await tester.pumpWidget(
        host(
          BibleRefsPicker(initial: const [], onChanged: (v) => captured = v),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bible_refs_add')));
      await tester.pump();
      expect(captured, hasLength(1));
      expect(captured!.single['from'], '1:1');
    });

    testWidgets('book / from / to 변경하면 onChanged 가 갱신된 리스트로 호출된다', (
      tester,
    ) async {
      var captured = <Map<String, String>>[];
      await tester.pumpWidget(
        host(
          BibleRefsPicker(
            initial: const [
              {'book': '창', 'from': '1:1', 'to': '1:1'},
            ],
            onChanged: (v) => captured = v,
          ),
        ),
      );

      // from 을 변경
      await tester.enterText(
        find.byKey(const ValueKey('bible_ref_from_0')),
        '2:4',
      );
      await tester.pump();
      expect(captured.single['from'], '2:4');

      // to 변경
      await tester.enterText(
        find.byKey(const ValueKey('bible_ref_to_0')),
        '2:25',
      );
      await tester.pump();
      expect(captured.single['to'], '2:25');
    });

    testWidgets('카드의 삭제 버튼으로 해당 ref 가 제거된다', (tester) async {
      var captured = <Map<String, String>>[];
      await tester.pumpWidget(
        host(
          BibleRefsPicker(
            initial: const [
              {'book': '창', 'from': '1:1', 'to': '2:3'},
              {'book': '요', 'from': '3:16', 'to': '3:16'},
            ],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bible_ref_remove_0')));
      await tester.pump();
      expect(captured, hasLength(1));
      expect(captured.single['book'], '요');
    });

    testWidgets('잘못된 from/to 값이 들어와도 onChanged 는 호출되지만 그대로 전달', (tester) async {
      var captured = <Map<String, String>>[];
      await tester.pumpWidget(
        host(
          BibleRefsPicker(
            initial: const [
              {'book': '창', 'from': '1:1', 'to': '2:3'},
            ],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('bible_ref_from_0')),
        'garbage',
      );
      await tester.pump();
      expect(captured.single['from'], 'garbage');
      // 검증은 상위 폼이 책임 — 여기서는 그대로 통과
    });
  });
}
