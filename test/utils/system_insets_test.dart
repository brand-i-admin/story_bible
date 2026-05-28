import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/system_insets.dart';

void main() {
  group('effectiveBottomSystemInset', () {
    test('내비게이션 바가 없는 기기의 작은 하단 padding 은 0 으로 본다', () {
      expect(effectiveBottomSystemInset(0), 0);
      expect(effectiveBottomSystemInset(4), 0);
      expect(effectiveBottomSystemInset(12), 0);
    });

    test('홈 인디케이터나 내비게이션 바 수준의 하단 padding 은 유지한다', () {
      expect(effectiveBottomSystemInset(16), 16);
      expect(effectiveBottomSystemInset(24), 24);
      expect(effectiveBottomSystemInset(34), 34);
    });
  });

  group('normalizeTinyBottomSystemInset', () {
    test('padding 과 viewPadding 의 작은 bottom 값을 함께 정규화한다', () {
      const media = MediaQueryData(
        padding: EdgeInsets.only(top: 24, bottom: 8),
        viewPadding: EdgeInsets.only(top: 24, bottom: 12),
      );

      final normalized = normalizeTinyBottomSystemInset(media);

      expect(normalized.padding.top, 24);
      expect(normalized.padding.bottom, 0);
      expect(normalized.viewPadding.top, 24);
      expect(normalized.viewPadding.bottom, 0);
    });

    test('의미 있는 bottom 값은 보존한다', () {
      const media = MediaQueryData(
        padding: EdgeInsets.only(bottom: 34),
        viewPadding: EdgeInsets.only(bottom: 34),
      );

      final normalized = normalizeTinyBottomSystemInset(media);

      expect(normalized.padding.bottom, 34);
      expect(normalized.viewPadding.bottom, 34);
    });
  });
}
