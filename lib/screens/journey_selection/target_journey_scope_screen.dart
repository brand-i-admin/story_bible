import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/journey_selection.dart';
import '../../models/story_event.dart';
import '../../state/journey_selection_providers.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/journey_filtering.dart';
import '../../utils/story_visibility.dart';
import '../../widgets/journey/journey_unit_selection_list.dart';
import '../../widgets/story_home_styles.dart';
import '../../widgets/sub_page_scaffold.dart';
import 'journey_selection_route.dart';

enum JourneyTargetKind { book, person }

class TargetJourneyScopeScreen extends ConsumerStatefulWidget {
  const TargetJourneyScopeScreen.book({
    super.key,
    required this.bookName,
    required this.catalog,
    required this.engravedEventIds,
    this.initialSelection,
    this.revealSelection = false,
  }) : kind = JourneyTargetKind.book,
       character = null;

  const TargetJourneyScopeScreen.person({
    super.key,
    required this.character,
    required this.catalog,
    required this.engravedEventIds,
    this.initialSelection,
    this.revealSelection = false,
  }) : kind = JourneyTargetKind.person,
       bookName = null;

  final JourneyTargetKind kind;
  final String? bookName;
  final Character? character;
  final JourneyCatalogData catalog;
  final Set<String> engravedEventIds;
  final JourneySelection? initialSelection;
  final bool revealSelection;

  String get targetName =>
      kind == JourneyTargetKind.book ? bookName! : character!.name;

  @override
  ConsumerState<TargetJourneyScopeScreen> createState() =>
      _TargetJourneyScopeScreenState();
}

class _TargetJourneyScopeScreenState
    extends ConsumerState<TargetJourneyScopeScreen> {
  JourneyScope _selectedScope = JourneyScope.targetOnly;
  Set<String> _selectedUnitKeys = <String>{};
  bool _unitsExpanded = false;

  @override
  void initState() {
    super.initState();
    final JourneySelection initial =
        widget.initialSelection ?? ref.read(journeySelectionProvider);
    final matchesTarget = switch (widget.kind) {
      JourneyTargetKind.book =>
        initial.source == JourneySource.book &&
            initial.bookName == widget.bookName,
      JourneyTargetKind.person =>
        initial.source == JourneySource.person &&
            initial.personCode == widget.character?.code,
    };
    if (!matchesTarget) return;
    _selectedScope = initial.scope;
    _selectedUnitKeys = {...initial.unitKeys};
    _unitsExpanded =
        widget.revealSelection && initial.scope == JourneyScope.units;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final eraById = {for (final era in widget.catalog.eras) era.id: era};
    bool targetMatches(StoryEvent event) {
      if (widget.kind == JourneyTargetKind.book) {
        return eventHasBibleBook(event, widget.bookName!);
      }
      final character = widget.character!;
      return eventMatchesJourneyCharacter(
        event,
        personCode: character.code,
        character: character,
        eraById: eraById,
      );
    }

    final groups = buildJourneyEraGroups(
      events: widget.catalog.events,
      eras: widget.catalog.eras,
      targetMatches: targetMatches,
      onlyTargetEras: true,
    );
    final targetEvents = visibleStoryEvents(
      events: widget.catalog.events,
      eras: widget.catalog.eras,
    ).where(targetMatches).toList(growable: false);
    final targetProgress = journeyProgress(
      targetEvents,
      engravedEventIds: widget.engravedEventIds,
    );
    final eraNames = groups.map((group) => group.era.name).join(' · ');
    final targetName = widget.targetName;
    final subjectParticle = _subjectParticle(targetName);
    final targetKindLabel = widget.kind == JourneyTargetKind.book ? '권' : '인물';
    return SubPageScaffold(
      title: '읽을 범위 선택',
      plainHeader: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x10,
        ),
        children: [
          Container(
            key: const ValueKey('journey-target-info'),
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: palette.mutedSurface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.kind == JourneyTargetKind.book
                      ? Icons.menu_book_outlined
                      : Icons.person_outline_rounded,
                  color: palette.characterAccent,
                  size: 21,
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.kind == JourneyTargetKind.book
                            ? '선택한 성경책'
                            : '선택한 인물',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: AppFontSizes.xs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        '$targetName$subjectParticle 선택되었어요',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: AppFontSizes.input,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Text(
                        '포함된 시대 · ${eraNames.isEmpty ? '연결된 시대 없음' : eraNames}',
                        style: TextStyle(
                          color: palette.characterAccent,
                          fontSize: AppFontSizes.base,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          Text(
            '읽을 범위를 하나 선택해 주세요',
            style: TextStyle(
              color: palette.text,
              fontSize: AppFontSizes.chip,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          _TargetOnlyCard(
            key: const ValueKey('journey-scope-target-only'),
            targetName: targetName,
            targetKindLabel: targetKindLabel,
            progress: targetProgress,
            selected: _selectedScope == JourneyScope.targetOnly,
            onTap: () {
              setState(() {
                _selectedScope = JourneyScope.targetOnly;
                _selectedUnitKeys = <String>{};
                _unitsExpanded = false;
              });
            },
          ),
          const SizedBox(height: AppSpacing.x4),
          Container(
            key: const ValueKey('journey-scope-units'),
            decoration: BoxDecoration(
              color: _selectedScope == JourneyScope.units
                  ? Color.alphaBlend(
                      palette.selectedSurface,
                      palette.softSurface,
                    )
                  : palette.softSurface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(
                color: _selectedScope == JourneyScope.units
                    ? palette.selectedBorder
                    : palette.subtleBorder,
                width: _selectedScope == JourneyScope.units ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: groups.isEmpty ? null : _toggleUnitsPanel,
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _selectedScope == JourneyScope.units
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: _selectedScope == JourneyScope.units
                              ? palette.primaryDeep
                              : palette.mutedText,
                          size: 24,
                        ),
                        const SizedBox(width: AppSpacing.x4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$targetName$subjectParticle 속한 시대 선택',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: AppFontSizes.base,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x1),
                              Text(
                                '시대와 소분류를 골라 넓게 읽어요.',
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: AppFontSizes.sm,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _unitsExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: palette.mutedText,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_unitsExpanded) ...[
                  Divider(height: 1, color: palette.subtleBorder),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.x3),
                    child: JourneyUnitSelectionList(
                      groups: groups,
                      selectedUnitKeys: _selectedUnitKeys,
                      completedEventIds: widget.engravedEventIds,
                      targetBadgeLabel: widget.kind == JourneyTargetKind.book
                          ? '이 권 포함'
                          : '이 인물 포함',
                      expandPartiallySelectedEras: false,
                      expandAllEras: true,
                      revealInitialSelection: widget.revealSelection,
                      onSelectionChanged: (keys) {
                        setState(() {
                          _selectedScope = JourneyScope.units;
                          _selectedUnitKeys = keys;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          Opacity(
            key: const ValueKey('journey-scope-apply'),
            opacity: _canApply ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !_canApply,
              child: filledActionButton(
                label: '이 범위로 선택',
                minHeight: 42,
                fontSize: AppFontSizes.base,
                fontWeight: FontWeight.w700,
                onTap: _apply,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleUnitsPanel() {
    setState(() {
      _selectedScope = JourneyScope.units;
      _unitsExpanded = !_unitsExpanded;
    });
  }

  bool get _canApply {
    if (_selectedScope == JourneyScope.targetOnly) return true;
    return _selectedScope == JourneyScope.units && _selectedUnitKeys.isNotEmpty;
  }

  Future<void> _apply() async {
    final selection = widget.kind == JourneyTargetKind.book
        ? JourneySelection(
            source: JourneySource.book,
            scope: _selectedScope,
            bookName: widget.bookName,
            unitKeys: _selectedUnitKeys,
          )
        : JourneySelection(
            source: JourneySource.person,
            scope: _selectedScope,
            personCode: widget.character!.code,
            personName: widget.character!.name,
            unitKeys: _selectedUnitKeys,
          );
    await ref.read(journeySelectionProvider.notifier).setSelection(selection);
    if (!mounted) return;
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name == journeySelectionRouteName);
  }
}

String _subjectParticle(String text) {
  final runes = text.trim().runes;
  if (runes.isEmpty) return '이/가';
  final last = runes.last;
  if (last < 0xAC00 || last > 0xD7A3) return '이/가';
  return (last - 0xAC00) % 28 == 0 ? '가' : '이';
}

class _TargetOnlyCard extends StatelessWidget {
  const _TargetOnlyCard({
    super.key,
    required this.targetName,
    required this.targetKindLabel,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final String targetName;
  final String targetKindLabel;
  final JourneyProgress progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: selected
          ? Color.alphaBlend(palette.selectedSurface, palette.cardSurface)
          : palette.cardSurface,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(
              color: selected ? palette.selectedBorder : palette.subtleBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? palette.primaryDeep : palette.mutedText,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$targetName 이야기만',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: AppFontSizes.base,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      '다른 $targetKindLabel의 이야기는 제외합니다.',
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: AppFontSizes.sm,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${progress.completed}/${progress.total}',
                style: TextStyle(
                  color: palette.primaryDeep,
                  fontSize: AppFontSizes.base,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
