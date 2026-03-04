import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bible_event_model.dart';
import '../models/book_model.dart';
import '../models/verse_page_model.dart';

class BibleStudyRepository {
  const BibleStudyRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Book>> getBooks(String testament) async {
    final rows = await _supabase
        .from('books')
        .select()
        .eq('testament', testament)
        .order('order_num', ascending: true);

    return rows.map<Book>((row) => Book.fromJson(row)).toList();
  }

  Future<List<BibleEvent>> getEvents(int bookId, String? userId) async {
    final rows = await _supabase
        .from('study_event_meta')
        .select('''
      event_id,
      book_id,
      order_num,
      section,
      section_order,
      emoji,
      snippet,
      quote,
      box_title,
      events!inner(
        id,
        title,
        summary,
        place_name,
        event_bible_refs(display_text),
        event_persons(person_id, persons(name))
      )
    ''')
        .eq('book_id', bookId)
        .order('order_num', ascending: true);

    final eventIds = rows
        .map((row) => row['event_id'] as String?)
        .whereType<String>()
        .toList();
    final progressMap = await _progressByEvent(
      eventIds: eventIds,
      userId: userId,
    );

    return rows.map<BibleEvent>((row) {
      final eventId = row['event_id'] as String;
      final event = row['events'] as Map<String, dynamic>;
      final refs = (event['event_bible_refs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final personRows = (event['event_persons'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final verseRef =
          refs
              .map((refRow) => refRow['display_text'] as String?)
              .whereType<String>()
              .firstOrNull ??
          '';
      final persons = personRows
          .map((personRow) {
            final person = personRow['persons'] as Map<String, dynamic>?;
            return person?['name'] as String?;
          })
          .whereType<String>()
          .toList();
      final placeName = event['place_name'] as String?;

      return BibleEvent(
        id: eventId,
        bookId: row['book_id'] as int,
        title: event['title'] as String? ?? '',
        verseRef: verseRef,
        emoji: row['emoji'] as String? ?? '📖',
        section: row['section'] as String? ?? '기타',
        sectionOrder: row['section_order'] as int? ?? 0,
        orderNum: row['order_num'] as int,
        snippet: row['snippet'] as String? ?? '',
        quote: row['quote'] as String? ?? '',
        summary: event['summary'] as String? ?? '',
        boxTitle: row['box_title'] as String? ?? '핵심 메시지',
        points: const [],
        versePages: const [],
        places: placeName == null || placeName.isEmpty ? const [] : [placeName],
        persons: persons,
        isCompleted: progressMap[eventId] ?? false,
        isDetailLoaded: false,
      );
    }).toList();
  }

  Future<BibleEvent> getEventDetail(String eventId, String? userId) async {
    final row = await _supabase
        .from('study_event_meta')
        .select('''
      event_id,
      book_id,
      order_num,
      section,
      section_order,
      emoji,
      snippet,
      quote,
      box_title,
      events!inner(
        id,
        title,
        summary,
        place_name,
        event_bible_refs(display_text),
        event_persons(person_id, persons(name))
      )
    ''')
        .eq('event_id', eventId)
        .single();

    bool isCompleted = false;
    if (userId != null) {
      final progress = await _supabase
          .from('user_event_progress')
          .select('is_completed')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .maybeSingle();
      isCompleted = progress?['is_completed'] as bool? ?? false;
    }

    final event = row['events'] as Map<String, dynamic>;
    final refs = (event['event_bible_refs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final personRows = (event['event_persons'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final pointsByEvent = await _loadPointsByEvent([eventId]);
    final pagesByEvent = await _loadPagesByEvent([eventId]);

    return BibleEvent(
      id: eventId,
      bookId: row['book_id'] as int,
      title: event['title'] as String? ?? '',
      verseRef:
          refs
              .map((refRow) => refRow['display_text'] as String?)
              .whereType<String>()
              .firstOrNull ??
          '',
      emoji: row['emoji'] as String? ?? '📖',
      section: row['section'] as String? ?? '기타',
      sectionOrder: row['section_order'] as int? ?? 0,
      orderNum: row['order_num'] as int,
      snippet: row['snippet'] as String? ?? '',
      quote: row['quote'] as String? ?? '',
      summary: event['summary'] as String? ?? '',
      boxTitle: row['box_title'] as String? ?? '핵심 메시지',
      points: pointsByEvent[eventId] ?? const [],
      versePages: pagesByEvent[eventId] ?? const [],
      places: (event['place_name'] as String?)?.isNotEmpty == true
          ? [event['place_name'] as String]
          : const [],
      persons: personRows
          .map((personRow) {
            final person = personRow['persons'] as Map<String, dynamic>?;
            return person?['name'] as String?;
          })
          .whereType<String>()
          .toList(),
      isCompleted: isCompleted,
      isDetailLoaded: true,
    );
  }

  Future<void> toggleProgress(
    String eventId,
    String userId,
    bool completed,
  ) async {
    await _supabase.from('user_event_progress').upsert({
      'user_id': userId,
      'event_id': eventId,
      'is_completed': completed,
      'score': 0,
      'xp_earned': 0,
      'completed_at': completed ? DateTime.now().toIso8601String() : null,
    }, onConflict: 'user_id,event_id');
  }

  Future<Map<String, bool>> _progressByEvent({
    required List<String> eventIds,
    required String? userId,
  }) async {
    if (userId == null || eventIds.isEmpty) {
      return const {};
    }
    final rows = await _supabase
        .from('user_event_progress')
        .select('event_id, is_completed')
        .eq('user_id', userId)
        .inFilter('event_id', eventIds);

    final progress = <String, bool>{};
    for (final row in rows) {
      progress[row['event_id'] as String] =
          row['is_completed'] as bool? ?? false;
    }
    return progress;
  }

  Future<Map<String, List<EventPoint>>> _loadPointsByEvent(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) {
      return const {};
    }
    final rows = await _supabase
        .from('study_event_points')
        .select('event_id, order_num, bold_label, content')
        .inFilter('event_id', eventIds)
        .order('event_id', ascending: true)
        .order('order_num', ascending: true);

    final result = <String, List<EventPoint>>{};
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      result.putIfAbsent(eventId, () => []);
      result[eventId]!.add(
        EventPoint(
          orderNum: row['order_num'] as int,
          boldLabel: row['bold_label'] as String,
          content: row['content'] as String,
        ),
      );
    }
    return result;
  }

  Future<Map<String, List<VersePage>>> _loadPagesByEvent(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) {
      return const {};
    }
    final rows = await _supabase
        .from('study_verse_pages')
        .select('event_id, order_num, ref, text')
        .inFilter('event_id', eventIds)
        .order('event_id', ascending: true)
        .order('order_num', ascending: true);

    final groupedRows = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final eventId = row['event_id'] as String;
      groupedRows.putIfAbsent(eventId, () => []);
      groupedRows[eventId]!.add(row);
    }

    final verseRangeCache = <String, List<_BibleVerseLine>>{};
    final result = <String, List<VersePage>>{};
    for (final entry in groupedRows.entries) {
      final pages = <VersePage>[];
      for (final sourceRow in entry.value) {
        final expanded = await _expandVersePages(
          sourceRow: sourceRow,
          cache: verseRangeCache,
        );
        pages.addAll(expanded);
      }
      result[entry.key] = [
        for (var i = 0; i < pages.length; i++)
          VersePage(orderNum: i + 1, ref: pages[i].ref, text: pages[i].text),
      ];
    }
    return result;
  }

  Future<List<VersePage>> _expandVersePages({
    required Map<String, dynamic> sourceRow,
    required Map<String, List<_BibleVerseLine>> cache,
  }) async {
    final ref = (sourceRow['ref'] as String? ?? '').trim();
    final fallbackText = (sourceRow['text'] as String? ?? '').trim();

    if (ref.isEmpty) {
      return [
        VersePage(
          orderNum: sourceRow['order_num'] as int? ?? 1,
          ref: '',
          text: fallbackText,
        ),
      ];
    }

    final range = _parseBibleRange(ref);
    if (range == null) {
      return [
        VersePage(
          orderNum: sourceRow['order_num'] as int? ?? 1,
          ref: ref,
          text: fallbackText,
        ),
      ];
    }

    final cacheKey =
        '${range.bookNo}:${range.startChapter}:${range.startVerse}-${range.endChapter}:${range.endVerse}';
    final verses = cache[cacheKey] ??= await _fetchVerseLines(range);
    if (verses.isEmpty) {
      return [
        VersePage(
          orderNum: sourceRow['order_num'] as int? ?? 1,
          ref: ref,
          text: fallbackText,
        ),
      ];
    }

    return [
      for (final verse in verses)
        VersePage(
          orderNum: 0,
          ref: '${range.bookLabel} ${verse.chapterNo}:${verse.verseNo}',
          text: verse.text,
        ),
    ];
  }

  Future<List<_BibleVerseLine>> _fetchVerseLines(_BibleRange range) async {
    final rows = await _supabase
        .from('bible_verses')
        .select('chapter_no, verse_no, verse_text')
        .eq('translation', 'KRV')
        .eq('book_no', range.bookNo)
        .gte('chapter_no', range.startChapter)
        .lte('chapter_no', range.endChapter)
        .order('chapter_no', ascending: true)
        .order('verse_no', ascending: true);

    return rows
        .where((row) {
          final chapterNo = row['chapter_no'] as int;
          final verseNo = row['verse_no'] as int;
          return _isWithinRange(
            range: range,
            chapterNo: chapterNo,
            verseNo: verseNo,
          );
        })
        .map(
          (row) => _BibleVerseLine(
            chapterNo: row['chapter_no'] as int,
            verseNo: row['verse_no'] as int,
            text: row['verse_text'] as String? ?? '',
          ),
        )
        .where((line) => line.text.trim().isNotEmpty)
        .toList();
  }

  bool _isWithinRange({
    required _BibleRange range,
    required int chapterNo,
    required int verseNo,
  }) {
    if (chapterNo < range.startChapter || chapterNo > range.endChapter) {
      return false;
    }
    if (range.startChapter == range.endChapter) {
      return verseNo >= range.startVerse && verseNo <= range.endVerse;
    }
    if (chapterNo == range.startChapter) {
      return verseNo >= range.startVerse;
    }
    if (chapterNo == range.endChapter) {
      return verseNo <= range.endVerse;
    }
    return true;
  }

  _BibleRange? _parseBibleRange(String rawRef) {
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

    final firstSegment = normalized.split(RegExp(r'[;,]')).first.trim();
    final match = RegExp(
      r'^([가-힣]+)\s*(\d+)\s*[:장]\s*(\d+)(?:\s*-\s*(?:(\d+)\s*[:장]\s*)?(\d+))?$',
    ).firstMatch(firstSegment);
    if (match == null) {
      return null;
    }

    final bookLabel = (match.group(1) ?? '').trim();
    final bookNo = _kBibleRefBookLookup[_normalizeBibleBookKey(bookLabel)];
    if (bookNo == null) {
      return null;
    }

    final startChapter = int.tryParse(match.group(2) ?? '');
    final startVerse = int.tryParse(match.group(3) ?? '');
    final endChapterRaw = match.group(4);
    final endVerseRaw = match.group(5);
    final endChapter = int.tryParse(endChapterRaw ?? '') ?? startChapter;
    final endVerse = int.tryParse(endVerseRaw ?? '') ?? startVerse;

    if (startChapter == null ||
        startVerse == null ||
        endChapter == null ||
        endVerse == null) {
      return null;
    }
    if (startChapter <= 0 ||
        startVerse <= 0 ||
        endChapter <= 0 ||
        endVerse <= 0) {
      return null;
    }
    if (endChapter < startChapter) {
      return null;
    }
    if (endChapter == startChapter && endVerse < startVerse) {
      return null;
    }

    return _BibleRange(
      bookNo: bookNo,
      bookLabel: bookLabel,
      startChapter: startChapter,
      startVerse: startVerse,
      endChapter: endChapter,
      endVerse: endVerse,
    );
  }
}

class _BibleRange {
  const _BibleRange({
    required this.bookNo,
    required this.bookLabel,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final int bookNo;
  final String bookLabel;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
}

class _BibleVerseLine {
  const _BibleVerseLine({
    required this.chapterNo,
    required this.verseNo,
    required this.text,
  });

  final int chapterNo;
  final int verseNo;
  final String text;
}

String _normalizeBibleBookKey(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
}

final Map<String, int> _kBibleRefBookLookup = () {
  final map = <String, int>{};
  for (var i = 0; i < _kBibleBooks.length; i++) {
    map[_normalizeBibleBookKey(_kBibleBooks[i])] = i + 1;
  }
  map.addAll(_kBibleRefAliasBookLookup);
  return map;
}();

const List<String> _kBibleBooks = [
  '창세기',
  '출애굽기',
  '레위기',
  '민수기',
  '신명기',
  '여호수아',
  '사사기',
  '룻기',
  '사무엘상',
  '사무엘하',
  '열왕기상',
  '열왕기하',
  '역대상',
  '역대하',
  '에스라',
  '느헤미야',
  '에스더',
  '욥기',
  '시편',
  '잠언',
  '전도서',
  '아가',
  '이사야',
  '예레미야',
  '예레미야애가',
  '에스겔',
  '다니엘',
  '호세아',
  '요엘',
  '아모스',
  '오바댜',
  '요나',
  '미가',
  '나훔',
  '하박국',
  '스바냐',
  '학개',
  '스가랴',
  '말라기',
  '마태복음',
  '마가복음',
  '누가복음',
  '요한복음',
  '사도행전',
  '로마서',
  '고린도전서',
  '고린도후서',
  '갈라디아서',
  '에베소서',
  '빌립보서',
  '골로새서',
  '데살로니가전서',
  '데살로니가후서',
  '디모데전서',
  '디모데후서',
  '디도서',
  '빌레몬서',
  '히브리서',
  '야고보서',
  '베드로전서',
  '베드로후서',
  '요한일서',
  '요한이서',
  '요한삼서',
  '유다서',
  '요한계시록',
];

const Map<String, int> _kBibleRefAliasBookLookup = {
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
