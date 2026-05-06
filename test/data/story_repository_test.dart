import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/story_event.dart';

StoryEvent _event({
  String id = 'e1',
  String title = '',
  String? summary,
  String? placeName,
  List<String> storyScenes = const [],
  List<String> characterCodes = const [],
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_test',
    eraId: 'era1',
    title: title,
    summary: summary,
    storyScenes: storyScenes,
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 0,
    rankInEra: 0,
    globalRank: 0,
    placeName: placeName,
    lat: null,
    lng: null,
    characterCodes: characterCodes,
    bibleRefs: const <BibleRef>[],
  );
}

void main() {
  group('scoreEventMatch (new weights)', () {
    test('title 완전 일치 시 130 + 토큰 25 + 보너스 40 = 195', () {
      final event = _event(title: '창조');
      final score = scoreEventMatch(event, '창조', ['창조']);
      expect(score, 195);
    });

    test('summary 매치는 120 + 토큰 18 = 138', () {
      final event = _event(title: '', summary: '창조 이야기');
      final score = scoreEventMatch(event, '창조', ['창조']);
      expect(score, 138);
    });

    test('storyScenes 합본에서 매치되면 100 + 토큰 15 = 115', () {
      final event = _event(title: '', storyScenes: const ['빛이 임하며 어둠이 갈라진다']);
      final score = scoreEventMatch(event, '어둠', ['어둠']);
      expect(score, 115);
    });

    test('인물명 매치는 80 + 토큰 18 = 98', () {
      final event = _event(title: '');
      final score = scoreEventMatch(
        event,
        '모세',
        const ['모세'],
        characterNames: const ['모세'],
      );
      expect(score, 98);
    });

    test('장소명 매치는 30 + 토큰 5 = 35', () {
      final event = _event(placeName: '애굽');
      final score = scoreEventMatch(event, '애굽', const ['애굽']);
      expect(score, 35);
    });

    test('매치 없으면 0', () {
      final event = _event(title: '출애굽');
      final score = scoreEventMatch(event, '창조', const ['창조']);
      expect(score, 0);
    });

    test('대소문자 무시 (쿼리/토큰은 이미 소문자 가정)', () {
      final event = _event(title: 'Exodus');
      final score = scoreEventMatch(event, 'exodus', const ['exodus']);
      expect(score, greaterThan(0));
    });
  });
}
