import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bible_verse.dart';
import '../models/era.dart';
import '../models/person.dart';
import '../models/quiz_question.dart';
import '../models/story_event.dart';
import '../models/story_scene_asset.dart';

class StoryRepository {
  StoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<Era>> fetchEras() async {
    final rows = await _client
        .from('eras')
        .select()
        .order('display_order', ascending: true);

    return rows.map<Era>((row) => Era.fromMap(row)).toList();
  }

  Future<List<Person>> fetchPersonsByEra(String eraId) async {
    final eraRows = await _client
        .from('character_eras')
        .select('character_id, display_order')
        .eq('era_id', eraId);

    if (eraRows.isEmpty) return const [];

    final orderById = <String, int>{};
    for (final row in eraRows) {
      final id = row['character_id'] as String?;
      if (id == null) continue;
      orderById[id] = (row['display_order'] as num?)?.toInt() ?? 0;
    }
    if (orderById.isEmpty) return const [];

    final charRows = await _client
        .from('characters')
        .select('id, code, name, tagline, description, avatar_url')
        .inFilter('id', orderById.keys.toList());

    final persons = charRows.map<Person>((row) {
      final id = row['id'] as String;
      final code = row['code'] as String;
      return Person(
        id: code,
        code: code,
        name: row['name'] as String,
        tagline: row['tagline'] as String?,
        description: row['description'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        avatarThumbUrl: null,
        displayOrder: orderById[id] ?? 0,
      );
    }).toList();

    persons.sort((a, b) {
      final byOrder = a.displayOrder.compareTo(b.displayOrder);
      return byOrder != 0 ? byOrder : a.code.compareTo(b.code);
    });
    return persons;
  }

  Future<List<StoryEvent>> fetchEventsByEra(String eraId) async {
    final rows = await _client
        .from('events')
        .select(_eventSelectColumns)
        .eq('era_id', eraId)
        .isFilter('deleted_at', null)
        .order('story_index', ascending: true);

    return rows.map<StoryEvent>((row) => _eventFromNewRow(row)).toList();
  }

  Future<List<StoryEvent>> fetchEventsForPerson(String personCode) async {
    final rows = await _client
        .from('events')
        .select(_eventSelectColumns)
        .isFilter('deleted_at', null)
        .contains('character_codes', [personCode])
        .order('story_index', ascending: true);

    return rows.map<StoryEvent>((row) => _eventFromNewRow(row)).toList();
  }

  Future<Map<String, double>> fetchPersonTimelineOrder() async {
    final rows = await _client
        .from('events_ordered')
        .select('global_rank, character_codes')
        .isFilter('deleted_at', null)
        .order('global_rank', ascending: true);

    final firstAppearanceByCode = <String, double>{};
    for (final row in rows) {
      final rank = (row['global_rank'] as num?)?.toDouble() ?? 0;
      final codes = (row['character_codes'] as List<dynamic>? ?? const [])
          .whereType<String>();
      for (final code in codes) {
        firstAppearanceByCode.putIfAbsent(code, () => rank);
      }
    }
    return firstAppearanceByCode;
  }

  Future<List<StoryEvent>> searchEventsByText(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final like = '%${normalized.replaceAll('%', r'\%')}%';
    final rows = await _client
        .from('events')
        .select(_eventSelectColumns)
        .isFilter('deleted_at', null)
        .or('title.ilike.$like,summary.ilike.$like,place_name.ilike.$like')
        .order('story_index', ascending: true)
        .limit(20);

    return rows.map<StoryEvent>((row) => _eventFromNewRow(row)).toList();
  }

  Future<List<QuizQuestion>> fetchQuizQuestions(String eventId) async {
    final rows = await _client
        .from('quiz_questions')
        .select(
          'id, question, choice_a, choice_b, choice_c, choice_d, answer_index, explanation, display_order',
        )
        .eq('event_id', eventId)
        .order('display_order', ascending: true);

    return rows.map<QuizQuestion>((row) {
      final choices = <String>[
        row['choice_a'] as String,
        row['choice_b'] as String,
        row['choice_c'] as String,
      ];
      final c4 = row['choice_d'] as String?;
      if (c4 != null && c4.trim().isNotEmpty) {
        choices.add(c4);
      }

      return QuizQuestion(
        id: row['id'] as String,
        question: row['question'] as String,
        choices: choices,
        answerIndex: row['answer_index'] as int,
        explanation: row['explanation'] as String?,
        displayOrder: row['display_order'] as int? ?? 0,
      );
    }).toList();
  }

  Future<List<StorySceneAsset>> fetchSceneAssetsForEvent(String eventId) async {
    return const [];
  }

  Future<List<BibleVerse>> fetchBibleVersesByChapter({
    required int bookNo,
    required int chapterNo,
    String translation = 'KRV',
  }) async {
    final rows = await _client
        .from('bible_verses')
        .select(
          'translation, book_no, book_name, chapter_no, verse_no, verse_text',
        )
        .eq('translation', translation)
        .eq('book_no', bookNo)
        .eq('chapter_no', chapterNo)
        .order('verse_no', ascending: true);

    return rows.map<BibleVerse>((row) => BibleVerse.fromMap(row)).toList();
  }

  Future<Set<String>> fetchCompletedEventIds(String userId) async {
    final rows = await _client
        .from('user_event_progress')
        .select('event_id, is_completed')
        .eq('user_id', userId)
        .eq('is_completed', true);

    return rows
        .map((row) => row['event_id'] as String)
        .whereType<String>()
        .toSet();
  }

  Future<void> upsertEventProgress({
    required String userId,
    required String eventId,
    required bool isCompleted,
    required int score,
    required int xpEarned,
  }) async {
    await _client.from('user_event_progress').upsert({
      'user_id': userId,
      'event_id': eventId,
      'is_completed': isCompleted,
      'completed_at': isCompleted ? DateTime.now().toIso8601String() : null,
    }, onConflict: 'user_id,event_id');
  }

  static const String _eventSelectColumns = '''
    id, era_id, title, summary, story_scenes, character_codes, bible_refs,
    start_year, end_year, story_index, place_name, lat, lng, scene_image_paths
  ''';

  StoryEvent _eventFromNewRow(Map<String, dynamic> row) {
    final title = row['title'] as String? ?? '';
    final displayMatch = RegExp(r'^(\d{3})\s').firstMatch(title);
    final displayNumber = displayMatch?.group(1) ?? '???';

    final scenesRaw = row['story_scenes'];
    final List<dynamic> scenes = scenesRaw is List
        ? scenesRaw
        : (scenesRaw is String && scenesRaw.isNotEmpty
              ? jsonDecode(scenesRaw) as List<dynamic>
              : const []);

    final bibleRaw = row['bible_refs'];
    final List<dynamic> bibleList = bibleRaw is List
        ? bibleRaw
        : (bibleRaw is String && bibleRaw.isNotEmpty
              ? jsonDecode(bibleRaw) as List<dynamic>
              : const []);
    final bibleRefs = bibleList
        .whereType<Map<String, dynamic>>()
        .map(_formatBibleRef)
        .where((s) => s.isNotEmpty)
        .toList();

    final storyIndex = (row['story_index'] as num?)?.toDouble() ?? 0;

    return StoryEvent(
      id: row['id'] as String,
      code: title,
      displayNumber: displayNumber,
      eraId: row['era_id'] as String,
      title: title,
      summary: row['summary'] as String?,
      story: null,
      shortStory: null,
      storyScenes: jsonEncode(scenes),
      timelineRank: storyIndex,
      startYear: row['start_year'] as int?,
      endYear: row['end_year'] as int?,
      timeSortKey: storyIndex.toInt(),
      placeName: row['place_name'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      thumbUrl: null,
      storyAssetDir: null,
      storyThumbnailDir: null,
      storySceneCount: scenes.length,
      personIds: (row['character_codes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      bibleRefs: bibleRefs,
    );
  }

  static String _formatBibleRef(Map<String, dynamic> ref) {
    final book = (ref['book'] ?? '').toString().trim();
    final from = (ref['from'] ?? '').toString().trim();
    final to = (ref['to'] ?? '').toString().trim();
    if (book.isEmpty) return '';
    if (from.isEmpty) return book;
    if (to.isEmpty || to == from) return '$book $from';
    return '$book $from-$to';
  }

}

/// Supabase 행을 [StoryEvent]로 변환한다.
///
/// `event_persons`, `event_bible_refs` 서브쿼리의 누락/null을 안전하게 처리한다.
/// 테스트 편의를 위해 top-level로 노출되어 있으며 [StoryRepository] 내부에서도
/// 재사용된다.
@visibleForTesting
StoryEvent storyEventFromRow(
  Map<String, dynamic> row, {
  bool includeBibleRefs = false,
}) {
  final personRows = (row['event_persons'] as List<dynamic>? ?? const []);
  final refRows = includeBibleRefs
      ? (row['event_bible_refs'] as List<dynamic>? ?? const [])
      : const [];

  final timelineRank = (row['timeline_rank'] as num?)?.toDouble();
  if (timelineRank == null || timelineRank <= 0) {
    throw StateError(
      'Event ${row['id']} has invalid timeline_rank: $timelineRank. '
      'Database integrity check required.',
    );
  }

  String? displayNumber = row['display_number'] as String?;
  if (displayNumber == null || displayNumber.trim().isEmpty) {
    final code = row['code'] as String;
    final match = RegExp(r'(\d+)$').firstMatch(code);
    displayNumber = match?.group(1)?.padLeft(3, '0') ?? '???';
  }

  return StoryEvent(
    id: row['id'] as String,
    code: row['code'] as String,
    displayNumber: displayNumber,
    eraId: row['era_id'] as String,
    title: row['title'] as String,
    summary: row['summary'] as String?,
    story: row['story'] as String?,
    shortStory: row['short_story'] as String?,
    storyScenes: row['story_scenes'] as String?,
    timelineRank: timelineRank,
    startYear: row['start_year'] as int?,
    endYear: row['end_year'] as int?,
    timeSortKey: row['time_sort_key'] as int,
    placeName: row['place_name'] as String?,
    lat: (row['lat'] as num?)?.toDouble(),
    lng: (row['lng'] as num?)?.toDouble(),
    thumbUrl: row['thumb_url'] as String?,
    storyAssetDir: row['story_asset_dir'] as String?,
    storyThumbnailDir: row['story_thumbnail_dir'] as String?,
    storySceneCount: row['story_scene_count'] as int? ?? 0,
    personIds: personRows
        .whereType<Map<String, dynamic>>()
        .map((entry) => entry['person_id'] as String?)
        .whereType<String>()
        .toList(),
    bibleRefs: includeBibleRefs
        ? refRows
              .whereType<Map<String, dynamic>>()
              .map((entry) => entry['display_text'] as String?)
              .whereType<String>()
              .toList()
        : const [],
  );
}

/// 이벤트 검색용 가중치 스코어링.
///
/// 제목/요약/본문/단문/장소/인물명 포함 여부와 토큰별 부분 매치에 따라 점수를
/// 누적한다. 단문(shortStory)이 가장 높은 가중치를 갖고, 제목 정확 일치 시
/// 보너스가 부여된다.
@visibleForTesting
int scoreEventMatch(
  StoryEvent event,
  String query,
  List<String> tokens, {
  List<String> personNames = const [],
}) {
  final title = event.title.toLowerCase();
  final summary = (event.summary ?? '').toLowerCase();
  final story = (event.story ?? '').toLowerCase();
  final shortStory = (event.shortStory ?? '').toLowerCase();
  final placeName = (event.placeName ?? '').toLowerCase();
  final personText = personNames.join(' ').toLowerCase();

  var score = 0;

  if (title.contains(query)) {
    score += 120;
  }
  if (summary.contains(query)) {
    score += 110;
  }
  if (story.contains(query)) {
    score += 120;
  }
  if (shortStory.contains(query)) {
    score += 130;
  }
  if (placeName.contains(query)) {
    score += 30;
  }
  if (personText.contains(query)) {
    score += 80;
  }

  for (final token in tokens) {
    if (title.contains(token)) {
      score += 25;
    }
    if (summary.contains(token)) {
      score += 16;
    }
    if (story.contains(token)) {
      score += 18;
    }
    if (shortStory.contains(token)) {
      score += 20;
    }
    if (placeName.contains(token)) {
      score += 5;
    }
    if (personText.contains(token)) {
      score += 18;
    }
  }

  if (event.title.isNotEmpty && event.title.toLowerCase() == query) {
    score += 40;
  }

  return score;
}

