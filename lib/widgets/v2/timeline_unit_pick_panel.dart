import 'package:flutter/material.dart';

import '../../models/story_event.dart';
import '../../theme/tokens.dart';

class TimelineUnitPickPanel extends StatelessWidget {
  const TimelineUnitPickPanel({
    super.key,
    required this.events,
    required this.selectedUnitCodes,
    required this.onToggleUnit,
    required this.onSelectAll,
    required this.onClearAll,
    this.bottomInset = 0,
  });

  final List<StoryEvent> events;
  final Set<String> selectedUnitCodes;
  final ValueChanged<String> onToggleUnit;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const cardGap = 8.0;
        const visibleCards = 3.5;
        final allSelected = units.every(
          (unit) => selectedUnitCodes.contains(unit.code),
        );
        final cardWidth =
            ((constraints.maxWidth -
                        horizontalPadding * 2 -
                        cardGap * (visibleCards - 1)) /
                    visibleCards)
                .clamp(86.0, 124.0)
                .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                horizontalPadding,
                6,
                horizontalPadding,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '단위 선택',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.ink700,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('timeline-unit-toggle-all'),
                    onPressed: allSelected ? onClearAll : onSelectAll,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      foregroundColor: allSelected
                          ? AppColors.greenBot
                          : AppColors.ink600,
                      backgroundColor: allSelected
                          ? AppColors.greenTint2
                          : AppColors.parchmentCream,
                      side: BorderSide(
                        color: allSelected
                            ? AppColors.greenBot
                            : AppColors.borderCard,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: Text(allSelected ? '전체 해제' : '전체 선택'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  12 + bottomInset,
                ),
                itemCount: units.length,
                separatorBuilder: (_, _) => const SizedBox(width: cardGap),
                itemBuilder: (context, index) {
                  final unit = units[index];
                  return Align(
                    alignment: Alignment.topLeft,
                    child: _TimelineUnitCard(
                      key: ValueKey('timeline-unit-card-${unit.code}'),
                      unit: unit,
                      selected: selectedUnitCodes.contains(unit.code),
                      width: cardWidth,
                      onTap: () => onToggleUnit(unit.code),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
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

  static const int _maxSubtitleCharacters = 89;

  String get subtitle {
    if (events.isEmpty) {
      return '사건 없음';
    }
    final first = _eventPhrase(events.first);
    if (events.length == 1) {
      return _fitSubtitle(first);
    }
    final last = _eventPhrase(events.last);
    if (events.length == 2) {
      return _composeSubtitle(first, last, middle: ' 이어 ');
    }
    return _composeSubtitle(first, last, middle: ' 여러 이야기를 지나 마지막에는 ');
  }

  String get numberedTitle => '$order. $title';

  static String _eventPhrase(StoryEvent event) {
    final summary = event.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return _firstSentence(summary);
    }
    return _firstSentence(_titleDescription(event.title));
  }

  static String _titleDescription(String title) {
    final parts = title.split(':');
    if (parts.length >= 2) {
      final subject = parts.first.trim();
      final detail = parts.sublist(1).join(':').trim();
      if (subject.isNotEmpty && detail.isNotEmpty) {
        return '$subject에서 $detail을 봅니다';
      }
    }
    return '$title 이야기를 봅니다';
  }

  static String _asSentence(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (RegExp(r'[.!?。！？]$').hasMatch(trimmed)) {
      return trimmed;
    }
    return '$trimmed.';
  }

  static String _firstSentence(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'^(.+?[.!?。！？])').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return _asSentence(trimmed);
  }

  static String _composeSubtitle(
    String first,
    String last, {
    required String middle,
  }) {
    const prefix = '먼저 ';
    final text = _asSentence('$prefix$first$middle$last');
    if (_charLength(text) <= _maxSubtitleCharacters) {
      return text;
    }
    final budget =
        ((_maxSubtitleCharacters - _charLength(prefix) - _charLength(middle)) /
                2)
            .floor()
            .clamp(24, 36);
    return _fitSubtitle(
      '$prefix${_shortenPhrase(first, budget)}$middle${_shortenPhrase(last, budget)}',
    );
  }

  static String _fitSubtitle(String value) {
    return _asSentence(_shortenPhrase(value, _maxSubtitleCharacters));
  }

  static String _shortenPhrase(String value, int maxCharacters) {
    var normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    normalized = normalized.replaceFirst(RegExp(r'[.!?。！？]+$'), '');
    if (_charLength(normalized) <= maxCharacters) {
      return normalized;
    }
    final chars = normalized.runes.toList();
    var cut = String.fromCharCodes(chars.take(maxCharacters)).trimRight();
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace >= (maxCharacters * 0.68).floor()) {
      cut = cut.substring(0, lastSpace).trimRight();
    }
    return cut.replaceFirst(RegExp(r'[,.，、]+$'), '').trimRight();
  }

  static int _charLength(String value) => value.runes.length;
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
    super.key,
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
    const selectedColor = AppColors.greenBot;
    final bodyColor = selected ? AppColors.ink600 : AppColors.ink350;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 116),
          child: Ink(
            width: width,
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: selected ? AppColors.greenTint2 : AppColors.parchmentCard,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: selected ? selectedColor : AppColors.borderCard,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected ? AppShadows.green : AppShadows.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.numberedTitle,
                  maxLines: null,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.ink800,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${unit.events.length}개 이야기',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selectedColor,
                    fontSize: 10.6,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  unit.subtitle,
                  maxLines: 8,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: bodyColor,
                    fontSize: 9.4,
                    height: 1.16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
