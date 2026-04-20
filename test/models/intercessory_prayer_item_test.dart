import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/intercessory_prayer_item.dart';

void main() {
  group('IntercessoryPrayerItem.fromMap', () {
    final validMap = <String, dynamic>{
      'id': 'ip1',
      'target_user_id': 'u2',
      'share_id': 'XYZ7890',
      'nickname': '김철수',
      'photo_url': 'https://example.com/photo.png',
      'prayer_request': '건강을 위해 기도해주세요',
      'created_at': '2024-05-20T14:00:00Z',
    };

    test('유효한 map에서 모든 필드를 올바르게 파싱한다', () {
      final item = IntercessoryPrayerItem.fromMap(validMap);
      expect(item.id, 'ip1');
      expect(item.targetUserId, 'u2');
      expect(item.shareId, 'XYZ7890');
      expect(item.nickname, '김철수');
      expect(item.photoUrl, 'https://example.com/photo.png');
      expect(item.prayerRequest, '건강을 위해 기도해주세요');
      expect(item.createdAt, DateTime.parse('2024-05-20T14:00:00Z'));
    });

    test('nickname이 null이면 "사용자"로 기본값 설정', () {
      final map = Map<String, dynamic>.from(validMap)..['nickname'] = null;
      final item = IntercessoryPrayerItem.fromMap(map);
      expect(item.nickname, '사용자');
    });

    test('nickname이 빈 문자열이면 "사용자"로 기본값 설정', () {
      final map = Map<String, dynamic>.from(validMap)..['nickname'] = '';
      final item = IntercessoryPrayerItem.fromMap(map);
      expect(item.nickname, '사용자');
    });

    test('share_id가 null이면 빈 문자열로 처리', () {
      final map = Map<String, dynamic>.from(validMap)..['share_id'] = null;
      final item = IntercessoryPrayerItem.fromMap(map);
      expect(item.shareId, '');
    });

    test('photo_url이 null이면 null 유지', () {
      final map = Map<String, dynamic>.from(validMap)..['photo_url'] = null;
      final item = IntercessoryPrayerItem.fromMap(map);
      expect(item.photoUrl, isNull);
    });

    test('prayer_request가 null이면 null 유지', () {
      final map = Map<String, dynamic>.from(validMap)
        ..['prayer_request'] = null;
      final item = IntercessoryPrayerItem.fromMap(map);
      expect(item.prayerRequest, isNull);
    });
  });
}
