import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/story_event.dart';

class StoryState {
  const StoryState({
    this.loading = false,
    this.error,
    this.eras = const [],
    this.characters = const [],
    this.events = const [],
    this.selectedEraId,
    this.selectedCharacterCodes = const {},
    this.selectedCharacterColors = const {},
    this.selectedEventId,
    this.displayedEventIds = const {},
    this.completedEventIds = const {},
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.selectedTestament = 'old',
  });

  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Character> characters;
  final List<StoryEvent> events;
  final String? selectedEraId;
  final Set<String> selectedCharacterCodes;
  final Map<String, Color> selectedCharacterColors;
  final String? selectedEventId;

  /// 지도에 핀/화살표로 렌더할 이벤트 id 집합.
  ///
  /// 홈 화면의 Step 3 에서 사용자가 체크박스로 고르고 "다음" 을 눌러야만
  /// 커밋된다. 비어 있으면 지도에 아무 것도 표시하지 않는다 (인물을 골라도
  /// 자동으로 모든 사건이 튀어나오지 않도록 하기 위함).
  final Set<String> displayedEventIds;

  final Set<String> completedEventIds;
  final String searchQuery;
  final List<StoryEvent> searchResults;
  final bool isSearching;
  final String selectedTestament;

  StoryState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<Era>? eras,
    List<Character>? characters,
    List<StoryEvent>? events,
    String? selectedEraId,
    bool clearSelectedEra = false,
    Set<String>? selectedCharacterCodes,
    Map<String, Color>? selectedCharacterColors,
    String? selectedEventId,
    Set<String>? displayedEventIds,
    Set<String>? completedEventIds,
    bool clearSelectedEvent = false,
    String? searchQuery,
    List<StoryEvent>? searchResults,
    bool? isSearching,
    String? selectedTestament,
  }) {
    return StoryState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      eras: eras ?? this.eras,
      characters: characters ?? this.characters,
      events: events ?? this.events,
      selectedEraId: clearSelectedEra
          ? null
          : selectedEraId ?? this.selectedEraId,
      selectedCharacterCodes:
          selectedCharacterCodes ?? this.selectedCharacterCodes,
      selectedCharacterColors:
          selectedCharacterColors ?? this.selectedCharacterColors,
      selectedEventId: clearSelectedEvent
          ? null
          : selectedEventId ?? this.selectedEventId,
      displayedEventIds: displayedEventIds ?? this.displayedEventIds,
      completedEventIds: completedEventIds ?? this.completedEventIds,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      selectedTestament: selectedTestament ?? this.selectedTestament,
    );
  }
}
