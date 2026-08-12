import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/journey_selection_repository.dart';
import '../models/character.dart';
import '../models/era.dart';
import '../models/journey_selection.dart';
import '../models/story_event.dart';
import 'daily_mission_provider.dart';
import 'font_scale_providers.dart';
import 'story_controller.dart';

class JourneyCatalogData {
  const JourneyCatalogData({
    required this.eras,
    required this.events,
    required this.characters,
  });

  final List<Era> eras;
  final List<StoryEvent> events;
  final List<Character> characters;
}

final journeySelectionRepositoryProvider = Provider<JourneySelectionRepository>(
  (ref) => JourneySelectionRepository(ref.watch(sharedPreferencesProvider)),
);

final journeySelectionProvider =
    NotifierProvider<JourneySelectionNotifier, JourneySelection>(
      JourneySelectionNotifier.new,
    );

class JourneySelectionNotifier extends Notifier<JourneySelection> {
  @override
  JourneySelection build() {
    return ref.read(journeySelectionRepositoryProvider).read();
  }

  Future<void> setSelection(JourneySelection selection) async {
    state = selection;
    await ref.read(journeySelectionRepositoryProvider).write(selection);
  }
}

final journeyCatalogProvider = FutureProvider<JourneyCatalogData>((ref) async {
  final eras = ref.watch(storyControllerProvider.select((state) => state.eras));
  if (eras.isEmpty) {
    return const JourneyCatalogData(eras: [], events: [], characters: []);
  }
  final eventsFuture = ref.watch(dailyExplorationCatalogProvider.future);
  final charactersFuture = ref
      .read(storyRepositoryProvider)
      .fetchAllActiveCharacters();
  final events = await eventsFuture;
  final characters = await charactersFuture;
  return JourneyCatalogData(
    eras: List.unmodifiable(eras),
    events: List.unmodifiable(events),
    characters: List.unmodifiable(characters),
  );
});
