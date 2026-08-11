import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/journey_selection.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/utils/journey_filtering.dart';

void main() {
  const oldEra = Era(
    id: 'old-era',
    code: 'era_primeval',
    testament: 'old',
    name: '원역사',
    displayOrder: 1,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  );
  const newEra = Era(
    id: 'new-era',
    code: 'era_nt_apostolic',
    testament: 'new',
    name: '사도',
    displayOrder: 1,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  );
  final events = [
    _event(
      id: 'creation',
      eraId: oldEra.id,
      unitCode: 'creation-unit',
      unitTitle: '창조와 사람의 사명',
      book: '창',
      characterCodes: const ['god'],
      rank: 1,
    ),
    _event(
      id: 'babel',
      eraId: oldEra.id,
      unitCode: 'outside-unit',
      unitTitle: '에덴 밖 세상',
      book: '창',
      characterCodes: const ['noah'],
      rank: 2,
    ),
    _event(
      id: 'paul',
      eraId: newEra.id,
      unitCode: 'paul-unit',
      unitTitle: '바울의 전도 여행',
      book: '행',
      characterCodes: const ['paul'],
      rank: 3,
    ),
  ];

  test('일부 구간은 선택한 소분류 이야기만 시간순으로 남긴다', () {
    final filtered = filterJourneyEvents(
      events: events,
      eras: const [oldEra, newEra],
      selection: const JourneySelection(
        source: JourneySource.segments,
        scope: JourneyScope.units,
        unitKeys: {'old-era::outside-unit', 'new-era::paul-unit'},
      ),
    );

    expect(filtered.map((event) => event.id), ['babel', 'paul']);
  });

  test('성경책 이야기만과 인물 이야기만을 실제 연결 데이터로 고른다', () {
    final bookEvents = filterJourneyEvents(
      events: events,
      eras: const [oldEra, newEra],
      selection: const JourneySelection(
        source: JourneySource.book,
        scope: JourneyScope.targetOnly,
        bookName: '창세기',
      ),
    );
    final personEvents = filterJourneyEvents(
      events: events,
      eras: const [oldEra, newEra],
      selection: const JourneySelection(
        source: JourneySource.person,
        scope: JourneyScope.targetOnly,
        personCode: 'paul',
        personName: '바울',
      ),
    );

    expect(bookEvents.map((event) => event.id), ['creation', 'babel']);
    expect(personEvents.map((event) => event.id), ['paul']);
  });

  test('권과 인물이 포함된 실제 소분류를 표시한다', () {
    final bookGroups = buildJourneyEraGroups(
      events: events,
      eras: const [oldEra, newEra],
      targetMatches: (event) => eventHasBibleBook(event, '창세기'),
      onlyTargetEras: true,
    );
    final personGroups = buildJourneyEraGroups(
      events: events,
      eras: const [oldEra, newEra],
      targetMatches: (event) => event.characterCodes.contains('paul'),
      onlyTargetEras: true,
    );

    expect(bookGroups.single.units, hasLength(2));
    expect(
      bookGroups.single.units.every((unit) => unit.containsTarget),
      isTrue,
    );
    expect(personGroups.single.era.id, newEra.id);
    expect(personGroups.single.units.single.containsTarget, isTrue);
    expect(bookGroups.single.bibleBookNames, ['창세기']);
  });

  test('진행 수치는 필터 안에서 감정을 새긴 이야기만 센다', () {
    final progress = journeyProgress(
      events,
      engravedEventIds: const {'creation', 'paul', 'outside-filter'},
    );

    expect(progress.completed, 2);
    expect(progress.total, 3);
  });
}

StoryEvent _event({
  required String id,
  required String eraId,
  required String unitCode,
  required String unitTitle,
  required String book,
  required List<String> characterCodes,
  required int rank,
}) {
  return StoryEvent(
    id: id,
    eraId: eraId,
    title: id,
    summary: id,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: rank,
    unitCode: unitCode,
    unitTitle: unitTitle,
    unitOrder: rank,
    rankInEra: rank,
    globalRank: rank,
    landmarkId: 'landmark',
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: characterCodes,
    bibleRefs: [BibleRef(book: book, from: '1:1', to: '1:2')],
  );
}
