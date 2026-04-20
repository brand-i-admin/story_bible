import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  group('FontScale enum', () {
    test('각 단계의 ratio 값이 정확하다', () {
      expect(FontScale.small.ratio, 0.9);
      expect(FontScale.normal.ratio, 1.0);
      expect(FontScale.large.ratio, 1.2);
    });

    test('라벨은 한국어로 표시된다', () {
      expect(FontScale.small.label, '작게');
      expect(FontScale.normal.label, '보통');
      expect(FontScale.large.label, '크게');
    });

    test('storageKey는 enum name과 동일하다', () {
      expect(FontScale.small.storageKey, 'small');
      expect(FontScale.normal.storageKey, 'normal');
      expect(FontScale.large.storageKey, 'large');
    });

    group('fromStorage', () {
      test('알려진 값은 대응되는 enum으로 복원된다', () {
        expect(FontScale.fromStorage('small'), FontScale.small);
        expect(FontScale.fromStorage('normal'), FontScale.normal);
        expect(FontScale.fromStorage('large'), FontScale.large);
      });

      test('null은 normal로 복원된다', () {
        expect(FontScale.fromStorage(null), FontScale.normal);
      });

      test('알 수 없는 값은 normal로 복원된다', () {
        expect(FontScale.fromStorage('xlarge'), FontScale.normal);
        expect(FontScale.fromStorage(''), FontScale.normal);
      });
    });
  });
}
