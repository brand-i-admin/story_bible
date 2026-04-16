// 주간 학습 페이지에서 사용하는 순수 함수 모음.
//
// 모두 부수효과 없이 입력 → 출력만 수행.
// 원래 `_WeeklyTabPageState` 내부의 private 메소드들이었다.

/// 주어진 날짜의 같은 주 월요일 자정(시/분/초 0)을 반환.
DateTime weekStartMonday(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// 월요일 날짜를 'YYYY-M-D' 형식의 키로 변환.
/// 같은 주의 모든 사용자가 같은 인물을 받도록 시드 입력으로 사용.
String weeklyKeyFor(DateTime monday) {
  return '${monday.year}-${monday.month}-${monday.day}';
}

/// 주간 키에서 결정적 시드 값을 계산 (32-bit 양수 정수).
/// 같은 키 → 같은 시드 → 같은 인물 선택.
int seedFromKey(String key) {
  return key.codeUnits.fold<int>(
    0,
    (acc, value) => ((acc * 31) + value) & 0x7fffffff,
  );
}
