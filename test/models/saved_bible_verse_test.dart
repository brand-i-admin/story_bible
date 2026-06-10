import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/saved_bible_verse.dart';

void main() {
  group('SavedBibleVerse.fromMap', () {
    final validMap = <String, dynamic>{
      'id': 'v1',
      'user_id': 'u1',
      'translation': 'KRV',
      'book_no': 1,
      'book_name': '창세기',
      'chapter_no': 1,
      'verse_no': 1,
      'verse_text': '태초에 하나님이 천지를 창조하시니라',
      'comment': '창조의 시작을 기억하고 싶어서',
      'created_at': '2024-03-10T09:00:00Z',
    };

    test('유효한 map에서 모든 필드를 올바르게 파싱한다', () {
      final verse = SavedBibleVerse.fromMap(validMap);
      expect(verse.id, 'v1');
      expect(verse.userId, 'u1');
      expect(verse.translation, 'KRV');
      expect(verse.bookNo, 1);
      expect(verse.bookName, '창세기');
      expect(verse.chapterNo, 1);
      expect(verse.verseNo, 1);
      expect(verse.verseText, '태초에 하나님이 천지를 창조하시니라');
      expect(verse.comment, '창조의 시작을 기억하고 싶어서');
      expect(verse.createdAt, DateTime.parse('2024-03-10T09:00:00Z'));
    });

    test('comment가 없으면 빈 문자열로 파싱한다', () {
      final verse = SavedBibleVerse.fromMap({...validMap, 'comment': null});

      expect(verse.comment, '');
    });
  });

  group('SavedBibleVerse.referenceText', () {
    test('bookName chapter:verse 형식', () {
      final verse = SavedBibleVerse(
        id: 'v1',
        userId: 'u1',
        translation: 'KRV',
        bookNo: 1,
        bookName: '창세기',
        chapterNo: 1,
        verseNo: 27,
        verseText: '',
        createdAt: DateTime(2024),
      );
      expect(verse.referenceText, '창세기 1:27');
    });
  });

  group('SavedBibleVerse.key', () {
    test('translation:bookNo:chapterNo:verseNo 형식', () {
      final verse = SavedBibleVerse(
        id: 'v1',
        userId: 'u1',
        translation: 'KRV',
        bookNo: 43,
        bookName: '요한복음',
        chapterNo: 3,
        verseNo: 16,
        verseText: '',
        createdAt: DateTime(2024),
      );
      expect(verse.key, 'KRV:43:3:16');
    });
  });

  group('SavedBibleVerse.buildVerseKey', () {
    test('정적 메소드도 동일한 형식', () {
      expect(
        SavedBibleVerse.buildVerseKey(
          translation: 'NIV',
          bookNo: 1,
          chapterNo: 1,
          verseNo: 1,
        ),
        'NIV:1:1:1',
      );
    });
  });
}
