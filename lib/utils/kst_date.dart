const kstOffset = Duration(hours: 9);

DateTime toKst(DateTime dateTime) => dateTime.toUtc().add(kstOffset);

Duration durationUntilNextKstMidnight(DateTime now) {
  final nowUtc = now.toUtc();
  final nowKst = nowUtc.add(kstOffset);
  final nextKstMidnightUtc = DateTime.utc(
    nowKst.year,
    nowKst.month,
    nowKst.day + 1,
  ).subtract(kstOffset);
  return nextKstMidnightUtc.difference(nowUtc);
}

DateTime _dateOnly(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

DateTime kstDateForDisplay(DateTime dateTime, {DateTime? now}) {
  final kst = toKst(dateTime);
  final todayKst = toKst(now ?? DateTime.now());
  if (_dateOnly(kst).isAfter(_dateOnly(todayKst))) {
    return todayKst;
  }
  return kst;
}

String formatKoreanMonthDayKst(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) return '';
  final displayDate = kstDateForDisplay(dateTime, now: now);
  return '${displayDate.month}월 ${displayDate.day}일';
}
