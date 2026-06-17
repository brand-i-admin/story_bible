import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/story_repository.dart';
import '../models/character.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/landmark.dart';
import '../models/quiz_attempt_summary.dart';
import '../models/story_event.dart';
import '../theme/tokens.dart';
import 'auth_providers.dart';
import 'story_state.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  return StoryRepository(ref.watch(supabaseClientProvider));
});

final storyControllerProvider = NotifierProvider<StoryController, StoryState>(
  StoryController.new,
);

class StoryController extends Notifier<StoryState> {
  Timer? _searchDebounce;

  StoryRepository get _repo => ref.read(storyRepositoryProvider);

  @override
  StoryState build() => const StoryState(loading: true);

  Future<void> initialize() async {
    try {
      state = state.copyWith(loading: true, clearError: true);
      final eras = await _repo.fetchEras();
      final eventProgress = await _fetchEventProgressForCurrentUser();
      final eventEmotionMarks = await _fetchEventEmotionMarksForCurrentUser();
      final savedEventIds = await _fetchSavedEventIdsForCurrentUser();
      final completedEventIds = _completedIdsFromProgress(
        eventProgress,
        eventEmotionMarks,
      );
      final quizAttemptSummaries =
          await _fetchQuizAttemptSummariesForCurrentUser();
      if (eras.isEmpty) {
        state = state.copyWith(
          loading: false,
          eras: const [],
          characters: const [],
          events: const [],
          error: '시대 데이터가 없습니다.',
        );
        return;
      }

      // 시대별 랜드마크는 시대/인물 선택과 무관하게 부팅 시 한 번만 전체 로드.
      // 실패해도 나머지 화면은 살려야 하므로 swallow.
      List<Landmark> landmarks = const [];
      try {
        landmarks = await _repo.fetchLandmarks();
      } catch (e) {
        debugPrint(
          '[StoryController] fetchLandmarks failed: $e — '
          'apply-seeds-landmarks 가 적용됐는지 확인하세요.',
        );
        landmarks = const [];
      }

      final hasOldTestament = eras.any((era) => _eraTestament(era) == 'old');
      state = state.copyWith(
        loading: false,
        eras: eras,
        characters: const [],
        events: const [],
        completedEventIds: completedEventIds,
        bibleReadEventIds: _bibleReadIdsFromProgress(eventProgress),
        quizCompletedEventIds: _quizCompletedIdsFromProgress(eventProgress),
        lastQuizScores: _scoresFromAttempts(quizAttemptSummaries),
        quizAttemptSummaries: quizAttemptSummaries,
        eventEmotionMarks: eventEmotionMarks,
        savedEventIds: savedEventIds,
        selectedEraId: null,
        selectedCharacterCodes: const {},
        selectedCharacterColors: const {},
        selectedTestament: hasOldTestament ? 'old' : _eraTestament(eras.first),
        searchQuery: '',
        searchResults: const [],
        isSearching: false,
        clearSelectedEvent: true,
        landmarks: landmarks,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _buildLoadErrorMessage(prefix: '초기 데이터를 불러오지 못했습니다.', error: e),
      );
    }
  }

  Future<void> selectTestament(String testament) async {
    final normalized = testament == 'new' ? 'new' : 'old';
    final selectedEra = state.eras
        .where((era) => era.id == state.selectedEraId)
        .firstOrNull;
    final selectedEraMatches =
        selectedEra != null && _eraTestament(selectedEra) == normalized;

    if (state.selectedTestament == normalized && selectedEraMatches) {
      return;
    }

    state = state.copyWith(
      selectedTestament: normalized,
      clearSelectedEvent: true,
      clearError: true,
    );

    if (selectedEraMatches) {
      return;
    }

    final available =
        state.eras.where((era) => _eraTestament(era) == normalized).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    if (available.isEmpty) {
      state = state.copyWith(
        clearSelectedEra: true,
        characters: const [],
        events: const [],
        selectedCharacterCodes: const {},
        selectedCharacterColors: const {},
        completedEventIds: const {},
        clearSelectedEvent: true,
      );
      return;
    }

    await selectEra(available.first.id);
  }

  Future<void> toggleEra(String eraId) async {
    if (state.selectedEraId == eraId) {
      clearEraSelection();
      return;
    }
    await selectEra(eraId);
  }

  /// 단일 시대 선택 — 멀티 시대 기능은 제거됨. 선택된 시대를 다시 누르면 해제.
  /// 외부에서 [setSelectedEras] / [toggleEraMulti] 를 부르던 호출자는 이 메서드
  /// 한 번으로 통일.
  Future<void> setSelectedEra(String? eraId) async {
    if (eraId == null) {
      clearEraSelection();
      return;
    }
    await selectEra(eraId);
  }

  /// v2 — 사용자가 시대 선택 후 탐색 모드([SelectionMode]) 를 골랐을 때 호출.
  void setSelectionMode(SelectionMode mode) {
    state = state.copyWith(
      selectionMode: mode,
      clearSelectedLandmark: true,
      clearSelectedEvent: true,
      // 모드 전환 시 인물 선택은 character 모드에서 다시 정하고, 나머지
      // 모드는 인물 선택을 무시(지역/전체 시간순 단위로 사건 표시).
      selectedCharacterCodes: mode == SelectionMode.character
          ? state.selectedCharacterCodes
          : const {},
      selectedTimelineUnitCodes: mode == SelectionMode.timeline
          ? state.selectedTimelineUnitCodes
          : const {},
      displayedEventIds: const {},
    );
  }

  void clearSelectionMode() {
    state = state.copyWith(
      clearSelectionMode: true,
      clearSelectedLandmark: true,
      selectedTimelineUnitCodes: const {},
    );
  }

  /// v2 — region 모드에서 landmark(region/anchor/minor) 선택 시.
  void selectLandmark(String? id) {
    state = state.copyWith(
      selectedLandmarkId: id,
      clearSelectedLandmark: id == null,
      clearSelectedEvent: true,
    );
  }

  void clearEraSelection() {
    state = state.copyWith(
      loading: false,
      clearSelectedEra: true,
      characters: const [],
      events: const [],
      selectedCharacterCodes: const {},
      selectedCharacterColors: const {},
      selectedTimelineUnitCodes: const {},
      displayedEventIds: const {},
      completedEventIds: const {},
      searchQuery: '',
      searchResults: const [],
      isSearching: false,
      clearSelectedEvent: true,
      clearError: true,
    );
  }

  Future<void> selectEra(String eraId) async {
    if (state.selectedEraId == eraId && state.characters.isNotEmpty) {
      return;
    }
    final selectedEra = state.eras.where((era) => era.id == eraId).firstOrNull;
    final eraTestament = selectedEra == null
        ? state.selectedTestament
        : _eraTestament(selectedEra);
    try {
      state = state.copyWith(
        loading: true,
        selectedEraId: eraId,
        selectedTestament: eraTestament,
        clearError: true,
      );
      final characters = await _repo.fetchCharactersByEra(eraId);
      final events = await _repo.fetchEventsByEra(eraId);
      final selectedCharacterCodes = _ensureSelectedCharacterCodes(
        characters,
        const {},
      );
      final eventProgress = await _fetchEventProgressForCurrentUser();
      final eventEmotionMarks = await _fetchEventEmotionMarksForCurrentUser();
      final savedEventIds = await _fetchSavedEventIdsForCurrentUser();
      final completedEventIds = _completedIdsFromProgress(
        eventProgress,
        eventEmotionMarks,
      );
      final quizAttemptSummaries =
          await _fetchQuizAttemptSummariesForCurrentUser();
      state = state.copyWith(
        loading: false,
        characters: characters,
        events: events,
        completedEventIds: completedEventIds,
        bibleReadEventIds: _bibleReadIdsFromProgress(eventProgress),
        quizCompletedEventIds: _quizCompletedIdsFromProgress(eventProgress),
        lastQuizScores: _scoresFromAttempts(quizAttemptSummaries),
        quizAttemptSummaries: quizAttemptSummaries,
        eventEmotionMarks: eventEmotionMarks,
        savedEventIds: savedEventIds,
        selectedCharacterCodes: selectedCharacterCodes,
        selectedCharacterColors: _assignSelectedColors(selectedCharacterCodes),
        selectedTimelineUnitCodes: const {},
        // 시대 전환 시 지도 표시는 항상 초기화 (사용자가 다시 고르도록)
        displayedEventIds: const {},
        searchQuery: '',
        searchResults: const [],
        isSearching: false,
        clearSelectedEvent: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _buildLoadErrorMessage(prefix: '시대 변경 중 오류가 발생했습니다.', error: e),
      );
    }
  }

  void toggleCharacter(String characterCode) {
    final next = {...state.selectedCharacterCodes};
    if (next.contains(characterCode)) {
      next.remove(characterCode);
    } else {
      next.add(characterCode);
    }

    state = state.copyWith(
      selectedCharacterCodes: next,
      selectedCharacterColors: _assignSelectedColors(next),
      // 인물 구성이 바뀌면 지도 표시를 리셋 — Step 3 에서 다시 고르게 함
      displayedEventIds: const {},
      clearSelectedEvent: true,
    );
  }

  void setSelectedCharacters(Set<String> characterCodes) {
    final next = characterCodes
        .where(
          (code) => state.characters.any((character) => character.code == code),
        )
        .toSet();
    final charactersChanged = !_characterSetsEqual(
      next,
      state.selectedCharacterCodes,
    );
    state = state.copyWith(
      selectedCharacterCodes: next,
      selectedCharacterColors: _assignSelectedColors(next),
      // 인물 구성이 **변경된 경우에만** 지도 표시를 리셋.
      // (사용자가 Step 3 ↔ Step 2 를 오가며 인물을 안 바꾸고 "다음" 만 눌렀을
      // 때 지도 선택을 잃지 않도록 보호)
      displayedEventIds: charactersChanged ? const <String>{} : null,
      clearSelectedEvent: true,
    );
  }

  void setSelectedTimelineUnits(Set<String> unitCodes) {
    final validCodes = state.events.map((event) => event.unitCode).toSet();
    final next = unitCodes.intersection(validCodes);
    state = state.copyWith(
      selectedTimelineUnitCodes: next,
      displayedEventIds: const {},
      clearSelectedEvent: true,
    );
  }

  void toggleTimelineUnit(String unitCode) {
    final validCodes = state.events.map((event) => event.unitCode).toSet();
    if (!validCodes.contains(unitCode)) {
      return;
    }
    final next = {...state.selectedTimelineUnitCodes};
    if (next.contains(unitCode)) {
      next.remove(unitCode);
    } else {
      next.add(unitCode);
    }
    setSelectedTimelineUnits(next);
  }

  bool _characterSetsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final code in a) {
      if (!b.contains(code)) {
        return false;
      }
    }
    return true;
  }

  void selectEvent(String? eventId) {
    if (eventId == null) {
      state = state.copyWith(clearSelectedEvent: true);
      return;
    }
    state = state.copyWith(selectedEventId: eventId);
  }

  /// 지도에 핀/화살표로 표시할 이벤트 집합을 커밋한다.
  ///
  /// 현재 `state.events` 에 실제 존재하는 id 만 통과시키고, 다음 렌더에서
  /// `_timelineForSelectedCharacters` 가 이 집합으로 필터되어 핀+화살표 애니메이션이
  /// 시작된다. 홈의 Step 3 "다음" 버튼이 이 메서드를 호출한다.
  void setDisplayedEvents(Set<String> eventIds) {
    final validIds = state.events.map((e) => e.id).toSet();
    final next = eventIds.intersection(validIds);
    state = state.copyWith(displayedEventIds: next);
  }

  Future<void> markEventCompleted({
    required String eventId,
    required bool isCompleted,
  }) async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return;
    }

    await _repo.upsertEventProgress(
      userId: user.id,
      eventId: eventId,
      isCompleted: isCompleted,
    );

    final nextCompleted = {...state.completedEventIds};
    if (isCompleted) {
      nextCompleted.add(eventId);
    } else {
      nextCompleted.remove(eventId);
    }

    state = state.copyWith(completedEventIds: nextCompleted);
  }

  Future<void> refreshCompletedEventIds() async {
    final eventProgress = await _fetchEventProgressForCurrentUser();
    final eventEmotionMarks = await _fetchEventEmotionMarksForCurrentUser();
    state = state.copyWith(
      completedEventIds: _completedIdsFromProgress(
        eventProgress,
        eventEmotionMarks,
      ),
      bibleReadEventIds: _bibleReadIdsFromProgress(eventProgress),
      quizCompletedEventIds: _quizCompletedIdsFromProgress(eventProgress),
      eventEmotionMarks: eventEmotionMarks,
    );
  }

  Future<void> refreshQuizAttemptSummaries() async {
    final summaries = await _fetchQuizAttemptSummariesForCurrentUser();
    state = state.copyWith(
      quizAttemptSummaries: summaries,
      lastQuizScores: _scoresFromAttempts(summaries),
    );
  }

  Future<void> refreshEventEmotionMarks() async {
    final eventProgress = await _fetchEventProgressForCurrentUser();
    final eventEmotionMarks = await _fetchEventEmotionMarksForCurrentUser();
    state = state.copyWith(
      eventEmotionMarks: eventEmotionMarks,
      completedEventIds: _completedIdsFromProgress(
        eventProgress,
        eventEmotionMarks,
      ),
    );
  }

  Future<void> refreshSavedEventIds() async {
    final savedEventIds = await _fetchSavedEventIdsForCurrentUser();
    if (_characterSetsEqual(savedEventIds, state.savedEventIds)) {
      return;
    }
    state = state.copyWith(savedEventIds: savedEventIds);
  }

  Future<bool> toggleSavedEvent(String eventId) async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return false;
    }
    final nowSaved = await _repo.toggleSavedEvent(
      userId: user.id,
      eventId: eventId,
    );
    final next = {...state.savedEventIds};
    if (nowSaved) {
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    state = state.copyWith(savedEventIds: next);
    return nowSaved;
  }

  /// 본문 읽기 완료/취소 토글. 본문 + 퀴즈 둘 다 완료 시 자동으로
  /// `markEventCompleted` 호출.
  Future<void> setBibleRead({
    required String eventId,
    required bool isRead,
  }) async {
    final next = {...state.bibleReadEventIds};
    if (isRead) {
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    state = state.copyWith(bibleReadEventIds: next);
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user != null) {
      await _repo.upsertEventProgress(
        userId: user.id,
        eventId: eventId,
        isBibleRead: isRead,
      );
    }
    await _syncOverallCompletion(eventId);
  }

  /// 퀴즈 완료/취소 토글. 본문 + 퀴즈 둘 다 완료 시 자동으로
  /// `markEventCompleted` 호출. 점수가 있으면 함께 저장.
  Future<void> setQuizCompleted({
    required String eventId,
    required bool isCompleted,
    int? correct,
    int? total,
    int? confusedCount,
    List<int?> selectedAnswers = const [],
  }) async {
    final next = {...state.quizCompletedEventIds};
    if (isCompleted) {
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    final nextScores = {...state.lastQuizScores};
    if (isCompleted && correct != null && total != null) {
      nextScores[eventId] = (correct: correct, total: total);
    } else if (!isCompleted) {
      nextScores.remove(eventId);
    }
    final nextAttempts = {...state.quizAttemptSummaries};
    QuizAttemptSummary? attemptSummary;
    if (isCompleted && correct != null && total != null) {
      attemptSummary = _buildQuizAttemptSummary(
        eventId: eventId,
        correct: correct,
        total: total,
        confusedCount: confusedCount ?? 0,
        selectedAnswers: selectedAnswers,
      );
      nextAttempts[eventId] = attemptSummary;
    }
    state = state.copyWith(
      quizCompletedEventIds: next,
      lastQuizScores: nextScores,
      quizAttemptSummaries: nextAttempts,
    );
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user != null && attemptSummary != null) {
      await _repo.upsertQuizAttempt(userId: user.id, summary: attemptSummary);
    }
    if (user != null) {
      await _repo.upsertEventProgress(
        userId: user.id,
        eventId: eventId,
        isQuizCompleted: isCompleted,
      );
    }
    await _syncOverallCompletion(eventId);
  }

  Future<void> setEmotionMark({
    required String eventId,
    required EventEmotionOption option,
    required String note,
  }) async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return;
    }
    final normalizedNote = note.trim();
    final mark = EventEmotionMark(
      eventId: eventId,
      emotionKey: option.key,
      emotionLabel: option.label,
      emotionEmoji: option.emoji,
      note: normalizedNote.length > 100
          ? normalizedNote.substring(0, 100)
          : normalizedNote,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repo.upsertEventEmotionMark(userId: user.id, mark: mark);
    state = state.copyWith(
      eventEmotionMarks: {...state.eventEmotionMarks, eventId: mark},
    );
    await _syncOverallCompletion(eventId);
  }

  Future<void> clearEmotionMark({required String eventId}) async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return;
    }
    await _repo.deleteEventEmotionMark(userId: user.id, eventId: eventId);
    final nextMarks = {...state.eventEmotionMarks}..remove(eventId);
    state = state.copyWith(eventEmotionMarks: nextMarks);
    await _syncOverallCompletion(eventId);
  }

  /// bibleRead + quizCompleted + emotion mark 모두 완료면 [markEventCompleted] 호출,
  /// 어느 한쪽이라도 미완이면 false 로 호출하여 DB 와 동기화.
  Future<void> _syncOverallCompletion(String eventId) async {
    final read = state.bibleReadEventIds.contains(eventId);
    final quiz = state.quizCompletedEventIds.contains(eventId);
    final engraved = state.eventEmotionMarks.containsKey(eventId);
    final shouldComplete = read && quiz && engraved;
    final isCurrentlyCompleted = state.completedEventIds.contains(eventId);
    if (shouldComplete == isCurrentlyCompleted) return;
    await markEventCompleted(eventId: eventId, isCompleted: shouldComplete);
  }

  /// 주간 퀴즈 모드 — 특정 week_key 의 진행도를 DB 에서 로드하고 state 캐시.
  /// 같은 weekKey 가 이미 캐시돼 있으면 noop.
  Future<void> ensureWeeklyQuizProgressLoaded(String weekKey) async {
    if (state.weeklyQuizWeekKey == weekKey) return;
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      state = state.copyWith(
        weeklyQuizBibleReadEventIds: const {},
        weeklyQuizCompletedEventIds: const {},
        weeklyQuizLastScores: const {},
        weeklyQuizWeekKey: weekKey,
      );
      return;
    }
    final rows = await _repo.fetchWeeklyQuizProgress(
      userId: user.id,
      weekKey: weekKey,
    );
    final read = <String>{};
    final quiz = <String>{};
    for (final entry in rows.entries) {
      if (entry.value.bibleRead) read.add(entry.key);
      if (entry.value.quizCompleted) quiz.add(entry.key);
    }
    state = state.copyWith(
      weeklyQuizBibleReadEventIds: read,
      weeklyQuizCompletedEventIds: quiz,
      weeklyQuizLastScores: const {},
      weeklyQuizWeekKey: weekKey,
    );
  }

  /// 주간 퀴즈 — 본문 읽기 토글. 프로필 진행도(setBibleRead)와 독립.
  Future<void> setWeeklyQuizBibleRead({
    required String weekKey,
    required String eventId,
    required bool isRead,
  }) async {
    final next = {...state.weeklyQuizBibleReadEventIds};
    if (isRead) {
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    state = state.copyWith(
      weeklyQuizBibleReadEventIds: next,
      weeklyQuizWeekKey: weekKey,
    );
    final user = ref.read(signedInUserProvider);
    if (user == null) return;
    await _repo.upsertWeeklyQuizProgress(
      userId: user.id,
      weekKey: weekKey,
      eventId: eventId,
      isBibleRead: isRead,
    );
  }

  /// 주간 퀴즈 — 퀴즈 완료 토글. 점수도 함께 저장.
  Future<void> setWeeklyQuizCompleted({
    required String weekKey,
    required String eventId,
    required bool isCompleted,
    int? correct,
    int? total,
    int? confusedCount,
    List<int?> selectedAnswers = const [],
  }) async {
    final next = {...state.weeklyQuizCompletedEventIds};
    if (isCompleted) {
      next.add(eventId);
    } else {
      next.remove(eventId);
    }
    final nextScores = {...state.weeklyQuizLastScores};
    if (isCompleted && correct != null && total != null) {
      nextScores[eventId] = (correct: correct, total: total);
    } else if (!isCompleted) {
      nextScores.remove(eventId);
    }
    final nextAttempts = {...state.quizAttemptSummaries};
    QuizAttemptSummary? attemptSummary;
    if (isCompleted && correct != null && total != null) {
      attemptSummary = _buildQuizAttemptSummary(
        eventId: eventId,
        correct: correct,
        total: total,
        confusedCount: confusedCount ?? 0,
        selectedAnswers: selectedAnswers,
      );
      nextAttempts[eventId] = attemptSummary;
    }
    state = state.copyWith(
      weeklyQuizCompletedEventIds: next,
      weeklyQuizLastScores: nextScores,
      weeklyQuizWeekKey: weekKey,
      quizAttemptSummaries: nextAttempts,
    );
    final user = ref.read(signedInUserProvider);
    if (user == null) return;
    if (attemptSummary != null) {
      await _repo.upsertQuizAttempt(userId: user.id, summary: attemptSummary);
    }
    await _repo.upsertWeeklyQuizProgress(
      userId: user.id,
      weekKey: weekKey,
      eventId: eventId,
      isQuizCompleted: isCompleted,
      lastScoreCorrect: correct,
      lastScoreTotal: total,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: const [], isSearching: false);
      return;
    }

    state = state.copyWith(isSearching: true, searchResults: const []);
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> selectSearchResult(StoryEvent event) async {
    state = state.copyWith(
      loading: true,
      clearSelectedEvent: true,
      clearError: true,
    );

    try {
      if (state.selectedEraId != event.eraId) {
        await selectEra(event.eraId);
      }

      final searchSelectedCodes = event.characterCodes.toSet();
      var selectedCodes = {
        ...searchSelectedCodes.where(
          (code) => state.characters.any((character) => character.code == code),
        ),
      };

      if (selectedCodes.isEmpty &&
          state.events.where((e) => e.id == event.id).isNotEmpty) {
        selectedCodes.addAll(
          state.events
              .firstWhere((e) => e.id == event.id)
              .characterCodes
              .where(
                (code) =>
                    state.characters.any((character) => character.code == code),
              ),
        );
      }
      if (selectedCodes.isEmpty) {
        selectedCodes = {
          if (searchSelectedCodes.isNotEmpty) searchSelectedCodes.first,
        };
      }

      state = state.copyWith(
        loading: false,
        selectedCharacterCodes: selectedCodes,
        selectedCharacterColors: _assignSelectedColors(selectedCodes),
        selectedEventId: event.id,
        searchQuery: '',
        searchResults: const [],
        isSearching: false,
      );
      _focusOnSearchSelection(event.id);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: '검색 결과 선택 중 오류가 발생했습니다: $error',
      );
    }
  }

  Future<void> _runSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(searchResults: const [], isSearching: false);
      return;
    }

    try {
      final results = await _repo.searchEventsByText(normalized);
      state = state.copyWith(
        isSearching: false,
        searchResults: results.take(12).toList(),
      );
    } catch (error) {
      state = state.copyWith(
        isSearching: false,
        searchResults: const [],
        error: '검색에 실패했습니다: $error',
      );
    }
  }

  Future<Map<String, ({bool bibleRead, bool quizCompleted, bool completed})>>
  _fetchEventProgressForCurrentUser() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return const <
        String,
        ({bool bibleRead, bool quizCompleted, bool completed})
      >{};
    }
    return _repo.fetchEventProgress(user.id);
  }

  Future<Map<String, QuizAttemptSummary>>
  _fetchQuizAttemptSummariesForCurrentUser() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return const <String, QuizAttemptSummary>{};
    }
    return _repo.fetchQuizAttemptSummaries(user.id);
  }

  Future<Map<String, EventEmotionMark>>
  _fetchEventEmotionMarksForCurrentUser() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return const <String, EventEmotionMark>{};
    }
    return _repo.fetchEventEmotionMarks(user.id);
  }

  Future<Set<String>> _fetchSavedEventIdsForCurrentUser() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return const <String>{};
    }
    return _repo.fetchSavedEventIds(user.id);
  }

  Set<String> _bibleReadIdsFromProgress(
    Map<String, ({bool bibleRead, bool quizCompleted, bool completed})>
    progress,
  ) {
    return {
      for (final entry in progress.entries)
        if (entry.value.bibleRead) entry.key,
    };
  }

  Set<String> _quizCompletedIdsFromProgress(
    Map<String, ({bool bibleRead, bool quizCompleted, bool completed})>
    progress,
  ) {
    return {
      for (final entry in progress.entries)
        if (entry.value.quizCompleted) entry.key,
    };
  }

  Set<String> _completedIdsFromProgress(
    Map<String, ({bool bibleRead, bool quizCompleted, bool completed})>
    progress,
    Map<String, EventEmotionMark> emotionMarks,
  ) {
    return {
      for (final entry in progress.entries)
        if (entry.value.bibleRead &&
            entry.value.quizCompleted &&
            emotionMarks.containsKey(entry.key))
          entry.key,
    };
  }

  Map<String, ({int correct, int total})> _scoresFromAttempts(
    Map<String, QuizAttemptSummary> summaries,
  ) {
    return {
      for (final entry in summaries.entries)
        entry.key: (
          correct: entry.value.correctCount,
          total: entry.value.totalCount,
        ),
    };
  }

  QuizAttemptSummary _buildQuizAttemptSummary({
    required String eventId,
    required int correct,
    required int total,
    required int confusedCount,
    required List<int?> selectedAnswers,
  }) {
    final normalizedConfused = confusedCount < 0
        ? 0
        : (confusedCount > total ? total : confusedCount);
    final rawWrong = total - correct - normalizedConfused;
    final wrong = rawWrong < 0 ? 0 : (rawWrong > total ? total : rawWrong);
    return QuizAttemptSummary(
      eventId: eventId,
      correctCount: correct,
      totalCount: total,
      wrongCount: wrong,
      confusedCount: normalizedConfused,
      selectedAnswers: selectedAnswers,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  List<StoryEvent> mergedTimeline() {
    final filtered = state.events.where((event) {
      return event.characterCodes.any(state.selectedCharacterCodes.contains);
    }).toList();

    filtered.sort((a, b) {
      final cmp = a.globalRank.compareTo(b.globalRank);
      if (cmp != 0) {
        return cmp;
      }
      return a.id.compareTo(b.id);
    });

    return filtered;
  }

  List<StoryEvent> searchResults() {
    return state.searchResults;
  }

  Color colorForCharacter(String characterCode) {
    // 1) 사용자가 선택한 인물은 미리 할당된 8색 팔레트에서 정해진 색을 사용
    //    (선택 순서대로 분배 — 시각적으로 비교 가능).
    final assigned = state.selectedCharacterColors[characterCode];
    if (assigned != null) {
      return assigned;
    }
    // 2) 미선택 인물도 코드 hash 로 안정적 색을 부여한다 (앱을 다시 켜도 같은 색).
    //    "시대 미리보기" 모드에서 모든 인물 path 가 자기만의 색을 갖도록 하기
    //    위한 fallback. 같은 길이의 코드가 비슷한 색에 몰리지 않게 단순 해시 +
    //    팔레트 길이 모듈로 사용.
    if (characterCode.isEmpty) {
      return AppColors.characterFallback;
    }
    return AppColors.characterAt(characterCode.hashCode);
  }

  Character? characterByCode(String characterCode) {
    for (final character in state.characters) {
      if (character.code == characterCode) {
        return character;
      }
    }
    return null;
  }

  Set<String> _ensureSelectedCharacterCodes(
    List<Character> characters,
    Set<String> current,
  ) {
    if (characters.isEmpty) {
      return const {};
    }
    return current
        .where((code) => characters.any((p) => p.code == code))
        .toSet();
  }

  void _focusOnSearchSelection(String eventId) {
    final event = state.events.where((item) => item.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    state = state.copyWith(selectedEventId: event.id);
  }

  Map<String, Color> _assignSelectedColors(Set<String> selectedIds) {
    final next = <String, Color>{};
    final ordered = selectedIds.toList();
    for (var i = 0; i < ordered.length; i++) {
      next[ordered[i]] = AppColors.characterAt(i);
    }
    return next;
  }

  String _eraTestament(Era era) {
    final raw = era.testament.toString().trim().toLowerCase();
    if (raw == 'new' || raw == 'nt' || raw == 'new_testament') {
      return 'new';
    }
    if (era.code.toString().startsWith('era_nt_')) {
      return 'new';
    }
    return 'old';
  }

  String _buildLoadErrorMessage({
    required String prefix,
    required Object error,
  }) {
    if (error is SocketException) {
      return '$prefix 네트워크 연결 또는 Supabase 주소 설정을 확인하세요.';
    }

    final message = error.toString();
    if (message.contains('Failed host lookup')) {
      return '$prefix Supabase 주소를 찾지 못했습니다. .env의 SUPABASE_URL_DEV 또는 SUPABASE_URL_PROD 설정을 확인하세요.';
    }

    return '$prefix $message';
  }
}
