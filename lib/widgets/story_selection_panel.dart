import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/era.dart';
import '../models/person.dart';
import '../models/story_event.dart';
import '../theme/tokens.dart';
import 'person_panel.dart';

// 패널 외곽/단계 UI/카드를 별도 파트 파일로 분리하여 가독성과 작업 단위를 유지.
part 'selection/panel_chrome.dart';
part 'selection/selection_cards.dart';
part 'selection/step_chip.dart';

enum StorySelectionPanelStage { collapsed, half, expanded }

class StorySelectionPanel extends StatefulWidget {
  const StorySelectionPanel({
    super.key,
    required this.scrollController,
    required this.step,
    required this.panelStage,
    required this.onStepUp,
    required this.onStepDown,
    required this.canOpenStep,
    required this.onSelectStep,
    required this.eras,
    required this.selectedEraId,
    required this.selectedTestament,
    required this.onSelectEra,
    required this.onSelectTestament,
    required this.persons,
    required this.personSortMode,
    required this.onPersonSortModeChanged,
    required this.draftSelectedPersonIds,
    required this.onToggleDraftPerson,
    required this.committedSelectedPersonIds,
    required this.hasPendingPersonChanges,
    required this.colorForDraftPerson,
    required this.colorForCommittedPerson,
    required this.events,
    required this.selectedEventId,
    required this.completedEventIds,
    required this.onSelectEvent,
    required this.onNextFromEra,
    required this.onNextFromPersons,
    required this.onStartQuiz,
  });

  final ScrollController scrollController;
  final int step;
  final StorySelectionPanelStage panelStage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;
  final bool Function(int step) canOpenStep;
  final ValueChanged<int> onSelectStep;

  final List<Era> eras;
  final String? selectedEraId;
  final String selectedTestament;
  final ValueChanged<String> onSelectEra;
  final ValueChanged<String> onSelectTestament;

  final List<Person> persons;
  final PersonSortMode personSortMode;
  final ValueChanged<PersonSortMode> onPersonSortModeChanged;
  final Set<String> draftSelectedPersonIds;
  final ValueChanged<String> onToggleDraftPerson;
  final Set<String> committedSelectedPersonIds;
  final bool hasPendingPersonChanges;
  final Color Function(String personId) colorForDraftPerson;
  final Color Function(String personId) colorForCommittedPerson;

  final List<StoryEvent> events;
  final String? selectedEventId;
  final Set<String> completedEventIds;
  final ValueChanged<String> onSelectEvent;

  final VoidCallback onNextFromEra;
  final VoidCallback onNextFromPersons;
  final VoidCallback onStartQuiz;

  @override
  State<StorySelectionPanel> createState() => _StorySelectionPanelState();
}

class _StorySelectionPanelState extends State<StorySelectionPanel> {
  bool _isPrimaryPressed = false;

  Era? get _selectedEra {
    final selectedEraId = widget.selectedEraId;
    if (selectedEraId == null) {
      return null;
    }
    for (final era in widget.eras) {
      if (era.id == selectedEraId) {
        return era;
      }
    }
    return null;
  }

  List<Person> get _selectedPersonsForSummary {
    final sourceIds = widget.draftSelectedPersonIds.isNotEmpty
        ? widget.draftSelectedPersonIds
        : widget.committedSelectedPersonIds;
    return widget.persons
        .where((person) => sourceIds.contains(person.id))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final primaryAction = _primaryAction();
    final canRunPrimaryAction = primaryAction != null;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final collapsedStubThreshold = math.max(72.0, bottomInset + 54.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCollapsedStub = constraints.maxHeight <= collapsedStubThreshold;
        final accentColor = _stageAccentColor(widget.panelStage);
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: DecoratedBox(
            decoration: _panelDecoration(accentColor),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(child: _PanelTextureLayer()),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _PanelTexturePainter()),
                  ),
                ),
                if (isCollapsedStub)
                  _CollapsedSelectionPeek(
                    scrollController: widget.scrollController,
                    bottomInset: bottomInset,
                    stage: widget.panelStage,
                    onStepUp: widget.onStepUp,
                    onStepDown: widget.onStepDown,
                  )
                else
                  Stack(
                    children: [
                      CustomScrollView(
                        controller: widget.scrollController,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                          SliverToBoxAdapter(
                            child: Center(
                              child: _SelectionSheetTopBar(
                                stage: widget.panelStage,
                                onStepUp: widget.onStepUp,
                                onStepDown: widget.onStepDown,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            sliver: SliverToBoxAdapter(
                              child: _buildHeaderSection(
                                canRunPrimaryAction: canRunPrimaryAction,
                                primaryAction: primaryAction,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                          ..._buildBodySlivers(),
                          SliverToBoxAdapter(
                            child: SizedBox(height: bottomInset + 18),
                          ),
                        ],
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(child: _BottomFadeHint()),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handlePressedState(bool pressed) {
    if (_isPrimaryPressed == pressed) {
      return;
    }
    setState(() {
      _isPrimaryPressed = pressed;
    });
  }

  BoxDecoration _panelDecoration(Color accentColor) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFBF5E9), Color(0xFFF6EAD5), Color(0xFFEEDCBE)],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      border: Border.fromBorderSide(
        BorderSide(
          color: Color.lerp(const Color(0xFF8C6743), accentColor, 0.38)!,
          width: 1.15,
        ),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x38000000),
          blurRadius: 16,
          offset: Offset(0, -2),
        ),
      ],
    );
  }

  VoidCallback? _primaryAction() {
    if (widget.step == 1) {
      if (widget.selectedEraId == null) {
        return null;
      }
      return widget.onNextFromEra;
    }
    if (widget.step == 2) {
      if (widget.draftSelectedPersonIds.isEmpty) {
        return null;
      }
      return widget.onNextFromPersons;
    }
    if (widget.selectedEventId == null) {
      return null;
    }
    return widget.onStartQuiz;
  }

  Widget _buildHeaderSection({
    required bool canRunPrimaryAction,
    required VoidCallback? primaryAction,
  }) {
    final selectedStoryCompleted =
        widget.step == 3 &&
        widget.selectedEventId != null &&
        widget.completedEventIds.contains(widget.selectedEventId!);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isNarrow = width < 620;
        final headerControl = _buildHeaderControl();

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildStepRow()),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 98,
                    child: _PrimaryActionButton(
                      label: widget.step == 3 ? '퀴즈 시작' : '다음',
                      enabled: canRunPrimaryAction,
                      pressed: _isPrimaryPressed,
                      completed: selectedStoryCompleted,
                      onPressed: primaryAction,
                      onPressedStateChanged: _handlePressedState,
                      compact: true,
                    ),
                  ),
                ],
              ),
              if (headerControl != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: headerControl),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 7, child: _buildStepRow()),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: headerControl == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: headerControl,
                    ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 116,
              child: _PrimaryActionButton(
                label: widget.step == 3 ? '퀴즈 시작' : '다음',
                enabled: canRunPrimaryAction,
                pressed: _isPrimaryPressed,
                completed: selectedStoryCompleted,
                onPressed: primaryAction,
                onPressedStateChanged: _handlePressedState,
                compact: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepRow() {
    final selectedPersons = _selectedPersonsForSummary;
    final stepTwoLabels = selectedPersons.length > 3
        ? [selectedPersons[0].name, selectedPersons[1].name, '...']
        : selectedPersons
              .take(3)
              .map((person) => person.name)
              .toList(growable: false);

    return Row(
      children: [
        Expanded(
          child: _StepChip(
            title: '1. 시대 선택',
            selected: widget.step == 1,
            enabled: widget.canOpenStep(1),
            summaryLabels: _selectedEra == null
                ? const []
                : [_selectedEra!.name],
            onTap: () => widget.onSelectStep(1),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StepChip(
            title: '2. 인물 선택',
            selected: widget.step == 2,
            enabled: widget.canOpenStep(2),
            summaryLabels: stepTwoLabels,
            onTap: () => widget.onSelectStep(2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StepChip(
            title: '3. 사건 선택',
            selected: widget.step == 3,
            enabled: widget.canOpenStep(3),
            onTap: () => widget.onSelectStep(3),
          ),
        ),
      ],
    );
  }

  Widget? _buildHeaderControl() {
    return switch (widget.step) {
      1 => _CompactSegmentedToggle(
        firstLabel: '구약',
        secondLabel: '신약',
        firstSelected: widget.selectedTestament != 'new',
        onSelectFirst: () => widget.onSelectTestament('old'),
        onSelectSecond: () => widget.onSelectTestament('new'),
      ),
      2 => _CompactSegmentedToggle(
        firstLabel: '시대순',
        secondLabel: '가나다',
        firstSelected: widget.personSortMode == PersonSortMode.eraOrder,
        onSelectFirst: () =>
            widget.onPersonSortModeChanged(PersonSortMode.eraOrder),
        onSelectSecond: () =>
            widget.onPersonSortModeChanged(PersonSortMode.alphabetical),
      ),
      _ => null,
    };
  }

  List<Widget> _buildBodySlivers() {
    return switch (widget.step) {
      1 => _buildEraBodySlivers(),
      2 => _buildPersonBodySlivers(),
      _ => _buildStoryBodySlivers(),
    };
  }

  List<Widget> _buildEraBodySlivers() {
    if (widget.eras.isEmpty) {
      return <Widget>[_buildEmptyBodySliver('선택 가능한 시대가 없습니다.')];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 66,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final era = widget.eras[index];
            return _EraCompactCard(
              index: index + 1,
              era: era,
              selected: era.id == widget.selectedEraId,
              onTap: () => widget.onSelectEra(era.id),
              dateLabel: _eraDateLabel(era),
            );
          }, childCount: widget.eras.length),
        ),
      ),
    ];
  }

  List<Widget> _buildPersonBodySlivers() {
    final sortedPersons = [...widget.persons]
      ..sort((a, b) {
        if (widget.personSortMode == PersonSortMode.eraOrder) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          if (byOrder != 0) {
            return byOrder;
          }
          final byName = a.name.compareTo(b.name);
          if (byName != 0) {
            return byName;
          }
          return a.code.compareTo(b.code);
        }
        final byName = a.name.compareTo(b.name);
        if (byName != 0) {
          return byName;
        }
        return a.code.compareTo(b.code);
      });

    if (sortedPersons.isEmpty) {
      return <Widget>[_buildEmptyBodySliver('선택 가능한 인물이 없습니다.')];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 102,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final person = sortedPersons[index];
            return _PersonCompactCard(
              person: person,
              selected: widget.draftSelectedPersonIds.contains(person.id),
              accentColor: widget.colorForDraftPerson(person.id),
              description: _personDescription(person),
              onTap: () => widget.onToggleDraftPerson(person.id),
            );
          }, childCount: sortedPersons.length),
        ),
      ),
    ];
  }

  List<Widget> _buildStoryBodySlivers() {
    if (widget.events.isEmpty) {
      return <Widget>[_buildEmptyBodySliver('선택된 인물의 사건이 없습니다.')];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 94,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final event = widget.events[index];
            return _StoryCompactCard(
              index: index + 1,
              title: event.title,
              subtitle: _storySubtitle(event),
              selected: event.id == widget.selectedEventId,
              isCompleted: widget.completedEventIds.contains(event.id),
              highlightedPersonIds: event.personIds
                  .where(widget.committedSelectedPersonIds.contains)
                  .toList(growable: false),
              colorForPerson: widget.colorForCommittedPerson,
              onTap: () => widget.onSelectEvent(event.id),
            );
          }, childCount: widget.events.length),
        ),
      ),
    ];
  }

  Widget _buildEmptyBodySliver(String text) {
    return SliverToBoxAdapter(
      child: SizedBox(height: 180, child: _EmptyStepMessage(text: text)),
    );
  }

  String _personDescription(Person person) {
    final description = (person.description ?? '').trim();
    if (description.isNotEmpty) {
      return description;
    }
    final tagline = (person.tagline ?? '').trim();
    if (tagline.isNotEmpty) {
      return tagline;
    }
    return '이 인물과 관련된 성경 이야기를 이어서 살펴볼 수 있습니다.';
  }

  String _storySubtitle(StoryEvent event) {
    final placeName = (event.placeName ?? '').trim();
    if (placeName.isNotEmpty) {
      return placeName;
    }
    final shortSummary = event.shortSummary.trim();
    if (shortSummary.isNotEmpty) {
      return shortSummary;
    }
    return '사건을 선택해 자세한 내용을 확인하세요.';
  }

  String? _eraDateLabel(Era era) {
    if (era.startYear == null && era.endYear == null) {
      return null;
    }
    if (era.startYear == era.endYear && era.startYear != null) {
      return _formatYear(era.startYear!);
    }
    final start = era.startYear == null ? '?' : _formatYear(era.startYear!);
    final end = era.endYear == null ? '?' : _formatYear(era.endYear!);
    return '$start ~ $end';
  }

  String _formatYear(int year) {
    if (year < 0) {
      return 'B.C. ${year.abs()}';
    }
    if (year == 0) {
      return 'A.D. 0';
    }
    return 'A.D. $year';
  }
}
