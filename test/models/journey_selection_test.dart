import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/journey_selection.dart';

void main() {
  group('JourneySelection', () {
    test('전체 순서가 기본값이다', () {
      const selection = JourneySelection.all();

      expect(selection.source, JourneySource.all);
      expect(selection.scope, JourneyScope.all);
      expect(selection.unitKeys, isEmpty);
    });

    test('권·방식·선택 구간을 저장 형식으로 왕복한다', () {
      const selection = JourneySelection(
        source: JourneySource.book,
        scope: JourneyScope.units,
        bookName: '다니엘',
        unitKeys: {'era-exile::unit-one', 'era-exile::unit-two'},
      );

      final restored = JourneySelection.fromMap(selection.toMap());

      expect(restored.source, JourneySource.book);
      expect(restored.scope, JourneyScope.units);
      expect(restored.bookName, '다니엘');
      expect(restored.unitKeys, selection.unitKeys);
      expect(restored.displayLabel, '다니엘 · 시대 구간');
      expect(restored.boundaryLabel, '선택된 시대');
    });

    test('알 수 없는 저장값은 전체 순서로 복구한다', () {
      final restored = JourneySelection.fromMap(const {
        'source': 'removed-mode',
        'scope': 'removed-scope',
      });

      expect(restored.source, JourneySource.all);
      expect(restored.scope, JourneyScope.all);
    });
  });
}
