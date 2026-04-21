import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible_admin/widgets/person_codes_picker.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('PersonCodesPicker', () {
    final available = [
      const PersonOption(code: 'peter', name: '베드로'),
      const PersonOption(code: 'paul', name: '바울'),
      const PersonOption(code: 'mary', name: '마리아'),
    ];

    testWidgets('초기 상태에서 선택된 인물이 chip 으로 표시된다', (tester) async {
      var picked = <String>[];
      await tester.pumpWidget(
        host(
          PersonCodesPicker(
            available: available,
            initial: const ['peter', 'paul'],
            onChanged: (next) => picked = next,
          ),
        ),
      );
      expect(find.text('peter'), findsOneWidget);
      expect(find.text('paul'), findsOneWidget);
      expect(picked, isEmpty); // 초기엔 onChanged 안 불림
    });

    testWidgets('chip x 버튼으로 제거하면 onChanged 가 변경된 리스트로 호출된다', (tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        host(
          PersonCodesPicker(
            available: available,
            initial: const ['peter', 'paul'],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('person_chip_remove_peter')));
      await tester.pump();
      expect(captured, ['paul']);
    });

    testWidgets('자유 입력 후 추가 버튼으로 신규 코드 등록 가능 (목록에 없어도 OK)', (tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        host(
          PersonCodesPicker(
            available: available,
            initial: const [],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('person_picker_input')),
        'newperson',
      );
      await tester.tap(find.byKey(const ValueKey('person_picker_add')));
      await tester.pump();
      expect(captured, ['newperson']);
    });

    testWidgets('중복 코드는 추가되지 않는다', (tester) async {
      var lastEmit = <String>[];
      await tester.pumpWidget(
        host(
          PersonCodesPicker(
            available: available,
            initial: const ['peter'],
            onChanged: (v) => lastEmit = v,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('person_picker_input')),
        'peter',
      );
      await tester.tap(find.byKey(const ValueKey('person_picker_add')));
      await tester.pump();
      expect(lastEmit, isEmpty); // emit 안 됨 (중복이라 무시)
    });

    testWidgets('빈 입력은 추가되지 않는다', (tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        host(
          PersonCodesPicker(
            available: available,
            initial: const [],
            onChanged: (v) => captured = v,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('person_picker_input')),
        '   ',
      );
      await tester.tap(find.byKey(const ValueKey('person_picker_add')));
      await tester.pump();
      expect(captured, isNull);
    });
  });
}
