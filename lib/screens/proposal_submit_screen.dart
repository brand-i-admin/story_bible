import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/event_proposal.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../widgets/proposal/bible_refs_picker.dart';
import '../widgets/proposal/character_codes_picker.dart';
import '../widgets/proposal/new_character_dialog.dart';
import '../widgets/proposal/proposal_character_row.dart';
import '../widgets/proposal/proposal_location_picker.dart';
import '../widgets/proposal/proposal_quiz_editor.dart';
import '../widgets/proposal/proposal_scenes_editor.dart';

part 'proposal_submit_screen_state.dart';

/// 이야기 제안 등록/수정 폼 (wizard).
///
/// 홈 UI 톤으로 5 단계:
///   Step 0. 안내
///   Step 1. 시대 선택 (구약/신약 탭 + era 카드 그리드)
///   Step 2. 등장인물과 위치 선택
///           sub-phase: characters(복수) → event:0 → event:1 → ... → summary
///   Step 3. 세부 내용 (제목 / 요약 / 장소(지도) / 연도 / 성경 / 장면)
///   Step 4. 퀴즈 (4지선다 1~3개) + 최종 "제안 등록" 버튼
///
/// 최종 `after_story_index` 는 **선택된 인물별 사건의 story_index 중 최댓값**.
/// 이 뒤에 삽입되면 모든 선택된 사건 이상(+) 으로 시프트되어 정합성 유지.
class ProposalSubmitScreen extends ConsumerStatefulWidget {
  const ProposalSubmitScreen({super.key, this.existing});

  final EventProposal? existing;

  @override
  ConsumerState<ProposalSubmitScreen> createState() =>
      _ProposalSubmitScreenState();
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});
  final int step;

  static const _labels = ['제안 안내', '시대', '등장인물과 위치', '세부 내용', '퀴즈'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: step == i
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${i + 1}. ${_labels[i]}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: step == i
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: step == i ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (i < _labels.length - 1)
                Container(
                  width: 12,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: theme.dividerColor,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EraCard extends StatelessWidget {
  const _EraCard({
    required this.index,
    required this.era,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final Era era;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 1.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.secondaryContainer,
                ),
                child: Text(
                  '$index',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(era.name, style: theme.textTheme.titleSmall),
                    if (era.startYear != null || era.endYear != null)
                      Text(
                        _yearRange(era),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  String _yearRange(Era era) {
    String fmt(int? y) {
      if (y == null) return '?';
      return y < 0 ? 'B.C. ${-y}' : 'A.D. $y';
    }

    return '(${fmt(era.startYear)} ~ ${fmt(era.endYear)})';
  }
}

class _CharacterLabel {
  const _CharacterLabel({required this.name, this.highlighted = false});
  final String name;
  final bool highlighted;
}

class _InsertionCard extends StatelessWidget {
  const _InsertionCard({
    required this.title,
    required this.subtitle,
    this.characterLabels,
    this.storyIndex,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<_CharacterLabel>? characterLabels;
  final int? storyIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? highlight.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? highlight : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (storyIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: Text(
                      '#$storyIndex',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (characterLabels != null &&
                          characterLabels!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final l in characterLabels!)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: l.highlighted
                                      ? highlight.withValues(alpha: 0.18)
                                      : theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: l.highlighted
                                        ? highlight.withValues(alpha: 0.6)
                                        : theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  l.name,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: l.highlighted
                                        ? highlight
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: l.highlighted
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: highlight, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _IntroBullet extends StatelessWidget {
  const _IntroBullet({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondaryContainer,
            ),
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrEmptyExt on Iterable<String> {
  String firstOrEmpty() => isEmpty ? '' : first;
}

/// 이미지 생성 중 전체 화면을 블록하는 모달 overlay.
///
/// AI 에 한 번에 한 장만 보낼 수 있으므로 생성이 돌아가는 동안 사용자가 다른
/// 장면 생성을 시도하지 못하도록 입력 이벤트를 흡수한다. `AbsorbPointer` +
/// 반투명 배경 + 중앙 안내 카드.
class _GeneratingImageOverlay extends StatelessWidget {
  const _GeneratingImageOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(strokeWidth: 3.5),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'AI 가 그림을 생성중입니다',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '한 번에 한 장만 생성할 수 있어요. 잠시만 기다려주세요. '
                        '완료되면 자동으로 다음 작업을 할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
