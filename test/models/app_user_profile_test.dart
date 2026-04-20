import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/app_user_profile.dart';

void main() {
  group('AppUserProfile.fromMap', () {
    final validMap = <String, dynamic>{
      'user_id': 'u1',
      'share_id': 'ABC1234',
      'nickname': '홍길동',
      'photo_url': 'https://example.com/photo.png',
      'prayer_request': '세계 평화를 위해 기도합니다',
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-06-15T12:30:00Z',
    };

    test('유효한 map에서 모든 필드를 올바르게 파싱한다', () {
      final profile = AppUserProfile.fromMap(validMap);
      expect(profile.userId, 'u1');
      expect(profile.shareId, 'ABC1234');
      expect(profile.nickname, '홍길동');
      expect(profile.photoUrl, 'https://example.com/photo.png');
      expect(profile.prayerRequest, '세계 평화를 위해 기도합니다');
      expect(profile.createdAt, DateTime.parse('2024-01-01T00:00:00Z'));
      expect(profile.updatedAt, DateTime.parse('2024-06-15T12:30:00Z'));
    });

    test('nickname이 null이면 "사용자"로 기본값 설정', () {
      final map = Map<String, dynamic>.from(validMap)..['nickname'] = null;
      final profile = AppUserProfile.fromMap(map);
      expect(profile.nickname, '사용자');
    });

    test('nickname이 공백만 있으면 "사용자"로 기본값 설정', () {
      final map = Map<String, dynamic>.from(validMap)..['nickname'] = '   ';
      final profile = AppUserProfile.fromMap(map);
      expect(profile.nickname, '사용자');
    });

    test('nickname 앞뒤 공백을 제거한다', () {
      final map = Map<String, dynamic>.from(validMap)..['nickname'] = '  홍길동  ';
      final profile = AppUserProfile.fromMap(map);
      expect(profile.nickname, '홍길동');
    });

    test('share_id가 null이면 빈 문자열로 처리', () {
      final map = Map<String, dynamic>.from(validMap)..['share_id'] = null;
      final profile = AppUserProfile.fromMap(map);
      expect(profile.shareId, '');
    });

    test('photo_url이 null이면 null 유지', () {
      final map = Map<String, dynamic>.from(validMap)..['photo_url'] = null;
      final profile = AppUserProfile.fromMap(map);
      expect(profile.photoUrl, isNull);
    });

    test('prayer_request가 null이면 null 유지', () {
      final map = Map<String, dynamic>.from(validMap)
        ..['prayer_request'] = null;
      final profile = AppUserProfile.fromMap(map);
      expect(profile.prayerRequest, isNull);
    });
  });
}
