import '../models/story_event.dart';
import 'weekly_selection.dart';

/// KST 기준 날짜를 'YYYY-M-D' 형식의 매일 미션 키로 변환한다.
String dailyExplorationKeyForKst(DateTime instant) {
  final kst = instant.toUtc().add(const Duration(hours: 9));
  return '${kst.year}-${kst.month}-${kst.day}';
}

/// 날짜 키가 같으면 모든 사용자에게 같은 오늘의 사건을 제공한다.
StoryEvent? pickDailyExplorationEvent({
  required List<StoryEvent> events,
  required String dayKey,
}) {
  if (events.isEmpty) return null;
  final ordered = [...events]
    ..sort((a, b) {
      final rank = a.globalRank.compareTo(b.globalRank);
      if (rank != 0) return rank;
      return a.id.compareTo(b.id);
    });
  final seed = seedFromKey('daily-exploration:$dayKey');
  return ordered[seed % ordered.length];
}
