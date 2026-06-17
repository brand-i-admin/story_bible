import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프로필 기록 퀴즈 통계 카드는 높이와 여백을 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('EdgeInsets.fromLTRB(12, 11, 12, 11)'));
    expect(source, contains('const SizedBox(width: 9)'));
    expect(source, contains('BoxConstraints(minHeight: 62)'));
    expect(source, contains('mainAxisAlignment: MainAxisAlignment.center'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.center'));
  });
}
