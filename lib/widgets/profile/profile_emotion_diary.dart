import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/event_emotion_mark.dart';
import '../../models/story_event.dart';
import '../../models/user_companion_diary_entry.dart';
import '../../state/story_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/kst_date.dart';
import '../emotion_badge_icon.dart';
import 'companion_diary_entry_card.dart';
import 'profile_companion_diary.dart';
import 'profile_emotion_stats.dart';

class ProfileEmotionDiary extends ConsumerStatefulWidget {
  const ProfileEmotionDiary({
    super.key,
    required this.eventEmotionMarks,
    required this.onOpenEventDetail,
    this.companionDiaryEntries = const <UserCompanionDiaryEntry>[],
    this.companionDiaryLoading = false,
    this.companionDiaryError,
    this.onSaveCompanionDiary,
    this.onDeleteCompanionDiary,
    this.emotionStats,
    this.onTapEmotion,
    this.now,
  });

  final Map<String, EventEmotionMark> eventEmotionMarks;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final CompanionDiarySaveCallback? onSaveCompanionDiary;
  final CompanionDiaryDeleteCallback? onDeleteCompanionDiary;
  final ProfileEmotionStats? emotionStats;
  final ValueChanged<EventEmotionOption>? onTapEmotion;
  final DateTime? now;

  @override
  ConsumerState<ProfileEmotionDiary> createState() =>
      _ProfileEmotionDiaryState();
}

class _ProfileEmotionDiaryState extends ConsumerState<ProfileEmotionDiary> {
  late Future<List<StoryEvent>> _eventsFuture;
  String _eventIdFingerprint = '';
  late DateTime _focusedMonth;
  late DateTime _selectedDate;
  _DiaryContentTab _selectedContentTab = _DiaryContentTab.companion;
  bool _expanded = false;
  String? _openingEventId;
  Timer? _openingResetTimer;

  @override
  void initState() {
    super.initState();
    final today = _todayKst();
    _focusedMonth = _monthStart(today);
    _selectedDate = today;
    _eventIdFingerprint = _fingerprint(widget.eventEmotionMarks.keys);
    _eventsFuture = _loadMarkedEvents();
  }

  @override
  void didUpdateWidget(covariant ProfileEmotionDiary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFingerprint = _fingerprint(widget.eventEmotionMarks.keys);
    if (nextFingerprint != _eventIdFingerprint) {
      _eventIdFingerprint = nextFingerprint;
      _eventsFuture = _loadMarkedEvents();
    }
    if (oldWidget.now != widget.now) {
      final today = _todayKst();
      if (_selectedDate.isAfter(today)) {
        _selectedDate = today;
        _focusedMonth = _monthStart(today);
      }
    }
  }

  @override
  void dispose() {
    _openingResetTimer?.cancel();
    super.dispose();
  }

  Future<List<StoryEvent>> _loadMarkedEvents() {
    return ref
        .read(storyRepositoryProvider)
        .fetchEventsByIds(widget.eventEmotionMarks.keys.toSet());
  }

  String _fingerprint(Iterable<String> ids) {
    final sorted = ids.toList()..sort();
    return sorted.join('|');
  }

  DateTime _todayKst() => _dateOnly(toKst(widget.now ?? DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final nowUtc = widget.now ?? DateTime.now();
    final today = _todayKst();
    final marksByDate = _groupMarksByKstDate(
      widget.eventEmotionMarks.values,
      nowUtc: nowUtc,
    );
    final companionDiaryByDate = _groupCompanionDiaryEntriesByDate(
      widget.companionDiaryEntries,
    );

    return FutureBuilder<List<StoryEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <StoryEvent>[];
        final eventById = {for (final event in events) event.id: event};
        final selectedMarks =
            marksByDate[_selectedDate] ?? const <EventEmotionMark>[];
        final selectedCompanionDiary =
            companionDiaryByDate[_dateOnly(_selectedDate)];
        return Stack(
          children: [
            _EmotionDiaryPanel(
              focusedMonth: _focusedMonth,
              selectedDate: _selectedDate,
              today: today,
              expanded: _expanded,
              marksByDate: marksByDate,
              companionDiaryByDate: companionDiaryByDate,
              companionDiaryEntries: widget.companionDiaryEntries,
              selectedCompanionDiary: selectedCompanionDiary,
              companionDiaryLoading: widget.companionDiaryLoading,
              companionDiaryError: widget.companionDiaryError,
              selectedMarks: selectedMarks,
              emotionStats: widget.emotionStats,
              eventById: eventById,
              onToggleExpanded: () {
                setState(() => _expanded = !_expanded);
              },
              onMoveMonth: _moveMonth,
              onSelectDate: _selectDate,
              selectedContentTab: _selectedContentTab,
              onSelectContentTab: (tab) {
                setState(() => _selectedContentTab = tab);
              },
              onSaveCompanionDiary: widget.onSaveCompanionDiary,
              onDeleteCompanionDiary: widget.onDeleteCompanionDiary,
              onTapEmotion: widget.onTapEmotion,
              onOpenEventDetail: _openEventDetailWithLoading,
              loading: snapshot.connectionState == ConnectionState.waiting,
              hasError: snapshot.hasError,
            ),
            if (_openingEventId != null)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.parchmentCream.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.parchmentCream,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0x99D6BF8D),
                          width: 0.8,
                        ),
                        boxShadow: AppShadows.sm,
                      ),
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openEventDetailWithLoading(StoryEvent event) {
    if (_openingEventId != null) {
      return;
    }
    _openingResetTimer?.cancel();
    setState(() => _openingEventId = event.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onOpenEventDetail(event);
      _openingResetTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) {
          setState(() => _openingEventId = null);
        }
      });
    });
  }

  void _selectDate(DateTime date) {
    final today = _todayKst();
    final nextMonth = _monthStart(date);
    if (nextMonth.isAfter(_monthStart(today))) {
      return;
    }
    setState(() {
      _selectedDate = _dateOnly(date);
      _focusedMonth = nextMonth;
    });
  }

  void _moveMonth(int delta) {
    final today = _todayKst();
    final currentMonth = _monthStart(today);
    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    if (nextMonth.isAfter(currentMonth)) {
      return;
    }
    setState(() {
      _focusedMonth = nextMonth;
      if (!_isSameMonth(_selectedDate, nextMonth)) {
        _selectedDate = _isSameMonth(today, nextMonth) ? today : nextMonth;
      }
    });
  }
}

enum _DiaryContentTab { companion, emotion }

class _EmotionDiaryPanel extends StatelessWidget {
  const _EmotionDiaryPanel({
    required this.focusedMonth,
    required this.selectedDate,
    required this.today,
    required this.expanded,
    required this.marksByDate,
    required this.companionDiaryByDate,
    required this.companionDiaryEntries,
    required this.selectedCompanionDiary,
    required this.companionDiaryLoading,
    required this.companionDiaryError,
    required this.selectedMarks,
    required this.emotionStats,
    required this.eventById,
    required this.onToggleExpanded,
    required this.onMoveMonth,
    required this.onSelectDate,
    required this.selectedContentTab,
    required this.onSelectContentTab,
    required this.onSaveCompanionDiary,
    required this.onDeleteCompanionDiary,
    required this.onTapEmotion,
    required this.onOpenEventDetail,
    required this.loading,
    required this.hasError,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final DateTime today;
  final bool expanded;
  final Map<DateTime, List<EventEmotionMark>> marksByDate;
  final Map<DateTime, UserCompanionDiaryEntry> companionDiaryByDate;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final UserCompanionDiaryEntry? selectedCompanionDiary;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final List<EventEmotionMark> selectedMarks;
  final ProfileEmotionStats? emotionStats;
  final Map<String, StoryEvent> eventById;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onMoveMonth;
  final ValueChanged<DateTime> onSelectDate;
  final _DiaryContentTab selectedContentTab;
  final ValueChanged<_DiaryContentTab> onSelectContentTab;
  final CompanionDiarySaveCallback? onSaveCompanionDiary;
  final CompanionDiaryDeleteCallback? onDeleteCompanionDiary;
  final ValueChanged<EventEmotionOption>? onTapEmotion;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final currentMonth = _monthStart(today);
    final canGoNext = focusedMonth.isBefore(currentMonth);
    final visibleDates = expanded
        ? _monthVisibleDates(focusedMonth)
        : _twoWeekVisibleDates(selectedDate);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x99D6BF8D), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (emotionStats != null && onTapEmotion != null) ...[
            ProfileEmotionStatsRows(
              stats: emotionStats!,
              onTapEmotion: onTapEmotion!,
            ),
            const Divider(height: 22, color: Color(0x338E6F48)),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '${focusedMonth.year}년 ${focusedMonth.month}월',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink800,
                    fontSize: 15.4,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
              if (expanded) ...[
                _CalendarIconButton(
                  tooltip: '이전 달',
                  icon: Icons.chevron_left_rounded,
                  onTap: () => onMoveMonth(-1),
                ),
                const SizedBox(width: 2),
                _CalendarIconButton(
                  tooltip: '다음 달',
                  icon: Icons.chevron_right_rounded,
                  onTap: canGoNext ? () => onMoveMonth(1) : null,
                ),
                const SizedBox(width: 5),
              ],
              _CalendarToggleButton(
                expanded: expanded,
                onTap: onToggleExpanded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _WeekdayHeader(),
          const SizedBox(height: 5),
          for (var i = 0; i < visibleDates.length; i += 7) ...[
            if (i > 0) const _CalendarGridHorizontalDivider(),
            Builder(
              builder: (context) {
                final weekDates = visibleDates.skip(i).take(7).toList();
                final weekHeight = _calendarWeekRowHeight(
                  weekDates,
                  marksByDate,
                );
                final weekEmotionLineCount = _calendarWeekEmotionLineCount(
                  weekDates,
                  marksByDate,
                );
                return SizedBox(
                  height: weekHeight,
                  child: Row(
                    children: [
                      for (final date in weekDates) ...[
                        Expanded(
                          child: _EmotionCalendarDayCell(
                            date: date,
                            focusedMonth: focusedMonth,
                            selected: _isSameDate(date, selectedDate),
                            today: _isSameDate(date, today),
                            marks:
                                marksByDate[_dateOnly(date)] ??
                                const <EventEmotionMark>[],
                            hasCompanionDiary: companionDiaryByDate.containsKey(
                              _dateOnly(date),
                            ),
                            compact: weekEmotionLineCount == 0,
                            onTap: () => onSelectDate(date),
                          ),
                        ),
                        if (date.weekday != DateTime.saturday)
                          const _CalendarGridVerticalDivider(),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
          const Divider(height: 22, color: Color(0x338E6F48)),
          _DiaryContentTabBar(
            selected: selectedContentTab,
            onSelect: onSelectContentTab,
          ),
          const SizedBox(height: 11),
          if (selectedContentTab == _DiaryContentTab.companion)
            CompanionDiaryTodaySection(
              entryDate: selectedDate,
              entry: selectedCompanionDiary,
              entries: companionDiaryEntries,
              loading: companionDiaryLoading,
              error: companionDiaryError,
              onSave: onSaveCompanionDiary,
              onDelete: onDeleteCompanionDiary,
            )
          else
            _SelectedDayEmotionList(
              date: selectedDate,
              today: today,
              marks: selectedMarks,
              eventById: eventById,
              onOpenEventDetail: onOpenEventDetail,
              loading: loading,
              hasError: hasError,
            ),
        ],
      ),
    );
  }
}

class _DiaryContentTabBar extends StatelessWidget {
  const _DiaryContentTabBar({required this.selected, required this.onSelect});

  final _DiaryContentTab selected;
  final ValueChanged<_DiaryContentTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.parchmentCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xAA8E6F48), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DiaryContentTabButton(
              label: '오늘의 신앙 기록',
              selected: selected == _DiaryContentTab.companion,
              onTap: () => onSelect(_DiaryContentTab.companion),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _DiaryContentTabButton(
              label: '오늘의 내 감정',
              selected: selected == _DiaryContentTab.emotion,
              onTap: () => onSelect(_DiaryContentTab.emotion),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryContentTabButton extends StatelessWidget {
  const _DiaryContentTabButton({
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
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brownWarm : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? AppShadows.sm : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.ink350,
              fontSize: 11.8,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarGridHorizontalDivider extends StatelessWidget {
  const _CalendarGridHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: const Color(0x228E6F48)),
    );
  }
}

class _CalendarGridVerticalDivider extends StatelessWidget {
  const _CalendarGridVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: const Color(0x228E6F48),
      ),
    );
  }
}

class _CalendarIconButton extends StatelessWidget {
  const _CalendarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null
            ? const Color(0x44E4DEC8)
            : AppColors.parchmentCard,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              icon,
              color: onTap == null ? AppColors.ink150 : AppColors.ink500,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarToggleButton extends StatelessWidget {
  const _CalendarToggleButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brownWarm.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.brownWarm2,
                size: 17,
              ),
              const SizedBox(width: 2),
              Text(
                expanded ? '접기' : '펼치기',
                style: const TextStyle(
                  color: AppColors.brownWarm2,
                  fontSize: 11.4,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final label in labels) ...[
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: label == '일'
                    ? AppColors.dangerBot
                    : label == '토'
                    ? AppColors.greenBot
                    : AppColors.ink300,
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          if (label != labels.last) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _EmotionCalendarDayCell extends StatelessWidget {
  const _EmotionCalendarDayCell({
    required this.date,
    required this.focusedMonth,
    required this.selected,
    required this.today,
    required this.marks,
    required this.hasCompanionDiary,
    required this.compact,
    required this.onTap,
  });

  final DateTime date;
  final DateTime focusedMonth;
  final bool selected;
  final bool today;
  final List<EventEmotionMark> marks;
  final bool hasCompanionDiary;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inFocusedMonth = _isSameMonth(date, focusedMonth);
    final visibleMarks = marks.length > _calendarVisibleEmotionMarksBeforeMore
        ? marks.take(_calendarVisibleEmotionMarksBeforeMore).toList()
        : marks;
    final remainingCount = marks.length > _calendarVisibleEmotionMarksBeforeMore
        ? marks.length - _calendarVisibleEmotionMarksBeforeMore
        : 0;
    final textColor = selected
        ? AppColors.ink900
        : inFocusedMonth
        ? AppColors.ink700
        : AppColors.ink150;

    return Semantics(
      button: true,
      selected: selected,
      label: '${date.month}월 ${date.day}일',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey(
            'emotion-calendar-day-${date.year}-${date.month}-${date.day}',
          ),
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.fromLTRB(4, compact ? 4 : 5, 4, 5),
          decoration: selected
              ? BoxDecoration(
                  color: AppColors.greenTint2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.greenBot.withAlpha(0x66),
                    width: 1,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DayNumber(
                day: date.day,
                today: today,
                selected: selected,
                color: textColor,
                hasCompanionDiary: hasCompanionDiary,
                dayNumberKey: ValueKey(
                  'emotion-calendar-day-number-${date.year}-${date.month}-${date.day}',
                ),
                markerKey: ValueKey(
                  'companion-diary-marker-${date.year}-${date.month}-${date.day}',
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 5),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _CalendarEmotionMarkGrid(
                      visibleMarks: visibleMarks,
                      remainingCount: remainingCount,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarEmotionMarkGrid extends StatelessWidget {
  const _CalendarEmotionMarkGrid({
    required this.visibleMarks,
    required this.remainingCount,
  });

  final List<EventEmotionMark> visibleMarks;
  final int remainingCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 2.0;
        final maxSlotSize =
            (constraints.maxWidth -
                spacing * (_calendarEmotionSlotsPerRow - 1)) /
            _calendarEmotionSlotsPerRow;
        final slotSize = math.min(18.0, math.max(12.0, maxSlotSize));

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final mark in visibleMarks)
              _TinyEmotionMarkBadge(mark: mark, size: slotSize),
            if (remainingCount > 0)
              _MoreEmotionMarkBadge(count: remainingCount, size: slotSize),
          ],
        );
      },
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.day,
    required this.today,
    required this.selected,
    required this.color,
    required this.hasCompanionDiary,
    required this.dayNumberKey,
    required this.markerKey,
  });

  final int day;
  final bool today;
  final bool selected;
  final Color color;
  final bool hasCompanionDiary;
  final Key dayNumberKey;
  final Key markerKey;

  @override
  Widget build(BuildContext context) {
    final child = _DayNumberText(
      day: day,
      today: today,
      selected: selected,
      color: color,
    );
    final content = SizedBox(
      key: dayNumberKey,
      width: hasCompanionDiary
          ? _calendarDayNumberWithMarkerWidth
          : _calendarDayNumberSize,
      height: _calendarDayNumberSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          child,
          if (hasCompanionDiary)
            Positioned(
              top: -2,
              right: 0,
              child: _CalendarCompanionDiaryMarker(key: markerKey),
            ),
        ],
      ),
    );
    return SizedBox(
      height: _calendarDayNumberSize,
      child: Center(child: content),
    );
  }
}

class _CalendarCompanionDiaryMarker extends StatelessWidget {
  const _CalendarCompanionDiaryMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.greenTint1,
        border: Border.all(color: AppColors.greenBot.withAlpha(0x55)),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('📝', style: TextStyle(fontSize: 8.5, height: 1)),
      ),
    );
  }
}

class _DayNumberText extends StatelessWidget {
  const _DayNumberText({
    required this.day,
    required this.today,
    required this.selected,
    required this.color,
  });

  final int day;
  final bool today;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '$day',
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: today ? AppColors.ink900 : color,
        fontSize: 11.6,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    );
    final fittedText = FittedBox(fit: BoxFit.scaleDown, child: text);
    if (!today) {
      return SizedBox(
        width: _calendarDayNumberSize,
        height: _calendarDayNumberSize,
        child: Center(child: fittedText),
      );
    }
    return Container(
      width: _calendarDayNumberSize,
      height: _calendarDayNumberSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.transparent : AppColors.parchmentCream,
        border: Border.all(color: AppColors.goldDeep, width: 1.1),
      ),
      child: Center(child: fittedText),
    );
  }
}

class _TinyEmotionMarkBadge extends StatelessWidget {
  const _TinyEmotionMarkBadge({required this.mark, required this.size});

  final EventEmotionMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: mark.emotionLabel,
      child: EmotionBadgeIcon(
        emotionKey: mark.emotionKey,
        size: size,
        iconSize: size * 0.58,
        elevation: false,
      ),
    );
  }
}

class _MoreEmotionMarkBadge extends StatelessWidget {
  const _MoreEmotionMarkBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.parchmentCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x77A8834D), width: 0.8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '+$count',
          maxLines: 1,
          style: const TextStyle(
            color: AppColors.ink400,
            fontSize: 8.0,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _SelectedDayEmotionList extends StatelessWidget {
  const _SelectedDayEmotionList({
    required this.date,
    required this.today,
    required this.marks,
    required this.eventById,
    required this.onOpenEventDetail,
    required this.loading,
    required this.hasError,
  });

  final DateTime date;
  final DateTime today;
  final List<EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final sorted = [...marks]..sort(_compareMarksNewestFirst);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading && sorted.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
          )
        else if (sorted.isEmpty)
          _EmotionDiaryEmptyMessage(
            message: _isSameDate(date, today)
                ? '오늘 새긴 감정이 없습니다.\n이야기를 마치고 마음에 남은 감정을 남겨보세요.'
                : '이 날에 새긴 감정이 없습니다.',
          )
        else ...[
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const Divider(height: 16, color: Color(0x55BCA47A)),
            _SelectedEmotionRow(
              mark: sorted[i],
              event: eventById[sorted[i].eventId],
              onOpenEventDetail: onOpenEventDetail,
            ),
          ],
          if (hasError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '일부 이야기 정보를 불러오지 못했습니다.',
                style: TextStyle(
                  color: AppColors.dangerBot,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SelectedEmotionRow extends StatelessWidget {
  const _SelectedEmotionRow({
    required this.mark,
    required this.event,
    required this.onOpenEventDetail,
  });

  final EventEmotionMark mark;
  final StoryEvent? event;
  final ValueChanged<StoryEvent> onOpenEventDetail;

  @override
  Widget build(BuildContext context) {
    final note = mark.note.trim().isEmpty
        ? '${mark.emotionLabel}으로 새겼어요.'
        : mark.note.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: event == null ? null : () => onOpenEventDetail(event!),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              EmotionBadgeIcon(
                emotionKey: mark.emotionKey,
                size: 28,
                iconSize: 16,
                elevation: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event?.title ?? '이야기 정보를 불러오는 중',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink200,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          mark.emotionLabel,
                          style: const TextStyle(
                            color: AppColors.greenBot,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink700,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (event != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.ink200,
                  size: 19,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmotionDiaryEmptyMessage extends StatelessWidget {
  const _EmotionDiaryEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.ink300,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

Map<DateTime, List<EventEmotionMark>> _groupMarksByKstDate(
  Iterable<EventEmotionMark> marks, {
  required DateTime nowUtc,
}) {
  final grouped = <DateTime, List<EventEmotionMark>>{};
  for (final mark in marks) {
    final date = _markKstDate(mark, nowUtc: nowUtc);
    (grouped[date] ??= <EventEmotionMark>[]).add(mark);
  }
  for (final dayMarks in grouped.values) {
    dayMarks.sort(_compareMarksNewestFirst);
  }
  return grouped;
}

Map<DateTime, UserCompanionDiaryEntry> _groupCompanionDiaryEntriesByDate(
  Iterable<UserCompanionDiaryEntry> entries,
) {
  final grouped = <DateTime, UserCompanionDiaryEntry>{};
  for (final entry in entries) {
    final date = _dateOnly(entry.entryDate);
    final existing = grouped[date];
    if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
      grouped[date] = entry;
    }
  }
  return grouped;
}

DateTime _markKstDate(EventEmotionMark mark, {required DateTime nowUtc}) {
  final updatedAt = mark.updatedAt;
  if (updatedAt == null) {
    return _dateOnly(toKst(nowUtc));
  }
  return _dateOnly(kstDateForDisplay(updatedAt, now: nowUtc));
}

int _compareMarksNewestFirst(EventEmotionMark a, EventEmotionMark b) {
  final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final timeCompare = bTime.compareTo(aTime);
  if (timeCompare != 0) return timeCompare;
  return a.eventId.compareTo(b.eventId);
}

List<DateTime> _twoWeekVisibleDates(DateTime selectedDate) {
  final start = _weekStartSunday(selectedDate);
  final previousStart = start.subtract(const Duration(days: 7));
  return [for (var i = 0; i < 14; i++) previousStart.add(Duration(days: i))];
}

List<DateTime> _monthVisibleDates(DateTime month) {
  final firstDay = _monthStart(month);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  final start = _weekStartSunday(firstDay);
  final end = _weekStartSunday(lastDay).add(const Duration(days: 6));
  final dates = <DateTime>[];
  for (
    var date = start;
    !date.isAfter(end);
    date = date.add(const Duration(days: 1))
  ) {
    dates.add(date);
  }
  return dates;
}

DateTime _weekStartSunday(DateTime date) {
  return _dateOnly(date).subtract(Duration(days: date.weekday % 7));
}

DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

const double _emptyCalendarWeekHeight = 36;
const double _oneLineCalendarWeekHeight = 56;
const double _twoLineCalendarWeekHeight = 76;
const double _calendarDayNumberSize = 24;
const double _calendarDayNumberWithMarkerWidth = 32;
const int _calendarEmotionSlotsPerRow = 2;
const int _calendarMaxVisibleEmotionSlots = 4;
const int _calendarVisibleEmotionMarksBeforeMore = 3;

double _calendarWeekRowHeight(
  List<DateTime> weekDates,
  Map<DateTime, List<EventEmotionMark>> marksByDate,
) {
  return switch (_calendarWeekEmotionLineCount(weekDates, marksByDate)) {
    0 => _emptyCalendarWeekHeight,
    1 => _oneLineCalendarWeekHeight,
    _ => _twoLineCalendarWeekHeight,
  };
}

int _calendarWeekEmotionLineCount(
  List<DateTime> weekDates,
  Map<DateTime, List<EventEmotionMark>> marksByDate,
) {
  var maxVisibleSlots = 0;
  for (final date in weekDates) {
    final markCount = marksByDate[_dateOnly(date)]?.length ?? 0;
    final visibleSlots = markCount >= _calendarMaxVisibleEmotionSlots
        ? _calendarMaxVisibleEmotionSlots
        : markCount;
    maxVisibleSlots = math.max(maxVisibleSlots, visibleSlots);
  }
  return (maxVisibleSlots / _calendarEmotionSlotsPerRow).ceil().clamp(0, 2);
}
