import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/event_proposal.dart';
import '../../models/story_event.dart';
import '../../state/proposal_providers.dart';
import '../../state/story_controller.dart';

/// "위치 재선택" 다이얼로그 — 같은 era + 같은 after_story_index 에 다른 제안이
/// 먼저 승인되어 자기 제안이 `position_invalidated_at` 으로 잠겼을 때, 제안자
/// 본인이 새 위치(after_story_index)와 연도(start_year/end_year)를 제출한다.
///
/// 흐름:
/// 1. 같은 era 의 활성 events 를 시간순(rank_in_era)으로 표시 — 사용자는 0(맨 앞)
///    또는 K(K번째 다음)을 선택.
/// 2. 선택 즉시 prev/next 이벤트의 연도 범위를 미리 보여 사용자가 자기 연도 입력의
///    허용 범위를 알 수 있게 한다.
/// 3. start_year/end_year 입력 — `prev.endYear <= start <= end <= next.startYear` 로
///    사전 검증해 빨간 에러 메시지로 안내. RPC 가 다시 한 번 동일 검증.
/// 4. 제출 시 `revise_proposal_position` RPC. 성공 시 다이얼로그 닫고 true 반환.
class RevisePositionDialog extends ConsumerStatefulWidget {
  const RevisePositionDialog({super.key, required this.proposal});

  final EventProposal proposal;

  @override
  ConsumerState<RevisePositionDialog> createState() =>
      _RevisePositionDialogState();
}

class _RevisePositionDialogState extends ConsumerState<RevisePositionDialog> {
  late final TextEditingController _startYearCtrl;
  late final TextEditingController _endYearCtrl;
  int? _afterStoryIndex; // null 이면 미선택, 0 이면 맨 앞
  Future<List<StoryEvent>>? _eventsFuture;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _startYearCtrl = TextEditingController(
      text: widget.proposal.startYear?.toString() ?? '',
    );
    _endYearCtrl = TextEditingController(
      text: widget.proposal.endYear?.toString() ?? '',
    );
    _afterStoryIndex = widget.proposal.afterStoryIndex;
    // 이 다이얼로그는 'new' 제안 (eraId 필수) 에서만 호출되므로 ! 안전.
    _eventsFuture = ref
        .read(storyRepositoryProvider)
        .fetchEventsByEra(widget.proposal.eraId!);
  }

  @override
  void dispose() {
    _startYearCtrl.dispose();
    _endYearCtrl.dispose();
    super.dispose();
  }

  StoryEvent? _prevEvent(List<StoryEvent> events) {
    if (_afterStoryIndex == null || _afterStoryIndex == 0) return null;
    final matches = events.where((e) => e.storyIndex == _afterStoryIndex);
    return matches.isEmpty ? null : matches.first;
  }

  StoryEvent? _nextEvent(List<StoryEvent> events) {
    if (_afterStoryIndex == null) return null;
    final after = events.where((e) => e.storyIndex > _afterStoryIndex!).toList()
      ..sort((a, b) => a.storyIndex.compareTo(b.storyIndex));
    return after.isEmpty ? null : after.first;
  }

  /// 클라이언트 측 사전 검증. RPC 가 동일 규칙으로 한 번 더 본다.
  String? _validate(List<StoryEvent> events) {
    if (_afterStoryIndex == null) return '위치를 선택해주세요.';
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null || ey == null) return '시작/끝 연도를 입력해주세요.';
    if (ey < sy) return '끝 연도는 시작 연도와 같거나 더 뒤여야 합니다.';
    final prev = _prevEvent(events);
    if (prev != null && prev.endYear != null && sy < prev.endYear!) {
      return '시작 연도는 이전 이야기 "${prev.title}" 의 끝 연도(${prev.endYear}) 이상이어야 합니다.';
    }
    final next = _nextEvent(events);
    if (next != null && next.startYear != null && ey > next.startYear!) {
      return '끝 연도는 다음 이야기 "${next.title}" 의 시작 연도(${next.startYear}) 이하여야 합니다.';
    }
    return null;
  }

  Future<void> _submit(List<StoryEvent> events) async {
    final err = _validate(events);
    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref
          .read(proposalRepositoryProvider)
          .revisePosition(
            proposalId: widget.proposal.id,
            afterStoryIndex: _afterStoryIndex!,
            startYear: int.parse(_startYearCtrl.text.trim()),
            endYear: int.parse(_endYearCtrl.text.trim()),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '제출 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('위치 재선택'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: FutureBuilder<List<StoryEvent>>(
          future: _eventsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('이야기 목록 불러오기 실패: ${snap.error}');
            }
            final events = snap.data ?? const <StoryEvent>[];
            final prev = _prevEvent(events);
            final next = _nextEvent(events);
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '같은 era 의 이야기 목록입니다. 어디 다음에 들어갈지 골라주세요. '
                    '맨 앞도 선택 가능합니다.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _PositionRadio(
                    label: '맨 앞에 삽입',
                    selected: _afterStoryIndex == 0,
                    onTap: () => setState(() => _afterStoryIndex = 0),
                  ),
                  ...events.map(
                    (e) => _PositionRadio(
                      label:
                          '${e.title} 다음 (story_index ${e.storyIndex}, '
                          '${e.startYear ?? '?'}–${e.endYear ?? '?'})',
                      selected: _afterStoryIndex == e.storyIndex,
                      onTap: () =>
                          setState(() => _afterStoryIndex = e.storyIndex),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (prev != null || next != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '허용 연도 범위: '
                        '${prev?.endYear ?? '제한 없음'} ≤ 시작 ≤ 끝 ≤ '
                        '${next?.startYear ?? '제한 없음'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startYearCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(labelText: '시작 연도'),
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _endYearCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(labelText: '끝 연도'),
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FutureBuilder<List<StoryEvent>>(
          future: _eventsFuture,
          builder: (context, snap) {
            final events = snap.data ?? const <StoryEvent>[];
            return FilledButton(
              onPressed:
                  (_submitting || snap.connectionState != ConnectionState.done)
                  ? null
                  : () => _submit(events),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('재제출'),
            );
          },
        ),
      ],
    );
  }
}

class _PositionRadio extends StatelessWidget {
  const _PositionRadio({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
