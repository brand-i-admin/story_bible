import 'character.dart';
import 'story_event.dart';

/// 이 주(월요일 시작 기준)에 사용자가 학습할 인물과 사건 목록을 담는다.
///
/// [story_home_screen.dart]의 주간 탭에서 표시하는 데이터 구조다.
class WeeklyStudyData {
  const WeeklyStudyData({
    required this.character,
    required this.events,
    required this.weekStartMonday,
  });

  final Character character;
  final List<StoryEvent> events;
  final DateTime weekStartMonday;
}
