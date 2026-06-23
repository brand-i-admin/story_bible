import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/character_name_fallbacks.dart';
import '../../models/event_proposal.dart';
import '../../models/story_event.dart';
import '../../state/story_controller.dart';

/// 새 이야기 제안 승인 전 띄우는 확인 다이얼로그.
///
/// 1) 제안 작성자가 새로 만든 캐릭터 + 기존 등장 인물의 `is_active` 를 관리자가
///    토글로 결정. 신규 인물은 기본 ON, 기존 인물은 현재 DB 값 그대로 시작.
/// 2) "승인" 클릭 시 `{ code: bool }` 매핑을 반환해 호출자가 RPC 에 전달.
/// 3) 취소면 null 반환.
///
/// 다이얼로그 안에서 직접 Supabase 를 한 번만 query 한다 (작은 N개라 OK).
class ApproveProposalReviewResult {
  const ApproveProposalReviewResult({
    required this.characterActiveOverrides,
    required this.afterStoryIndexOverride,
  });

  final Map<String, bool> characterActiveOverrides;
  final int afterStoryIndexOverride;
}

class ApproveProposalDialog extends ConsumerStatefulWidget {
  const ApproveProposalDialog({super.key, required this.proposal});

  final EventProposal proposal;

  /// 결과: 등장인물 노출 override + 관리자 삽입 위치 override. 취소 시 null.
  static Future<ApproveProposalReviewResult?> show(
    BuildContext context,
    EventProposal proposal,
  ) {
    return showDialog<ApproveProposalReviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApproveProposalDialog(proposal: proposal),
    );
  }

  @override
  ConsumerState<ApproveProposalDialog> createState() =>
      _ApproveProposalDialogState();
}

class _CharRow {
  _CharRow({
    required this.code,
    required this.name,
    required this.isNew,
    required this.isActive,
  });
  final String code;
  final String name;
  final bool isNew;
  bool isActive;
}

class _ApproveProposalDialogState extends ConsumerState<ApproveProposalDialog> {
  late Future<List<_CharRow>> _rowsFuture;
  late Future<List<StoryEvent>> _eventsFuture;
  late int _selectedAfterStoryIndex;

  @override
  void initState() {
    super.initState();
    _selectedAfterStoryIndex = widget.proposal.afterStoryIndex ?? 0;
    _rowsFuture = _loadRows();
    _eventsFuture = _loadEvents();
  }

  Future<List<StoryEvent>> _loadEvents() async {
    final eraId = widget.proposal.eraId;
    if (eraId == null) return const [];
    return ref.read(storyRepositoryProvider).fetchEventsByEra(eraId);
  }

  Future<List<_CharRow>> _loadRows() async {
    final p = widget.proposal;
    final newCodes = {for (final c in p.proposedCharacters) c.code};
    final allCodes = <String>{...p.characterCodes, ...newCodes};
    if (allCodes.isEmpty) return const [];

    // 기존 characters 의 현재 name + is_active 조회.
    final client = Supabase.instance.client;
    final existing = <String, Map<String, dynamic>>{};
    try {
      final rows = await client
          .from('characters')
          .select('code, name, is_active')
          .inFilter('code', allCodes.toList());
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        existing[r['code'] as String] = r;
      }
    } catch (_) {
      // 조회 실패 시 모두 신규 취급 — 기본 활성으로 보여주고 진행.
    }

    final result = <_CharRow>[];
    // 신규 인물 먼저 (UI 가시성).
    for (final c in p.proposedCharacters) {
      final ex = existing[c.code];
      result.add(
        _CharRow(
          code: c.code,
          name: localizedCharacterName(code: c.code, name: c.name),
          isNew: ex == null,
          isActive: ex == null ? true : (ex['is_active'] as bool?) ?? true,
        ),
      );
    }
    // 기존 등장 인물.
    for (final code in p.characterCodes) {
      if (newCodes.contains(code)) continue; // 위에서 처리됨
      final ex = existing[code];
      result.add(
        _CharRow(
          code: code,
          name: localizedCharacterName(
            code: code,
            name: ex?['name'] as String?,
          ),
          isNew: false,
          isActive: (ex?['is_active'] as bool?) ?? true,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('제안 승인 — 위치와 인물 검토')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: FutureBuilder<List<_CharRow>>(
            future: _rowsFuture,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '인물 정보를 불러오지 못했어요\n${snap.error}',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }
              final rows = snap.data ?? const [];
              return FutureBuilder<List<StoryEvent>>(
                future: _eventsFuture,
                builder: (context, eventsSnap) {
                  if (eventsSnap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (eventsSnap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '위치 정보를 불러오지 못했어요\n${eventsSnap.error}',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  final events = eventsSnap.data ?? const <StoryEvent>[];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '승인하면 이 이야기가 사용자 지도에 즉시 표시됩니다.\n'
                          '들어갈 위치와 인물 노출 여부를 마지막으로 확인해 주세요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.proposal.needsPositionRevision) ...[
                          const SizedBox(height: 10),
                          _PositionWarning(
                            message: widget.proposal.positionInvalidationReason,
                          ),
                        ],
                        const SizedBox(height: 14),
                        _PositionReviewSection(
                          events: events,
                          selectedAfterStoryIndex: _selectedAfterStoryIndex,
                          onSelect: (value) =>
                              setState(() => _selectedAfterStoryIndex = value),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '등장 인물 노출',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '등장 인물이 없습니다.',
                              style: theme.textTheme.bodySmall,
                            ),
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < rows.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _CharSwitchRow(
                                  row: rows[i],
                                  onToggle: (v) =>
                                      setState(() => rows[i].isActive = v),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FutureBuilder<List<_CharRow>>(
          future: _rowsFuture,
          builder: (ctx, rowSnap) {
            return FutureBuilder<List<StoryEvent>>(
              future: _eventsFuture,
              builder: (ctx, eventSnap) {
                final ready =
                    rowSnap.connectionState == ConnectionState.done &&
                    eventSnap.connectionState == ConnectionState.done &&
                    !rowSnap.hasError &&
                    !eventSnap.hasError;
                final rows = rowSnap.data;
                return FilledButton.icon(
                  onPressed: !ready
                      ? null
                      : () {
                          final overrides = <String, bool>{
                            for (final r in (rows ?? const <_CharRow>[]))
                              r.code: r.isActive,
                          };
                          Navigator.of(context).pop(
                            ApproveProposalReviewResult(
                              characterActiveOverrides: overrides,
                              afterStoryIndexOverride: _selectedAfterStoryIndex,
                            ),
                          );
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('최종 승인'),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _PositionWarning extends StatelessWidget {
  const _PositionWarning({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_problem_outlined,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message?.trim().isNotEmpty == true
                  ? message!.trim()
                  : '같은 위치에 다른 이야기가 먼저 승인되었습니다. 아래에서 새 위치를 고른 뒤 승인하세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionReviewSection extends StatelessWidget {
  const _PositionReviewSection({
    required this.events,
    required this.selectedAfterStoryIndex,
    required this.onSelect,
  });

  final List<StoryEvent> events;
  final int selectedAfterStoryIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '삽입 위치',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '여기서 고른 위치가 승인 RPC의 after_story_index override로 전달됩니다.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _PositionChoiceTile(
          label: '맨 앞에 삽입',
          selected: selectedAfterStoryIndex == 0,
          onTap: () => onSelect(0),
        ),
        ...events.map(
          (event) => _PositionChoiceTile(
            label:
                '${event.title} 다음 (#${event.storyIndex}, ${_formatYear(event.startYear)}-${_formatYear(event.endYear)})',
            selected: selectedAfterStoryIndex == event.storyIndex,
            onTap: () => onSelect(event.storyIndex),
          ),
        ),
      ],
    );
  }

  static String _formatYear(int? year) => year?.toString() ?? '?';
}

class _PositionChoiceTile extends StatelessWidget {
  const _PositionChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharSwitchRow extends StatelessWidget {
  const _CharSwitchRow({required this.row, required this.onToggle});
  final _CharRow row;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (row.isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'NEW',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  row.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            row.isActive ? '노출' : '숨김',
            style: theme.textTheme.bodySmall?.copyWith(
              color: row.isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Switch(value: row.isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}
