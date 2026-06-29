import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_event.dart';
import '../utils/daily_exploration_selection.dart';
import 'story_controller.dart';

final dailyMissionEventProvider = FutureProvider<StoryEvent?>((ref) async {
  final eras = ref.watch(storyControllerProvider.select((state) => state.eras));
  if (eras.isEmpty) {
    return null;
  }

  final repo = ref.read(storyRepositoryProvider);
  final eventLists = await Future.wait(
    eras.map((era) => repo.fetchEventsByEra(era.id)),
  );
  final events = eventLists.expand((items) => items).toList(growable: false);
  return pickDailyExplorationEvent(
    events: events,
    dayKey: dailyExplorationKeyForKst(DateTime.now()),
  );
});
