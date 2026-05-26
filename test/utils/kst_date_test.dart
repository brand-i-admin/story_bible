import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/kst_date.dart';

void main() {
  group('KST date formatting', () {
    test('UTC 시각을 한국 날짜로 표현한다', () {
      final text = formatKoreanMonthDayKst(
        DateTime.parse('2026-05-25T16:30:00Z'),
        now: DateTime.parse('2026-05-26T06:00:00Z'),
      );

      expect(text, '5월 26일');
    });

    test('미래로 밀린 날짜는 오늘 한국 날짜로 보정한다', () {
      final text = formatKoreanMonthDayKst(
        DateTime.parse('2026-05-26T15:30:00Z'),
        now: DateTime.parse('2026-05-26T06:00:00Z'),
      );

      expect(text, '5월 26일');
    });
  });
}
