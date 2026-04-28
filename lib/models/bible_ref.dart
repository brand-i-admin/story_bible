/// `events.bible_refs` jsonb 항목 한 건을 표현한다.
///
/// JSON 형태(저장된 그대로): `{"book": "창", "from": "1:1", "to": "2:3"}`.
/// `book`은 한국어 약어, `from`/`to`는 `chapter:verse` 문자열이다.
class BibleRef {
  const BibleRef({required this.book, required this.from, required this.to});

  factory BibleRef.fromMap(Map<String, dynamic> map) {
    return BibleRef(
      book: (map['book'] as String?)?.trim() ?? '',
      from: (map['from'] as String?)?.trim() ?? '',
      to: (map['to'] as String?)?.trim() ?? '',
    );
  }

  static List<BibleRef> fromList(dynamic raw) {
    if (raw is! List) {
      return const <BibleRef>[];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(BibleRef.fromMap)
        .toList(growable: false);
  }

  final String book;
  final String from;
  final String to;

  String get displayText {
    if (book.isEmpty) {
      return '';
    }
    if (from.isEmpty) {
      return book;
    }
    if (to.isEmpty || from == to) {
      return '$book $from';
    }
    return '$book $from-$to';
  }

  @override
  String toString() => displayText;

  @override
  bool operator ==(Object other) =>
      other is BibleRef &&
      other.book == book &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(book, from, to);
}
