import 'package:flutter/material.dart';

import '../models/era.dart';
import '../models/person.dart';
import '../models/story_event.dart';

class StoryState {
  const StoryState({
    this.loading = false,
    this.error,
    this.eras = const [],
    this.persons = const [],
    this.events = const [],
    this.selectedEraId,
    this.selectedPersonIds = const {},
    this.selectedPersonColors = const {},
    this.selectedEventId,
    this.completedEventIds = const {},
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.selectedTestament = 'old',
  });

  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Person> persons;
  final List<StoryEvent> events;
  final String? selectedEraId;
  final Set<String> selectedPersonIds;
  final Map<String, Color> selectedPersonColors;
  final String? selectedEventId;
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
    List<Person>? persons,
    List<StoryEvent>? events,
    String? selectedEraId,
    bool clearSelectedEra = false,
    Set<String>? selectedPersonIds,
    Map<String, Color>? selectedPersonColors,
    String? selectedEventId,
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
      persons: persons ?? this.persons,
      events: events ?? this.events,
      selectedEraId: clearSelectedEra
          ? null
          : selectedEraId ?? this.selectedEraId,
      selectedPersonIds: selectedPersonIds ?? this.selectedPersonIds,
      selectedPersonColors: selectedPersonColors ?? this.selectedPersonColors,
      selectedEventId: clearSelectedEvent
          ? null
          : selectedEventId ?? this.selectedEventId,
      completedEventIds: completedEventIds ?? this.completedEventIds,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      selectedTestament: selectedTestament ?? this.selectedTestament,
    );
  }
}
