import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/quiz_attempt_summary.dart';
import '../models/story_event.dart';
import '../state/story_controller.dart';
import '../theme/tokens.dart';
import 'character_panel.dart';
import 'event_timeline_row.dart';

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
    this.eventEmotionMarks = const {},
    this.quizAttemptSummaries = const {},
    this.celebrationEventId,
    this.celebrationStampLabel,
    this.celebrationNonce = 0,
    this.onCelebrationComplete,
    this.quizReviewEventIds = const <String>{},
    this.quizConfusedEventIds = const <String>{},
    required this.draftDisplayedEventIds,
    required this.committedDisplayedEventIds,
    required this.onToggleDisplayedEvent,
    required this.onSelectAllDisplayedEvents,
    required this.onDeselectAllDisplayedEvents,
    required this.onCommitDisplayedEvents,
    required this.onNextFromEra,
    required this.onNextFromCharacters,
    this.onOpenEventDetail,
    this.currentSelectedEventId,
    this.headerOverride,
    this.eraEvents = const <StoryEvent>[],
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
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final String? celebrationEventId;
  final String? celebrationStampLabel;
  final int celebrationNonce;
  final VoidCallback? onCelebrationComplete;
  final Set<String> quizReviewEventIds;
  final Set<String> quizConfusedEventIds;

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

  /// 사건 카드 클릭 시 즉시 호출 — 부모가 EventDetailPage 로 이동.
  /// v3 — 체크박스 토글 + '다음' 흐름 대신 카드 즉시 클릭으로 통일.
  final ValueChanged<StoryEvent>? onOpenEventDetail;

  /// 지도 핀 클릭 등으로 controller 가 가지고 있는 "현재 강조 사건" id.
  /// EventTimelineRow 의 selectedEventId 로 그대로 전달 → 그 카드에 '현재 이야기'
  /// 라벨 + viewport 중앙으로 자동 스크롤.
  final String? currentSelectedEventId;

  /// 부모가 _panelStageHandle (위/아래 chevron + stepper) 를 직접 주입할 수 있도록
  /// 한다. 지정 시 기본 [_PanelTopRow] 를 대체. 장소 모드와 동일한 헤더 UX 를
  /// 제공하기 위해 사용.
  final Widget? headerOverride;

  /// step 2 인물 카드에 표시할 "사건 N개" 카운트의 source. step 3 의 [events]
  /// 는 선택된 인물 timeline 만 갖고 있어, 선택 전(빈 상태) 에는 모든 카드가
  /// 0개로 표시되는 문제가 있다. 부모가 era 의 전체 사건을 그대로 넘긴다.
  final List<StoryEvent> eraEvents;

  @override
  State<StorySelectionPanel> createState() => _StorySelectionPanelState();
}

class _StorySelectionPanelState extends State<StorySelectionPanel> {
  @override
  Widget build(BuildContext context) {
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
                  // 헤더(toggle + stepper) 는 Column 으로 분리해 sticky.
                  // 옛 구조(headerOverride 도 SliverToBoxAdapter) 에서는
                  // 사건 카드 스크롤 시 헤더가 함께 위로 사라져 카드가 잘린
                  // 인상을 주었다. 이제 헤더 아래까지만 컨텐츠가 스크롤된다.
                  Column(
                    children: [
                      if (widget.headerOverride != null)
                        widget.headerOverride!
                      else ...[
                        const SizedBox(height: 10),
                        _PanelTopRow(
                          stage: widget.panelStage,
                          onStepUp: widget.onStepUp,
                          onStepDown: widget.onStepDown,
                          // step 2 + 선택 있을 때만 우측 작은 '다음' 핀.
                          showCharacterNext:
                              widget.step == 2 &&
                              widget.draftSelectedCharacterCodes.isNotEmpty,
                          characterCount:
                              widget.draftSelectedCharacterCodes.length,
                          onNextFromCharacters: widget.onNextFromCharacters,
                        ),
                      ],
                      Expanded(
                        child: Stack(
                          children: [
                            CustomScrollView(
                              controller: widget.scrollController,
                              physics: const ClampingScrollPhysics(),
                              slivers: [
                                // v3 — step 1/2/3 칩 + '다음' 버튼 헤더 제거.
                                // 우측 상단 _SelectionStepper 가 단계 이동 담당.
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 6),
                                ),
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

  // v3 — _primaryAction / _buildHeaderSection / _buildStepRow /
  // _buildHeaderControl 모두 제거. 헤더는 우측 상단 _SelectionStepper 가
  // 담당하고, '다음' 버튼은 흐름이 자동 진입으로 변경되어 불필요.

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
            mainAxisExtent: 108,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final character = sortedCharacters[index];
            // step 2 의 카운트는 era 전체 사건 기준 — widget.events 는 step 3
            // 의 선택된 인물 timeline 이라 빈 상태에서 0 으로 잘못 표시됨.
            final countSource = widget.eraEvents.isNotEmpty
                ? widget.eraEvents
                : widget.events;
            final count = countSource
                .where((e) => e.characterCodes.contains(character.code))
                .length;
            return _CharacterCompactCard(
              character: character,
              selected: widget.draftSelectedCharacterCodes.contains(
                character.code,
              ),
              accentColor: widget.colorForDraftCharacter(character.code),
              eventCount: count,
              onTap: () => widget.onToggleDraftCharacter(character.code),
            );
          }, childCount: sortedCharacters.length),
        ),
      ),
      // v3 — '다음' 버튼은 panel 상단 핸들 우측의 작은 핀으로 이동.
      // _PanelTopRow.showCharacterNext 가 step 2 + 선택 있을 때만 노출.
    ];
  }

  List<Widget> _buildStoryBodySlivers() {
    if (widget.events.isEmpty) {
      return <Widget>[_buildEmptyBodySliver('표시할 사건이 없습니다.')];
    }
    // v3 — 카드 클릭 즉시 EventDetailPage 이동. selectedEventId 로 '현재 이야기'
    // 강조 + 자동 스크롤. EventTimelineRow 가 region 모드와 동일하게 동작.
    final charactersByCode = <String, Character>{
      for (final p in widget.characters) p.code: p,
    };
    // 지도 핀 클릭 시 controller 가 selectEvent 로 selectedEventId 를 갱신하면
    // 그 카드가 강조 + 자동 스크롤. committed 가 1개일 땐 fallback.
    final selectedEventId =
        widget.currentSelectedEventId ??
        (widget.committedDisplayedEventIds.length == 1
            ? widget.committedDisplayedEventIds.first
            : null);
    return <Widget>[
      SliverToBoxAdapter(
        child: EventTimelineRow(
          events: widget.events,
          allEras: widget.eras,
          charactersByCode: charactersByCode,
          selectedEventId: selectedEventId,
          completedEventIds: widget.completedEventIds,
          eventEmotionMarks: widget.eventEmotionMarks,
          quizAttemptSummaries: widget.quizAttemptSummaries,
          celebrationEventId: widget.celebrationEventId,
          celebrationStampLabel: widget.celebrationStampLabel,
          celebrationNonce: widget.celebrationNonce,
          onCelebrationComplete: widget.onCelebrationComplete,
          quizReviewEventIds: widget.quizReviewEventIds,
          quizConfusedEventIds: widget.quizConfusedEventIds,
          onTapEvent: (event) => widget.onOpenEventDetail?.call(event),
          // SliverToBoxAdapter 안 — fixed height 필요.
          rowHeight: 248,
          // 카드 안 인물 pill: 사용자가 인물 모드에서 고른 인물을 가장 앞쪽에
          // 배치하고 지도 path 색과 동일한 톤으로 강조 — 모든 등장 인물이
          // 똑같이 보여서 헷갈리던 문제 해결.
          highlightedCharacterCodes: widget.committedSelectedCharacterCodes,
          colorForHighlightedCharacter: widget.colorForCommittedCharacter,
        ),
      ),
    ];
  }

  Widget _buildEmptyBodySliver(String text) {
    return SliverToBoxAdapter(
      child: SizedBox(height: 180, child: _EmptyStepMessage(text: text)),
    );
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

/// 패널 상단 핸들 행 — 가운데 chevron pill, (step 2 + 선택 있을 때) 우측에
/// 작은 "다음" 핀. 큰 바닥 버튼 대신 핸들과 같은 줄에 자그마하게 배치한다.
class _PanelTopRow extends StatelessWidget {
  const _PanelTopRow({
    required this.stage,
    required this.onStepUp,
    required this.onStepDown,
    required this.showCharacterNext,
    required this.characterCount,
    required this.onNextFromCharacters,
  });

  final StorySelectionPanelStage stage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;
  final bool showCharacterNext;
  final int characterCount;
  final VoidCallback onNextFromCharacters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _SelectionSheetTopBar(
            stage: stage,
            onStepUp: onStepUp,
            onStepDown: onStepDown,
          ),
          if (showCharacterNext)
            Positioned(
              right: 0,
              child: _CharacterStepNextPill(
                count: characterCount,
                onPressed: onNextFromCharacters,
              ),
            ),
        ],
      ),
    );
  }
}

/// 인물 step 2 의 "다음" 작은 핀 — chevron pill 우측 정렬. 1명 이상 선택돼야
/// 노출되며, 누르면 부모가 step 3 진입 + 사건 timeline reveal 시작.
class _CharacterStepNextPill extends StatelessWidget {
  const _CharacterStepNextPill({required this.count, required this.onPressed});
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF8C5A2E),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count명 다음',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// _EventCardConnector / _DashedConnectorPainter 는 lib/widgets/event_timeline_row.dart
// 로 이동 — region 모드와 character 모드가 같은 위젯 (EventTimelineRow) 을 공유.
