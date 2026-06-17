import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/character_name_fallbacks.dart';

void main() {
  group('localizedCharacterName', () {
    test('이미 한글 이름이면 DB 값을 그대로 사용한다', () {
      expect(localizedCharacterName(code: 'john_mark', name: '마가 요한'), '마가 요한');
    });

    test('DB 이름이 code 또는 영어이면 로컬 한글 이름으로 보정한다', () {
      expect(
        localizedCharacterName(code: 'john_mark', name: 'john_mark'),
        '마가 요한',
      );
      expect(localizedCharacterName(code: 'reuben', name: 'Reuben'), '르우벤');
      expect(localizedCharacterName(code: 'simeon', name: 'simeon'), '시므온');
      expect(localizedCharacterName(code: 'naphtali', name: ''), '납달리');
      expect(localizedCharacterName(code: 'shadrach', name: 'shadrach'), '사드락');
      expect(localizedCharacterName(code: 'dan', name: 'dan'), '단');
    });

    test('로컬 한글 이름이 없으면 기존 이름 또는 code를 유지한다', () {
      expect(
        localizedCharacterName(code: 'custom_character', name: 'Custom'),
        'Custom',
      );
      expect(
        localizedCharacterName(code: 'custom_character'),
        'custom_character',
      );
    });
  });
}
