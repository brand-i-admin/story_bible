import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/widgets/profile/profile_event_review_grid.dart';

Era _era({
  required String id,
  required String name,
  required int displayOrder,
}) {
  return Era(
    id: id,
    code: id,
    testament: 'old',
    name: name,
    displayOrder: displayOrder,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  );
}

StoryEvent _event({
  required String id,
  required String eraId,
  required String title,
  required int storyIndex,
  required int globalRank,
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'landmark_$id',
    eraId: eraId,
    title: title,
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    rankInEra: storyIndex,
    globalRank: globalRank,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const <String>[],
    bibleRefs: const [],
  );
}

Widget _wrap(List<StoryEvent> events) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 620,
        height: 620,
        child: ProfileEventReviewGrid(
          events: events,
          eras: [
            _era(id: 'era_exodus', name: '출애굽 시대', displayOrder: 2),
            _era(id: 'era_primeval', name: '태초 시대', displayOrder: 1),
          ],
          charactersByCode: const {},
          completedEventIds: const {},
          eventEmotionMarks: const {},
          quizAttemptSummaries: const {},
          onOpenEventDetail: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('첫 시대와 시대 변경 지점을 경계 마커로 표시한다', (tester) async {
    await tester.pumpWidget(
      _wrap([
        _event(
          id: 'event_2',
          eraId: 'era_exodus',
          title: '홍해를 건너다',
          storyIndex: 1,
          globalRank: 2,
        ),
        _event(
          id: 'event_1',
          eraId: 'era_primeval',
          title: '방주를 짓다',
          storyIndex: 1,
          globalRank: 1,
        ),
      ]),
    );

    expect(find.text('태초 시대'), findsOneWidget);
    expect(find.text('출애굽 시대'), findsOneWidget);

    final primevalTop = tester.getTopLeft(find.text('태초 시대')).dy;
    final arkTop = tester.getTopLeft(find.text('방주를 짓다')).dy;
    final exodusTop = tester.getTopLeft(find.text('출애굽 시대')).dy;
    final redSeaTop = tester.getTopLeft(find.text('홍해를 건너다')).dy;

    expect(primevalTop, lessThan(arkTop));
    expect(arkTop, lessThan(exodusTop));
    expect(exodusTop, lessThan(redSeaTop));
  });

  testWidgets('같은 시대의 카드 세 개를 한 줄에 배치한다', (tester) async {
    await tester.pumpWidget(
      _wrap([
        _event(
          id: 'event_1',
          eraId: 'era_primeval',
          title: '첫째 이야기',
          storyIndex: 1,
          globalRank: 1,
        ),
        _event(
          id: 'event_2',
          eraId: 'era_primeval',
          title: '둘째 이야기',
          storyIndex: 2,
          globalRank: 2,
        ),
        _event(
          id: 'event_3',
          eraId: 'era_primeval',
          title: '셋째 이야기',
          storyIndex: 3,
          globalRank: 3,
        ),
      ]),
    );

    final first = tester.getTopLeft(find.text('첫째 이야기'));
    final second = tester.getTopLeft(find.text('둘째 이야기'));
    final third = tester.getTopLeft(find.text('셋째 이야기'));

    expect((first.dy - second.dy).abs(), lessThan(1));
    expect((second.dy - third.dy).abs(), lessThan(1));
    expect(first.dx, lessThan(second.dx));
    expect(second.dx, lessThan(third.dx));
  });
}
