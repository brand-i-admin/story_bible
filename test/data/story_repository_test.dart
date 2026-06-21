import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/story_event.dart';

StoryEvent _event({
  String id = 'e1',
  String title = '',
  String? summary,
  String? backgroundContext,
  String? placeName,
  List<String> storyScenes = const [],
  List<String> characterCodes = const [],
  List<BibleRef> bibleRefs = const <BibleRef>[],
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_test',
    eraId: 'era1',
    title: title,
    summary: summary,
    backgroundContext: backgroundContext,
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
    bibleRefs: bibleRefs,
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

    test('backgroundContext 매치는 70 + 토큰 10 = 80', () {
      final event = _event(title: '', backgroundContext: '분열왕국 배경 지식');
      final score = scoreEventMatch(event, '분열왕국', ['분열왕국']);
      expect(score, 80);
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

  group('eventContainsBibleVerse', () {
    test('단일 절 참조가 선택 절과 일치하면 true', () {
      final event = _event(
        title: '니고데모를 만나다',
        bibleRefs: const [BibleRef(book: '요', from: '3:16', to: '3:16')],
      );

      expect(
        eventContainsBibleVerse(event, bookNo: 43, chapterNo: 3, verseNo: 16),
        isTrue,
      );
    });

    test('같은 장 범위 안의 절을 포함한다', () {
      final event = _event(
        title: '요셉이 유혹을 이기다',
        bibleRefs: const [BibleRef(book: '창', from: '39:1', to: '39:23')],
      );

      expect(
        eventContainsBibleVerse(event, bookNo: 1, chapterNo: 39, verseNo: 12),
        isTrue,
      );
      expect(
        eventContainsBibleVerse(event, bookNo: 1, chapterNo: 39, verseNo: 24),
        isFalse,
      );
    });

    test('여러 장에 걸친 범위 안의 절을 포함한다', () {
      final event = _event(
        title: '천지 창조',
        bibleRefs: const [BibleRef(book: '창', from: '1:31', to: '2:3')],
      );

      expect(
        eventContainsBibleVerse(event, bookNo: 1, chapterNo: 2, verseNo: 1),
        isTrue,
      );
      expect(
        eventContainsBibleVerse(event, bookNo: 1, chapterNo: 2, verseNo: 4),
        isFalse,
      );
    });

    test('여러 성경 본문 중 하나라도 선택 절을 포함하면 true', () {
      final event = _event(
        title: '두 본문 사건',
        bibleRefs: const [
          BibleRef(book: '마', from: '1:1', to: '1:17'),
          BibleRef(book: '눅', from: '2:1', to: '2:20'),
        ],
      );

      expect(
        eventContainsBibleVerse(event, bookNo: 42, chapterNo: 2, verseNo: 7),
        isTrue,
      );
    });

    test('다른 책이거나 잘못된 입력이면 false', () {
      final event = _event(
        title: '산상수훈',
        bibleRefs: const [BibleRef(book: '마', from: '5:1', to: '5:12')],
      );

      expect(
        eventContainsBibleVerse(event, bookNo: 41, chapterNo: 5, verseNo: 3),
        isFalse,
      );
      expect(
        eventContainsBibleVerse(event, bookNo: 40, chapterNo: 0, verseNo: 3),
        isFalse,
      );
    });
  });
}
