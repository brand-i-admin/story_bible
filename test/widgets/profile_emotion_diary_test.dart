import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/profile/profile_emotion_diary.dart';
import 'package:story_bible/widgets/profile/profile_emotion_stats.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

StoryEvent _event({
  required String id,
  required String title,
  int storyIndex = 1,
  int globalRank = 1,
}) {
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

EventEmotionMark _mark({
  required StoryEvent event,
  required String emotionKey,
  required String emotionLabel,
  required String note,
  required DateTime updatedAt,
}) {
  final option = EventEmotionOption.byKey(emotionKey);
  return EventEmotionMark(
    eventId: event.id,
    emotionKey: emotionKey,
    emotionLabel: emotionLabel,
    emotionEmoji: option?.emoji ?? '·',
    note: note,
    updatedAt: updatedAt,
  );
}

Widget _wrap({
  required StoryRepository repository,
  required Map<String, EventEmotionMark> marks,
  DateTime? now,
  ProfileEmotionStats? emotionStats,
  ValueChanged<EventEmotionOption>? onTapEmotion,
  ValueChanged<StoryEvent>? onOpenEventDetail,
}) {
  return ProviderScope(
    overrides: [storyRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 430,
            child: ProfileEmotionDiary(
              eventEmotionMarks: marks,
              emotionStats: emotionStats,
              onTapEmotion: onTapEmotion,
              now: now,
              onOpenEventDetail: onOpenEventDetail ?? (_) {},
            ),
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

  testWidgets('감정 새김이 없으면 지난주와 이번 주 달력, 빈 오늘 감정 상태를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pump();

    expect(find.text('나의 다이어리'), findsNothing);
    expect(find.text('내 삶의 지도'), findsNothing);
    expect(find.text('2026년 6월'), findsOneWidget);
    for (final day in ['31', '1', '2', '3', '4', '5', '6']) {
      expect(find.text(day), findsOneWidget);
    }
    for (final day in ['7', '8', '9', '10', '11', '12', '13']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('오늘의 내 감정'), findsOneWidget);
    expect(find.textContaining('오늘 새긴 감정이 없습니다'), findsOneWidget);
  });

  testWidgets('감정 카테고리 버튼은 달력 아래와 오늘의 내 감정 사이에서 동작한다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    final marks = {event.id: mark};
    EventEmotionOption? tappedOption;
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: marks,
        emotionStats: buildProfileEmotionStats(marks),
        onTapEmotion: (option) => tappedOption = option,
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기쁨 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('기쁨 1')).dy,
      lessThan(tester.getTopLeft(find.text('오늘의 내 감정')).dy),
    );

    await tester.tap(find.text('기쁨 1'));
    await tester.pump();

    expect(tappedOption?.key, 'joy');
  });

  testWidgets('펼치기 후 이전 달로 이동할 수 있다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('펼치기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();

    expect(find.text('2026년 5월'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
  });

  testWidgets('KST 기준 오늘 남긴 감정과 이야기 정보를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: {event.id: mark},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('6월 10일 오늘'), findsOneWidget);
    expect(find.text('홍해를 건너다'), findsOneWidget);
    expect(find.text('구원의 기쁨을 기억합니다.'), findsOneWidget);
  });

  testWidgets('감정이 없는 주는 감정이 있는 주보다 낮게 표시한다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: {event.id: mark},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    final previousWeekTop = tester.getTopLeft(find.text('31')).dy;
    final currentWeekTop = tester.getTopLeft(find.text('7')).dy;
    final diaryTitleTop = tester.getTopLeft(find.text('오늘의 내 감정')).dy;
    final previousWeekHeight = currentWeekTop - previousWeekTop;
    final currentWeekHeight = diaryTitleTop - currentWeekTop;

    expect(previousWeekHeight, lessThan(currentWeekHeight));
  });

  testWidgets('주차 높이는 해당 주의 최대 감정 개수에 따라 1줄 또는 2줄로 조정된다', (tester) async {
    final repository = _MockStoryRepository();
    final events = [
      for (var index = 0; index < 5; index++)
        _event(
          id: 'event_$index',
          title: '이야기 $index',
          storyIndex: index + 1,
          globalRank: index + 1,
        ),
    ];
    final marks = <String, EventEmotionMark>{
      for (var index = 0; index < 2; index++)
        events[index].id: _mark(
          event: events[index],
          emotionKey: 'joy',
          emotionLabel: '기쁨',
          note: '지난주 감정 $index',
          updatedAt: DateTime.utc(2026, 6, 1, 16),
        ),
      for (var index = 2; index < 5; index++)
        events[index].id: _mark(
          event: events[index],
          emotionKey: 'gratitude',
          emotionLabel: '감사',
          note: '이번주 감정 $index',
          updatedAt: DateTime.utc(2026, 6, 9, 16),
        ),
    };
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => events);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: marks,
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    final previousWeekTop = tester.getTopLeft(find.text('31')).dy;
    final currentWeekTop = tester.getTopLeft(find.text('7')).dy;
    final diaryTitleTop = tester.getTopLeft(find.text('오늘의 내 감정')).dy;
    final previousWeekHeight = currentWeekTop - previousWeekTop;
    final currentWeekHeight = diaryTitleTop - currentWeekTop;

    expect(previousWeekHeight, lessThan(currentWeekHeight));
  });

  testWidgets('하루 4개 이상 새기면 달력에는 3개 감정과 남은 개수를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    final events = [
      for (var index = 0; index < 5; index++)
        _event(
          id: 'overflow_event_$index',
          title: '많이 새긴 이야기 $index',
          storyIndex: index + 1,
          globalRank: index + 1,
        ),
    ];
    final marks = <String, EventEmotionMark>{
      for (var index = 0; index < events.length; index++)
        events[index].id: _mark(
          event: events[index],
          emotionKey: 'joy',
          emotionLabel: '기쁨',
          note: '많이 새긴 감정 $index',
          updatedAt: DateTime.utc(2026, 6, 9, 16),
        ),
    };
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => events);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: marks,
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('감정 row를 누르면 상세 이동 콜백을 즉시 호출하고 로딩을 짧게 닫는다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    var openCount = 0;
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: {event.id: mark},
        now: DateTime.utc(2026, 6, 10),
        onOpenEventDetail: (_) => openCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('홍해를 건너다'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(openCount, 1);

    await tester.tap(find.text('9'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('6월 10일 오늘'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('날짜를 선택하면 해당일의 감정 기록으로 아래 섹션이 바뀐다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'event_1', title: '만나를 먹다');
    final mark = _mark(
      event: event,
      emotionKey: 'gratitude',
      emotionLabel: '감사',
      note: '오늘 필요한 만큼 채워주심을 봅니다.',
      updatedAt: DateTime.utc(2026, 6, 8, 2),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: {event.id: mark},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('만나를 먹다'), findsNothing);

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    expect(find.text('6월 8일 월요일'), findsOneWidget);
    expect(find.text('만나를 먹다'), findsOneWidget);
    expect(find.text('오늘 필요한 만큼 채워주심을 봅니다.'), findsOneWidget);
  });
}
