import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/journey_selection.dart';
import '../../state/journey_selection_providers.dart';
import '../../state/story_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/journey_filtering.dart';
import '../../utils/story_visibility.dart';
import '../../widgets/journey/journey_filter_controls.dart';
import '../../widgets/journey/journey_unit_selection_list.dart';
import '../../widgets/story_home_styles.dart';
import '../../widgets/sub_page_scaffold.dart';

class PartialJourneyScreen extends ConsumerStatefulWidget {
  const PartialJourneyScreen({
    super.key,
    required this.catalog,
    this.revealSelection = false,
  });

  final JourneyCatalogData catalog;
  final bool revealSelection;

  @override
  ConsumerState<PartialJourneyScreen> createState() =>
      _PartialJourneyScreenState();
}

class _PartialJourneyScreenState extends ConsumerState<PartialJourneyScreen> {
  late Set<String> _selectedUnitKeys;
  late String _testament;

  @override
  void initState() {
    super.initState();
    final current = ref.read(journeySelectionProvider);
    _selectedUnitKeys = current.source == JourneySource.segments
        ? {...current.unitKeys}
        : <String>{};
    final eraById = {for (final era in widget.catalog.eras) era.id: era};
    final selectedTestaments = widget.catalog.events
        .where(
          (event) => _selectedUnitKeys.contains(journeyUnitKeyForEvent(event)),
        )
        .map((event) => eraById[event.eraId]?.testament)
        .whereType<String>()
        .toSet();
    _testament =
        selectedTestaments.length == 1 && selectedTestaments.single == 'new'
        ? 'new'
        : 'old';
  }

  @override
  Widget build(BuildContext context) {
    final allGroups = buildJourneyEraGroups(
      events: widget.catalog.events,
      eras: widget.catalog.eras,
    );
    final groups = allGroups
        .where((group) => group.era.testament == _testament)
        .toList(growable: false);
    final selectedEvents =
        visibleStoryEvents(
              events: widget.catalog.events,
              eras: widget.catalog.eras,
            )
            .where(
              (event) =>
                  _selectedUnitKeys.contains(journeyUnitKeyForEvent(event)),
            )
            .toList(growable: false);
    return SubPageScaffold(
      title: '시대·구간에서 고르기',
      plainHeader: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x6,
                AppSpacing.x3,
                AppSpacing.x6,
                96,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: JourneySegmentButton(
                        controlKey: const ValueKey(
                          'journey-partial-testament-old',
                        ),
                        label: '구약',
                        selected: _testament == 'old',
                        onTap: () => setState(() => _testament = 'old'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: JourneySegmentButton(
                        controlKey: const ValueKey(
                          'journey-partial-testament-new',
                        ),
                        label: '신약',
                        selected: _testament == 'new',
                        onTap: () => setState(() => _testament = 'new'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                JourneyUnitSelectionList(
                  groups: groups,
                  selectedUnitKeys: _selectedUnitKeys,
                  completedEventIds: ref.watch(
                    storyControllerProvider.select(
                      (state) => state.eventEmotionMarks.keys.toSet(),
                    ),
                  ),
                  revealInitialSelection: widget.revealSelection,
                  showEraLabel: true,
                  unifiedEraSurface: true,
                  onSelectionChanged: (keys) {
                    setState(() => _selectedUnitKeys = keys);
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.x6,
            right: AppSpacing.x6,
            bottom: AppSpacing.x5,
            child: Container(
              key: const ValueKey('partial-journey-apply'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: AppShadows.lg,
              ),
              child: Opacity(
                opacity: _selectedUnitKeys.isEmpty ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: _selectedUnitKeys.isEmpty,
                  child: filledActionButton(
                    label: '선택한 ${selectedEvents.length}개 이야기로 시작',
                    minHeight: 42,
                    fontSize: AppFontSizes.base,
                    fontWeight: FontWeight.w700,
                    onTap: _applySelection,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applySelection() async {
    await ref
        .read(journeySelectionProvider.notifier)
        .setSelection(
          JourneySelection(
            source: JourneySource.segments,
            scope: JourneyScope.units,
            unitKeys: _selectedUnitKeys,
          ),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
