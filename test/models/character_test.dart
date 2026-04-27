import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/character.dart';

void main() {
  group('Character.avatarAssetPath', () {
    test('avatarUrl이 null 이면 빈 문자열을 반환한다 (storage fallback 신호)', () {
      // 빈 문자열은 호출처(CharacterAvatar 등) 가 isEmpty 체크로 storage 분기를
      // 타게 하는 신호. 옛 구현은 존재하지 않는 placeholder 경로를 반환해
      // Image.asset 이 404 → errorBuilder fallback 으로 떨어져 네트워크 fallback
      // 진입을 막는 버그가 있었다.
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: null,
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, '');
    });

    test('avatarUrl 이 빈 문자열이면 빈 문자열을 반환한다', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: '',
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, '');
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

    test('로컬 자산 prefix(assets/)가 아니면 빈 문자열을 반환한다', () {
      // http(s) URL 이나 supabase storage 경로 등은 로컬 번들 자산이 아니다 →
      // Image.asset 으로 시도하면 무조건 실패하므로 빈 문자열로 표시. 호출처가
      // avatarStoragePath 로 storage URL 을 따로 만들어 Image.network 분기를 탄다.
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: 'https://example.com/avatar.png',
        displayOrder: 1,
      );

      expect(character.avatarAssetPath, '');
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

  group('Character.hasLocalAvatar', () {
    test('avatarUrl이 null 이면 false', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: null,
        displayOrder: 1,
      );

      expect(character.hasLocalAvatar, isFalse);
    });

    test('avatarUrl이 빈 문자열이면 false', () {
      const character = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: '',
        displayOrder: 1,
      );

      expect(character.hasLocalAvatar, isFalse);
    });

    test('avatars/ 또는 avatars_thumbs/ 로 시작하면 true', () {
      const c1 = Character(
        id: 'p1',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: 'assets/avatars/abraham.png',
        displayOrder: 1,
      );
      const c2 = Character(
        id: 'p2',
        code: 'abraham',
        name: '아브라함',
        tagline: null,
        description: null,
        avatarUrl: 'assets/avatars_thumbs/abraham.png',
        displayOrder: 1,
      );

      expect(c1.hasLocalAvatar, isTrue);
      expect(c2.hasLocalAvatar, isTrue);
    });

    test('http(s) URL 이나 storage 경로는 로컬 번들이 아님 → false', () {
      const c1 = Character(
        id: 'p1',
        code: 'tester',
        name: '테스터',
        tagline: null,
        description: null,
        avatarUrl: 'https://example.com/avatar.png',
        displayOrder: 1,
      );
      const c2 = Character(
        id: 'p2',
        code: 'tester',
        name: '테스터',
        tagline: null,
        description: null,
        avatarUrl: 'proposal-characters/uid/draft/tester.png',
        displayOrder: 1,
      );

      expect(c1.hasLocalAvatar, isFalse);
      expect(c2.hasLocalAvatar, isFalse);
    });
  });
}
