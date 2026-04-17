import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/person.dart';
import '../models/story_event.dart';
import '../models/story_scene_asset.dart';
import '../models/quiz_question.dart';
import '../models/bible_verse.dart';

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
    final rows = await _client
        .from('person_eras')
        .select(
          'display_order, persons!inner(id, code, name, tagline, description, avatar_url, avatar_thumb_url)',
        )
        .eq('era_id', eraId)
        .order('display_order', ascending: true);

    return rows.map<Person>((row) {
      final person = row['persons'] as Map<String, dynamic>;
      return Person(
        id: person['id'] as String,
        code: person['code'] as String,
        name: person['name'] as String,
        tagline: person['tagline'] as String?,
        description: person['description'] as String?,
        avatarUrl: person['avatar_url'] as String?,
        avatarThumbUrl: person['avatar_thumb_url'] as String?,
        displayOrder: row['display_order'] as int,
      );
    }).toList();
  }

  Future<List<StoryEvent>> fetchEventsByEra(String eraId) async {
    final rows = await _client
        .from('events')
        .select('''
          id,
          code,
          display_number,
          era_id,
          title,
          summary,
          story,
          short_story,
          story_scenes,
          timeline_rank,
          start_year,
          end_year,
          time_sort_key,
          place_name,
          lat,
          lng,
          thumb_url,
          story_asset_dir,
          story_thumbnail_dir,
          story_scene_count,
          event_persons(person_id),
          event_bible_refs(display_text)
        ''')
        .eq('era_id', eraId)
        .order('timeline_rank', ascending: true)
        .order('time_sort_key', ascending: true);

    return rows
        .map<StoryEvent>(
          (row) => _storyEventFromRow(row, includeBibleRefs: true),
        )
        .toList();
  }

  Future<List<StoryEvent>> fetchEventsForPerson(String personId) async {
    final rows = await _client
        .from('events')
        .select('''
          id,
          code,
          display_number,
          era_id,
          title,
          summary,
          story,
          short_story,
          story_scenes,
          timeline_rank,
          start_year,
          end_year,
          time_sort_key,
          place_name,
          lat,
          lng,
          thumb_url,
          story_asset_dir,
          story_thumbnail_dir,
          story_scene_count,
          event_persons!inner(person_id),
          event_bible_refs(display_text)
        ''')
        .eq('event_persons.person_id', personId)
        .order('timeline_rank', ascending: true)
        .order('time_sort_key', ascending: true);

    return rows
        .map<StoryEvent>(
          (row) => _storyEventFromRow(row, includeBibleRefs: true),
        )
        .toList();
  }

  Future<Map<String, double>> fetchPersonTimelineOrder() async {
    final rows = await _client
        .from('events')
        .select('timeline_rank, event_persons(person_id)')
        .order('timeline_rank', ascending: true)
        .order('time_sort_key', ascending: true);

    final firstAppearanceByPersonId = <String, double>{};
    for (final row in rows) {
      final timelineRank = (row['timeline_rank'] as num?)?.toDouble() ?? 0;
      final personRows = row['event_persons'] as List<dynamic>? ?? const [];
      for (final personRow in personRows.whereType<Map<String, dynamic>>()) {
        final personId = personRow['person_id'] as String?;
        if (personId == null) {
          continue;
        }
        firstAppearanceByPersonId.putIfAbsent(personId, () => timelineRank);
      }
    }
    return firstAppearanceByPersonId;
  }

  Future<List<StoryEvent>> searchEventsByText(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('events')
        .select('''
          id,
          code,
          display_number,
          era_id,
          title,
          summary,
          story,
          short_story,
          story_scenes,
          timeline_rank,
          start_year,
          end_year,
          time_sort_key,
          place_name,
          lat,
          lng,
          thumb_url,
          story_asset_dir,
          story_thumbnail_dir,
          story_scene_count,
          event_persons(person_id, persons(name))
        ''')
        .order('timeline_rank', ascending: true)
        .order('time_sort_key', ascending: true);

    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    final scored = <_ScoredEvent>[];
    for (final row in rows) {
      final event = _storyEventFromRow(row);
      final personRows = (row['event_persons'] as List<dynamic>? ?? const []);
      final personNames = personRows
          .whereType<Map<String, dynamic>>()
          .map((entry) {
            final person = entry['persons'] as Map<String, dynamic>?;
            return person?['name'] as String?;
          })
          .whereType<String>()
          .map((name) => name.toLowerCase())
          .toList();
      final score = _scoreForEvent(
        event,
        normalized,
        tokens,
        personNames: personNames,
      );
      if (score > 0) {
        scored.add(_ScoredEvent(event: event, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) {
        return scoreDiff;
      }
      return a.event.compareTimelineTo(b.event);
    });

    return scored.take(20).map((entry) => entry.event).toList();
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
    final rows = await _client
        .from('event_scene_generated_assets')
        .select('scene_index, original_path, thumbnail_path, status, metadata')
        .eq('event_id', eventId)
        .order('scene_index', ascending: true);

    return rows
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => StorySceneAsset(
            sceneIndex: row['scene_index'] as int? ?? 0,
            originalPath: row['original_path'] as String?,
            thumbnailPath: row['thumbnail_path'] as String?,
            status: row['status'] as String? ?? 'unknown',
            metadata:
                (row['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
        )
        .where((asset) => asset.sceneIndex > 0)
        .toList(growable: false);
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
      'score': score,
      'xp_earned': xpEarned,
      'completed_at': isCompleted ? DateTime.now().toIso8601String() : null,
    }, onConflict: 'user_id,event_id');
  }

  StoryEvent _storyEventFromRow(
    Map<String, dynamic> row, {
    bool includeBibleRefs = false,
  }) {
    final personRows = (row['event_persons'] as List<dynamic>? ?? const []);
    final refRows = includeBibleRefs
        ? (row['event_bible_refs'] as List<dynamic>? ?? const [])
        : const [];

    // Validate timeline_rank
    final timelineRank = (row['timeline_rank'] as num?)?.toDouble();
    if (timelineRank == null || timelineRank <= 0) {
      throw StateError(
        'Event ${row['id']} has invalid timeline_rank: $timelineRank. '
        'Database integrity check required.',
      );
    }

    // Extract or generate display_number
    String? displayNumber = row['display_number'] as String?;
    if (displayNumber == null || displayNumber.trim().isEmpty) {
      // Fallback to code-derived number
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

  int _scoreForEvent(
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
}

class _ScoredEvent {
  const _ScoredEvent({required this.event, required this.score});

  final StoryEvent event;
  final int score;
}
