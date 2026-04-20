import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/weekly_selection.dart';

void main() {
  group('weekStartMonday', () {
    test('월요일은 그대로 반환 (시간은 0으로 정규화)', () {
      // 2024-01-01 (월)
      final monday = weekStartMonday(DateTime(2024, 1, 1, 13, 45));
      expect(monday, DateTime(2024, 1, 1));
    });

    test('일요일은 6일 전 월요일을 반환', () {
      // 2024-01-07 (일)
      final monday = weekStartMonday(DateTime(2024, 1, 7));
      expect(monday, DateTime(2024, 1, 1));
    });

    test('수요일은 2일 전 월요일을 반환', () {
      // 2024-01-03 (수)
      final monday = weekStartMonday(DateTime(2024, 1, 3));
      expect(monday, DateTime(2024, 1, 1));
    });

    test('월 경계를 넘어가도 정확히 동작', () {
      // 2024-04-02 (화) → 2024-04-01 (월)
      final monday = weekStartMonday(DateTime(2024, 4, 2));
      expect(monday, DateTime(2024, 4, 1));
    });
  });

  group('weeklyKeyFor', () {
    test('YYYY-M-D 형식', () {
      expect(weeklyKeyFor(DateTime(2024, 1, 1)), '2024-1-1');
    });

    test('두자리 월/일도 패딩 없이 그대로', () {
      expect(weeklyKeyFor(DateTime(2024, 12, 25)), '2024-12-25');
    });
  });

  group('seedFromKey', () {
    test('같은 키면 같은 시드', () {
      expect(seedFromKey('2024-1-1'), seedFromKey('2024-1-1'));
    });

    test('다른 키면 보통 다른 시드', () {
      expect(seedFromKey('2024-1-1'), isNot(seedFromKey('2024-1-8')));
    });

    test('항상 양의 정수 (32-bit)', () {
      for (final key in ['2024-1-1', '2024-12-31', '1900-1-1', '9999-12-31']) {
        final s = seedFromKey(key);
        expect(s, greaterThanOrEqualTo(0));
        expect(s, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('빈 문자열은 0', () {
      expect(seedFromKey(''), 0);
    });
  });
}
