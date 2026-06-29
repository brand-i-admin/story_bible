import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/parchment_page_scaffold.dart';
import 'package:story_bible/widgets/profile/companion_diary_entry_card.dart';
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

UserCompanionDiaryEntry _diaryEntry({
  required DateTime entryDate,
  String id = 'diary_1',
  String title = '오늘의 걸음',
  String body = '예수님과 함께 하루를 돌아보았습니다.',
}) {
  return UserCompanionDiaryEntry(
    id: id,
    userId: 'user_1',
    entryDate: entryDate,
    title: title,
    body: body,
    createdAt: DateTime.utc(2026, 6, 10),
    updatedAt: DateTime.utc(2026, 6, 10, 1),
  );
}

Widget _wrap({
  required StoryRepository repository,
  required Map<String, EventEmotionMark> marks,
  DateTime? now,
  double width = 430,
  double textScale = 1.0,
  List<UserCompanionDiaryEntry> companionDiaryEntries = const [],
  CompanionDiarySaveCallback? onSaveCompanionDiary,
  CompanionDiaryDeleteCallback? onDeleteCompanionDiary,
  ProfileEmotionStats? emotionStats,
  ValueChanged<EventEmotionOption>? onTapEmotion,
  ValueChanged<StoryEvent>? onOpenEventDetail,
}) {
  return ProviderScope(
    overrides: [storyRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: ProfileEmotionDiary(
                eventEmotionMarks: marks,
                companionDiaryEntries: companionDiaryEntries,
                onSaveCompanionDiary:
                    onSaveCompanionDiary ??
                    ({
                      required entryDate,
                      required title,
                      required body,
                    }) async => _diaryEntry(
                      entryDate: entryDate,
                      title: title,
                      body: body,
                    ),
                onDeleteCompanionDiary: onDeleteCompanionDiary ?? (_) async {},
                emotionStats: emotionStats,
                onTapEmotion: onTapEmotion,
                now: now,
                onOpenEventDetail: onOpenEventDetail ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _companionDiaryWidgetTests() {
  testWidgets('감정 새김이 없으면 동행 일지 탭을 기본으로 보여주고 감정 탭을 전환할 수 있다', (tester) async {
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
    expect(find.text('오늘의 신앙 기록'), findsOneWidget);
    expect(find.text('신앙(예배,말씀,기도,삶의 사건)을 기록해보세요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-add-button')),
      findsOneWidget,
    );
    expect(find.textContaining('오늘 새긴 감정이 없습니다'), findsNothing);

    await tester.tap(find.text('오늘의 내 감정'));
    await tester.pumpAndSettle();

    expect(find.text('신앙(예배,말씀,기도,삶의 사건)을 기록해보세요'), findsNothing);
    expect(
      find.byKey(const ValueKey('companion-diary-add-button')),
      findsNothing,
    );
    expect(find.textContaining('오늘 새긴 감정이 없습니다'), findsOneWidget);
  });

  testWidgets('아주크게에서도 두 자리 날짜는 한 줄로 표시된다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 25),
        width: 390,
        textScale: 1.4,
      ),
    );
    await tester.pumpAndSettle();

    final todayNumberBoxSize = tester.getSize(
      find.byKey(const ValueKey('emotion-calendar-day-number-2026-6-25')),
    );
    final todayText = tester.renderObject<RenderParagraph>(find.text('25'));

    expect(todayNumberBoxSize.width, greaterThanOrEqualTo(24));
    expect(
      todayText.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(todayText.size.width),
    );
  });

  testWidgets('아주크게에서 신앙 기록 탭 선택 배경은 탭 높이를 채운다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 25),
        width: 390,
        textScale: 1.4,
      ),
    );
    await tester.pumpAndSettle();

    final selectedBackground = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == AppColors.brownWarm;
    });

    expect(selectedBackground, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('diary-content-tab-bar')))
          .height,
      42,
    );
    expect(tester.getSize(selectedBackground).height, lessThanOrEqualTo(34));
    expect(
      tester.getSize(selectedBackground).height,
      greaterThan(tester.getSize(find.text('오늘의 신앙 기록')).height + 8),
    );
  });

  testWidgets('날짜를 선택하면 해당일의 동행 일지를 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    final todayEntry = _diaryEntry(
      entryDate: DateTime(2026, 6, 10),
      title: '오늘의 걸음',
      body: '오늘 본문입니다.',
    );
    final selectedDateEntry = _diaryEntry(
      id: 'diary_2',
      entryDate: DateTime(2026, 6, 8),
      title: '만나의 하루',
      body: '그날의 동행을 기록했습니다.',
    );

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        companionDiaryEntries: [todayEntry, selectedDateEntry],
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 걸음'), findsOneWidget);
    expect(find.text('만나의 하루'), findsNothing);

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 걸음'), findsNothing);
    expect(find.text('만나의 하루'), findsOneWidget);
    expect(find.text('그날의 동행을 기록했습니다.'), findsOneWidget);
  });

  testWidgets('선택한 날짜에서 동행 일지를 작성하면 그 날짜로 저장한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    DateTime? savedEntryDate;

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 10),
        onSaveCompanionDiary:
            ({required entryDate, required title, required body}) async {
              savedEntryDate = entryDate;
              return _diaryEntry(
                entryDate: entryDate,
                title: title,
                body: body,
              );
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('companion-diary-add-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '선택한 날');
    await tester.enterText(find.byType(TextField).at(1), '그날의 본문');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(savedEntryDate, DateTime(2026, 6, 8));
  });

  testWidgets('오늘의 신앙 기록은 본문을 왼쪽부터 쓰고 상세 팝업에서 수정/삭제한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    final entry = _diaryEntry(
      entryDate: DateTime(2026, 6, 10),
      title: '갈릴리의 하루',
      body: '말씀을 묵상하며 차분히 걸었습니다.',
    );

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        companionDiaryEntries: [entry],
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('companion-diary-add-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-edit-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-delete-button')),
      findsNothing,
    );
    expect(find.text('갈릴리의 하루'), findsOneWidget);
    expect(find.text('말씀을 묵상하며 차분히 걸었습니다.'), findsOneWidget);
    expect(find.text('✍️'), findsNothing);
    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-10')),
      findsOneWidget,
    );
    final emojiCenter = tester.getCenter(
      find.byKey(const ValueKey('companion-diary-entry-emoji-badge')),
    );
    final titleCenter = tester.getCenter(find.text('갈릴리의 하루'));
    final bodyLeft = tester.getTopLeft(
      find.byKey(const ValueKey('companion-diary-preview-body-diary_1')),
    );

    expect(emojiCenter.dx, lessThan(titleCenter.dx));
    expect(bodyLeft.dx, lessThan(titleCenter.dx));

    await tester.tap(find.text('갈릴리의 하루'));
    await tester.pumpAndSettle();

    expect(find.text('동행 일지 상세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-detail-body-diary_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-edit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-delete-button')),
      findsOneWidget,
    );
  });

  testWidgets('동행 일지 마커는 좁은 달력 셀에서도 overflow 없이 렌더링된다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    final entry = _diaryEntry(entryDate: DateTime(2026, 6, 23));

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        companionDiaryEntries: [entry],
        now: DateTime.utc(2026, 6, 23),
        width: 320,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-23')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('전체보기는 같은 동행 일지 카드와 상세 팝업을 사용한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    final entry = _diaryEntry(
      entryDate: DateTime(2026, 6, 9),
      title: '광야의 감사',
      body: '작은 공급을 놓치지 않기로 했습니다.',
    );

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        companionDiaryEntries: [entry],
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 신앙 기록'), findsWidgets);
    expect(tester.getTopLeft(find.byType(ParchmentCard).last).dx, lessThan(24));
    expect(find.text('6월 9일'), findsOneWidget);
    expect(find.text('광야의 감사'), findsOneWidget);
    expect(find.text('작은 공급을 놓치지 않기로 했습니다.'), findsOneWidget);
    expect(find.byType(CompanionDiaryEntryPreviewCard), findsOneWidget);

    await tester.tap(find.text('광야의 감사'));
    await tester.pumpAndSettle();

    expect(find.text('동행 일지 상세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-detail-body-diary_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-edit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-delete-button')),
      findsOneWidget,
    );
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  _companionDiaryWidgetTests();

  testWidgets('감정 카테고리 버튼은 달력 연월보다 위에서 동작한다', (tester) async {
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
      lessThan(tester.getTopLeft(find.text('2026년 6월')).dy),
    );
    expect(
      tester.getTopLeft(find.text('2026년 6월')).dy,
      lessThan(tester.getTopLeft(find.text('31')).dy),
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

    await tester.tap(find.text('오늘의 내 감정'));
    await tester.pumpAndSettle();

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
    final diaryTitleTop = tester.getTopLeft(find.text('오늘의 신앙 기록')).dy;
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
    final diaryTitleTop = tester.getTopLeft(find.text('오늘의 신앙 기록')).dy;
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

    await tester.tap(find.text('오늘의 내 감정'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('홍해를 건너다'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(openCount, 1);

    await tester.tap(find.text('9'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('오늘의 내 감정'), findsOneWidget);

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
    await tester.tap(find.text('오늘의 내 감정'));
    await tester.pumpAndSettle();

    expect(find.text('만나를 먹다'), findsOneWidget);
    expect(find.text('오늘 필요한 만큼 채워주심을 봅니다.'), findsOneWidget);
  });

  testWidgets('선택한 날짜는 검정 날짜와 초록 칸 배경으로 표시된다', (tester) async {
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

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    final selectedCell = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('emotion-calendar-day-2026-6-8')),
    );
    final decoration = selectedCell.decoration as BoxDecoration?;
    expect(decoration?.color, AppColors.greenTint2);

    final dayText = tester.widget<Text>(find.text('8'));
    expect(dayText.style?.color, AppColors.ink900);
  });
}
