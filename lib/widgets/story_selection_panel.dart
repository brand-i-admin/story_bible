import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/story_event.dart';
import '../state/story_controller.dart';
import '../theme/tokens.dart';
import 'character_panel.dart';

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
    required this.characters,
    required this.characterSortMode,
    required this.onCharacterSortModeChanged,
    required this.draftSelectedCharacterCodes,
    required this.onToggleDraftCharacter,
    required this.committedSelectedCharacterCodes,
    required this.hasPendingCharacterChanges,
    required this.colorForDraftCharacter,
    required this.colorForCommittedCharacter,
    required this.events,
    required this.completedEventIds,
    required this.draftDisplayedEventIds,
    required this.committedDisplayedEventIds,
    required this.onToggleDisplayedEvent,
    required this.onSelectAllDisplayedEvents,
    required this.onDeselectAllDisplayedEvents,
    required this.onCommitDisplayedEvents,
    required this.onNextFromEra,
    required this.onNextFromCharacters,
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

  final List<Character> characters;
  final CharacterSortMode characterSortMode;
  final ValueChanged<CharacterSortMode> onCharacterSortModeChanged;
  final Set<String> draftSelectedCharacterCodes;
  final ValueChanged<String> onToggleDraftCharacter;
  final Set<String> committedSelectedCharacterCodes;
  final bool hasPendingCharacterChanges;
  final Color Function(String characterId) colorForDraftCharacter;
  final Color Function(String characterId) colorForCommittedCharacter;

  /// Step 3 에서 보여줄 후보 이벤트. 선택된 인물이 등장하는 전체 사건을
  /// globalRank 순서로 전달받는다 (부모가 정렬).
  final List<StoryEvent> events;
  final Set<String> completedEventIds;

  /// Step 3 체크박스의 "현재 드래프트 선택" 집합 (아직 커밋 전).
  final Set<String> draftDisplayedEventIds;

  /// 현재 지도에 실제로 렌더 중인 커밋 집합 — 드래프트와 비교해 "변경됨" 뱃지를
  /// 보이는 데 사용.
  final Set<String> committedDisplayedEventIds;

  /// 카드 탭 → 드래프트 토글.
  final ValueChanged<String> onToggleDisplayedEvent;

  /// Step 3 툴바의 전체 선택 / 전체 해제 버튼.
  final VoidCallback onSelectAllDisplayedEvents;
  final VoidCallback onDeselectAllDisplayedEvents;

  /// Step 3 "다음" 버튼 — 드래프트를 커밋하고 지도 애니메이션 트리거.
  final VoidCallback onCommitDisplayedEvents;

  final VoidCallback onNextFromEra;
  final VoidCallback onNextFromCharacters;

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

  List<Character> get _selectedCharactersForSummary {
    final sourceIds = widget.draftSelectedCharacterCodes.isNotEmpty
        ? widget.draftSelectedCharacterCodes
        : widget.committedSelectedCharacterCodes;
    return widget.characters
        .where((character) => sourceIds.contains(character.code))
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
      if (widget.draftSelectedCharacterCodes.isEmpty) {
        return null;
      }
      return widget.onNextFromCharacters;
    }
    // Step 3: 체크된 사건이 하나도 없으면 "다음" 비활성. 드래프트가 커밋과
    // 동일해도 (재커밋 = 재애니메이션) 허용.
    if (widget.draftDisplayedEventIds.isEmpty) {
      return null;
    }
    return widget.onCommitDisplayedEvents;
  }

  Widget _buildHeaderSection({
    required bool canRunPrimaryAction,
    required VoidCallback? primaryAction,
  }) {
    // Step 3 기준: 현재 드래프트 사건들이 모두 이수 상태면 "완료" 톤으로.
    // (과거 단일 선택 모델에서 선택된 사건의 완료 여부로 표시하던 것을 대체)
    final selectedStoryCompleted =
        widget.step == 3 &&
        widget.draftDisplayedEventIds.isNotEmpty &&
        widget.draftDisplayedEventIds.every(widget.completedEventIds.contains);
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
                      label: '다음',
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
                label: '다음',
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
    final selectedCharacters = _selectedCharactersForSummary;
    final stepTwoLabels = selectedCharacters.length > 3
        ? [selectedCharacters[0].name, selectedCharacters[1].name, '...']
        : selectedCharacters
              .take(3)
              .map((character) => character.name)
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
        firstSelected: widget.characterSortMode == CharacterSortMode.eraOrder,
        onSelectFirst: () =>
            widget.onCharacterSortModeChanged(CharacterSortMode.eraOrder),
        onSelectSecond: () =>
            widget.onCharacterSortModeChanged(CharacterSortMode.alphabetical),
      ),
      _ => null,
    };
  }

  List<Widget> _buildBodySlivers() {
    return switch (widget.step) {
      1 => _buildEraBodySlivers(),
      2 => _buildCharacterBodySlivers(),
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

  List<Widget> _buildCharacterBodySlivers() {
    final sortedCharacters = [...widget.characters]
      ..sort((a, b) {
        if (widget.characterSortMode == CharacterSortMode.eraOrder) {
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

    if (sortedCharacters.isEmpty) {
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
            final character = sortedCharacters[index];
            return _CharacterCompactCard(
              character: character,
              selected: widget.draftSelectedCharacterCodes.contains(
                character.code,
              ),
              accentColor: widget.colorForDraftCharacter(character.code),
              description: _characterDescription(character),
              onTap: () => widget.onToggleDraftCharacter(character.code),
            );
          }, childCount: sortedCharacters.length),
        ),
      ),
    ];
  }

  List<Widget> _buildStoryBodySlivers() {
    if (widget.events.isEmpty) {
      return <Widget>[_buildEmptyBodySliver('선택된 인물의 사건이 없습니다.')];
    }

    final total = widget.events.length;
    final selectedCount = widget.events
        .where((e) => widget.draftDisplayedEventIds.contains(e.id))
        .length;

    // code → name 룩업을 한 번만 만들어서 카드마다 재사용.
    final characterNameByCode = <String, String>{
      for (final p in widget.characters) p.code: p.name,
    };
    String nameForCharacter(String code) => characterNameByCode[code] ?? code;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        sliver: SliverToBoxAdapter(
          child: _StoryBulkActionsBar(
            total: total,
            selectedCount: selectedCount,
            onSelectAll: selectedCount == total
                ? null
                : widget.onSelectAllDisplayedEvents,
            onDeselectAll: selectedCount == 0
                ? null
                : widget.onDeselectAllDisplayedEvents,
          ),
        ),
      ),
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
            final checked = widget.draftDisplayedEventIds.contains(event.id);
            return _StoryCompactCard(
              index: index + 1,
              title: event.title,
              subtitle: _storySubtitle(event),
              selected: checked,
              isCompleted: widget.completedEventIds.contains(event.id),
              highlightedCharacterCodes: event.characterCodes
                  .where(widget.committedSelectedCharacterCodes.contains)
                  .toList(growable: false),
              colorForCharacter: widget.colorForCommittedCharacter,
              nameForCharacter: nameForCharacter,
              onTap: () => widget.onToggleDisplayedEvent(event.id),
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

  String _characterDescription(Character character) {
    final description = (character.description ?? '').trim();
    if (description.isNotEmpty) {
      return description;
    }
    final tagline = (character.tagline ?? '').trim();
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
