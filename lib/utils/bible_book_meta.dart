// 성경 책 메타데이터와 참조 문자열 파서.
//
// story_home_screen.dart에서 추출한 공통 유틸리티다.
// - bibleBooks: 66권의 이름 + 장 수
// - parseBibleNavigationTarget: "마 1:1" 같은 참조를 BibleNavigationTarget으로 변환

class BibleBookMeta {
  const BibleBookMeta({required this.name, required this.chapters});

  final String name;
  final int chapters;
}

class BibleNavigationTarget {
  const BibleNavigationTarget({
    required this.bookNo,
    required this.chapterNo,
    required this.verseNo,
    this.endChapterNo,
    this.endVerseNo,
  });

  final int bookNo;
  final int chapterNo;
  final int verseNo;
  final int? endChapterNo;
  final int? endVerseNo;

  bool containsVerse({
    required int bookNo,
    required int chapterNo,
    required int verseNo,
  }) {
    if (bookNo != this.bookNo) {
      return false;
    }
    final start = (chapter: this.chapterNo, verse: this.verseNo);
    final end = (
      chapter: endChapterNo ?? this.chapterNo,
      verse: endVerseNo ?? this.verseNo,
    );
    final lo = _compareBiblePosition(start, end) <= 0 ? start : end;
    final hi = _compareBiblePosition(start, end) <= 0 ? end : start;
    final current = (chapter: chapterNo, verse: verseNo);
    return _compareBiblePosition(lo, current) <= 0 &&
        _compareBiblePosition(current, hi) <= 0;
  }

  bool isBoundaryVerse({
    required int bookNo,
    required int chapterNo,
    required int verseNo,
  }) {
    if (bookNo != this.bookNo) {
      return false;
    }
    final endChapter = endChapterNo ?? this.chapterNo;
    final endVerse = endVerseNo ?? this.verseNo;
    return (chapterNo == this.chapterNo && verseNo == this.verseNo) ||
        (chapterNo == endChapter && verseNo == endVerse);
  }
}

int _compareBiblePosition(
  ({int chapter, int verse}) left,
  ({int chapter, int verse}) right,
) {
  final chapterCompare = left.chapter.compareTo(right.chapter);
  if (chapterCompare != 0) {
    return chapterCompare;
  }
  return left.verse.compareTo(right.verse);
}

String normalizeBibleBookKey(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
}

const Map<String, int> bibleRefAliasBookLookup = {
  '창': 1,
  '출': 2,
  '레': 3,
  '민': 4,
  '신': 5,
  '수': 6,
  '삿': 7,
  '룻': 8,
  '삼상': 9,
  '삼하': 10,
  '왕상': 11,
  '왕하': 12,
  '대상': 13,
  '대하': 14,
  '스': 15,
  '느': 16,
  '에': 17,
  '욥': 18,
  '시': 19,
  '잠': 20,
  '전': 21,
  '아': 22,
  '사': 23,
  '렘': 24,
  '애': 25,
  '겔': 26,
  '단': 27,
  '호': 28,
  '욜': 29,
  '암': 30,
  '옵': 31,
  '욘': 32,
  '미': 33,
  '나': 34,
  '합': 35,
  '습': 36,
  '학': 37,
  '슥': 38,
  '말': 39,
  '마': 40,
  '막': 41,
  '눅': 42,
  '요': 43,
  '행': 44,
  '롬': 45,
  '고전': 46,
  '고후': 47,
  '갈': 48,
  '엡': 49,
  '빌': 50,
  '골': 51,
  '살전': 52,
  '살후': 53,
  '딤전': 54,
  '딤후': 55,
  '딛': 56,
  '몬': 57,
  '히': 58,
  '약': 59,
  '벧전': 60,
  '벧후': 61,
  '요일': 62,
  '요이': 63,
  '요삼': 64,
  '유': 65,
  '계': 66,
};

const List<BibleBookMeta> bibleBooks = [
  BibleBookMeta(name: '창세기', chapters: 50),
  BibleBookMeta(name: '출애굽기', chapters: 40),
  BibleBookMeta(name: '레위기', chapters: 27),
  BibleBookMeta(name: '민수기', chapters: 36),
  BibleBookMeta(name: '신명기', chapters: 34),
  BibleBookMeta(name: '여호수아', chapters: 24),
  BibleBookMeta(name: '사사기', chapters: 21),
  BibleBookMeta(name: '룻기', chapters: 4),
  BibleBookMeta(name: '사무엘상', chapters: 31),
  BibleBookMeta(name: '사무엘하', chapters: 24),
  BibleBookMeta(name: '열왕기상', chapters: 22),
  BibleBookMeta(name: '열왕기하', chapters: 25),
  BibleBookMeta(name: '역대상', chapters: 29),
  BibleBookMeta(name: '역대하', chapters: 36),
  BibleBookMeta(name: '에스라', chapters: 10),
  BibleBookMeta(name: '느헤미야', chapters: 13),
  BibleBookMeta(name: '에스더', chapters: 10),
  BibleBookMeta(name: '욥기', chapters: 42),
  BibleBookMeta(name: '시편', chapters: 150),
  BibleBookMeta(name: '잠언', chapters: 31),
  BibleBookMeta(name: '전도서', chapters: 12),
  BibleBookMeta(name: '아가', chapters: 8),
  BibleBookMeta(name: '이사야', chapters: 66),
  BibleBookMeta(name: '예레미야', chapters: 52),
  BibleBookMeta(name: '예레미야애가', chapters: 5),
  BibleBookMeta(name: '에스겔', chapters: 48),
  BibleBookMeta(name: '다니엘', chapters: 12),
  BibleBookMeta(name: '호세아', chapters: 14),
  BibleBookMeta(name: '요엘', chapters: 3),
  BibleBookMeta(name: '아모스', chapters: 9),
  BibleBookMeta(name: '오바댜', chapters: 1),
  BibleBookMeta(name: '요나', chapters: 4),
  BibleBookMeta(name: '미가', chapters: 7),
  BibleBookMeta(name: '나훔', chapters: 3),
  BibleBookMeta(name: '하박국', chapters: 3),
  BibleBookMeta(name: '스바냐', chapters: 3),
  BibleBookMeta(name: '학개', chapters: 2),
  BibleBookMeta(name: '스가랴', chapters: 14),
  BibleBookMeta(name: '말라기', chapters: 4),
  BibleBookMeta(name: '마태복음', chapters: 28),
  BibleBookMeta(name: '마가복음', chapters: 16),
  BibleBookMeta(name: '누가복음', chapters: 24),
  BibleBookMeta(name: '요한복음', chapters: 21),
  BibleBookMeta(name: '사도행전', chapters: 28),
  BibleBookMeta(name: '로마서', chapters: 16),
  BibleBookMeta(name: '고린도전서', chapters: 16),
  BibleBookMeta(name: '고린도후서', chapters: 13),
  BibleBookMeta(name: '갈라디아서', chapters: 6),
  BibleBookMeta(name: '에베소서', chapters: 6),
  BibleBookMeta(name: '빌립보서', chapters: 4),
  BibleBookMeta(name: '골로새서', chapters: 4),
  BibleBookMeta(name: '데살로니가전서', chapters: 5),
  BibleBookMeta(name: '데살로니가후서', chapters: 3),
  BibleBookMeta(name: '디모데전서', chapters: 6),
  BibleBookMeta(name: '디모데후서', chapters: 4),
  BibleBookMeta(name: '디도서', chapters: 3),
  BibleBookMeta(name: '빌레몬서', chapters: 1),
  BibleBookMeta(name: '히브리서', chapters: 13),
  BibleBookMeta(name: '야고보서', chapters: 5),
  BibleBookMeta(name: '베드로전서', chapters: 5),
  BibleBookMeta(name: '베드로후서', chapters: 3),
  BibleBookMeta(name: '요한일서', chapters: 5),
  BibleBookMeta(name: '요한이서', chapters: 1),
  BibleBookMeta(name: '요한삼서', chapters: 1),
  BibleBookMeta(name: '유다서', chapters: 1),
  BibleBookMeta(name: '요한계시록', chapters: 22),
];

final Map<String, int> bibleRefBookLookup = () {
  final map = <String, int>{};
  for (var i = 0; i < bibleBooks.length; i++) {
    map[normalizeBibleBookKey(bibleBooks[i].name)] = i + 1;
  }
  map.addAll(bibleRefAliasBookLookup);
  return map;
}();

/// 책 번호(1~66) → 짧은 한글 약어 (예: 1 → "창", 9 → "삼상").
/// `bibleRefAliasBookLookup` 의 역매핑. events.bible_refs 가 약어를 사용하므로
/// 현재 책+장 → era 를 찾을 때 필요하다.
final Map<int, String> bibleBookNoToAlias = () {
  final map = <int, String>{};
  bibleRefAliasBookLookup.forEach((alias, bookNo) {
    map.putIfAbsent(bookNo, () => alias);
  });
  return Map<int, String>.unmodifiable(map);
}();

BibleNavigationTarget? parseBibleNavigationTarget(String? rawRef) {
  if (rawRef == null) {
    return null;
  }
  final normalized = rawRef
      .replaceAll('：', ':')
      .replaceAll('∼', '-')
      .replaceAll('~', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .trim();
  if (normalized.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^([가-힣]+)\s*(\d+)\s*[:장]\s*(\d+)(?:\s*-\s*(?:(\d+)\s*[:장]\s*)?(\d+))?',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final rawBook = match.group(1) ?? '';
  final bookNo = bibleRefBookLookup[normalizeBibleBookKey(rawBook)];
  if (bookNo == null) {
    return null;
  }

  final chapterNo = int.tryParse(match.group(2) ?? '');
  final verseNo = int.tryParse(match.group(3) ?? '');
  final rawEndChapter = match.group(4);
  final rawEndVerse = match.group(5);
  final endChapterNo = rawEndChapter == null || rawEndChapter.isEmpty
      ? chapterNo
      : int.tryParse(rawEndChapter);
  final endVerseNo = rawEndVerse == null || rawEndVerse.isEmpty
      ? null
      : int.tryParse(rawEndVerse);
  if (chapterNo == null || chapterNo <= 0 || verseNo == null || verseNo <= 0) {
    return null;
  }
  if (rawEndVerse != null &&
      (endChapterNo == null ||
          endChapterNo <= 0 ||
          endVerseNo == null ||
          endVerseNo <= 0)) {
    return null;
  }

  final maxChapter = bibleBooks[bookNo - 1].chapters;
  final safeChapter = chapterNo > maxChapter ? maxChapter : chapterNo;
  final safeEndChapter = endChapterNo == null || endChapterNo > maxChapter
      ? maxChapter
      : endChapterNo;
  return BibleNavigationTarget(
    bookNo: bookNo,
    chapterNo: safeChapter,
    verseNo: verseNo,
    endChapterNo: rawEndVerse == null ? null : safeEndChapter,
    endVerseNo: rawEndVerse == null ? null : endVerseNo,
  );
}
