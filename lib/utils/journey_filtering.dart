import '../models/character.dart';
import '../models/era.dart';
import '../models/journey_selection.dart';
import '../models/story_event.dart';
import 'bible_book_meta.dart';
import 'daily_exploration_selection.dart';

String journeyUnitKey({required String eraId, required String unitCode}) {
  return '$eraId::$unitCode';
}

String journeyUnitKeyForEvent(StoryEvent event) {
  return journeyUnitKey(eraId: event.eraId, unitCode: event.unitCode);
}

class JourneyProgress {
  const JourneyProgress({required this.completed, required this.total});

  final int completed;
  final int total;
}

class JourneyUnitGroup {
  const JourneyUnitGroup({
    required this.key,
    required this.code,
    required this.title,
    required this.order,
    required this.events,
    required this.targetEventCount,
  });

  final String key;
  final String code;
  final String title;
  final int order;
  final List<StoryEvent> events;
  final int targetEventCount;

  bool get containsTarget => targetEventCount > 0;
}

class JourneyEraGroup {
  const JourneyEraGroup({
    required this.era,
    required this.friendlyTitle,
    required this.bibleBookNames,
    required this.events,
    required this.units,
  });

  final Era era;
  final String friendlyTitle;
  final List<String> bibleBookNames;
  final List<StoryEvent> events;
  final List<JourneyUnitGroup> units;
}

List<StoryEvent> filterJourneyEvents({
  required List<StoryEvent> events,
  required List<Era> eras,
  required JourneySelection selection,
  Map<String, Character> charactersByCode = const <String, Character>{},
}) {
  final eraById = {for (final era in eras) era.id: era};
  final filtered = switch (selection.source) {
    JourneySource.all => events,
    JourneySource.segments => events.where(
      (event) => selection.unitKeys.contains(journeyUnitKeyForEvent(event)),
    ),
    JourneySource.book =>
      selection.scope == JourneyScope.targetOnly
          ? events.where(
              (event) =>
                  selection.bookName != null &&
                  eventHasBibleBook(event, selection.bookName!),
            )
          : events.where(
              (event) =>
                  selection.unitKeys.contains(journeyUnitKeyForEvent(event)),
            ),
    JourneySource.person =>
      selection.scope == JourneyScope.targetOnly
          ? events.where(
              (event) =>
                  selection.personCode != null &&
                  eventMatchesJourneyCharacter(
                    event,
                    personCode: selection.personCode!,
                    character: charactersByCode[selection.personCode],
                    eraById: eraById,
                  ),
            )
          : events.where(
              (event) =>
                  selection.unitKeys.contains(journeyUnitKeyForEvent(event)),
            ),
  };
  return orderedExplorationEventsByEra(
    events: filtered.toList(growable: false),
    eras: eras,
  );
}

bool eventMatchesJourneyCharacter(
  StoryEvent event, {
  required String personCode,
  required Character? character,
  required Map<String, Era> eraById,
}) {
  if (!event.characterCodes.contains(personCode)) return false;
  final allowedEraCodes = character?.eraCodes ?? const <String>[];
  if (allowedEraCodes.isEmpty) return true;
  final eraCode = eraById[event.eraId]?.code;
  return eraCode != null && allowedEraCodes.contains(eraCode);
}

JourneyProgress journeyProgress(
  Iterable<StoryEvent> events, {
  required Set<String> engravedEventIds,
}) {
  var completed = 0;
  var total = 0;
  for (final event in events) {
    total += 1;
    if (engravedEventIds.contains(event.id)) {
      completed += 1;
    }
  }
  return JourneyProgress(completed: completed, total: total);
}

bool eventHasBibleBook(StoryEvent event, String bookName) {
  final normalizedTarget = normalizeBibleBookKey(bookName);
  if (normalizedTarget.isEmpty) return false;
  return event.bibleRefs.any((reference) {
    final canonical = canonicalBibleBookNames([reference.book]);
    return canonical.any(
      (name) => normalizeBibleBookKey(name) == normalizedTarget,
    );
  });
}

List<JourneyEraGroup> buildJourneyEraGroups({
  required List<StoryEvent> events,
  required List<Era> eras,
  bool Function(StoryEvent event)? targetMatches,
  bool onlyTargetEras = false,
}) {
  final ordered = orderedExplorationEventsByEra(events: events, eras: eras);
  final targetEraIds = targetMatches == null
      ? const <String>{}
      : {
          for (final event in ordered)
            if (targetMatches(event)) event.eraId,
        };
  final eraById = {for (final era in eras) era.id: era};
  final orderedEraIds = <String>[];
  for (final event in ordered) {
    if (!orderedEraIds.contains(event.eraId)) {
      orderedEraIds.add(event.eraId);
    }
  }

  final groups = <JourneyEraGroup>[];
  for (final eraId in orderedEraIds) {
    if (onlyTargetEras && !targetEraIds.contains(eraId)) continue;
    final era = eraById[eraId];
    if (era == null) continue;
    final eraEvents = ordered
        .where((event) => event.eraId == eraId)
        .toList(growable: false);
    final eventsByUnit = <String, List<StoryEvent>>{};
    for (final event in eraEvents) {
      eventsByUnit.putIfAbsent(event.unitCode, () => []).add(event);
    }
    final units =
        eventsByUnit.entries.map((entry) {
          final unitEvents = entry.value;
          final first = unitEvents.first;
          return JourneyUnitGroup(
            key: journeyUnitKey(eraId: eraId, unitCode: entry.key),
            code: entry.key,
            title: first.unitTitle,
            order: first.unitOrder,
            events: List.unmodifiable(unitEvents),
            targetEventCount: targetMatches == null
                ? 0
                : unitEvents.where(targetMatches).length,
          );
        }).toList()..sort((left, right) {
          final order = left.order.compareTo(right.order);
          if (order != 0) return order;
          return left.title.compareTo(right.title);
        });
    groups.add(
      JourneyEraGroup(
        era: era,
        friendlyTitle: friendlyJourneyEraTitle(era),
        bibleBookNames: List.unmodifiable(
          canonicalBibleBookNames(
            eraEvents.expand(
              (event) => event.bibleRefs.map((reference) => reference.book),
            ),
          ),
        ),
        events: List.unmodifiable(eraEvents),
        units: List.unmodifiable(units),
      ),
    );
  }
  return List.unmodifiable(groups);
}

String friendlyJourneyEraTitle(Era era) => switch (era.code) {
  'era_primeval' => '세상의 시작과 첫 사람들',
  'era_patriarch' => '아브라함과 가족 이야기',
  'era_exodus' => '모세와 이집트 탈출',
  'era_judges' => '약속의 땅과 사사들',
  'era_monarchy' => '다윗과 왕들의 시대',
  'era_divided_kingdom' => '두 왕국과 예언자들',
  'era_exile_return' => '나라를 잃고 다시 돌아온 때',
  'era_nt_public_ministry' => '예수님의 삶과 가르침',
  'era_nt_apostolic' => '초대교회와 바울의 여정',
  'era_nt_post_apostolic' => '교회에 보낸 편지들',
  'era_nt_consummation' => '마지막 소망과 새 창조',
  _ => era.name,
};
