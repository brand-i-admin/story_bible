import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/story_repository.dart';
import '../models/era.dart';
import '../models/person.dart';
import '../models/story_event.dart';
import '../state/auth_providers.dart';
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

  static const _palette = <Color>[
    Color(0xFF3B6C94),
    Color(0xFFB6673C),
    Color(0xFF557C3E),
    Color(0xFF8A4E5D),
    Color(0xFF616161),
    Color(0xFF9E7C24),
    Color(0xFF7B5D43),
    Color(0xFF5C6B9F),
  ];

  StoryRepository get _repo => ref.read(storyRepositoryProvider);

  @override
  StoryState build() => const StoryState(loading: true);

  Future<void> initialize() async {
    try {
      state = state.copyWith(loading: true, clearError: true);
      final eras = await _repo.fetchEras();
      final completedEventIds = await _fetchCompletedEventIdsForCurrentUser();
      if (eras.isEmpty) {
        state = state.copyWith(
          loading: false,
          eras: const [],
          persons: const [],
          events: const [],
          error: '시대 데이터가 없습니다.',
        );
        return;
      }

      final hasOldTestament = eras.any((era) => _eraTestament(era) == 'old');
      state = state.copyWith(
        loading: false,
        eras: eras,
        persons: const [],
        events: const [],
        completedEventIds: completedEventIds,
        selectedEraId: null,
        selectedPersonIds: const {},
        selectedPersonColors: const {},
        selectedTestament: hasOldTestament ? 'old' : _eraTestament(eras.first),
        searchQuery: '',
        searchResults: const [],
        isSearching: false,
        clearSelectedEvent: true,
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
        persons: const [],
        events: const [],
        selectedPersonIds: const {},
        selectedPersonColors: const {},
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

  void clearEraSelection() {
    state = state.copyWith(
      loading: false,
      clearSelectedEra: true,
      persons: const [],
      events: const [],
      selectedPersonIds: const {},
      selectedPersonColors: const {},
      completedEventIds: const {},
      searchQuery: '',
      searchResults: const [],
      isSearching: false,
      clearSelectedEvent: true,
      clearError: true,
    );
  }

  Future<void> selectEra(String eraId) async {
    if (state.selectedEraId == eraId && state.persons.isNotEmpty) {
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
      final persons = await _repo.fetchPersonsByEra(eraId);
      final events = await _repo.fetchEventsByEra(eraId);
      final selectedPersonIds = _ensureSelectedPersons(persons, const {});
      final completedEventIds = await _fetchCompletedEventIdsForCurrentUser();
      state = state.copyWith(
        loading: false,
        persons: persons,
        events: events,
        completedEventIds: completedEventIds,
        selectedPersonIds: selectedPersonIds,
        selectedPersonColors: _assignSelectedColors(selectedPersonIds),
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

  void togglePerson(String personId) {
    final next = {...state.selectedPersonIds};
    if (next.contains(personId)) {
      next.remove(personId);
    } else {
      next.add(personId);
    }

    state = state.copyWith(
      selectedPersonIds: next,
      selectedPersonColors: _assignSelectedColors(next),
      clearSelectedEvent: true,
    );
  }

  void setSelectedPersons(Set<String> personIds) {
    final next = personIds
        .where((id) => state.persons.any((person) => person.id == id))
        .toSet();
    state = state.copyWith(
      selectedPersonIds: next,
      selectedPersonColors: _assignSelectedColors(next),
      clearSelectedEvent: true,
    );
  }

  void selectEvent(String? eventId) {
    if (eventId == null) {
      state = state.copyWith(clearSelectedEvent: true);
      return;
    }
    state = state.copyWith(selectedEventId: eventId);
  }

  Future<void> markEventCompleted({
    required String eventId,
    required int score,
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
      score: score,
      xpEarned: isCompleted ? score * 10 : 0,
    );

    if (isCompleted) {
      await ref.read(userRepositoryProvider).recordStudyDay(user.id);
    }

    final nextCompleted = {...state.completedEventIds};
    if (isCompleted) {
      nextCompleted.add(eventId);
    } else {
      nextCompleted.remove(eventId);
    }

    state = state.copyWith(completedEventIds: nextCompleted);
  }

  Future<void> refreshCompletedEventIds() async {
    final completedEventIds = await _fetchCompletedEventIdsForCurrentUser();
    state = state.copyWith(completedEventIds: completedEventIds);
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

      final searchSelectedIds = event.personIds.toSet();
      var selectedIds = {
        ...searchSelectedIds.where(
          (personId) => state.persons.any((person) => person.id == personId),
        ),
      };

      if (selectedIds.isEmpty &&
          state.events.where((e) => e.id == event.id).isNotEmpty) {
        selectedIds.addAll(
          state.events
              .firstWhere((e) => e.id == event.id)
              .personIds
              .where(
                (personId) =>
                    state.persons.any((person) => person.id == personId),
              ),
        );
      }
      if (selectedIds.isEmpty) {
        selectedIds = {
          if (searchSelectedIds.isNotEmpty) searchSelectedIds.first,
        };
      }

      state = state.copyWith(
        loading: false,
        selectedPersonIds: selectedIds,
        selectedPersonColors: _assignSelectedColors(selectedIds),
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

  Future<Set<String>> _fetchCompletedEventIdsForCurrentUser() async {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    if (user == null) {
      return const <String>{};
    }
    return _repo.fetchCompletedEventIds(user.id);
  }

  List<StoryEvent> mergedTimeline() {
    final filtered = state.events.where((event) {
      final hasSelectedPerson = event.personIds.any(
        state.selectedPersonIds.contains,
      );
      return hasSelectedPerson;
    }).toList();

    filtered.sort((a, b) {
      final cmp = a.timeSortKey.compareTo(b.timeSortKey);
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

  Color colorForPerson(String personId) {
    final assigned = state.selectedPersonColors[personId];
    if (assigned != null) {
      return assigned;
    }
    return const Color(0xFF8E7B61);
  }

  Person? personById(String personId) {
    for (final person in state.persons) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  Set<String> _ensureSelectedPersons(
    List<Person> persons,
    Set<String> current,
  ) {
    if (persons.isEmpty) {
      return const {};
    }
    return current.where((id) => persons.any((p) => p.id == id)).toSet();
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
      next[ordered[i]] = _palette[i % _palette.length];
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
