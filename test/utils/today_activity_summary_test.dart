import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/utils/today_activity_summary.dart';

void main() {
  test('KST 자정 기준으로 탐험·다이어리·통독 당일 수치를 집계한다', () {
    final summary = summarizeTodayActivity(
      now: DateTime.utc(2026, 7, 15, 15), // 7월 16일 00:00 KST
      emotionMarks: {
        'before-midnight': _emotionMark(
          eventId: 'before-midnight',
          updatedAt: DateTime.utc(2026, 7, 15, 14, 59),
        ),
        'today-1': _emotionMark(
          eventId: 'today-1',
          updatedAt: DateTime.utc(2026, 7, 15, 15),
        ),
        'today-2': _emotionMark(
          eventId: 'today-2',
          updatedAt: DateTime.utc(2026, 7, 15, 16),
        ),
      },
      diaryEntries: [
        _diaryEntry(DateTime(2026, 7, 16)),
        _diaryEntry(DateTime(2026, 7, 15), id: 'yesterday-diary'),
      ],
      bibleChapterReadAts: {
        '1:1': DateTime.utc(2026, 7, 15, 14, 59),
        '1:2': DateTime.utc(2026, 7, 15, 15),
        '1:3': DateTime.utc(2026, 7, 15, 17),
      },
    );

    expect(summary.explorationCount, 2);
    expect(summary.hasDiary, isTrue);
    expect(summary.bibleChapterCount, 2);
  });

  test('세 활동 중 하나라도 한 날짜를 합쳐 연속일을 계산한다', () {
    final summary = summarizeTodayActivity(
      now: DateTime.utc(2026, 7, 16, 3), // 7월 16일 12:00 KST
      emotionMarks: {
        'today': _emotionMark(
          eventId: 'today',
          updatedAt: DateTime.utc(2026, 7, 15, 16),
        ),
      },
      diaryEntries: [_diaryEntry(DateTime(2026, 7, 15))],
      bibleChapterReadAts: {
        '1:1': DateTime.utc(2026, 7, 13, 18), // 7월 14일 KST
      },
    );

    expect(summary.streakDays, 3);
  });

  test('자정 직후 당일 활동이 없어도 전날까지의 연속 기록은 유지한다', () {
    final summary = summarizeTodayActivity(
      now: DateTime.utc(2026, 7, 15, 15), // 7월 16일 00:00 KST
      emotionMarks: {
        'yesterday': _emotionMark(
          eventId: 'yesterday',
          updatedAt: DateTime.utc(2026, 7, 15, 10),
        ),
      },
      diaryEntries: [_diaryEntry(DateTime(2026, 7, 14))],
      bibleChapterReadAts: const {},
    );

    expect(summary.explorationCount, 0);
    expect(summary.hasDiary, isFalse);
    expect(summary.bibleChapterCount, 0);
    expect(summary.streakDays, 2);
  });

  test('오늘과 어제 모두 활동이 없으면 연속일은 0일이다', () {
    final summary = summarizeTodayActivity(
      now: DateTime.utc(2026, 7, 16, 3),
      emotionMarks: const {},
      diaryEntries: [_diaryEntry(DateTime(2026, 7, 14))],
      bibleChapterReadAts: const {},
    );

    expect(summary.streakDays, 0);
  });
}

EventEmotionMark _emotionMark({
  required String eventId,
  required DateTime updatedAt,
}) {
  return EventEmotionMark(
    eventId: eventId,
    emotionKey: 'joy',
    emotionLabel: '기쁨',
    emotionEmoji: '🌟',
    note: '',
    updatedAt: updatedAt,
  );
}

UserCompanionDiaryEntry _diaryEntry(DateTime entryDate, {String? id}) {
  return UserCompanionDiaryEntry(
    id: id ?? 'diary-${entryDate.toIso8601String()}',
    userId: 'user-1',
    entryDate: entryDate,
    title: '오늘의 기록',
    body: '함께 걸었습니다.',
    createdAt: entryDate,
    updatedAt: entryDate,
  );
}
