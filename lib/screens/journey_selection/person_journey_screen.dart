import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/journey_selection.dart';
import '../../models/story_event.dart';
import '../../state/journey_selection_providers.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/daily_exploration_selection.dart';
import '../../utils/journey_filtering.dart';
import '../../widgets/character_avatar.dart';
import '../../widgets/journey/journey_filter_controls.dart';
import '../../widgets/sub_page_scaffold.dart';
import 'target_journey_scope_screen.dart';

enum _PersonSortMode { chronology, alphabetical }

class PersonJourneyScreen extends ConsumerStatefulWidget {
  const PersonJourneyScreen({
    super.key,
    required this.catalog,
    required this.engravedEventIds,
  });

  final JourneyCatalogData catalog;
  final Set<String> engravedEventIds;

  @override
  ConsumerState<PersonJourneyScreen> createState() =>
      _PersonJourneyScreenState();
}

class _PersonJourneyScreenState extends ConsumerState<PersonJourneyScreen> {
  String _testament = 'old';
  _PersonSortMode _sortMode = _PersonSortMode.chronology;

  @override
  void initState() {
    super.initState();
    final current = ref.read(journeySelectionProvider);
    if (current.source == JourneySource.person && current.personCode != null) {
      final character = widget.catalog.characters
          .where((item) => item.code == current.personCode)
          .firstOrNull;
      if (character != null &&
          _eventsFor(
            character,
          ).any((event) => _eraById[event.eraId]?.testament == 'new')) {
        _testament = 'new';
      }
    }
  }

  Map<String, Era> get _eraById => {
    for (final era in widget.catalog.eras) era.id: era,
  };

  List<StoryEvent> _eventsFor(Character character) {
    final eraById = _eraById;
    return widget.catalog.events
        .where(
          (event) => eventMatchesJourneyCharacter(
            event,
            personCode: character.code,
            character: character,
            eraById: eraById,
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(journeySelectionProvider);
    final orderedEvents = orderedExplorationEventsByEra(
      events: widget.catalog.events,
      eras: widget.catalog.eras,
    );
    final orderByEventId = {
      for (var index = 0; index < orderedEvents.length; index++)
        orderedEvents[index].id: index,
    };
    final counts = <String, int>{};
    final firstOrder = <String, int>{};
    final characters = widget.catalog.characters.where((character) {
      final events = _eventsFor(
        character,
      ).where((event) => _eraById[event.eraId]?.testament == _testament);
      if (events.isEmpty) return false;
      counts[character.code] = events.length;
      firstOrder[character.code] = events
          .map((event) => orderByEventId[event.id] ?? 1 << 30)
          .reduce((left, right) => left < right ? left : right);
      return true;
    }).toList();
    characters.sort((left, right) {
      if (_sortMode == _PersonSortMode.alphabetical) {
        return left.name.compareTo(right.name);
      }
      final order = (firstOrder[left.code] ?? 1 << 30).compareTo(
        firstOrder[right.code] ?? 1 << 30,
      );
      if (order != 0) return order;
      return left.name.compareTo(right.name);
    });
    return SubPageScaffold(
      title: '인물로 찾기',
      plainHeader: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x10,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: JourneySegmentButton(
                  controlKey: const ValueKey('journey-person-testament-old'),
                  label: '구약',
                  selected: _testament == 'old',
                  onTap: () => setState(() => _testament = 'old'),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: JourneySegmentButton(
                  controlKey: const ValueKey('journey-person-testament-new'),
                  label: '신약',
                  selected: _testament == 'new',
                  onTap: () => setState(() => _testament = 'new'),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: JourneySortDropdown<_PersonSortMode>(
                  controlKey: const ValueKey('journey-person-sort-dropdown'),
                  value: _sortMode,
                  options: const [
                    JourneyDropdownOption(
                      value: _PersonSortMode.chronology,
                      label: '시간순',
                    ),
                    JourneyDropdownOption(
                      value: _PersonSortMode.alphabetical,
                      label: '가나다순',
                    ),
                  ],
                  onChanged: (next) => setState(() => _sortMode = next),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: AppSpacing.x2,
              mainAxisSpacing: AppSpacing.x2,
              childAspectRatio: 0.78,
            ),
            itemCount: characters.length,
            itemBuilder: (context, index) {
              final character = characters[index];
              return _PersonButton(
                character: character,
                eventCount: counts[character.code] ?? 0,
                selected:
                    current.source == JourneySource.person &&
                    current.personCode == character.code,
                onTap: () => _openPerson(character),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openPerson(Character character) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TargetJourneyScopeScreen.person(
          character: character,
          catalog: widget.catalog,
          engravedEventIds: widget.engravedEventIds,
        ),
      ),
    );
  }
}

class _PersonButton extends StatelessWidget {
  const _PersonButton({
    required this.character,
    required this.eventCount,
    required this.selected,
    required this.onTap,
  });

  final Character character;
  final int eventCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: selected ? palette.utilitySelectedBackground : palette.cardSurface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected ? palette.selectedBorder : palette.subtleBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CharacterAvatar(character: character, size: 26),
              const SizedBox(height: AppSpacing.x1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  character.name,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: selected ? palette.activeTextOnAccent : palette.text,
                    fontSize: AppFontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$eventCount개',
                style: TextStyle(
                  color: selected
                      ? palette.activeTextOnAccent.withValues(alpha: 0.88)
                      : palette.mutedText,
                  fontSize: AppFontSizes.xs,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
