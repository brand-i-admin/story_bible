import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/story_event.dart';

StoryEvent _event({
  String id = 'e1',
  String title = '',
  String? summary,
  String? story,
  String? shortStory,
  String? placeName,
}) {
  return StoryEvent(
    id: id,
    code: id,
    displayNumber: '001',
    eraId: 'era1',
    title: title,
    summary: summary,
    story: story,
    shortStory: shortStory,
    storyScenes: null,
    timelineRank: 1.0,
    startYear: null,
    endYear: null,
    timeSortKey: 0,
    placeName: placeName,
    lat: null,
    lng: null,
    personIds: const [],
    bibleRefs: const [],
    thumbUrl: null,
    storyAssetDir: null,
    storyThumbnailDir: null,
    storySceneCount: 0,
  );
}

void main() {
  group('storyEventFromRow', () {
    test('기본 필드를 모두 올바르게 파싱한다', () {
      final row = <String, dynamic>{
        'id': 'e1',
        'code': 'evt_001',
        'display_number': '001',
        'era_id': 'era_primeval',
        'title': '창조',
        'summary': '7일과 안식',
        'story': null,
        'short_story': null,
        'story_scenes': null,
        'timeline_rank': 1.0,
        'start_year': -4000,
        'end_year': -4000,
        'time_sort_key': 1000,
        'place_name': '메소포타미아',
        'lat': 31.018,
        'lng': 47.423,
        'event_persons': [
          {'person_id': 'god'},
        ],
      };

      final event = storyEventFromRow(row);

      expect(event.id, 'e1');
      expect(event.code, 'evt_001');
      expect(event.title, '창조');
      expect(event.summary, '7일과 안식');
      expect(event.lat, 31.018);
      expect(event.personIds, ['god']);
      expect(event.bibleRefs, isEmpty);
    });

    test('event_persons가 null이면 빈 personIds를 반환한다', () {
      final row = <String, dynamic>{
        'id': 'e1',
        'code': 'e1',
        'display_number': '001',
        'era_id': 'era1',
        'title': 't',
        'summary': null,
        'story': null,
        'short_story': null,
        'story_scenes': null,
        'timeline_rank': 1.0,
        'start_year': null,
        'end_year': null,
        'time_sort_key': 0,
        'place_name': null,
        'lat': null,
        'lng': null,
        'event_persons': null,
      };
      final event = storyEventFromRow(row);
      expect(event.personIds, isEmpty);
    });

    test('includeBibleRefs=true면 event_bible_refs를 반영한다', () {
      final row = <String, dynamic>{
        'id': 'e1',
        'code': 'e1',
        'display_number': '001',
        'era_id': 'era1',
        'title': 't',
        'summary': null,
        'story': null,
        'short_story': null,
        'story_scenes': null,
        'timeline_rank': 1.0,
        'start_year': null,
        'end_year': null,
        'time_sort_key': 0,
        'place_name': null,
        'lat': null,
        'lng': null,
        'event_persons': const [],
        'event_bible_refs': [
          {'display_text': '창 1:1-2:3'},
          {'display_text': '요 1:1'},
        ],
      };
      final event = storyEventFromRow(row, includeBibleRefs: true);
      expect(event.bibleRefs, ['창 1:1-2:3', '요 1:1']);
    });

    test('int 좌표를 double로 변환한다', () {
      final row = <String, dynamic>{
        'id': 'e1',
        'code': 'e1',
        'display_number': '001',
        'era_id': 'era1',
        'title': 't',
        'summary': null,
        'story': null,
        'short_story': null,
        'story_scenes': null,
        'timeline_rank': 1.0,
        'start_year': null,
        'end_year': null,
        'time_sort_key': 0,
        'place_name': null,
        'lat': 31, // int
        'lng': 47, // int
        'event_persons': const [],
      };
      final event = storyEventFromRow(row);
      expect(event.lat, 31.0);
      expect(event.lng, 47.0);
    });
  });

  group('scoreEventMatch', () {
    test('제목 완전 일치 시 기본 120 + 보너스 40 + 토큰 25 = 185', () {
      final event = _event(title: '창조');
      final score = scoreEventMatch(event, '창조', ['창조']);
      expect(score, 185);
    });

    test('shortStory가 가장 높은 가중치 (130)', () {
      final event = _event(title: '', shortStory: '창조');
      final score = scoreEventMatch(event, '창조', const []);
      expect(score, 130);
    });

    test('매치 없으면 0 반환', () {
      final event = _event(title: '출애굽');
      final score = scoreEventMatch(event, '창조', const ['창조']);
      expect(score, 0);
    });

    test('인물명 포함 시 쿼리 매치 80 + 토큰 매치 18 = 98', () {
      final event = _event(title: '');
      final score = scoreEventMatch(
        event,
        '모세',
        const ['모세'],
        personNames: const ['모세'],
      );
      expect(score, 98);
    });

    test('장소명 매치 시 쿼리 30 + 토큰 5 = 35', () {
      final event = _event(placeName: '애굽');
      final score = scoreEventMatch(event, '애굽', const ['애굽']);
      expect(score, 35);
    });

    test('대소문자 무시 (쿼리/토큰은 이미 소문자 가정)', () {
      final event = _event(title: 'Exodus');
      final score = scoreEventMatch(event, 'exodus', const ['exodus']);
      expect(score, greaterThan(0));
    });

    test('여러 토큰이 각각 매치되면 점수 누적', () {
      final event = _event(title: '출애굽기', summary: '모세 이야기');
      // query='출애굽 모세'는 title/summary에 통째로는 없지만 토큰별 매치
      final score = scoreEventMatch(event, '출애굽 모세', const ['출애굽', '모세']);
      // title '출애굽' 토큰 매치(25) + summary '모세' 토큰 매치(16) = 최소 41
      expect(score, greaterThanOrEqualTo(41));
    });
  });
}
