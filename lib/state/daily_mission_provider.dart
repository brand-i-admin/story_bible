import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_event.dart';
import '../utils/daily_exploration_selection.dart';
import 'story_controller.dart';

final dailyExplorationCatalogProvider = FutureProvider<List<StoryEvent>>((
  ref,
) async {
  final eras = ref.watch(storyControllerProvider.select((state) => state.eras));
  if (eras.isEmpty) {
    return const [];
  }

  final repo = ref.read(storyRepositoryProvider);
  final eventLists = await Future.wait(
    eras.map((era) => repo.fetchEventsByEra(era.id)),
  );
  return orderedDailyExplorationEvents(
    eventLists.expand((items) => items).toList(growable: false),
  );
});

final dailyExplorationJourneyProvider = FutureProvider<List<StoryEvent>>((
  ref,
) async {
  final events = await ref.watch(dailyExplorationCatalogProvider.future);
  return pickDailyExplorationJourney(
    events: events,
    dayKey: dailyExplorationKeyForKst(DateTime.now()),
  );
});

final dailyMissionEventProvider = FutureProvider<StoryEvent?>((ref) async {
  final journey = await ref.watch(dailyExplorationJourneyProvider.future);
  if (journey.isEmpty) {
    return null;
  }
  return journey.length >= 3 ? journey[1] : journey.last;
});
