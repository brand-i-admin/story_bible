import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프로필 인물 상세 사건 그리드는 좁은 3열에서도 충분한 카드 높이를 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_character_overview.dart',
    ).readAsStringSync();

    expect(source, contains('mainAxisExtent: 226'));
    expect(source, isNot(contains('childAspectRatio: 0.78')));
  });
}
