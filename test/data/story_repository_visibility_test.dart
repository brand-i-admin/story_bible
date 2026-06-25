import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/story_repository.dart';

void main() {
  group('filterByVisibleEventIds', () {
    test('active events에 없는 진행/퀴즈/감정 기록을 제외한다', () {
      final filtered = filterByVisibleEventIds(
        {'active-1': 'keep', 'deleted-1': 'drop', 'active-2': 'keep-too'},
        {'active-1', 'active-2'},
      );

      expect(filtered, {'active-1': 'keep', 'active-2': 'keep-too'});
      expect(filtered.containsKey('deleted-1'), isFalse);
    });

    test('visible event가 없으면 빈 map을 반환한다', () {
      final filtered = filterByVisibleEventIds({'deleted-1': 'drop'}, const {});

      expect(filtered, isEmpty);
    });
  });
}
