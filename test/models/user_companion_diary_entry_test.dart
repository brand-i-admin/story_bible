import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/user_companion_diary_entry.dart';

void main() {
  group('UserCompanionDiaryEntry.fromMap', () {
    test('Supabase row를 동행 일지 모델로 변환한다', () {
      final entry = UserCompanionDiaryEntry.fromMap({
        'id': 'entry_1',
        'user_id': 'user_1',
        'entry_date': '2026-06-23',
        'title': '오늘의 걸음',
        'body': '기도하며 하루를 돌아보았습니다.',
        'created_at': '2026-06-23T01:00:00Z',
        'updated_at': '2026-06-23T02:00:00Z',
      });

      expect(entry.id, 'entry_1');
      expect(entry.userId, 'user_1');
      expect(entry.entryDate, DateTime(2026, 6, 23));
      expect(entry.title, '오늘의 걸음');
      expect(entry.body, '기도하며 하루를 돌아보았습니다.');
      expect(entry.createdAt, DateTime.parse('2026-06-23T01:00:00Z'));
      expect(entry.updatedAt, DateTime.parse('2026-06-23T02:00:00Z'));
    });
  });
}
