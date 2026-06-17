import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/story_event.dart';

StoryEvent _buildEvent({
  String? summary,
  double? lat,
  double? lng,
  List<String> storyScenes = const ['장면1'],
  List<List<String>> sceneCharacters = const [
    ['god'],
  ],
  List<String> characterCodes = const ['god'],
  List<BibleRef> bibleRefs = const [
    BibleRef(book: '창', from: '1:1', to: '2:3'),
  ],
  int rankInEra = 1,
  int globalRank = 1,
}) {
  return StoryEvent(
    id: 'e1',
    landmarkId: 'lm_test',
    eraId: 'era_primeval',
    title: '001 창조: 7일과 안식',
    summary: summary,
    storyScenes: storyScenes,
    sceneCharacters: sceneCharacters,
    startYear: -4000,
    endYear: -4000,
    timePrecision: 'approx',
    storyIndex: 1,
    rankInEra: rankInEra,
    globalRank: globalRank,
    placeName: '메소포타미아',
    lat: lat,
    lng: lng,
    characterCodes: characterCodes,
    bibleRefs: bibleRefs,
  );
}

void main() {
  group('StoryEvent', () {
    group('shortSummary', () {
      test('summary가 있으면 그대로 반환', () {
        final event = _buildEvent(summary: '하나님이 세상을 창조하신다.');
        expect(event.shortSummary, '하나님이 세상을 창조하신다.');
      });

      test('summary가 비어 있으면 기본 메시지', () {
        final event = _buildEvent();
        expect(event.shortSummary, '요약 정보가 없습니다.');
      });
    });

    group('hasCoordinate / latLng', () {
      test('lat/lng이 모두 있으면 hasCoordinate는 true', () {
        final event = _buildEvent(lat: 31.0, lng: 47.0);
        expect(event.hasCoordinate, isTrue);
        expect(event.latLng.latitude, 31.0);
        expect(event.latLng.longitude, 47.0);
      });

      test('lat이 null이면 hasCoordinate는 false', () {
        final event = _buildEvent(lng: 47.0);
        expect(event.hasCoordinate, isFalse);
      });
    });

    group('fromMap', () {
      test('events_ordered view 행을 모두 파싱한다', () {
        final event = StoryEvent.fromMap(<String, dynamic>{
          'id': 'e1',
          'era_id': 'era_primeval',
          'title': '001 창조',
          'summary': '하나님이 세상을 창조하신다.',
          'story_scenes': <dynamic>['장면1', '장면2'],
          'scene_characters': <dynamic>[
            <dynamic>['god'],
            <dynamic>[],
          ],
          'character_codes': <dynamic>['god', 'adam'],
          'bible_refs': <dynamic>[
            {'book': '창', 'from': '1:1', 'to': '2:3'},
          ],
          'start_year': -4000,
          'end_year': -4000,
          'time_precision': 'approx',
          'story_index': 1,
          'unit_code': 'birth_early_ministry',
          'unit_title': '탄생과 초기 사역',
          'unit_order': 2,
          'rank_in_era': 1,
          'global_rank': 1,
          'place_name': '메소포타미아',
          'landmark_id': 'lm_test',
          'lat': 31.018,
          'lng': 47.423,
        });

        expect(event.id, 'e1');
        expect(event.title, '001 창조');
        expect(event.characterCodes, ['god', 'adam']);
        expect(event.storyScenes, ['장면1', '장면2']);
        expect(event.sceneCharacters, [
          ['god'],
          <String>[],
        ]);
        expect(event.bibleRefs, hasLength(1));
        expect(event.bibleRefs.single.displayText, '창 1:1-2:3');
        expect(event.unitCode, 'birth_early_ministry');
        expect(event.unitTitle, '탄생과 초기 사역');
        expect(event.unitOrder, 2);
        expect(event.rankInEra, 1);
        expect(event.globalRank, 1);
      });

      test('unit 컬럼이 없으면 전체 흐름 기본값을 사용한다', () {
        final event = StoryEvent.fromMap(<String, dynamic>{
          'id': 'e1',
          'era_id': 'era_primeval',
          'title': '001 창조',
          'summary': '하나님이 세상을 창조하신다.',
          'story_scenes': <dynamic>[],
          'scene_characters': <dynamic>[],
          'character_codes': <dynamic>[],
          'bible_refs': <dynamic>[],
          'story_index': 1,
          'rank_in_era': 1,
          'global_rank': 1,
          'landmark_id': 'lm_test',
        });

        expect(event.unitCode, 'default');
        expect(event.unitTitle, '전체 흐름');
        expect(event.unitOrder, 1);
      });

      test('character_codes가 null이면 빈 리스트', () {
        final event = StoryEvent.fromMap(<String, dynamic>{
          'id': 'e1',
          'era_id': 'era1',
          'title': 't',
          'summary': null,
          'story_scenes': null,
          'scene_characters': null,
          'character_codes': null,
          'bible_refs': null,
          'start_year': null,
          'end_year': null,
          'time_precision': null,
          'story_index': null,
          'rank_in_era': null,
          'global_rank': null,
          'place_name': null,
          'landmark_id': 'lm_test',
          'lat': null,
          'lng': null,
        });
        expect(event.characterCodes, isEmpty);
        expect(event.bibleRefs, isEmpty);
        expect(event.storyScenes, isEmpty);
        expect(event.sceneCharacters, isEmpty);
        expect(event.timePrecision, 'approx');
      });

      test('int 좌표를 double로 변환', () {
        final event = StoryEvent.fromMap(<String, dynamic>{
          'id': 'e1',
          'era_id': 'era1',
          'title': 't',
          'summary': null,
          'story_scenes': null,
          'scene_characters': null,
          'character_codes': null,
          'bible_refs': null,
          'start_year': null,
          'end_year': null,
          'time_precision': 'approx',
          'story_index': 0,
          'rank_in_era': 0,
          'global_rank': 0,
          'place_name': null,
          'landmark_id': 'lm_test',
          'lat': 31,
          'lng': 47,
        });
        expect(event.lat, 31.0);
        expect(event.lng, 47.0);
      });
    });
  });
}
