import 'package:flutter/material.dart';

import '../../models/event_emotion_mark.dart';
import '../../models/story_event.dart';
import '../../models/user_companion_diary_entry.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../utils/bible_book_meta.dart';
import '../../utils/kst_date.dart';
import '../emotion_badge_icon.dart';
import '../pulse_highlight.dart';
import 'companion_diary_entry_card.dart';
import 'profile_activity_badge.dart';
import 'profile_companion_diary.dart';

class ProfileBibleProgressSummary {
  const ProfileBibleProgressSummary({
    required this.completed,
    required this.total,
    required this.fraction,
    this.lastCompletedBookNo,
    this.lastCompletedChapterNo,
    this.completedToday = false,
  });

  final int completed;
  final int total;
  final double fraction;
  final int? lastCompletedBookNo;
  final int? lastCompletedChapterNo;
  final bool completedToday;

  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();

  String get chapterReferenceText {
    final bookNo = lastCompletedBookNo;
    final chapterNo = lastCompletedChapterNo;
    if (bookNo == null ||
        chapterNo == null ||
        bookNo < 1 ||
        bookNo > bibleBooks.length) {
      return '창세기 1장';
    }
    final maxChapter = bibleBooks[bookNo - 1].chapters;
    final safeChapterNo = chapterNo.clamp(1, maxChapter).toInt();
    return '${bibleBooks[bookNo - 1].name} $safeChapterNo장';
  }
}

class ProfileEmotionDiary extends StatefulWidget {
  const ProfileEmotionDiary({
    super.key,
    required this.eventEmotionMarks,
    this.completedBibleChapterReadAts = const <String, DateTime?>{},
    this.companionDiaryEntries = const <UserCompanionDiaryEntry>[],
    this.companionDiaryLoading = false,
    this.companionDiaryError,
    this.onSaveCompanionDiary,
    this.onDeleteCompanionDiary,
    this.bibleProgress,
    this.onOpenBibleProgress,
    this.onContinueBibleReading,
    this.now,
    this.featureCardsFirst = false,
    this.showFeatureCards = true,
    this.onSelectedDateChanged,
  });

  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, DateTime?> completedBibleChapterReadAts;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final CompanionDiarySaveCallback? onSaveCompanionDiary;
  final CompanionDiaryDeleteCallback? onDeleteCompanionDiary;
  final ProfileBibleProgressSummary? bibleProgress;
  final VoidCallback? onOpenBibleProgress;
  final VoidCallback? onContinueBibleReading;
  final DateTime? now;
  final bool featureCardsFirst;
  final bool showFeatureCards;
  final ValueChanged<DateTime>? onSelectedDateChanged;

  @override
  State<ProfileEmotionDiary> createState() => _ProfileEmotionDiaryState();
}

class _ProfileEmotionDiaryState extends State<ProfileEmotionDiary> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final today = _todayKst();
    _focusedMonth = _monthStart(today);
    _selectedDate = today;
  }

  @override
  void didUpdateWidget(covariant ProfileEmotionDiary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now) {
      final today = _todayKst();
      if (_selectedDate.isAfter(today)) {
        _selectedDate = today;
        _focusedMonth = _monthStart(today);
      }
    }
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
    final bibleReadingDates = _groupBibleReadingDates(
      widget.completedBibleChapterReadAts.values,
    );

    return _EmotionDiaryPanel(
      focusedMonth: _focusedMonth,
      selectedDate: _selectedDate,
      today: today,
      expanded: _expanded,
      marksByDate: marksByDate,
      companionDiaryByDate: companionDiaryByDate,
      bibleReadingDates: bibleReadingDates,
      companionDiaryEntries: widget.companionDiaryEntries,
      todayCompanionDiary: companionDiaryByDate[_dateOnly(today)],
      companionDiaryLoading: widget.companionDiaryLoading,
      companionDiaryError: widget.companionDiaryError,
      onToggleExpanded: () {
        DateTime? selectedDateAfterToggle;
        setState(() {
          final today = _todayKst();
          _expanded = !_expanded;
          _focusedMonth = _monthStart(today);
          if (!_expanded &&
              !_isWithinCollapsedVisibleRange(_selectedDate, today)) {
            _selectedDate = today;
          }
          selectedDateAfterToggle = _selectedDate;
        });
        final selected = selectedDateAfterToggle;
        if (selected != null) {
          widget.onSelectedDateChanged?.call(selected);
        }
      },
      onMoveMonth: _moveMonth,
      onSelectDate: _selectDate,
      onSaveCompanionDiary: widget.onSaveCompanionDiary,
      onDeleteCompanionDiary: widget.onDeleteCompanionDiary,
      bibleProgress: widget.bibleProgress,
      onOpenBibleProgress: widget.onOpenBibleProgress,
      onContinueBibleReading: widget.onContinueBibleReading,
      featureCardsFirst: widget.featureCardsFirst,
      showFeatureCards: widget.showFeatureCards,
    );
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
    widget.onSelectedDateChanged?.call(_selectedDate);
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
    widget.onSelectedDateChanged?.call(_selectedDate);
  }
}

class _EmotionDiaryPanel extends StatelessWidget {
  const _EmotionDiaryPanel({
    required this.focusedMonth,
    required this.selectedDate,
    required this.today,
    required this.expanded,
    required this.marksByDate,
    required this.companionDiaryByDate,
    required this.bibleReadingDates,
    required this.companionDiaryEntries,
    required this.todayCompanionDiary,
    required this.companionDiaryLoading,
    required this.companionDiaryError,
    required this.onToggleExpanded,
    required this.onMoveMonth,
    required this.onSelectDate,
    required this.onSaveCompanionDiary,
    required this.onDeleteCompanionDiary,
    required this.bibleProgress,
    required this.onOpenBibleProgress,
    required this.onContinueBibleReading,
    required this.featureCardsFirst,
    required this.showFeatureCards,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final DateTime today;
  final bool expanded;
  final Map<DateTime, List<EventEmotionMark>> marksByDate;
  final Map<DateTime, UserCompanionDiaryEntry> companionDiaryByDate;
  final Set<DateTime> bibleReadingDates;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final UserCompanionDiaryEntry? todayCompanionDiary;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onMoveMonth;
  final ValueChanged<DateTime> onSelectDate;
  final CompanionDiarySaveCallback? onSaveCompanionDiary;
  final CompanionDiaryDeleteCallback? onDeleteCompanionDiary;
  final ProfileBibleProgressSummary? bibleProgress;
  final VoidCallback? onOpenBibleProgress;
  final VoidCallback? onContinueBibleReading;
  final bool featureCardsFirst;
  final bool showFeatureCards;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final currentMonth = _monthStart(today);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final canGoNext = focusedMonth.isBefore(currentMonth);
    final visibleDates = expanded
        ? _monthVisibleDates(focusedMonth)
        : _collapsedVisibleDates(today);
    final featureCards = showFeatureCards
        ? ProfileDiaryFeatureCards(
            today: today,
            todayCompanionDiary: todayCompanionDiary,
            companionDiaryEntries: companionDiaryEntries,
            companionDiaryLoading: companionDiaryLoading,
            companionDiaryError: companionDiaryError,
            onSaveCompanionDiary: onSaveCompanionDiary,
            onDeleteCompanionDiary: onDeleteCompanionDiary,
            bibleProgress: bibleProgress,
            onOpenBibleProgress: onOpenBibleProgress,
            onContinueBibleReading: onContinueBibleReading,
          )
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.subtleBorder, width: 0.8),
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
          if (showFeatureCards && featureCardsFirst) ...[
            featureCards!,
            Divider(height: 22, color: palette.subtleBorder),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '${focusedMonth.year}년 ${focusedMonth.month}월',
                  maxLines: largeText ? 2 : 1,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: palette.text,
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
                  companionDiaryByDate,
                  bibleReadingDates,
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
                            hasBibleReading: bibleReadingDates.contains(
                              _dateOnly(date),
                            ),
                            compact: weekHeight == _emptyCalendarWeekHeight,
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
          if (showFeatureCards && !featureCardsFirst) ...[
            Divider(height: 22, color: palette.subtleBorder),
            featureCards!,
          ],
        ],
      ),
    );
  }
}

class ProfileDiaryFeatureCards extends StatelessWidget {
  const ProfileDiaryFeatureCards({
    super.key,
    required this.today,
    required this.todayCompanionDiary,
    required this.companionDiaryEntries,
    required this.companionDiaryLoading,
    required this.companionDiaryError,
    required this.onSaveCompanionDiary,
    required this.onDeleteCompanionDiary,
    required this.bibleProgress,
    required this.onOpenBibleProgress,
    required this.onContinueBibleReading,
    this.profileSummaryMode = false,
  });

  final DateTime today;
  final UserCompanionDiaryEntry? todayCompanionDiary;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final CompanionDiarySaveCallback? onSaveCompanionDiary;
  final CompanionDiaryDeleteCallback? onDeleteCompanionDiary;
  final ProfileBibleProgressSummary? bibleProgress;
  final VoidCallback? onOpenBibleProgress;
  final VoidCallback? onContinueBibleReading;
  final bool profileSummaryMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('profile-diary-feature-cards'),
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
        final cardWidth = (constraints.maxWidth - 10) / 2;
        final expandTextForNarrowLargeText = largeText && cardWidth < 176;
        final featureCardMinHeight = profileSummaryMode ? 138.0 : 158.0;
        final diaryCard = CompanionDiaryFeatureCard(
          entryDate: today,
          entry: todayCompanionDiary,
          entries: companionDiaryEntries,
          loading: companionDiaryLoading,
          error: companionDiaryError,
          onSave: onSaveCompanionDiary,
          onDelete: onDeleteCompanionDiary,
          minHeight: featureCardMinHeight,
          expandTextForNarrowLargeText: expandTextForNarrowLargeText,
          readOnlySummary: profileSummaryMode,
        );
        final bibleCard = _BibleProgressFeatureCard(
          summary: bibleProgress,
          onTapCard: onOpenBibleProgress,
          onContinue: onContinueBibleReading,
          minHeight: featureCardMinHeight,
          expandTextForNarrowLargeText: expandTextForNarrowLargeText,
          showContinueAction: !profileSummaryMode,
        );
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: diaryCard),
              const SizedBox(width: 10),
              Expanded(child: bibleCard),
            ],
          ),
        );
      },
    );
  }
}

class _BibleProgressFeatureCard extends StatelessWidget {
  const _BibleProgressFeatureCard({
    required this.summary,
    required this.onTapCard,
    required this.onContinue,
    required this.minHeight,
    required this.expandTextForNarrowLargeText,
    required this.showContinueAction,
  });

  final ProfileBibleProgressSummary? summary;
  final VoidCallback? onTapCard;
  final VoidCallback? onContinue;
  final double minHeight;
  final bool expandTextForNarrowLargeText;
  final bool showContinueAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final expandReadableText = largeText && expandTextForNarrowLargeText;
    final progress =
        summary ??
        const ProfileBibleProgressSummary(completed: 0, total: 0, fraction: 0);
    final fraction = progress.fraction.clamp(0.0, 1.0).toDouble();
    final darkSurface =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
        Brightness.dark;
    final readingAccent = palette.primaryDeep;
    final readingAccentSoft = palette.primary;
    final surfaceTop = Color.alphaBlend(
      readingAccent.withValues(alpha: darkSurface ? 0.18 : 0.10),
      darkSurface ? palette.cardSurface : AppColors.parchmentCream,
    );
    final surfaceBottom = Color.alphaBlend(
      readingAccentSoft.withValues(alpha: darkSurface ? 0.16 : 0.08),
      darkSurface ? palette.softSurface : AppColors.parchmentCard,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('bible-progress-feature-card'),
        onTap: onTapCard,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [surfaceTop, surfaceBottom],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.sm,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (showContinueAction)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 9,
                  child: Align(
                    alignment: Alignment.center,
                    child: PulseHighlight(
                      active: onContinue != null && !progress.completedToday,
                      pulseCount: null,
                      duration: const Duration(milliseconds: 2200),
                      borderRadius: BorderRadius.circular(999),
                      color: darkSurface
                          ? AppColors.goldLight
                          : AppColors.goldHi,
                      child: _BibleContinueButton(
                        onTap: onContinue,
                        completedToday: progress.completedToday,
                        readingAccent: readingAccent,
                        darkSurface: darkSurface,
                      ),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            readingAccent.withValues(
                              alpha: darkSurface ? 0.24 : 0.10,
                            ),
                            darkSurface
                                ? palette.softSurface
                                : AppColors.parchmentCream,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: readingAccent.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 14,
                          color: readingAccent,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '통독 진행률',
                          maxLines: expandReadableText ? 2 : 1,
                          overflow: expandReadableText
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          softWrap: true,
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: palette.mutedText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BibleProgressDonut(
                        fraction: fraction,
                        percent: progress.percent,
                        dimension: largeText ? 38 : 44,
                        color: readingAccent,
                      ),
                      SizedBox(width: largeText ? 7 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '마지막 통독 장',
                              maxLines: expandReadableText ? 2 : 1,
                              overflow: expandReadableText
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              softWrap: true,
                              style: TextStyle(
                                color: palette.mutedText,
                                fontSize: AppFontSizes.xs,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              progress.chapterReferenceText,
                              maxLines: largeText ? 2 : 1,
                              overflow: largeText
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              softWrap: true,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: largeText ? 12.2 : 12.8,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (showContinueAction) const SizedBox(height: 64),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BibleProgressDonut extends StatelessWidget {
  const _BibleProgressDonut({
    required this.fraction,
    required this.percent,
    required this.dimension,
    required this.color,
  });

  final double fraction;
  final int percent;
  final double dimension;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final darkSurface =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
        Brightness.dark;
    final trackColor = Color.alphaBlend(
      color.withValues(alpha: darkSurface ? 0.32 : 0.18),
      palette.cardSurface,
    );
    final progressColor = color;
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              key: const ValueKey('bible-progress-donut-indicator'),
              value: fraction,
              strokeWidth: 4.6,
              backgroundColor: trackColor,
              color: progressColor,
            ),
          ),
          Text(
            '$percent%',
            maxLines: 1,
            style: TextStyle(
              color: progressColor,
              fontSize: 11.2,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleContinueButton extends StatelessWidget {
  const _BibleContinueButton({
    required this.onTap,
    required this.completedToday,
    required this.readingAccent,
    required this.darkSurface,
  });

  final VoidCallback? onTap;
  final bool completedToday;
  final Color readingAccent;
  final bool darkSurface;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final enabled = onTap != null;
    final backgroundColor = !enabled
        ? palette.mutedSurface
        : completedToday
        ? palette.successBottom
        : Color.alphaBlend(
            readingAccent.withValues(alpha: darkSurface ? 0.32 : 0.16),
            palette.cardSurface,
          );
    final badgeColor = !enabled
        ? palette.mutedSurface
        : completedToday
        ? AppColors.fgOnDark
        : readingAccent;
    final badgeForegroundColor = !enabled
        ? palette.mutedText
        : completedToday
        ? palette.successBottom
        : AppColors.fgOnDark;
    final labelColor = !enabled
        ? palette.mutedText
        : completedToday || darkSurface
        ? AppColors.fgOnDark
        : readingAccent;
    return Material(
      key: const ValueKey('bible-progress-continue-button'),
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const ValueKey('bible-progress-continue-icon-badge'),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: enabled
                        ? readingAccent.withValues(alpha: 0.30)
                        : palette.subtleBorder,
                  ),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: badgeForegroundColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '이어읽기',
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 12.1,
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

class _CalendarGridHorizontalDivider extends StatelessWidget {
  const _CalendarGridHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: palette.subtleBorder),
    );
  }
}

class _CalendarGridVerticalDivider extends StatelessWidget {
  const _CalendarGridVerticalDivider();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: palette.subtleBorder,
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
    final palette = AppPaletteTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? palette.mutedSurface : palette.cardSurface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              icon,
              color: onTap == null
                  ? palette.mutedText.withValues(alpha: 0.42)
                  : palette.text,
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
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: palette.selectionFill,
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
                color: palette.primaryDeep,
                size: 17,
              ),
              const SizedBox(width: 2),
              Text(
                expanded ? '접기' : '펼치기',
                style: TextStyle(
                  color: palette.primaryDeep,
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
    final palette = AppPaletteTheme.of(context);
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
                    ? palette.successBottom
                    : palette.mutedText,
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
    required this.hasBibleReading,
    required this.compact,
    required this.onTap,
  });

  final DateTime date;
  final DateTime focusedMonth;
  final bool selected;
  final bool today;
  final List<EventEmotionMark> marks;
  final bool hasCompanionDiary;
  final bool hasBibleReading;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final inFocusedMonth = _isSameMonth(date, focusedMonth);
    final textColor = selected
        ? palette.text
        : inFocusedMonth
        ? palette.text.withValues(alpha: 0.86)
        : palette.mutedText.withValues(alpha: 0.46);

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
                  color: palette.selectionFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.selectedBorder, width: 1),
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
                dayNumberKey: ValueKey(
                  'emotion-calendar-day-number-${date.year}-${date.month}-${date.day}',
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _CalendarActivityMarkers(
                      date: date,
                      hasEmotion: marks.isNotEmpty,
                      hasBibleReading: hasBibleReading,
                      hasCompanionDiary: hasCompanionDiary,
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

class _CalendarActivityMarkers extends StatelessWidget {
  const _CalendarActivityMarkers({
    required this.date,
    required this.hasEmotion,
    required this.hasBibleReading,
    required this.hasCompanionDiary,
  });

  final DateTime date;
  final bool hasEmotion;
  final bool hasBibleReading;
  final bool hasCompanionDiary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final activityCount = [
      hasEmotion,
      hasBibleReading,
      hasCompanionDiary,
    ].where((value) => value).length;
    final dateKey = '${date.year}-${date.month}-${date.day}';
    if (activityCount == 3) {
      return Icon(
        Icons.check_rounded,
        key: ValueKey('calendar-all-actions-marker-$dateKey'),
        size: 21,
        color: palette.successBottom,
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasEmotion)
            ProfileActivityBadge(
              key: ValueKey('calendar-emotion-marker-$dateKey'),
              type: ProfileActivityBadgeType.emotion,
              size: 16,
              iconSize: 10,
            ),
          if (hasEmotion && (hasBibleReading || hasCompanionDiary))
            const SizedBox(width: 3),
          if (hasBibleReading)
            ProfileActivityBadge(
              key: ValueKey('bible-reading-marker-$dateKey'),
              type: ProfileActivityBadgeType.bibleReading,
              size: 16,
              iconSize: 10,
            ),
          if (hasBibleReading && hasCompanionDiary) const SizedBox(width: 3),
          if (hasCompanionDiary)
            ProfileActivityBadge(
              key: ValueKey('companion-diary-marker-$dateKey'),
              type: ProfileActivityBadgeType.companionDiary,
              size: 16,
              iconSize: 10,
            ),
        ],
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.day,
    required this.today,
    required this.selected,
    required this.color,
    required this.dayNumberKey,
  });

  final int day;
  final bool today;
  final bool selected;
  final Color color;
  final Key dayNumberKey;

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
      width: _calendarDayNumberSize,
      height: _calendarDayNumberSize,
      child: Center(child: child),
    );
    return SizedBox(
      height: _calendarDayNumberSize,
      child: Center(child: content),
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
    final palette = AppPaletteTheme.of(context);
    final text = Text(
      '$day',
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: today ? palette.text : color,
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
        color: selected ? Colors.transparent : palette.cardSurface,
        border: Border.all(color: palette.currentAccentDeep, width: 1.1),
      ),
      child: Center(child: fittedText),
    );
  }
}

class ProfileEmotionMarksList extends StatelessWidget {
  const ProfileEmotionMarksList({
    super.key,
    required this.marks,
    required this.eventById,
    required this.onOpenEventDetail,
    required this.loading,
    required this.hasError,
    required this.emptyMessage,
    this.showTimestamp = false,
  });

  final List<EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final bool loading;
  final bool hasError;
  final String emptyMessage;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
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
          _EmotionDiaryEmptyMessage(message: emptyMessage)
        else ...[
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) Divider(height: 16, color: palette.subtleBorder),
            _SelectedEmotionRow(
              mark: sorted[i],
              event: eventById[sorted[i].eventId],
              onOpenEventDetail: onOpenEventDetail,
              showTimestamp: showTimestamp,
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
    required this.showTimestamp,
  });

  final EventEmotionMark mark;
  final StoryEvent? event;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final note = mark.note.trim();
    final metaLabel = showTimestamp && mark.updatedAt != null
        ? _formatEmotionMarkDate(mark.updatedAt!)
        : '';
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
                            maxLines: largeText ? 2 : 1,
                            overflow: largeText
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            softWrap: true,
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (metaLabel.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Text(
                            metaLabel,
                            style: TextStyle(
                              color: palette.successBottom,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        maxLines: largeText ? null : 2,
                        overflow: largeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 13.2,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (event != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.mutedText,
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
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.mutedText,
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

Set<DateTime> _groupBibleReadingDates(Iterable<DateTime?> readAts) {
  return {
    for (final readAt in readAts)
      if (readAt != null) _dateOnly(toKst(readAt)),
  };
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

String _formatEmotionMarkDate(DateTime updatedAt) {
  final kst = toKst(updatedAt);
  return '${kst.month}월 ${kst.day}일';
}

List<DateTime> _collapsedVisibleDates(DateTime date) {
  final currentWeekStart = _weekStartSunday(date);
  final start = currentWeekStart.subtract(const Duration(days: 7));
  return [for (var i = 0; i < 14; i++) start.add(Duration(days: i))];
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

bool _isWithinCollapsedVisibleRange(DateTime date, DateTime today) {
  final start = _weekStartSunday(today).subtract(const Duration(days: 7));
  final end = start.add(const Duration(days: 13));
  final value = _dateOnly(date);
  return !value.isBefore(start) && !value.isAfter(end);
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
const double _calendarDayNumberSize = 24;

double _calendarWeekRowHeight(
  List<DateTime> weekDates,
  Map<DateTime, List<EventEmotionMark>> marksByDate,
  Map<DateTime, UserCompanionDiaryEntry> companionDiaryByDate,
  Set<DateTime> bibleReadingDates,
) {
  final hasRecord = weekDates.any((date) {
    final day = _dateOnly(date);
    return (marksByDate[day]?.isNotEmpty ?? false) ||
        companionDiaryByDate.containsKey(day) ||
        bibleReadingDates.contains(day);
  });
  return hasRecord ? _oneLineCalendarWeekHeight : _emptyCalendarWeekHeight;
}
