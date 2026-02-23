class BibleVerse {
  const BibleVerse({
    required this.translation,
    required this.bookNo,
    required this.bookName,
    required this.chapterNo,
    required this.verseNo,
    required this.verseText,
  });

  final String translation;
  final int bookNo;
  final String bookName;
  final int chapterNo;
  final int verseNo;
  final String verseText;

  factory BibleVerse.fromMap(Map<String, dynamic> map) {
    return BibleVerse(
      translation: map['translation'] as String,
      bookNo: map['book_no'] as int,
      bookName: map['book_name'] as String,
      chapterNo: map['chapter_no'] as int,
      verseNo: map['verse_no'] as int,
      verseText: map['verse_text'] as String,
    );
  }
}
