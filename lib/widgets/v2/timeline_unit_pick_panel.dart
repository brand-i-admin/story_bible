import 'package:flutter/material.dart';

import '../../models/story_event.dart';

class TimelineUnitPickPanel extends StatelessWidget {
  const TimelineUnitPickPanel({
    super.key,
    required this.events,
    required this.selectedUnitCodes,
    required this.onToggleUnit,
    required this.onSelectAll,
    required this.onClear,
    required this.onNext,
    this.bottomInset = 0,
  });

  final List<StoryEvent> events;
  final Set<String> selectedUnitCodes;
  final ValueChanged<String> onToggleUnit;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onNext;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = _timelineUnits(events);
    if (units.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Text(
            '선택한 시대에 표시할 단위가 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + bottomInset),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '보고 싶은 단위',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onSelectAll,
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text('전체'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: selectedUnitCodes.isEmpty ? null : onClear,
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('해제'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final unit in units)
                  _TimelineUnitCard(
                    unit: unit,
                    selected: selectedUnitCodes.contains(unit.code),
                    width: cardWidth,
                    onTap: () => onToggleUnit(unit.code),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: selectedUnitCodes.isEmpty ? null : onNext,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text('${selectedUnitCodes.length}개 단위 다음'),
        ),
      ],
    );
  }
}

class _TimelineUnit {
  const _TimelineUnit({
    required this.code,
    required this.title,
    required this.order,
    required this.events,
  });

  final String code;
  final String title;
  final int order;
  final List<StoryEvent> events;

  String get subtitle {
    if (events.isEmpty) {
      return '사건 없음';
    }
    if (events.length == 1) {
      return events.single.title;
    }
    return '${events.first.title} → ${events.last.title}';
  }
}

List<_TimelineUnit> _timelineUnits(List<StoryEvent> events) {
  final byCode = <String, List<StoryEvent>>{};
  for (final event in events) {
    byCode.putIfAbsent(event.unitCode, () => <StoryEvent>[]).add(event);
  }
  final units = <_TimelineUnit>[];
  for (final entry in byCode.entries) {
    final unitEvents = [...entry.value]
      ..sort((a, b) {
        final cmp = a.globalRank.compareTo(b.globalRank);
        if (cmp != 0) return cmp;
        return a.storyIndex.compareTo(b.storyIndex);
      });
    final first = unitEvents.first;
    units.add(
      _TimelineUnit(
        code: first.unitCode,
        title: first.unitTitle,
        order: first.unitOrder,
        events: unitEvents,
      ),
    );
  }
  units.sort((a, b) {
    final cmp = a.order.compareTo(b.order);
    if (cmp != 0) return cmp;
    return a.title.compareTo(b.title);
  });
  return units;
}

class _TimelineUnitCard extends StatelessWidget {
  const _TimelineUnitCard({
    required this.unit,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final _TimelineUnit unit;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    return Material(
      color: selected
          ? selectedColor.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? selectedColor
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 17,
                    color: selected
                        ? selectedColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      unit.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${unit.events.length}개 이야기',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selectedColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unit.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
