import '../models/event_emotion_mark.dart';
import 'kst_date.dart';

const dailyExplorationBlessingMessage = '오늘 새긴 감정을 가지고 주님과 함께하는 복된 하루 되세요!';

const dailyExplorationRevisitMessage =
    '이전에 느꼈던 성경 사건의 감정이 지금 나에게도 동일하게 와닿는지 다시 탐험해보시는 건 어떨까요?';

enum DailyExplorationCardNoteKind { blessing, revisit }

class DailyExplorationCardNote {
  const DailyExplorationCardNote({required this.kind, required this.message});

  final DailyExplorationCardNoteKind kind;
  final String message;
}

DailyExplorationCardNote? dailyExplorationCardNoteFor({
  required EventEmotionMark? mark,
  required DateTime now,
}) {
  if (mark == null) {
    return null;
  }
  if (_isSameKstDate(mark.updatedAt, now)) {
    return const DailyExplorationCardNote(
      kind: DailyExplorationCardNoteKind.blessing,
      message: dailyExplorationBlessingMessage,
    );
  }
  return const DailyExplorationCardNote(
    kind: DailyExplorationCardNoteKind.revisit,
    message: dailyExplorationRevisitMessage,
  );
}

bool _isSameKstDate(DateTime? a, DateTime b) {
  if (a == null) {
    return false;
  }
  final left = toKst(a);
  final right = toKst(b);
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
