import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/bible_book_meta.dart';
import 'package:story_bible/utils/bible_reading_progress.dart';

void main() {
  group('nextBibleReadingTarget', () {
    test('완료 기록이 없으면 창세기 1장을 반환한다', () {
      final target = nextBibleReadingTarget(const <String>{});

      expect(target, (bookNo: 1, chapterNo: 1));
      expect(bibleReadingTargetLabel(target), '창세기 1장');
    });

    test('마지막 완료 장의 다음 장을 반환한다', () {
      final target = nextBibleReadingTarget({
        bibleChapterProgressKey(bookNo: 1, chapterNo: 12),
        bibleChapterProgressKey(bookNo: 1, chapterNo: 13),
      });

      expect(target, (bookNo: 1, chapterNo: 14));
      expect(bibleReadingTargetLabel(target), '창세기 14장');
    });

    test('한 권의 마지막 장 다음에는 다음 권 1장을 반환한다', () {
      final target = nextBibleReadingTarget({
        bibleChapterProgressKey(bookNo: 1, chapterNo: 50),
      });

      expect(target, (bookNo: 2, chapterNo: 1));
      expect(bibleReadingTargetLabel(target), '출애굽기 1장');
    });

    test('요한계시록 마지막 장까지 완료하면 null을 반환한다', () {
      final target = nextBibleReadingTarget({
        bibleChapterProgressKey(bookNo: 66, chapterNo: 22),
      });

      expect(target, isNull);
      expect(bibleReadingTargetLabel(target), '통독 완료');
    });
  });
}
