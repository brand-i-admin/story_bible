import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/era.dart';
import '../models/person.dart';
import '../models/story_event.dart';
import 'person_panel.dart';

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
                    width: 92,
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
              width: 108,
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
            mainAxisExtent: 58,
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
            mainAxisExtent: 92,
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
            mainAxisExtent: 84,
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

Color _stageAccentColor(StorySelectionPanelStage stage) {
  return switch (stage) {
    StorySelectionPanelStage.collapsed => const Color(0xFFD2873E),
    StorySelectionPanelStage.half => const Color(0xFF77A85A),
    StorySelectionPanelStage.expanded => const Color(0xFF77A85A),
  };
}

class _PanelTexturePainter extends CustomPainter {
  const _PanelTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x0E845D38);
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x08FFFFFF);

    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.12 + (i * 0.12));
      final path = Path()
        ..moveTo(size.width * 0.05, y)
        ..quadraticBezierTo(
          size.width * 0.52,
          y + (i.isEven ? 8 : -8),
          size.width * 0.95,
          y + (i.isEven ? -3 : 3),
        );
      canvas.drawPath(path, linePaint);
    }

    final glowOffsets = <Offset>[
      Offset(size.width * 0.18, size.height * 0.16),
      Offset(size.width * 0.82, size.height * 0.26),
      Offset(size.width * 0.24, size.height * 0.64),
      Offset(size.width * 0.74, size.height * 0.82),
    ];
    for (final offset in glowOffsets) {
      canvas.drawCircle(offset, 24, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PanelTextureLayer extends StatelessWidget {
  const _PanelTextureLayer();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.16,
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xFFB88A57),
          BlendMode.multiply,
        ),
        child: Image.asset(
          'assets/elements/parchment_texture.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _BottomFadeHint extends StatelessWidget {
  const _BottomFadeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F2E5CC), Color(0xD7E8D2B1)],
        ),
      ),
    );
  }
}

class _CollapsedSelectionPeek extends StatelessWidget {
  const _CollapsedSelectionPeek({
    required this.scrollController,
    required this.bottomInset,
    required this.stage,
    required this.onStepUp,
    required this.onStepDown,
  });

  final ScrollController scrollController;
  final double bottomInset;
  final StorySelectionPanelStage stage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final peekBottomPadding = math.max(4.0, bottomInset * 0.22);

    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, peekBottomPadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: _SelectionSheetTopBar(
                stage: stage,
                onStepUp: onStepUp,
                onStepDown: onStepDown,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionSheetTopBar extends StatelessWidget {
  const _SelectionSheetTopBar({
    required this.stage,
    required this.onStepUp,
    required this.onStepDown,
  });

  final StorySelectionPanelStage stage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final accentColor = _stageAccentColor(stage);
    final containerColor = Color.lerp(
      const Color(0xFFF8F0DB),
      accentColor,
      0.30,
    )!;
    final canStepDown = stage != StorySelectionPanelStage.collapsed;
    final canStepUp = stage == StorySelectionPanelStage.collapsed;

    return Material(
      color: Colors.transparent,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accentColor, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetStepButton(
              icon: Icons.keyboard_arrow_down_rounded,
              semanticsLabel: '선택 창 한 단계 접기',
              enabled: canStepDown,
              accentColor: accentColor,
              onTap: canStepDown ? onStepDown : null,
            ),
            const SizedBox(width: 5),
            _SelectionSheetHandle(accentColor: accentColor),
            const SizedBox(width: 5),
            _SheetStepButton(
              icon: Icons.keyboard_arrow_up_rounded,
              semanticsLabel: '선택 창 한 단계 펼치기',
              enabled: canStepUp,
              accentColor: accentColor,
              onTap: canStepUp ? onStepUp : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSheetHandle extends StatelessWidget {
  const _SelectionSheetHandle({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 24,
        height: 3,
        decoration: BoxDecoration(
          color: const Color(0xAA6E573E),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _SheetStepButton extends StatelessWidget {
  const _SheetStepButton({
    required this.icon,
    required this.semanticsLabel,
    required this.enabled,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final bool enabled;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = enabled
        ? Color.lerp(const Color(0xFFFFFFFF), accentColor, 0.20)!
        : const Color(0xFFE5DDCC);
    final foregroundColor = enabled
        ? const Color(0xFF5F4529)
        : const Color(0xFFAA977D);

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: enabled ? accentColor : const Color(0xFFCABAA3),
                width: 0.9,
              ),
            ),
            child: Center(child: Icon(icon, color: foregroundColor, size: 15)),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.summaryLabels = const [],
  });

  final String title;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final List<String> summaryLabels;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? const LinearGradient(
            colors: [Color(0xFFD08943), Color(0xFF995B2C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0x4CFFFFF9), Color(0x12FFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF5D88F)
                    : const Color(0x77A57B56),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: selected
                        ? const Color(0xFFFDF8EE)
                        : const Color(0xFF6A4A31),
                  ),
                ),
                if (summaryLabels.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Row(
                    children: summaryLabels
                        .map(
                          (label) => Flexible(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: label == summaryLabels.last ? 0 : 3,
                              ),
                              child: _StepSummaryPill(
                                label: label,
                                selected: selected,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSummaryPill extends StatelessWidget {
  const _StepSummaryPill({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? const Color(0x2FFFFFFF) : const Color(0x28A57B56),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? const Color(0x66FFF4D6) : const Color(0x669E7A56),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 6.9,
          fontWeight: FontWeight.w700,
          color: selected ? const Color(0xFFFDF8EE) : const Color(0xFF6A4A31),
          height: 0.95,
        ),
      ),
    );
  }
}

class _CompactSegmentedToggle extends StatelessWidget {
  const _CompactSegmentedToggle({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onSelectFirst,
    required this.onSelectSecond,
  });

  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final VoidCallback onSelectFirst;
  final VoidCallback onSelectSecond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x30FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66A57B56)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactSegmentedToggleButton(
            label: firstLabel,
            selected: firstSelected,
            onTap: onSelectFirst,
          ),
          const SizedBox(width: 6),
          _CompactSegmentedToggleButton(
            label: secondLabel,
            selected: !firstSelected,
            onTap: onSelectSecond,
          ),
        ],
      ),
    );
  }
}

class _CompactSegmentedToggleButton extends StatelessWidget {
  const _CompactSegmentedToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 86,
          height: 34,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFB06C34), Color(0xFF7A4824)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0x17A57B56), Color(0x06A57B56)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF3D88C)
                  : const Color(0x6D9B795B),
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected
                    ? const Color(0xFFFDF8EE)
                    : const Color(0xFF654A31),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.enabled,
    required this.pressed,
    required this.completed,
    required this.onPressed,
    required this.onPressedStateChanged,
    this.compact = false,
  });

  final String label;
  final bool enabled;
  final bool pressed;
  final bool completed;
  final VoidCallback? onPressed;
  final ValueChanged<bool> onPressedStateChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gradient = completed
        ? pressed
              ? const LinearGradient(
                  colors: [Color(0xFF2D8A56), Color(0xFF226342)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFF6CC482), Color(0xFF2F8E5D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
        : pressed
        ? const LinearGradient(
            colors: [Color(0xFFB56B1F), Color(0xFF8B4B12)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFE1AA4A), Color(0xFFB06B25)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return GestureDetector(
      onTapDown: enabled ? (_) => onPressedStateChanged(true) : null,
      onTapCancel: enabled ? () => onPressedStateChanged(false) : null,
      onTapUp: enabled ? (_) => onPressedStateChanged(false) : null,
      onTap: enabled ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.54,
        child: Container(
          height: compact ? 40 : 44,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
            border: Border.all(
              color: completed
                  ? const Color(0xFFC9F0CB)
                  : const Color(0xFFF7DA93),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: completed
                    ? const Color(0x2D256E41)
                    : const Color(0x3A6C3E15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12.5 : 13.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFFDF8EE),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyStepMessage extends StatelessWidget {
  const _EmptyStepMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6A4C33),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    this.completed = false,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final bool completed;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected && completed
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4A9D61), Color(0xFF2E6F45)],
                  )
                : selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFAE6D37), Color(0xFF87502A)],
                  )
                : completed
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE3F3DC), Color(0xFFCFE8C6)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE7D2B2), Color(0xFFDDC29E)],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected && completed
                  ? const Color(0xFFD4F0C9)
                  : selected
                  ? const Color(0xFFF4D58A)
                  : completed
                  ? const Color(0xFF7EB07A)
                  : const Color(0xFFB78A63),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: selected || completed ? 0.12 : 0.07,
                ),
                blurRadius: selected || completed ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EraCompactCard extends StatelessWidget {
  const _EraCompactCard({
    required this.index,
    required this.era,
    required this.selected,
    required this.onTap,
    this.dateLabel,
  });

  final int index;
  final Era era;
  final bool selected;
  final VoidCallback onTap;
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          _IndexBadge(label: '$index'),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: era.name,
                    style: TextStyle(
                      fontSize: 12.4,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFFFDF8EE)
                          : const Color(0xFF5C3A20),
                    ),
                  ),
                  if (dateLabel != null)
                    TextSpan(
                      text: ' ($dateLabel)',
                      style: TextStyle(
                        fontSize: 10.6,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFFF4E6CD)
                            : const Color(0xFF75563C),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCompactCard extends StatelessWidget {
  const _PersonCompactCard({
    required this.person,
    required this.selected,
    required this.accentColor,
    required this.description,
    required this.onTap,
  });

  final Person person;
  final bool selected;
  final Color accentColor;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _PortraitAvatar(person: person, selected: selected, size: 60),
              Positioned(
                left: -2,
                top: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                    border: Border.all(color: const Color(0xFFF6E8CB)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.4,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? const Color(0xFFFDF8EE)
                              : const Color(0xFF5C3A20),
                        ),
                      ),
                    ),
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFF7D881),
                          size: 16,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.2,
                    height: 1.14,
                    color: selected
                        ? const Color(0xFFF4E6CD)
                        : const Color(0xFF75563C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCompactCard extends StatelessWidget {
  const _StoryCompactCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.isCompleted,
    required this.highlightedPersonIds,
    required this.colorForPerson,
    required this.onTap,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isCompleted;
  final List<String> highlightedPersonIds;
  final Color Function(String personId) colorForPerson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      completed: isCompleted,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: isCompleted
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF92E3A3),
                    size: 18,
                  )
                : _IndexBadge(label: '$index'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    color: selected
                        ? const Color(0xFFFDF8EE)
                        : isCompleted
                        ? const Color(0xFF2F5D3B)
                        : const Color(0xFF5C3A20),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.3,
                    height: 1.14,
                    color: selected
                        ? const Color(0xFFF4E6CD)
                        : isCompleted
                        ? const Color(0xFF52725B)
                        : const Color(0xFF75563C),
                  ),
                ),
              ],
            ),
          ),
          if (highlightedPersonIds.isNotEmpty) ...[
            const SizedBox(width: 6),
            _PersonDots(
              personIds: highlightedPersonIds,
              colorForPerson: colorForPerson,
            ),
          ],
        ],
      ),
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF4DA91),
        border: Border.all(color: const Color(0xFF7A4B21)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF5A3519),
        ),
      ),
    );
  }
}

class _PersonDots extends StatelessWidget {
  const _PersonDots({required this.personIds, required this.colorForPerson});

  final List<String> personIds;
  final Color Function(String personId) colorForPerson;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: personIds
          .take(3)
          .map((personId) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorForPerson(personId),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _PortraitAvatar extends StatelessWidget {
  const _PortraitAvatar({
    required this.person,
    required this.selected,
    this.size = 42,
  });

  final Person person;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarPath = person.avatarAssetPath.trim();
    final fallbackText = person.name.trim().isEmpty
        ? '?'
        : person.name.trim().substring(0, 1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF8D4E05) : const Color(0xFFC9A06B),
          width: selected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _AvatarFallback(name: fallbackText, selected: selected)
            : ColoredBox(
                color: Colors.white,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size,
                    height: size * 2,
                    child: Image.asset(
                      avatarPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => _AvatarFallback(
                        name: fallbackText,
                        selected: selected,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: selected ? const Color(0xFF8C6337) : const Color(0xFFA98657),
      alignment: Alignment.center,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}
