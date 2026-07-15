import '../models/era.dart';
import '../models/story_event.dart';
import 'weekly_selection.dart';

/// KST 기준 날짜를 'YYYY-M-D' 형식의 매일 미션 키로 변환한다.
String dailyExplorationKeyForKst(DateTime instant) {
  final kst = instant.toUtc().add(const Duration(hours: 9));
  return '${kst.year}-${kst.month}-${kst.day}';
}

/// 날짜 키가 같으면 모든 사용자에게 같은 오늘의 사건을 제공한다.
StoryEvent? pickDailyExplorationEvent({
  required List<StoryEvent> events,
  required String dayKey,
}) {
  final ordered = orderedDailyExplorationEvents(events);
  if (ordered.isEmpty) return null;
  final seed = seedFromKey('daily-exploration:$dayKey');
  return ordered[seed % ordered.length];
}

/// 오늘의 추천 사건을 가운데 두고 시간 순으로 이전·추천·이후 사건을 반환한다.
///
/// 첫/마지막 사건에서는 목록을 순환해 홈 지도와 카드에 항상 세 개의 서로 다른
/// 사건이 보이게 한다. 전체 사건이 세 개보다 적으면 중복 없이 가능한 사건만
/// 반환하며, 두 개인 경우 추천 사건은 마지막 원소에 놓인다.
List<StoryEvent> pickDailyExplorationJourney({
  required List<StoryEvent> events,
  required String dayKey,
}) {
  final ordered = orderedDailyExplorationEvents(events);
  if (ordered.isEmpty) return const [];
  final seed = seedFromKey('daily-exploration:$dayKey');
  final recommendedIndex = seed % ordered.length;
  return explorationJourneyAround(
    events: ordered,
    currentEventId: ordered[recommendedIndex].id,
  );
}

/// 전체 이야기 목록을 오늘 탐험 덱에서 사용하는 시간 순으로 정렬한다.
List<StoryEvent> orderedDailyExplorationEvents(List<StoryEvent> events) {
  return [...events]..sort((a, b) {
    final rank = a.globalRank.compareTo(b.globalRank);
    if (rank != 0) return rank;
    return a.id.compareTo(b.id);
  });
}

const _canonicalExplorationEraOrder = <String, int>{
  'era_primeval': 0,
  'era_patriarch': 1,
  'era_exodus': 2,
  'era_judges': 3,
  'era_monarchy': 4,
  'era_divided_kingdom': 5,
  'era_exile_return': 6,
  'era_nt_public_ministry': 7,
  'era_nt_apostolic': 8,
  'era_nt_post_apostolic': 9,
};

/// 오늘 탐험 덱을 `구약 7시대 → 신약 3시대 → 시대 내 사건 순서`로 정렬한다.
///
/// DB의 `display_order`는 구약과 신약에서 각각 1부터 시작하고, 과거
/// `global_rank` 값도 시대 경계를 안정적으로 표현하지 못한다. 따라서 공개된
/// 10개 시대는 앱의 정해진 절대 순서를 사용하고, 각 시대 안에서는
/// [StoryEvent.rankInEra]를 우선한다.
List<StoryEvent> orderedExplorationEventsByEra({
  required List<StoryEvent> events,
  required List<Era> eras,
}) {
  final eraById = <String, Era>{for (final era in eras) era.id: era};
  return [...events]..sort((a, b) {
    final aEra = eraById[a.eraId];
    final bEra = eraById[b.eraId];
    final eraOrder = _explorationEraOrder(
      aEra,
    ).compareTo(_explorationEraOrder(bEra));
    if (eraOrder != 0) return eraOrder;

    final eraIdentity = a.eraId.compareTo(b.eraId);
    if (eraIdentity != 0) return eraIdentity;

    final rankInEra = a.rankInEra.compareTo(b.rankInEra);
    if (rankInEra != 0) return rankInEra;
    final storyIndex = a.storyIndex.compareTo(b.storyIndex);
    if (storyIndex != 0) return storyIndex;
    final globalRank = a.globalRank.compareTo(b.globalRank);
    if (globalRank != 0) return globalRank;
    return a.id.compareTo(b.id);
  });
}

int _explorationEraOrder(Era? era) {
  if (era == null) return 10000;
  final canonical = _canonicalExplorationEraOrder[era.code];
  if (canonical != null) return canonical;
  final testamentOffset = era.testament == 'new' ? 1000 : 100;
  return testamentOffset + era.displayOrder;
}

/// 오늘 탐험이 이어질 사건을 최근 감정 새기기 기준으로 고른다.
///
/// 기록이 없으면 성경 전체 시간순 첫 사건을 반환한다. 기록이 있으면 가장 최근에
/// 감정을 새긴 사건의 바로 다음 사건을 반환해, 최근 사건이 카드 덱의 `이전 이야기`로
/// 보이게 한다. 마지막 사건에 기록했다면 더 진행할 사건이 없으므로 마지막을 유지한다.
StoryEvent? pickExplorationResumeEvent({
  required List<StoryEvent> events,
  required List<Era> eras,
  required Map<String, DateTime?> emotionUpdatedAtByEventId,
}) {
  final ordered = orderedExplorationEventsByEra(events: events, eras: eras);
  if (ordered.isEmpty) return null;

  var latestIndex = -1;
  DateTime? latestUpdatedAt;
  for (var index = 0; index < ordered.length; index += 1) {
    final event = ordered[index];
    if (!emotionUpdatedAtByEventId.containsKey(event.id)) continue;
    final updatedAt = emotionUpdatedAtByEventId[event.id];
    final isLater =
        updatedAt != null &&
        (latestUpdatedAt == null || updatedAt.isAfter(latestUpdatedAt));
    final isDeterministicTie =
        updatedAt == latestUpdatedAt &&
        (latestIndex < 0 || index > latestIndex);
    if (latestIndex < 0 || isLater || isDeterministicTie) {
      latestIndex = index;
      latestUpdatedAt = updatedAt;
    }
  }

  if (latestIndex < 0) return ordered.first;
  return ordered[(latestIndex + 1).clamp(0, ordered.length - 1)];
}

/// 전체 시간순 카드 덱에서 현재 이야기와 실제 이전·다음 위치를 표현한다.
class ExplorationPosition {
  const ExplorationPosition({
    required this.previous,
    required this.current,
    required this.next,
    required this.currentIndex,
  });

  final StoryEvent? previous;
  final StoryEvent current;
  final StoryEvent? next;
  final int currentIndex;
}

/// 첫/마지막에서 순환하지 않는 탐험 위치를 반환한다.
ExplorationPosition? explorationPositionFor({
  required List<StoryEvent> events,
  required List<Era> eras,
  required String? currentEventId,
}) {
  final ordered = orderedExplorationEventsByEra(events: events, eras: eras);
  if (ordered.isEmpty) return null;
  final foundIndex = ordered.indexWhere((event) => event.id == currentEventId);
  final currentIndex = foundIndex < 0 ? 0 : foundIndex;
  return ExplorationPosition(
    previous: currentIndex > 0 ? ordered[currentIndex - 1] : null,
    current: ordered[currentIndex],
    next: currentIndex + 1 < ordered.length ? ordered[currentIndex + 1] : null,
    currentIndex: currentIndex,
  );
}

class ExplorationMapSelection {
  const ExplorationMapSelection({
    required this.events,
    required this.markerRoles,
    required this.fitEventIds,
    required this.position,
  });

  final List<StoryEvent> events;
  final Map<String, String> markerRoles;
  final List<String> fitEventIds;
  final ExplorationPosition? position;
}

/// 오늘 지도에 표시할 현재 시대 전체 사건과 역할/카메라 기준 사건을 계산한다.
ExplorationMapSelection explorationMapSelectionFor({
  required List<StoryEvent> events,
  required List<Era> eras,
  required String? currentEventId,
}) {
  final ordered = orderedExplorationEventsByEra(events: events, eras: eras);
  final position = explorationPositionFor(
    events: ordered,
    eras: eras,
    currentEventId: currentEventId,
  );
  final current = position?.current;
  if (current == null) {
    return const ExplorationMapSelection(
      events: [],
      markerRoles: {},
      fitEventIds: [],
      position: null,
    );
  }

  final eraEvents = ordered
      .where((event) => event.eraId == current.eraId)
      .toList(growable: false);
  final markerRoles = <String, String>{current.id: 'current'};
  final fitEventIds = <String>[current.id];
  final previous = position?.previous;
  if (previous != null && previous.eraId == current.eraId) {
    markerRoles[previous.id] = 'previous';
    fitEventIds.insert(0, previous.id);
  }
  final next = position?.next;
  if (next != null && next.eraId == current.eraId) {
    markerRoles[next.id] = 'next';
    fitEventIds.add(next.id);
  }
  return ExplorationMapSelection(
    events: eraEvents,
    markerRoles: Map.unmodifiable(markerRoles),
    fitEventIds: List.unmodifiable(fitEventIds),
    position: position,
  );
}

/// [currentEventId]를 가운데 두고 이전·현재·다음 이야기를 순환해 반환한다.
List<StoryEvent> explorationJourneyAround({
  required List<StoryEvent> events,
  required String? currentEventId,
}) {
  final ordered = orderedDailyExplorationEvents(events);
  if (ordered.length <= 1) return ordered;
  final foundIndex = ordered.indexWhere((event) => event.id == currentEventId);
  final currentIndex = foundIndex < 0 ? 0 : foundIndex;
  final previousIndex = (currentIndex - 1) % ordered.length;
  if (ordered.length == 2) {
    return [ordered[previousIndex], ordered[currentIndex]];
  }
  final nextIndex = (currentIndex + 1) % ordered.length;
  return [ordered[previousIndex], ordered[currentIndex], ordered[nextIndex]];
}
