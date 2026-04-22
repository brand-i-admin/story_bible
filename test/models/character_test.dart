import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/character.dart';

void main() {
  group('Character.avatarAssetPath', () {
    test('avatarUrl이 null이면 placeholder 경로를 반환한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: null,
        displayOrder: 1,
      );

      expect(
        character.avatarAssetPath,
        'assets/avatars_thumbs/_placeholder.png',
      );
    });

    test('avatarUrl이 빈 문자열이면 placeholder 경로를 반환한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: '',
        displayOrder: 1,
      );

      expect(
        character.avatarAssetPath,
        'assets/avatars_thumbs/_placeholder.png',
      );
    });

    test('avatars/ 경로를 avatars_thumbs/ 경로로 교체한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: 'assets/avatars/abraham.png',
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, 'assets/avatars_thumbs/abraham.png');
    });

    test('다른 경로는 그대로 사용한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: 'https://example.com/avatar.png',
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, 'https://example.com/avatar.png');
    });

    test('경로 앞뒤 공백을 제거한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: '  assets/avatars/abraham.png  ',
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, 'assets/avatars_thumbs/abraham.png');
    });
  });
}
