import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_verse.dart';

void main() {
  group('BibleVerse.fromMap', () {
    test('유효한 map에서 모든 필드를 파싱한다', () {
      final map = <String, dynamic>{
        'translation': 'KRV',
        'book_no': 1,
        'book_name': '창세기',
        'chapter_no': 1,
        'verse_no': 1,
        'verse_text': '태초에 하나님이 천지를 창조하시니라',
      };

      final verse = BibleVerse.fromMap(map);

      expect(verse.translation, 'KRV');
      expect(verse.bookNo, 1);
      expect(verse.bookName, '창세기');
      expect(verse.chapterNo, 1);
      expect(verse.verseNo, 1);
      expect(verse.verseText, '태초에 하나님이 천지를 창조하시니라');
    });

    test('const 생성자로 생성 가능하다', () {
      const verse = BibleVerse(
        translation: 'KRV',
        bookNo: 1,
        bookName: '창세기',
        chapterNo: 1,
        verseNo: 1,
        verseText: '태초에 하나님이 천지를 창조하시니라',
      );

      expect(verse.translation, 'KRV');
    });
  });
}
