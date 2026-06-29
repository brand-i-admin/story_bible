import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/auth_repository.dart';
import 'package:story_bible/models/app_user_profile.dart';

void main() {
  group('googleAccountChooserQueryParams', () {
    test('Google OAuth 에 계정 선택 화면을 요청한다', () {
      expect(googleAccountChooserQueryParams(), const {
        'prompt': 'select_account',
      });
    });
  });

  group('accountDeletionConfirmationId', () {
    test('이메일이 있으면 이메일을 확인 아이디로 사용한다', () {
      const user = User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        email: 'test@example.com',
        createdAt: '2026-06-25T00:00:00Z',
      );

      expect(accountDeletionConfirmationId(user: user), 'test@example.com');
    });

    test('이메일이 없으면 프로필 공유 코드를 사용한다', () {
      const user = User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-06-25T00:00:00Z',
      );
      final profile = AppUserProfile(
        userId: 'user-1',
        shareId: 'ABC1234',
        nickname: '기도친구',
        photoUrl: null,
        prayerRequest: null,
        createdAt: DateTime.parse('2026-06-25T00:00:00Z'),
        updatedAt: DateTime.parse('2026-06-25T00:00:00Z'),
      );

      expect(
        accountDeletionConfirmationId(user: user, profile: profile),
        'ABC1234',
      );
    });

    test('입력 비교는 앞뒤 공백과 대소문자를 허용한다', () {
      expect(
        accountDeletionConfirmationMatches(
          input: '  abc1234 ',
          expected: 'ABC1234',
        ),
        isTrue,
      );
      expect(
        accountDeletionConfirmationMatches(input: 'wrong', expected: 'ABC1234'),
        isFalse,
      );
    });
  });
}
