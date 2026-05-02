import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/era_boundary.dart';
import '../models/landmark.dart';
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
    this.landmarks = const [],
    this.eraBoundaries = const [],
    this.viewportSearchPool = const [],
    this.viewportSearchResults = const [],
    this.selectedLandmarkCategories = const {},
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

  /// 시대별 랜드마크 카탈로그 (전체). 클라이언트가 selectedEraId 의 era code 로
  /// 각 랜드마크의 era_codes 배열과 매칭해 필터링.
  final List<Landmark> landmarks;

  /// 시대별 거친 지리 영역 폴리곤 (모든 시대 분량). 클라이언트가 selectedEraId
  /// 로 필터해서 그 시대만 지도에 띄운다.
  final List<EraBoundary> eraBoundaries;

  /// "현 지도에서 검색" 풀 — 처음 1회 fetch 후 캐시.
  final List<StoryEvent> viewportSearchPool;

  /// 현재 viewport 가운데 50% 박스 안 사건들 (검색 결과).
  final List<StoryEvent> viewportSearchResults;

  /// 사용자가 선택한 랜드마크 카테고리 필터 (예: 'mountain', 'battle', 'tomb').
  /// 비어 있으면 모든 카테고리 통과 (전체 표시).
  final Set<String> selectedLandmarkCategories;

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
    List<Landmark>? landmarks,
    List<EraBoundary>? eraBoundaries,
    List<StoryEvent>? viewportSearchPool,
    List<StoryEvent>? viewportSearchResults,
    Set<String>? selectedLandmarkCategories,
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
      landmarks: landmarks ?? this.landmarks,
      eraBoundaries: eraBoundaries ?? this.eraBoundaries,
      viewportSearchPool: viewportSearchPool ?? this.viewportSearchPool,
      viewportSearchResults:
          viewportSearchResults ?? this.viewportSearchResults,
      selectedLandmarkCategories:
          selectedLandmarkCategories ?? this.selectedLandmarkCategories,
    );
  }
}
