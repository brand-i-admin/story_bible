import 'package:flutter/foundation.dart';

/// Firebase Analytics로 보내는 기능 이벤트의 이름과 최소 파라미터 계약이다.
///
/// 사용자 ID, 이메일, 감정 메모, 다이어리 제목·본문은 이 객체가 받지 않는다.
@immutable
class AppAnalyticsEvent {
  const AppAnalyticsEvent._(this.name, this.parameters);

  static const names = <String>{
    'story_opened',
    'story_bible_read_completed',
    'quiz_completed',
    'emotion_engraving_started',
    'emotion_mark_saved',
    'story_completed',
    'diary_entry_saved',
    'bible_chapter_completed',
    'account_created',
  };

  static const _entryPoints = <String>{
    'today',
    'bible',
    'map',
    'profile',
    'search',
    'notification',
    'other',
  };

  final String name;
  final Map<String, Object> parameters;

  factory AppAnalyticsEvent.storyOpened({
    required String eventId,
    required String entryPoint,
  }) {
    final normalizedEntryPoint = entryPoint.trim().toLowerCase();
    return AppAnalyticsEvent._('story_opened', {
      'event_id': _contentId(eventId),
      'entry_point': _entryPoints.contains(normalizedEntryPoint)
          ? normalizedEntryPoint
          : 'other',
    });
  }

  factory AppAnalyticsEvent.storyBibleReadCompleted({required String eventId}) {
    return AppAnalyticsEvent._('story_bible_read_completed', {
      'event_id': _contentId(eventId),
    });
  }

  factory AppAnalyticsEvent.quizCompleted({
    required String eventId,
    int? correctCount,
    int? totalCount,
  }) {
    final normalizedTotal = totalCount == null || totalCount < 0
        ? null
        : totalCount;
    final normalizedCorrect = correctCount == null || normalizedTotal == null
        ? null
        : correctCount.clamp(0, normalizedTotal).toInt();
    return AppAnalyticsEvent._('quiz_completed', {
      'event_id': _contentId(eventId),
      if (normalizedCorrect != null) 'correct_count': normalizedCorrect,
      if (normalizedTotal != null) 'total_count': normalizedTotal,
    });
  }

  factory AppAnalyticsEvent.emotionEngravingStarted({required String eventId}) {
    return AppAnalyticsEvent._('emotion_engraving_started', {
      'event_id': _contentId(eventId),
    });
  }

  factory AppAnalyticsEvent.emotionMarkSaved({required String eventId}) {
    return AppAnalyticsEvent._('emotion_mark_saved', {
      'event_id': _contentId(eventId),
    });
  }

  factory AppAnalyticsEvent.storyCompleted({required String eventId}) {
    return AppAnalyticsEvent._('story_completed', {
      'event_id': _contentId(eventId),
    });
  }

  factory AppAnalyticsEvent.diaryEntrySaved({required bool isUpdate}) {
    return AppAnalyticsEvent._('diary_entry_saved', {
      'entry_mode': isUpdate ? 'update' : 'create',
    });
  }

  factory AppAnalyticsEvent.bibleChapterCompleted() {
    return const AppAnalyticsEvent._('bible_chapter_completed', {});
  }

  factory AppAnalyticsEvent.accountCreated() {
    return const AppAnalyticsEvent._('account_created', {});
  }

  static String _contentId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'unknown';
    }
    return trimmed.length <= 64 ? trimmed : trimmed.substring(0, 64);
  }
}
