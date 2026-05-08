import '../utils/weekly_selection.dart';
import 'character.dart';
import 'era.dart';
import 'landmark.dart';
import 'story_event.dart';

/// 이 주(월요일 시작 기준)에 사용자가 학습할 데이터.
///
/// 두 모드:
///  - [WeeklyMode.character]: `character` 가 채워지고 `events` 는 그 인물의 사건.
///  - [WeeklyMode.region]: `era` + `region` 이 채워지고 `events` 는 그 region 사건.
class WeeklyStudyData {
  const WeeklyStudyData.character({
    required Character this.character,
    required this.events,
    required this.weekStartMonday,
  }) : mode = WeeklyMode.character,
       era = null,
       region = null;

  const WeeklyStudyData.region({
    required Era this.era,
    required Landmark this.region,
    required this.events,
    required this.weekStartMonday,
  }) : mode = WeeklyMode.region,
       character = null;

  final WeeklyMode mode;

  /// `mode == character` 일 때만 non-null.
  final Character? character;

  /// `mode == region` 일 때만 non-null.
  final Era? era;

  /// `mode == region` 일 때만 non-null.
  final Landmark? region;

  final List<StoryEvent> events;
  final DateTime weekStartMonday;
}
