import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/services/app_analytics_event.dart';

void main() {
  group('AppAnalyticsEvent', () {
    test('기능 분석 이벤트 이름 7개를 고정한다', () {
      expect(AppAnalyticsEvent.names, {
        'story_opened',
        'quiz_completed',
        'emotion_mark_saved',
        'story_completed',
        'diary_entry_saved',
        'bible_chapter_completed',
        'account_created',
      });
      for (final name in AppAnalyticsEvent.names) {
        expect(name, matches(RegExp(r'^[a-z][a-z0-9_]{0,39}$')));
      }
    });

    test('이야기 열기는 콘텐츠 ID와 허용된 진입점만 기록한다', () {
      final event = AppAnalyticsEvent.storyOpened(
        eventId: ' story-1 ',
        entryPoint: 'unexpected-screen',
      );

      expect(event.name, 'story_opened');
      expect(event.parameters, {'event_id': 'story-1', 'entry_point': 'other'});
    });

    test('퀴즈 완료는 점수 요약만 기록하고 답안은 받지 않는다', () {
      final event = AppAnalyticsEvent.quizCompleted(
        eventId: 'story-1',
        correctCount: 9,
        totalCount: 3,
      );

      expect(event.name, 'quiz_completed');
      expect(event.parameters, {
        'event_id': 'story-1',
        'correct_count': 3,
        'total_count': 3,
      });
    });

    test('다이어리는 작성 내용이나 날짜 없이 생성·수정 여부만 기록한다', () {
      final created = AppAnalyticsEvent.diaryEntrySaved(isUpdate: false);
      final updated = AppAnalyticsEvent.diaryEntrySaved(isUpdate: true);

      expect(created.parameters, {'entry_mode': 'create'});
      expect(updated.parameters, {'entry_mode': 'update'});
    });

    test('감정·완료·통독·계정 이벤트에 민감한 작성 내용을 넣지 않는다', () {
      final events = [
        AppAnalyticsEvent.emotionMarkSaved(eventId: 'story-1'),
        AppAnalyticsEvent.storyCompleted(eventId: 'story-1'),
        AppAnalyticsEvent.bibleChapterCompleted(),
        AppAnalyticsEvent.accountCreated(),
      ];

      const forbiddenKeys = {
        'user_id',
        'email',
        'note',
        'body',
        'title',
        'emotion_key',
        'book_no',
        'chapter_no',
      };
      for (final event in events) {
        expect(
          event.parameters.keys.toSet().intersection(forbiddenKeys),
          isEmpty,
        );
      }
    });
  });
}
