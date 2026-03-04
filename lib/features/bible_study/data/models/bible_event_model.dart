import 'verse_page_model.dart';

class BibleEvent {
  const BibleEvent({
    required this.id,
    required this.bookId,
    required this.title,
    required this.verseRef,
    required this.emoji,
    required this.section,
    required this.sectionOrder,
    required this.orderNum,
    required this.snippet,
    required this.quote,
    required this.summary,
    required this.boxTitle,
    required this.points,
    required this.versePages,
    required this.places,
    required this.persons,
    required this.isCompleted,
    this.isDetailLoaded = false,
  });

  final String id;
  final int bookId;
  final String title;
  final String verseRef;
  final String emoji;
  final String section;
  final int sectionOrder;
  final int orderNum;
  final String snippet;
  final String quote;
  final String summary;
  final String boxTitle;
  final List<EventPoint> points;
  final List<VersePage> versePages;
  final List<String> places;
  final List<String> persons;
  final bool isCompleted;
  final bool isDetailLoaded;

  BibleEvent copyWith({
    bool? isCompleted,
    List<EventPoint>? points,
    List<VersePage>? versePages,
    List<String>? places,
    List<String>? persons,
    bool? isDetailLoaded,
  }) {
    return BibleEvent(
      id: id,
      bookId: bookId,
      title: title,
      verseRef: verseRef,
      emoji: emoji,
      section: section,
      sectionOrder: sectionOrder,
      orderNum: orderNum,
      snippet: snippet,
      quote: quote,
      summary: summary,
      boxTitle: boxTitle,
      points: points ?? this.points,
      versePages: versePages ?? this.versePages,
      places: places ?? this.places,
      persons: persons ?? this.persons,
      isCompleted: isCompleted ?? this.isCompleted,
      isDetailLoaded: isDetailLoaded ?? this.isDetailLoaded,
    );
  }

  factory BibleEvent.fromJson(
    Map<String, dynamic> json, {
    bool isCompleted = false,
  }) {
    final pointRows =
        (json['event_points'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => (a['order_num'] as int? ?? 0).compareTo(
              b['order_num'] as int? ?? 0,
            ),
          );
    final verseRows =
        (json['verse_pages'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => (a['order_num'] as int? ?? 0).compareTo(
              b['order_num'] as int? ?? 0,
            ),
          );
    final placeRows = (json['event_places'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final personRows = (json['event_persons'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    return BibleEvent(
      id: json['id'] as String,
      bookId: json['book_id'] as int,
      title: json['title'] as String,
      verseRef: json['verse_ref'] as String,
      emoji: (json['emoji'] as String?) ?? '📖',
      section: (json['section'] as String?) ?? '기타',
      sectionOrder: (json['section_order'] as int?) ?? 0,
      orderNum: json['order_num'] as int,
      snippet: (json['snippet'] as String?) ?? '',
      quote: (json['quote'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      boxTitle: (json['box_title'] as String?) ?? '핵심 메시지',
      points: pointRows.map(EventPoint.fromJson).toList(),
      versePages: verseRows.map(VersePage.fromJson).toList(),
      places: placeRows
          .map((row) => row['name'] as String?)
          .whereType<String>()
          .toList(),
      persons: personRows
          .map((row) => row['name'] as String?)
          .whereType<String>()
          .toList(),
      isCompleted: isCompleted,
      isDetailLoaded: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'book_id': bookId,
      'title': title,
      'verse_ref': verseRef,
      'emoji': emoji,
      'section': section,
      'section_order': sectionOrder,
      'order_num': orderNum,
      'snippet': snippet,
      'quote': quote,
      'summary': summary,
      'box_title': boxTitle,
      'event_points': points.map((e) => e.toJson()).toList(),
      'verse_pages': versePages.map((e) => e.toJson()).toList(),
      'event_places': places.map((e) => {'name': e}).toList(),
      'event_persons': persons.map((e) => {'name': e}).toList(),
      'is_completed': isCompleted,
      'is_detail_loaded': isDetailLoaded,
    };
  }
}

class EventPoint {
  const EventPoint({
    required this.orderNum,
    required this.boldLabel,
    required this.content,
  });

  final int orderNum;
  final String boldLabel;
  final String content;

  factory EventPoint.fromJson(Map<String, dynamic> json) {
    return EventPoint(
      orderNum: json['order_num'] as int,
      boldLabel: json['bold_label'] as String,
      content: json['content'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'order_num': orderNum, 'bold_label': boldLabel, 'content': content};
  }
}
