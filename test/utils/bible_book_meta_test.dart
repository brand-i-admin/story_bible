import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/bible_book_meta.dart';

void main() {
  group('bibleBooks', () {
    test('66권이 정의되어 있다', () {
      expect(bibleBooks.length, 66);
    });

    test('창세기는 50장이다', () {
      expect(bibleBooks[0].name, '창세기');
      expect(bibleBooks[0].chapters, 50);
    });

    test('요한계시록은 22장이다', () {
      expect(bibleBooks[65].name, '요한계시록');
      expect(bibleBooks[65].chapters, 22);
    });

    test('시편은 150장이다', () {
      final psalms = bibleBooks.firstWhere((b) => b.name == '시편');
      expect(psalms.chapters, 150);
    });
  });

  group('bibleRefAliasBookLookup', () {
    test('66권의 한글 약자가 모두 정의되어 있다', () {
      expect(bibleRefAliasBookLookup.length, 66);
    });

    test('창 → 1, 계 → 66', () {
      expect(bibleRefAliasBookLookup['창'], 1);
      expect(bibleRefAliasBookLookup['계'], 66);
    });
  });

  group('parseBibleNavigationTarget', () {
    test('null을 받으면 null을 반환한다', () {
      expect(parseBibleNavigationTarget(null), isNull);
    });

    test('빈 문자열을 받으면 null을 반환한다', () {
      expect(parseBibleNavigationTarget(''), isNull);
      expect(parseBibleNavigationTarget('   '), isNull);
    });

    test('유효한 약자 참조를 파싱한다 (창 1:1)', () {
      final target = parseBibleNavigationTarget('창 1:1');
      expect(target, isNotNull);
      expect(target!.bookNo, 1);
      expect(target.chapterNo, 1);
      expect(target.verseNo, 1);
    });

    test('유효한 풀네임 참조를 파싱한다 (창세기 1:1)', () {
      final target = parseBibleNavigationTarget('창세기 1:1');
      expect(target, isNotNull);
      expect(target!.bookNo, 1);
    });

    test('장 표기도 인식한다 (마 5장 3)', () {
      final target = parseBibleNavigationTarget('마 5장 3');
      expect(target, isNotNull);
      expect(target!.bookNo, 40);
      expect(target.chapterNo, 5);
      expect(target.verseNo, 3);
    });

    test('잘못된 책 이름은 null을 반환한다', () {
      expect(parseBibleNavigationTarget('존재하지않음 1:1'), isNull);
    });

    test('장 수가 범위를 초과하면 최대 장으로 보정한다', () {
      // 창세기는 50장까지
      final target = parseBibleNavigationTarget('창 100:5');
      expect(target, isNotNull);
      expect(target!.chapterNo, 50);
    });

    test('전각 콜론도 처리한다', () {
      final target = parseBibleNavigationTarget('창 1：1');
      expect(target, isNotNull);
      expect(target!.chapterNo, 1);
      expect(target.verseNo, 1);
    });
  });

  group('normalizeBibleBookKey', () {
    test('공백과 대소문자를 정규화한다', () {
      expect(normalizeBibleBookKey('  Mark  '), 'mark');
      expect(normalizeBibleBookKey('창 세 기'), '창세기');
    });
  });
}
