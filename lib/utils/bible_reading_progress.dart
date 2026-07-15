import 'bible_book_meta.dart';

typedef BibleReadingTarget = ({int bookNo, int chapterNo});

/// 저장된 완료 장 가운데 성경 순서상 가장 뒤의 장 다음 위치를 반환한다.
///
/// 완료 기록이 없으면 창세기 1장, 요한계시록 22장까지 완료했으면 null이다.
BibleReadingTarget? nextBibleReadingTarget(Set<String> completedChapterKeys) {
  BibleReadingTarget? latest;
  for (var bookNo = 1; bookNo <= bibleBooks.length; bookNo += 1) {
    final maxChapter = bibleBooks[bookNo - 1].chapters;
    for (var chapterNo = 1; chapterNo <= maxChapter; chapterNo += 1) {
      final key = bibleChapterProgressKey(bookNo: bookNo, chapterNo: chapterNo);
      if (completedChapterKeys.contains(key)) {
        latest = (bookNo: bookNo, chapterNo: chapterNo);
      }
    }
  }
  if (latest == null) {
    return (bookNo: oldTestamentFirstBookNo, chapterNo: 1);
  }
  final lastBookNo = latest.bookNo.clamp(1, bibleBooks.length).toInt();
  final lastChapterNo = latest.chapterNo
      .clamp(1, bibleBooks[lastBookNo - 1].chapters)
      .toInt();
  if (lastChapterNo < bibleBooks[lastBookNo - 1].chapters) {
    return (bookNo: lastBookNo, chapterNo: lastChapterNo + 1);
  }
  if (lastBookNo < bibleBooks.length) {
    return (bookNo: lastBookNo + 1, chapterNo: 1);
  }
  return null;
}

String bibleReadingTargetLabel(BibleReadingTarget? target) {
  if (target == null) {
    return '통독 완료';
  }
  final bookNo = target.bookNo.clamp(1, bibleBooks.length).toInt();
  return '${bibleBooks[bookNo - 1].name} ${target.chapterNo}장';
}
