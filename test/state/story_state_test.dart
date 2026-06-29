import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/state/story_state.dart';

void main() {
  group('StoryState 기본값', () {
    test('기본 생성 시 모든 필드가 초기값을 가진다', () {
      const state = StoryState();
      expect(state.loading, false);
      expect(state.error, isNull);
      expect(state.eras, isEmpty);
      expect(state.characters, isEmpty);
      expect(state.events, isEmpty);
      expect(state.selectedEraId, isNull);
      expect(state.selectedCharacterCodes, isEmpty);
      expect(state.selectedCharacterColors, isEmpty);
      expect(state.selectedEventId, isNull);
      expect(state.completedEventIds, isEmpty);
      expect(state.eventEmotionMarks, isEmpty);
      expect(state.savedEventIds, isEmpty);
      expect(state.completedBibleChapterKeys, isEmpty);
      expect(state.searchQuery, '');
      expect(state.searchResults, isEmpty);
      expect(state.isSearching, false);
      expect(state.selectedTestament, 'old');
    });
  });

  group('StoryState.copyWith', () {
    test('값을 전달하면 해당 필드만 변경한다', () {
      const original = StoryState();
      final updated = original.copyWith(
        loading: true,
        selectedTestament: 'new',
        searchQuery: '모세',
      );
      expect(updated.loading, true);
      expect(updated.selectedTestament, 'new');
      expect(updated.searchQuery, '모세');
      // 나머지는 원래 값 유지
      expect(updated.error, isNull);
      expect(updated.eras, isEmpty);
      expect(updated.isSearching, false);
    });

    test('값을 전달하지 않으면 원래 값을 유지한다', () {
      const original = StoryState(
        loading: true,
        error: '에러',
        selectedEraId: 'e1',
        selectedEventId: 'ev1',
      );
      final copy = original.copyWith();
      expect(copy.loading, true);
      expect(copy.error, '에러');
      expect(copy.selectedEraId, 'e1');
      expect(copy.selectedEventId, 'ev1');
    });

    test('clearError=true이면 error를 null로 초기화한다', () {
      const state = StoryState(error: '무언가 실패');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('clearError=true이면서 error 전달 시 clearError가 우선', () {
      const state = StoryState(error: '구 에러');
      final cleared = state.copyWith(clearError: true, error: '신 에러');
      expect(cleared.error, isNull);
    });

    test('clearSelectedEra=true이면 selectedEraId를 null로 초기화한다', () {
      const state = StoryState(selectedEraId: 'e1');
      final cleared = state.copyWith(clearSelectedEra: true);
      expect(cleared.selectedEraId, isNull);
    });

    test('clearSelectedEvent=true이면 selectedEventId를 null로 초기화한다', () {
      const state = StoryState(selectedEventId: 'ev1');
      final cleared = state.copyWith(clearSelectedEvent: true);
      expect(cleared.selectedEventId, isNull);
    });

    test('selectedCharacterCodes는 Set으로 교체된다', () {
      const original = StoryState();
      final updated = original.copyWith(selectedCharacterCodes: {'p1', 'p2'});
      expect(updated.selectedCharacterCodes, {'p1', 'p2'});
    });

    test('selectedCharacterColors는 Map으로 교체된다', () {
      const original = StoryState();
      final updated = original.copyWith(
        selectedCharacterColors: {'p1': Colors.red},
      );
      expect(updated.selectedCharacterColors['p1'], Colors.red);
    });

    test('completedEventIds를 교체할 수 있다', () {
      const original = StoryState();
      final updated = original.copyWith(
        completedEventIds: {'ev1', 'ev2', 'ev3'},
      );
      expect(updated.completedEventIds.length, 3);
      expect(updated.completedEventIds.contains('ev2'), true);
    });

    test('eventEmotionMarks를 교체할 수 있다', () {
      const original = StoryState();
      const mark = EventEmotionMark(
        eventId: 'ev1',
        emotionKey: 'joy',
        emotionLabel: '기쁨',
        emotionEmoji: '🌟',
        note: '기쁨이 남았다.',
        updatedAt: null,
      );
      final updated = original.copyWith(eventEmotionMarks: const {'ev1': mark});
      expect(updated.eventEmotionMarks['ev1']?.emotionEmoji, '🌟');
    });

    test('savedEventIds를 교체할 수 있다', () {
      const original = StoryState();
      final updated = original.copyWith(savedEventIds: {'ev1', 'ev2'});
      expect(updated.savedEventIds, {'ev1', 'ev2'});
    });

    test('completedBibleChapterKeys를 교체할 수 있다', () {
      const original = StoryState();
      final updated = original.copyWith(
        completedBibleChapterKeys: {'1:1', '1:2'},
      );
      expect(updated.completedBibleChapterKeys, {'1:1', '1:2'});
    });

    test('eras를 교체할 수 있다', () {
      const original = StoryState();
      final era = Era.fromMap({
        'id': 'e1',
        'code': 'creation',
        'name': '창조',
        'display_order': 1,
      });
      final updated = original.copyWith(eras: [era]);
      expect(updated.eras.length, 1);
      expect(updated.eras.first.name, '창조');
    });

    test('displayedEventIds 기본값은 빈 Set 이다', () {
      const state = StoryState();
      expect(state.displayedEventIds, isEmpty);
    });

    test('displayedEventIds 를 Set 으로 교체할 수 있다', () {
      const original = StoryState();
      final updated = original.copyWith(
        displayedEventIds: {'ev1', 'ev2', 'ev3'},
      );
      expect(updated.displayedEventIds.length, 3);
      expect(updated.displayedEventIds.contains('ev2'), true);
    });

    test('displayedEventIds 를 빈 Set 으로 클리어할 수 있다', () {
      const original = StoryState(displayedEventIds: {'ev1', 'ev2'});
      final cleared = original.copyWith(displayedEventIds: const <String>{});
      expect(cleared.displayedEventIds, isEmpty);
    });
  });
}
