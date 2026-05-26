import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/profile/profile_life_map.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

StoryEvent _event({required String id, required String title}) {
  return StoryEvent(
    id: id,
    landmarkId: 'landmark_$id',
    eraId: 'era_test',
    title: title,
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 1,
    rankInEra: 1,
    globalRank: 1,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const <String>[],
    bibleRefs: const [],
  );
}

Widget _wrap({
  required StoryRepository repository,
  required Map<String, EventEmotionMark> marks,
  ValueChanged<StoryEvent>? onOpenEventDetail,
}) {
  return ProviderScope(
    overrides: [storyRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 430,
          child: ProfileLifeMap(
            eventEmotionMarks: marks,
            quizAttemptSummaries: const {},
            onOpenEventDetail: onOpenEventDetail ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  testWidgets('ProfileLifeMap은 감정 새김이 없으면 빈 최근 한 줄 상태를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(repository: repository, marks: const <String, EventEmotionMark>{}),
    );
    await tester.pump();

    expect(find.text('내 삶의 지도'), findsOneWidget);
    for (final label in [
      '기쁨의 정원',
      '기대의 들판',
      '감사의 샘',
      '놀라움의 언덕',
      '안타까움의 골짜기',
      '위로의 숲',
      '두려움의 끝자락',
      '기타의 마을',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('최근 남긴 한 줄'), findsOneWidget);
    expect(find.textContaining('아직 지도에 새긴 한 줄이 없습니다'), findsOneWidget);
  });

  testWidgets('ProfileLifeMap은 감정 지역을 누르면 해당 사건과 코멘트를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = EventEmotionMark(
      eventId: event.id,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      emotionEmoji: '✨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.parse('2026-05-26T09:00:00Z'),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(repository: repository, marks: {event.id: mark}),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('기쁨의 정원'));
    await tester.pumpAndSettle();

    expect(find.text('기쁨의 정원'), findsWidgets);
    expect(find.text('홍해를 건너다'), findsWidgets);
    expect(find.text('구원의 기쁨을 기억합니다.'), findsWidgets);
  });

  testWidgets('최근 남긴 한 줄은 제목을 코멘트 위에 표시한다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = EventEmotionMark(
      eventId: event.id,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      emotionEmoji: '✨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.parse('2026-05-26T09:00:00Z'),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(repository: repository, marks: {event.id: mark}),
    );
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text('홍해를 건너다')).dy;
    final noteTop = tester.getTopLeft(find.text('구원의 기쁨을 기억합니다.')).dy;

    expect(titleTop, lessThan(noteTop));
    expect(find.text('5월 26일'), findsOneWidget);
  });
}
