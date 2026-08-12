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
import '../../utils/story_visibility.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, Era> get _eraById => {
    for (final era in widget.catalog.eras) era.id: era,
  };

  List<StoryEvent> _eventsFor(Character character) {
    final eraById = _eraById;
    return visibleStoryEvents(
          events: widget.catalog.events,
          eras: widget.catalog.eras,
        )
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
    final completedCounts = <String, int>{};
    final firstOrder = <String, int>{};
    final query = _searchQuery.trim();
    final characters = widget.catalog.characters.where((character) {
      final allEvents = _eventsFor(character);
      final events = query.isEmpty
          ? allEvents
                .where(
                  (event) => _eraById[event.eraId]?.testament == _testament,
                )
                .toList(growable: false)
          : allEvents;
      if (events.isEmpty) return false;
      if (query.isNotEmpty && !character.name.contains(query)) return false;
      counts[character.code] = events.length;
      completedCounts[character.code] = events
          .where((event) => widget.engravedEventIds.contains(event.id))
          .length;
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
      title: '인물에서 시작하기',
      plainHeader: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x10,
        ),
        children: [
          JourneySearchField(
            controlKey: const ValueKey('journey-person-search'),
            controller: _searchController,
            hintText: '인물 이름을 검색해 보세요',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: AppSpacing.x4),
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
          Container(
            key: const ValueKey('journey-person-grid-surface'),
            padding: const EdgeInsets.all(AppSpacing.x2),
            decoration: BoxDecoration(
              color: AppPaletteTheme.of(context).cardSurface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(
                color: AppPaletteTheme.of(context).subtleBorder,
              ),
              boxShadow: AppShadows.sm,
            ),
            child: characters.isEmpty
                ? const JourneySearchEmptyState()
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: AppSpacing.x1,
                          mainAxisSpacing: AppSpacing.x3,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: characters.length,
                    itemBuilder: (context, index) {
                      final character = characters[index];
                      return _PersonButton(
                        character: character,
                        totalCount: counts[character.code] ?? 0,
                        completedCount: completedCounts[character.code] ?? 0,
                        selected:
                            current.source == JourneySource.person &&
                            current.personCode == character.code,
                        onTap: () => _openPerson(character),
                      );
                    },
                  ),
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
    required this.totalCount,
    required this.completedCount,
    required this.selected,
    required this.onTap,
  });

  final Character character;
  final int totalCount;
  final int completedCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    return Material(
      key: ValueKey('journey-person-${character.code}'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ringSize = constraints.maxWidth.clamp(48.0, 62.0).toDouble();
            final avatarSize = (ringSize - 5).clamp(43.0, 57.0).toDouble();
            return Center(
              child: Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: palette.selectedBorder, width: 2)
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: palette.currentAccent.withValues(
                              alpha: 0.28,
                            ),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: ringSize,
                      height: ringSize,
                      child: CircularProgressIndicator(
                        key: ValueKey(
                          'journey-person-progress-${character.code}',
                        ),
                        value: progress,
                        strokeWidth: 3.2,
                        backgroundColor: palette.subtleBorder,
                        color: palette.successBottom,
                      ),
                    ),
                    CharacterAvatar(character: character, size: avatarSize),
                    Positioned(
                      top: -2,
                      left: 4,
                      right: 4,
                      child: Center(
                        child: Container(
                          key: ValueKey(
                            'journey-person-count-${character.code}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.x2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.cardSurface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: palette.successBottom.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ),
                          child: Text(
                            '$completedCount/$totalCount',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: palette.successBottom,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 3,
                      right: 3,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? palette.primaryDeep.withValues(alpha: 0.94)
                              : Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            character.name,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: AppColors.fgOnDark,
                              fontSize: AppFontSizes.xs,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
