class SavedBibleVerse {
  const SavedBibleVerse({
    required this.id,
    required this.userId,
    required this.translation,
    required this.bookNo,
    required this.bookName,
    required this.chapterNo,
    required this.verseNo,
    required this.verseText,
    required this.createdAt,
    DateTime? updatedAt,
    this.comment = '',
    this.isSaved = true,
    this.highlightColor,
  }) : updatedAt = updatedAt ?? createdAt;

  static const highlightBlue = 'blue';
  static const highlightYellow = 'yellow';
  static const highlightColors = {highlightBlue, highlightYellow};

  final String id;
  final String userId;
  final String translation;
  final int bookNo;
  final String bookName;
  final int chapterNo;
  final int verseNo;
  final String verseText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String comment;
  final bool isSaved;
  final String? highlightColor;

  String get referenceText => '$bookName $chapterNo:$verseNo';

  bool get isHighlighted => highlightColor != null;

  String get key => buildVerseKey(
    translation: translation,
    bookNo: bookNo,
    chapterNo: chapterNo,
    verseNo: verseNo,
  );

  factory SavedBibleVerse.fromMap(Map<String, dynamic> map) {
    return SavedBibleVerse(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      translation: map['translation'] as String,
      bookNo: map['book_no'] as int,
      bookName: map['book_name'] as String,
      chapterNo: map['chapter_no'] as int,
      verseNo: map['verse_no'] as int,
      verseText: map['verse_text'] as String,
      comment: (map['comment'] as String?) ?? '',
      isSaved: (map['is_saved'] as bool?) ?? true,
      highlightColor: normalizeHighlightColor(
        map['highlight_color'] as String?,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
    );
  }

  static String? normalizeHighlightColor(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return highlightColors.contains(normalized) ? normalized : null;
  }

  static String buildVerseKey({
    required String translation,
    required int bookNo,
    required int chapterNo,
    required int verseNo,
  }) {
    return '$translation:$bookNo:$chapterNo:$verseNo';
  }
}
