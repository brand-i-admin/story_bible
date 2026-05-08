import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/era_boundary.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';

/// 시대 선택 후 사용자가 선택할 수 있는 두 가지 탐색 모드.
/// - region: 지도 위 region(영역) 들이 라벨 + 사건 있는 인물 아바타와 함께 표시되고,
///   region 을 누르면 그 region 안의 사건들이 카드 슬라이딩으로 펼쳐진다.
/// - character: 인물 멀티 선택 → 사건 카드 5열 그리드 + 점선 연결 + 좌우 화살표.
enum SelectionMode { region, character }

class StoryState {
  const StoryState({
    this.loading = false,
    this.error,
    this.eras = const [],
    this.characters = const [],
    this.events = const [],
    this.selectedEraId,
    this.selectionMode,
    this.selectedLandmarkId,
    this.selectedCharacterCodes = const {},
    this.selectedCharacterColors = const {},
    this.selectedEventId,
    this.displayedEventIds = const {},
    this.completedEventIds = const {},
    this.bibleReadEventIds = const {},
    this.quizCompletedEventIds = const {},
    this.lastQuizScores = const {},
    this.weeklyQuizBibleReadEventIds = const {},
    this.weeklyQuizCompletedEventIds = const {},
    this.weeklyQuizLastScores = const {},
    this.weeklyQuizWeekKey,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.selectedTestament = 'old',
    this.landmarks = const [],
    this.eraBoundaries = const [],
    this.selectedLandmarkCategories = const {},
  });

  final bool loading;
  final String? error;
  final List<Era> eras;
  final List<Character> characters;
  final List<StoryEvent> events;

  /// 단일 시대 선택. 멀티 시대 기능은 제거됨.
  final String? selectedEraId;

  /// 호환 getter — 기존 호출자가 set 형태로 접근하던 것을 단일 시대 set 으로
  /// derive. 항상 0 또는 1 개 원소를 가진다.
  Set<String> get selectedEraIds =>
      selectedEraId == null ? const <String>{} : {selectedEraId!};

  /// v2 — 시대 선택 후 사용자가 고른 탐색 모드. null 이면 아직 모달이 안 떴거나
  /// 닫힌 상태.
  final SelectionMode? selectionMode;

  /// v2 — region 모드에서 사용자가 선택한 landmark (region/anchor/minor) id.
  /// 선택 시 하단 시트가 최소화되고 그 landmark 의 사건들이 카드로 펼쳐진다.
  final String? selectedLandmarkId;

  final Set<String> selectedCharacterCodes;
  final Map<String, Color> selectedCharacterColors;
  final String? selectedEventId;
  final Set<String> displayedEventIds;
  final Set<String> completedEventIds;

  /// 본문 읽기 완료 이벤트 ID. 사용자가 [event_detail] 의 '읽기' 버튼을 눌러
  /// bible reader 를 보고 돌아오면 추가됨. completedEventIds 와 별개로 추적해
  /// 부분 진행도(읽기만 했고 퀴즈 미완료) 를 표현한다.
  final Set<String> bibleReadEventIds;

  /// 퀴즈 완료 이벤트 ID. 모든 문제를 풀고 해설까지 본 경우만 추가됨.
  final Set<String> quizCompletedEventIds;

  /// 가장 최근 퀴즈 결과 (eventId → "맞춘수/총문제"). UI 표시용.
  final Map<String, ({int correct, int total})> lastQuizScores;

  /// 주간 퀴즈 — 이번 주에 본문 읽기 완료한 사건 ID. 프로필 진행도와 독립.
  /// week_key 가 바뀌면 (다음 주) 자동으로 비워진다.
  final Set<String> weeklyQuizBibleReadEventIds;

  /// 주간 퀴즈 — 이번 주에 퀴즈 완료한 사건 ID. 위와 한 쌍.
  final Set<String> weeklyQuizCompletedEventIds;

  /// 주간 퀴즈 — 이번 주 최근 퀴즈 점수 (eventId → 맞춘수/총문제).
  final Map<String, ({int correct, int total})> weeklyQuizLastScores;

  /// 현재 캐시된 주간 진행도가 어느 week_key 의 것인지. null 이면 미로드.
  final String? weeklyQuizWeekKey;
  final String searchQuery;
  final List<StoryEvent> searchResults;
  final bool isSearching;
  final String selectedTestament;
  final List<Landmark> landmarks;
  final List<EraBoundary> eraBoundaries;
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
    SelectionMode? selectionMode,
    bool clearSelectionMode = false,
    String? selectedLandmarkId,
    bool clearSelectedLandmark = false,
    Set<String>? selectedCharacterCodes,
    Map<String, Color>? selectedCharacterColors,
    String? selectedEventId,
    Set<String>? displayedEventIds,
    Set<String>? completedEventIds,
    Set<String>? bibleReadEventIds,
    Set<String>? quizCompletedEventIds,
    Map<String, ({int correct, int total})>? lastQuizScores,
    Set<String>? weeklyQuizBibleReadEventIds,
    Set<String>? weeklyQuizCompletedEventIds,
    Map<String, ({int correct, int total})>? weeklyQuizLastScores,
    String? weeklyQuizWeekKey,
    bool clearWeeklyQuizWeekKey = false,
    bool clearSelectedEvent = false,
    String? searchQuery,
    List<StoryEvent>? searchResults,
    bool? isSearching,
    String? selectedTestament,
    List<Landmark>? landmarks,
    List<EraBoundary>? eraBoundaries,
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
      selectionMode: clearSelectionMode
          ? null
          : selectionMode ?? this.selectionMode,
      selectedLandmarkId: clearSelectedLandmark
          ? null
          : selectedLandmarkId ?? this.selectedLandmarkId,
      selectedCharacterCodes:
          selectedCharacterCodes ?? this.selectedCharacterCodes,
      selectedCharacterColors:
          selectedCharacterColors ?? this.selectedCharacterColors,
      selectedEventId: clearSelectedEvent
          ? null
          : selectedEventId ?? this.selectedEventId,
      displayedEventIds: displayedEventIds ?? this.displayedEventIds,
      completedEventIds: completedEventIds ?? this.completedEventIds,
      bibleReadEventIds: bibleReadEventIds ?? this.bibleReadEventIds,
      quizCompletedEventIds:
          quizCompletedEventIds ?? this.quizCompletedEventIds,
      lastQuizScores: lastQuizScores ?? this.lastQuizScores,
      weeklyQuizBibleReadEventIds:
          weeklyQuizBibleReadEventIds ?? this.weeklyQuizBibleReadEventIds,
      weeklyQuizCompletedEventIds:
          weeklyQuizCompletedEventIds ?? this.weeklyQuizCompletedEventIds,
      weeklyQuizLastScores: weeklyQuizLastScores ?? this.weeklyQuizLastScores,
      weeklyQuizWeekKey: clearWeeklyQuizWeekKey
          ? null
          : weeklyQuizWeekKey ?? this.weeklyQuizWeekKey,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      selectedTestament: selectedTestament ?? this.selectedTestament,
      landmarks: landmarks ?? this.landmarks,
      eraBoundaries: eraBoundaries ?? this.eraBoundaries,
      selectedLandmarkCategories:
          selectedLandmarkCategories ?? this.selectedLandmarkCategories,
    );
  }

  /// id 로 landmark 찾기 (region/anchor/minor 통합 lookup).
  Landmark? landmarkById(String? id) {
    if (id == null) return null;
    for (final lm in landmarks) {
      if (lm.id == id) return lm;
    }
    return null;
  }

  /// landmark 의 region 부모. 이미 region 이면 자기 자신.
  Landmark? regionForLandmark(String landmarkId) {
    final lm = landmarkById(landmarkId);
    if (lm == null) return null;
    if (lm.isRegion) return lm;
    return landmarkById(lm.parentLandmarkId);
  }
}
