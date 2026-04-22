import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bible_verse.dart';
import '../models/character.dart';
import '../models/era.dart';
import '../models/quiz_question.dart';
import '../models/story_event.dart';

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

  Future<List<Character>> fetchCharactersByEra(String eraId) async {
    // 과거에는 character_eras view + characters!inner resource embedding 으로 조인했으나,
    // view 가 WITH + group by + row_number() 구조라 PostgREST 가 FK 를 자동
    // 추론하지 못해 PGRST200 이 발생한다. list_characters_by_era RPC 로 우회.
    final rows =
        await _client.rpc('list_characters_by_era', params: {'p_era_id': eraId})
            as List<dynamic>;

    return rows.map<Character>((row) {
      final map = row as Map<String, dynamic>;
      return Character(
        id: map['id'] as String,
        code: map['code'] as String,
        name: map['name'] as String,
        tagline: map['tagline'] as String?,
        description: map['description'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        displayOrder: (map['display_order'] as num).toInt(),
      );
    }).toList();
  }

  Future<List<StoryEvent>> fetchEventsByEra(String eraId) async {
    final rows = await _client
        .from('events_ordered')
        .select()
        .eq('era_id', eraId)
        .order('rank_in_era', ascending: true);
    return rows.map<StoryEvent>(StoryEvent.fromMap).toList();
  }

  Future<List<StoryEvent>> fetchEventsForCharacter(String characterCode) async {
    final rows = await _client
        .from('events_ordered')
        .select()
        .contains('character_codes', <String>[characterCode])
        .order('global_rank', ascending: true);
    return rows.map<StoryEvent>(StoryEvent.fromMap).toList();
  }

  /// 인물별 첫 등장 시점을 [StoryEvent.globalRank] 기준으로 반환한다.
  /// 키는 `characters.code` (어드민/외부 기여 모두 코드 기반).
  Future<Map<String, int>> fetchCharacterTimelineOrder() async {
    final rows = await _client
        .from('events_ordered')
        .select('global_rank, character_codes')
        .order('global_rank', ascending: true);

    final firstAppearanceByCode = <String, int>{};
    for (final row in rows) {
      final globalRank = (row['global_rank'] as num?)?.toInt() ?? 0;
      final codes = row['character_codes'];
      if (codes is! List) {
        continue;
      }
      for (final code in codes.whereType<String>()) {
        firstAppearanceByCode.putIfAbsent(code, () => globalRank);
      }
    }
    return firstAppearanceByCode;
  }

  Future<List<StoryEvent>> searchEventsByText(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('events_ordered')
        .select()
        .order('global_rank', ascending: true);

    final characterNameByCode = await _fetchActiveCharacterNamesByCode();

    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    final scored = <_ScoredEvent>[];
    for (final row in rows) {
      final event = StoryEvent.fromMap(row);
      final characterNames = event.characterCodes
          .map((code) => characterNameByCode[code])
          .whereType<String>()
          .map((name) => name.toLowerCase())
          .toList();
      final score = scoreEventMatch(
        event,
        normalized,
        tokens,
        characterNames: characterNames,
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
      return a.event.globalRank.compareTo(b.event.globalRank);
    });

    return scored.take(20).map((entry) => entry.event).toList();
  }

  Future<Map<String, String>> _fetchActiveCharacterNamesByCode() async {
    final rows = await _client.from('characters').select('code, name');
    final result = <String, String>{};
    for (final row in rows) {
      final code = row['code'] as String?;
      final name = row['name'] as String?;
      if (code != null && name != null) {
        result[code] = name;
      }
    }
    return result;
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
  }) async {
    await _client.from('user_event_progress').upsert({
      'user_id': userId,
      'event_id': eventId,
      'is_completed': isCompleted,
      'completed_at': isCompleted ? DateTime.now().toIso8601String() : null,
    }, onConflict: 'user_id,event_id');
  }
}

/// 이벤트 검색용 가중치 스코어링.
///
/// summary/title/장면/장소/인물명 매치에 따라 점수를 누적한다.
/// 새 스키마에는 `story`/`short_story` 컬럼이 없으므로 `story_scenes` 합본으로
/// 본문 매치를 평가한다.
@visibleForTesting
int scoreEventMatch(
  StoryEvent event,
  String query,
  List<String> tokens, {
  List<String> characterNames = const [],
}) {
  final title = event.title.toLowerCase();
  final summary = (event.summary ?? '').toLowerCase();
  final scenesText = event.storyScenes.join(' ').toLowerCase();
  final placeName = (event.placeName ?? '').toLowerCase();
  final characterText = characterNames.join(' ').toLowerCase();

  var score = 0;

  if (title.contains(query)) {
    score += 130;
  }
  if (summary.contains(query)) {
    score += 120;
  }
  if (scenesText.contains(query)) {
    score += 100;
  }
  if (placeName.contains(query)) {
    score += 30;
  }
  if (characterText.contains(query)) {
    score += 80;
  }

  for (final token in tokens) {
    if (title.contains(token)) {
      score += 25;
    }
    if (summary.contains(token)) {
      score += 18;
    }
    if (scenesText.contains(token)) {
      score += 15;
    }
    if (placeName.contains(token)) {
      score += 5;
    }
    if (characterText.contains(token)) {
      score += 18;
    }
  }

  if (event.title.isNotEmpty && event.title.toLowerCase() == query) {
    score += 40;
  }

  return score;
}

class _ScoredEvent {
  const _ScoredEvent({required this.event, required this.score});

  final StoryEvent event;
  final int score;
}
