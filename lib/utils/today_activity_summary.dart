import '../models/event_emotion_mark.dart';
import '../models/user_companion_diary_entry.dart';
import 'kst_date.dart';

class TodayActivitySummary {
  const TodayActivitySummary({
    required this.streakDays,
    required this.explorationCount,
    required this.hasDiary,
    required this.bibleChapterCount,
  });

  static const empty = TodayActivitySummary(
    streakDays: 0,
    explorationCount: 0,
    hasDiary: false,
    bibleChapterCount: 0,
  );

  final int streakDays;
  final int explorationCount;
  final bool hasDiary;
  final int bibleChapterCount;
}

TodayActivitySummary summarizeTodayActivity({
  required DateTime now,
  required Map<String, EventEmotionMark> emotionMarks,
  required List<UserCompanionDiaryEntry> diaryEntries,
  required Map<String, DateTime?> bibleChapterReadAts,
}) {
  final today = _dateOnly(toKst(now));
  final explorationDates = emotionMarks.values
      .map((mark) => mark.updatedAt)
      .whereType<DateTime>()
      .map((updatedAt) => _dateOnly(toKst(updatedAt)))
      .toList(growable: false);
  final diaryDates = diaryEntries
      .map((entry) => _dateOnly(entry.entryDate))
      .toList(growable: false);
  final bibleDates = bibleChapterReadAts.values
      .whereType<DateTime>()
      .map((readAt) => _dateOnly(toKst(readAt)))
      .toList(growable: false);
  final activeDates = <DateTime>{
    ...explorationDates,
    ...diaryDates,
    ...bibleDates,
  };

  return TodayActivitySummary(
    streakDays: _currentStreakDays(activeDates: activeDates, today: today),
    explorationCount: explorationDates.where((date) => date == today).length,
    hasDiary: diaryDates.contains(today),
    bibleChapterCount: bibleDates.where((date) => date == today).length,
  );
}

int _currentStreakDays({
  required Set<DateTime> activeDates,
  required DateTime today,
}) {
  var cursor = activeDates.contains(today)
      ? today
      : today.subtract(const Duration(days: 1));
  if (!activeDates.contains(cursor)) {
    return 0;
  }
  var streak = 0;
  while (activeDates.contains(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
