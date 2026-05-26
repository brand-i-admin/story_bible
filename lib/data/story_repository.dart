import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bible_verse.dart';
import '../models/character.dart';
import '../models/daily_quiz.dart';
import '../models/era.dart';
import '../models/era_boundary.dart';
import '../models/event_emotion_mark.dart';
import '../models/landmark.dart';
import '../models/quiz_attempt_summary.dart';
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
        avatarStoragePath: map['avatar_storage_path'] as String?,
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

  /// 시대별로 지도에 표시되는 랜드마크 카탈로그. 클라이언트가 selectedEraId 의
  /// era code 로 era_codes 배열 매칭 필터링해서 노출.
  Future<List<Landmark>> fetchLandmarks() async {
    final rows = await _client
        .from('landmarks')
        .select()
        .order('display_priority', ascending: true)
        .order('name', ascending: true);
    return rows.map<Landmark>(Landmark.fromMap).toList();
  }

  /// 시대별 거친 지리 영역 폴리곤. 시대 선택 시 지도에 반투명 영역으로 그려진다.
  Future<List<EraBoundary>> fetchEraBoundaries() async {
    final rows = await _client
        .from('era_boundaries')
        .select()
        .order('display_order', ascending: true)
        .order('polygon_index', ascending: true);
    return rows.map<EraBoundary>(EraBoundary.fromMap).toList();
  }

  Future<List<StoryEvent>> fetchEventsForCharacter(String characterCode) async {
    final rows = await _client
        .from('events_ordered')
        .select()
        .contains('character_codes', <String>[characterCode])
        .order('global_rank', ascending: true);
    return rows.map<StoryEvent>(StoryEvent.fromMap).toList();
  }

  Future<List<StoryEvent>> fetchEventsByIds(Set<String> eventIds) async {
    if (eventIds.isEmpty) {
      return const [];
    }
    final rows = await _client
        .from('events_ordered')
        .select()
        .inFilter('id', eventIds.toList())
        .order('global_rank', ascending: true);
    return rows.map<StoryEvent>(StoryEvent.fromMap).toList();
  }

  Future<Set<String>> fetchSavedEventIds(String userId) async {
    final rows = await _client
        .from('user_saved_events')
        .select('event_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return rows.map((row) => row['event_id'] as String).toSet();
  }

  Future<bool> toggleSavedEvent({
    required String userId,
    required String eventId,
  }) async {
    final existing = await _client
        .from('user_saved_events')
        .select('event_id')
        .eq('user_id', userId)
        .eq('event_id', eventId)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('user_saved_events')
          .delete()
          .eq('user_id', userId)
          .eq('event_id', eventId);
      return false;
    }

    await _client.from('user_saved_events').insert({
      'user_id': userId,
      'event_id': eventId,
    });
    return true;
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

  /// 매일 퀴즈 — 가장 최근 문제 1건. 데이터 없으면 null.
  ///
  /// 향후 "오늘의 퀴즈" 로 확장 시 created_at 기반 일자 매칭으로 갈 수 있도록
  /// 메서드 시그니처는 단일 결과 fetch 유지.
  Future<DailyQuiz?> fetchLatestDailyQuiz() async {
    final row = await _client
        .from('daily_quiz')
        .select(
          'id, question, choice_1, choice_2, choice_3, choice_4, answer_index, explanation, created_at',
        )
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return DailyQuiz.fromMap(row);
  }

  /// 사용자가 특정 daily_quiz 에 답한 기록 (단일). 없으면 null.
  /// 같은 quizId 에 대해 사용자당 1 row 만 존재 (PK).
  Future<({int selectedIndex, bool isCorrect})?> fetchDailyQuizAttempt({
    required String userId,
    required String quizId,
  }) async {
    final row = await _client
        .from('user_daily_quiz_attempts')
        .select('selected_index, is_correct')
        .eq('user_id', userId)
        .eq('daily_quiz_id', quizId)
        .maybeSingle();
    if (row == null) return null;
    return (
      selectedIndex: (row['selected_index'] as num).toInt(),
      isCorrect: (row['is_correct'] as bool?) ?? false,
    );
  }

  /// 매일 퀴즈 답안 저장. 같은 (user, quiz) 에 두 번째 시도는 무시 (재제출 차단)
  /// 하기 위해 upsert 가 아닌 insert ignore (on conflict do nothing) 패턴.
  Future<void> insertDailyQuizAttempt({
    required String userId,
    required String quizId,
    required int selectedIndex,
    required bool isCorrect,
  }) async {
    await _client
        .from('user_daily_quiz_attempts')
        .upsert(
          {
            'user_id': userId,
            'daily_quiz_id': quizId,
            'selected_index': selectedIndex,
            'is_correct': isCorrect,
          },
          onConflict: 'user_id,daily_quiz_id',
          ignoreDuplicates: true,
        );
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
      } else {
        choices.add(QuizQuestion.confusedChoiceLabel);
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

  Future<Map<String, ({bool bibleRead, bool quizCompleted, bool completed})>>
  fetchEventProgress(String userId) async {
    final rows = await _client
        .from('user_event_progress')
        .select('event_id, is_bible_read, is_quiz_completed, is_completed')
        .eq('user_id', userId);

    return {
      for (final row in rows)
        row['event_id'] as String: (
          bibleRead: (row['is_bible_read'] as bool?) ?? false,
          quizCompleted: (row['is_quiz_completed'] as bool?) ?? false,
          completed: (row['is_completed'] as bool?) ?? false,
        ),
    };
  }

  Future<Map<String, QuizAttemptSummary>> fetchQuizAttemptSummaries(
    String userId,
  ) async {
    final rows = await _client
        .from('user_quiz_attempts')
        .select(
          'event_id, correct_count, total_count, wrong_count, confused_count, selected_answers, updated_at',
        )
        .eq('user_id', userId)
        .order('updated_at', ascending: false);

    return {
      for (final row in rows)
        row['event_id'] as String: QuizAttemptSummary.fromMap(row),
    };
  }

  Future<void> upsertQuizAttempt({
    required String userId,
    required QuizAttemptSummary summary,
  }) async {
    await _client
        .from('user_quiz_attempts')
        .upsert(summary.toMap(userId: userId), onConflict: 'user_id,event_id');
  }

  Future<Map<String, EventEmotionMark>> fetchEventEmotionMarks(
    String userId,
  ) async {
    final rows = await _client
        .from('user_event_emotion_marks')
        .select(
          'event_id, emotion_key, emotion_label, emotion_emoji, note, updated_at',
        )
        .eq('user_id', userId)
        .order('updated_at', ascending: false);

    return {
      for (final row in rows)
        row['event_id'] as String: EventEmotionMark.fromMap(row),
    };
  }

  Future<void> upsertEventEmotionMark({
    required String userId,
    required EventEmotionMark mark,
  }) async {
    await _client
        .from('user_event_emotion_marks')
        .upsert(mark.toMap(userId: userId), onConflict: 'user_id,event_id');
  }

  Future<void> deleteEventEmotionMark({
    required String userId,
    required String eventId,
  }) async {
    await _client
        .from('user_event_emotion_marks')
        .delete()
        .eq('user_id', userId)
        .eq('event_id', eventId);
  }

  Future<void> upsertEventProgress({
    required String userId,
    required String eventId,
    bool? isBibleRead,
    bool? isQuizCompleted,
    bool? isCompleted,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'event_id': eventId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (isBibleRead != null) {
      payload['is_bible_read'] = isBibleRead;
    }
    if (isQuizCompleted != null) {
      payload['is_quiz_completed'] = isQuizCompleted;
    }
    if (isCompleted != null) {
      payload['is_completed'] = isCompleted;
      payload['completed_at'] = isCompleted
          ? DateTime.now().toIso8601String()
          : null;
    }
    await _client
        .from('user_event_progress')
        .upsert(payload, onConflict: 'user_id,event_id');
  }

  /// 주간 퀴즈 진행도 — 특정 user_id + week_key 의 모든 row.
  /// 반환은 `eventId → (bibleRead, quizCompleted)` 맵.
  Future<Map<String, ({bool bibleRead, bool quizCompleted})>>
  fetchWeeklyQuizProgress({
    required String userId,
    required String weekKey,
  }) async {
    final rows = await _client
        .from('weekly_quiz_progress')
        .select('event_id, is_bible_read, is_quiz_completed')
        .eq('user_id', userId)
        .eq('week_key', weekKey);
    return {
      for (final row in rows)
        row['event_id'] as String: (
          bibleRead: (row['is_bible_read'] as bool?) ?? false,
          quizCompleted: (row['is_quiz_completed'] as bool?) ?? false,
        ),
    };
  }

  /// 주간 퀴즈 진행도 upsert. `bibleRead`/`quizCompleted` 중 변경된 컬럼만
  /// 명시적으로 update — 다른 플래그는 보존.
  Future<void> upsertWeeklyQuizProgress({
    required String userId,
    required String weekKey,
    required String eventId,
    bool? isBibleRead,
    bool? isQuizCompleted,
    int? lastScoreCorrect,
    int? lastScoreTotal,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'week_key': weekKey,
      'event_id': eventId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (isBibleRead != null) {
      payload['is_bible_read'] = isBibleRead;
    }
    if (isQuizCompleted != null) {
      payload['is_quiz_completed'] = isQuizCompleted;
    }
    if (lastScoreCorrect != null) {
      payload['last_score_correct'] = lastScoreCorrect;
    }
    if (lastScoreTotal != null) {
      payload['last_score_total'] = lastScoreTotal;
    }
    await _client
        .from('weekly_quiz_progress')
        .upsert(payload, onConflict: 'user_id,week_key,event_id');
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
