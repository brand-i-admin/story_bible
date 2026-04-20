import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/user_note.dart';

void main() {
  group('UserNote.fromMap', () {
    final validMap = <String, dynamic>{
      'id': 'n1',
      'user_id': 'u1',
      'title': '오늘의 묵상',
      'content': '창세기 1장을 읽고 느낀 점',
      'created_at': '2024-04-01T08:00:00Z',
      'updated_at': '2024-04-01T09:30:00Z',
    };

    test('유효한 map에서 모든 필드를 올바르게 파싱한다', () {
      final note = UserNote.fromMap(validMap);
      expect(note.id, 'n1');
      expect(note.userId, 'u1');
      expect(note.title, '오늘의 묵상');
      expect(note.content, '창세기 1장을 읽고 느낀 점');
      expect(note.createdAt, DateTime.parse('2024-04-01T08:00:00Z'));
      expect(note.updatedAt, DateTime.parse('2024-04-01T09:30:00Z'));
    });
  });

  group('UserNote.previewLine', () {
    test('72자 이하면 그대로 반환 (공백 정규화)', () {
      final note = UserNote(
        id: 'n1',
        userId: 'u1',
        title: '테스트',
        content: '짧은  내용\n입니다',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(note.previewLine, '짧은 내용 입니다');
    });

    test('72자 초과면 72자에서 잘리고 ... 추가', () {
      final longContent = 'A' * 100;
      final note = UserNote(
        id: 'n1',
        userId: 'u1',
        title: '테스트',
        content: longContent,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(note.previewLine.length, 75); // 72 + '...'
      expect(note.previewLine.endsWith('...'), true);
    });

    test('정확히 72자면 잘리지 않음', () {
      final content = 'B' * 72;
      final note = UserNote(
        id: 'n1',
        userId: 'u1',
        title: '테스트',
        content: content,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(note.previewLine, content);
      expect(note.previewLine.contains('...'), false);
    });

    test('빈 content는 빈 문자열 반환', () {
      final note = UserNote(
        id: 'n1',
        userId: 'u1',
        title: '테스트',
        content: '',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(note.previewLine, '');
    });
  });
}
