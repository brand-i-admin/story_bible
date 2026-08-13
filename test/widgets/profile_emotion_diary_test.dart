import 'dart:io';

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
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/profile/companion_diary_entry_card.dart';
import 'package:story_bible/widgets/profile/profile_emotion_diary.dart';

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
  ProfileBibleProgressSummary? bibleProgress,
  VoidCallback? onOpenBibleProgress,
  VoidCallback? onContinueBibleReading,
  Map<String, DateTime?> completedBibleChapterReadAts = const {},
  AppColorPalette palette = AppColorPalette.classic,
}) {
  return ProviderScope(
    overrides: [storyRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: AppTheme.light(palette: palette),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: TickerMode(
                enabled: false,
                child: ProfileEmotionDiary(
                  eventEmotionMarks: marks,
                  completedBibleChapterReadAts: completedBibleChapterReadAts,
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
                  onDeleteCompanionDiary:
                      onDeleteCompanionDiary ?? (_) async {},
                  bibleProgress:
                      bibleProgress ??
                      const ProfileBibleProgressSummary(
                        completed: 12,
                        total: 1189,
                        fraction: 12 / 1189,
                      ),
                  onOpenBibleProgress: onOpenBibleProgress ?? () {},
                  onContinueBibleReading: onContinueBibleReading ?? () {},
                  now: now,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _companionDiaryWidgetTests() {
  testWidgets('감정 새김이 없으면 신앙 다이어리와 통독 카드를 보여준다', (tester) async {
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
    for (final day in [
      '31',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
      '13',
    ]) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('다이어리'), findsOneWidget);
    expect(find.text('오늘 하나님과 함께한 순간을 기록해 보세요!'), findsOneWidget);
    final diaryTitle = tester.widget<Text>(find.text('다이어리'));
    final diaryPrompt = tester.widget<Text>(
      find.text('오늘 하나님과 함께한 순간을 기록해 보세요!'),
    );
    expect(diaryTitle.style?.color, AppColorPalette.classic.text);
    expect(diaryPrompt.style?.color, AppColorPalette.classic.text);
    expect(find.text('기록하기'), findsOneWidget);
    expect(find.text('전체 보기'), findsNothing);
    expect(
      find.byKey(const ValueKey('companion-diary-feature-card')),
      findsOneWidget,
    );
    expect(find.text('통독 진행률'), findsOneWidget);
    expect(find.text('마지막 통독 장'), findsOneWidget);
    expect(find.text('이어읽기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-add-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bible-progress-continue-icon-badge')),
      findsOneWidget,
    );
    final diaryWritePill = find.byKey(
      const ValueKey('companion-diary-write-button-pill'),
    );
    final bibleContinuePill = find.byKey(
      const ValueKey('bible-progress-continue-button'),
    );
    expect(
      tester.getTopLeft(diaryWritePill).dy,
      moreOrLessEquals(tester.getTopLeft(bibleContinuePill).dy, epsilon: 1.0),
    );
    expect(
      tester.getSize(diaryWritePill).height,
      moreOrLessEquals(tester.getSize(bibleContinuePill).height, epsilon: 1.0),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('companion-diary-add-button')))
          .dy,
      greaterThan(tester.getTopLeft(find.text('오늘 하나님과 함께한 순간을 기록해 보세요!')).dy),
    );
    expect(
      tester.getTopLeft(diaryWritePill).dy -
          tester.getBottomLeft(find.text('오늘 하나님과 함께한 순간을 기록해 보세요!')).dy,
      lessThan(26),
    );
    expect(
      tester.getTopLeft(bibleContinuePill).dy -
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('bible-progress-donut-indicator')),
              )
              .dy,
      lessThan(22),
    );
    expect(find.textContaining('오늘 새긴 감정이 없습니다'), findsNothing);
  });

  testWidgets('남색 테마의 기록하기와 이어읽기는 pill과 원형 기호로 표시한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        now: DateTime.utc(2026, 6, 10),
        palette: AppColorPalette.atlasNavy,
      ),
    );
    await tester.pumpAndSettle();

    final writePill = tester.widget<Material>(
      find.byKey(const ValueKey('companion-diary-write-button-pill')),
    );
    final continuePill = tester.widget<Material>(
      find.byKey(const ValueKey('bible-progress-continue-button')),
    );
    final writeOutline = tester.widget<Container>(
      find.byKey(const ValueKey('companion-diary-write-button-outline')),
    );
    final continueOutline = tester.widget<Container>(
      find.byKey(const ValueKey('bible-progress-continue-button-outline')),
    );
    final writeLabel = tester.widget<Text>(find.text('기록하기'));
    final writeIconBadge = tester.widget<Container>(
      find.byKey(const ValueKey('companion-diary-add-button')),
    );
    final continueIconBadge = tester.widget<Container>(
      find.byKey(const ValueKey('bible-progress-continue-icon-badge')),
    );
    final donut = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('bible-progress-donut-indicator')),
    );

    expect(writePill.color, isNot(AppColorPalette.atlasNavy.cardSurface));
    expect(writePill.borderRadius, BorderRadius.circular(AppRadii.pill));
    expect(continuePill.borderRadius, BorderRadius.circular(AppRadii.pill));
    for (final outline in [writeOutline, continueOutline]) {
      final decoration = outline.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.pill));
    }
    expect(writeLabel.style?.color, AppColorPalette.atlasNavy.successBottom);
    for (final badge in [writeIconBadge, continueIconBadge]) {
      final decoration = badge.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
      expect(decoration.color?.a ?? 0, lessThan(0.18));
    }
    expect(donut.backgroundColor, isNot(AppColorPalette.atlasNavy.cardSurface));
    expect(donut.color, isNot(AppColorPalette.atlasNavy.cardSurface));
    expect(donut.color?.a, 1);
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

  testWidgets('아주크게에서 다이어리와 통독 카드는 핵심 버튼을 유지한다', (tester) async {
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

    expect(find.text('다이어리'), findsOneWidget);
    expect(find.text('통독 진행률'), findsOneWidget);
    expect(find.text('이어읽기'), findsOneWidget);
    final diaryWritePill = find.byKey(
      const ValueKey('companion-diary-write-button-pill'),
    );
    final bibleContinuePill = find.byKey(
      const ValueKey('bible-progress-continue-button'),
    );
    expect(
      tester.getTopLeft(diaryWritePill).dy,
      moreOrLessEquals(tester.getTopLeft(bibleContinuePill).dy, epsilon: 1.0),
    );
    expect(
      tester.getSize(diaryWritePill).height,
      moreOrLessEquals(tester.getSize(bibleContinuePill).height, epsilon: 1.0),
    );
    expect(find.byKey(const ValueKey('diary-content-tab-bar')), findsNothing);
  });

  testWidgets('아주크게에서도 내정보 다이어리 제목은 한 줄 수동 스크롤이고 본문은 카드 끝까지 세 줄을 쓴다', (
    tester,
  ) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    final entry = _diaryEntry(
      entryDate: DateTime(2026, 6, 10),
      title: '오늘 하루 받은 은혜와 감사의 이유를 오래 기록하는 다이어리 제목',
      body:
          '오늘 본문에서 만난 말씀을 되새기며 하루 동안 함께하신 은혜를 차분히 기록했습니다. 내일도 이 마음을 기억하고 싶습니다.',
    );

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        companionDiaryEntries: [entry],
        now: DateTime.utc(2026, 6, 10),
        width: 390,
        textScale: 1.4,
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('companion-diary-entry-title')),
    );
    final body = tester.widget<Text>(
      find.byKey(const ValueKey('companion-diary-entry-body')),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('companion-diary-feature-card')),
    );
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey('companion-diary-entry-body')),
    );
    expect(title.maxLines, 1);
    expect(title.softWrap, isFalse);
    expect(title.textScaler, isNotNull);
    expect(title.textScaler!.scale(1), 1.4);
    expect(title.style?.fontWeight, FontWeight.w900);
    expect(body.maxLines, 3);
    expect(body.overflow, TextOverflow.ellipsis);
    expect(bodyRect.right, greaterThan(cardRect.right - 28));
    expect(
      find.byKey(const ValueKey('companion-diary-entry-title-scroll')),
      findsOneWidget,
    );
    final titleScroll = find.byKey(
      const ValueKey('companion-diary-entry-title-scroll'),
    );
    final titleScrollPosition = tester
        .state<ScrollableState>(
          find.descendant(of: titleScroll, matching: find.byType(Scrollable)),
        )
        .position;
    expect(titleScrollPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(titleScroll, const Offset(-48, 0));
    await tester.pump();
    expect(titleScrollPosition.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('아주크게에서 긴 마지막 통독 권도 통독 카드 안에 맞춘다', (tester) async {
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
        bibleProgress: const ProfileBibleProgressSummary(
          completed: 12,
          total: 1189,
          fraction: 12 / 1189,
          lastCompletedBookNo: 44,
          lastCompletedChapterNo: 15,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('사도행전 15장'), findsOneWidget);
    final chapterText = tester.widget<Text>(find.text('사도행전 15장'));
    expect(chapterText.maxLines, 2);
    expect(chapterText.overflow, TextOverflow.visible);
    expect(find.text('이어읽기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('날짜를 선택해도 신앙 다이어리 카드는 오늘 기록 기준을 유지한다', (tester) async {
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
    expect(find.text('오늘 본문입니다.'), findsOneWidget);
    expect(find.text('만나의 하루'), findsNothing);

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 걸음'), findsOneWidget);
    expect(find.text('오늘 본문입니다.'), findsOneWidget);
    expect(find.text('만나의 하루'), findsNothing);
    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-8')),
      findsOneWidget,
    );
  });

  testWidgets('신앙 다이어리 기록하기는 오늘 날짜로 저장한다', (tester) async {
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
    expect(find.text('다이어리 작성'), findsOneWidget);
    expect(find.text('오늘의 말씀 연결'), findsNothing);
    await tester.tap(find.text('기록 저장'));
    await tester.pumpAndSettle();

    expect(savedEntryDate, DateTime(2026, 6, 10));
  });

  testWidgets('오늘 신앙 다이어리가 있으면 하단 버튼에서 수정하고 카드는 상세 목록을 연다', (tester) async {
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
      findsOneWidget,
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
    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-10')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('companion-diary-add-button')));
    await tester.pumpAndSettle();

    expect(find.text('다이어리 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, '갈릴리의 하루'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '말씀을 묵상하며 차분히 걸었습니다.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('companion-diary-feature-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('다이어리'), findsWidgets);
    expect(find.text('갈릴리의 하루'), findsOneWidget);
    expect(find.text('말씀을 묵상하며 차분히 걸었습니다.'), findsOneWidget);

    await tester.tap(find.text('갈릴리의 하루'));
    await tester.pumpAndSettle();

    expect(find.text('다이어리 상세'), findsOneWidget);
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

  testWidgets('신앙 다이어리 마커는 좁은 달력 셀에서도 overflow 없이 렌더링된다', (tester) async {
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

  testWidgets('신앙 다이어리 카드는 같은 미리보기 카드와 상세 팝업을 사용한다', (tester) async {
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

    await tester.tap(
      find.byKey(const ValueKey('companion-diary-feature-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('다이어리'), findsWidgets);
    expect(
      tester.getTopLeft(find.byType(CompanionDiaryEntryPreviewCard)).dx,
      lessThan(24),
    );
    expect(find.text('6월 9일 화요일 · 오전 10:00'), findsOneWidget);
    expect(find.text('광야의 감사'), findsOneWidget);
    expect(find.text('작은 공급을 놓치지 않기로 했습니다.'), findsOneWidget);
    expect(find.byType(CompanionDiaryEntryPreviewCard), findsOneWidget);

    await tester.tap(find.text('광야의 감사'));
    await tester.pumpAndSettle();

    expect(find.text('다이어리 상세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-detail-body-diary_1')),
      findsOneWidget,
    );
    final bodySurface = tester.widget<Container>(
      find.byKey(const ValueKey('companion-diary-detail-body-surface')),
    );
    final bodyDecoration = bodySurface.decoration! as BoxDecoration;
    expect(bodyDecoration.borderRadius, BorderRadius.circular(AppRadii.lg));
    expect(bodyDecoration.border, isNotNull);
    expect(
      find.byKey(const ValueKey('companion-diary-detail-edit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-delete-button')),
      findsOneWidget,
    );
  });

  testWidgets('신앙 다이어리 미리보기와 상세 팝업은 다크 팔레트 색을 사용한다', (tester) async {
    final entry = _diaryEntry(
      entryDate: DateTime(2026, 6, 10),
      title: '어두운 밤의 기도',
      body: '밤에도 말씀을 붙들었습니다.',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(palette: AppColorPalette.blackMap),
        home: Scaffold(
          body: Builder(
            builder: (context) => CompanionDiaryEntryPreviewCard(
              entry: entry,
              dateLabel: '6월 10일',
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => CompanionDiaryEntryDetailDialog(entry: entry),
              ),
            ),
          ),
        ),
      ),
    );

    final cardInk = tester.widget<Ink>(
      find
          .descendant(
            of: find.byType(CompanionDiaryEntryPreviewCard),
            matching: find.byType(Ink),
          )
          .first,
    );
    final cardDecoration = cardInk.decoration! as BoxDecoration;
    expect(cardDecoration.color, AppColorPalette.blackMap.cardSurface);
    expect(
      tester.widget<Text>(find.text('어두운 밤의 기도')).style?.color,
      AppColorPalette.blackMap.text,
    );

    await tester.tap(find.text('어두운 밤의 기도'));
    await tester.pumpAndSettle();

    expect(find.text('다이어리 상세'), findsOneWidget);
    final detailBody = tester.widget<Text>(
      find.byKey(const ValueKey('companion-diary-detail-body-diary_1')),
    );
    expect(detailBody.style?.color, AppColorPalette.blackMap.text);
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  test('달력 아래 섹션은 신앙 다이어리와 통독 카드로 구성한다', () {
    final source = File(
      'lib/widgets/profile/profile_emotion_diary.dart',
    ).readAsStringSync();
    final companionSource = File(
      'lib/widgets/profile/profile_companion_diary.dart',
    ).readAsStringSync();

    expect(source, contains('ProfileDiaryFeatureCards'));
    expect(source, contains('CompanionDiaryFeatureCard'));
    expect(source, contains('_BibleProgressFeatureCard'));
    expect(source, contains('IntrinsicHeight'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(source, contains('AppTextStyles.sectionTitle'));
    expect(source, contains('_BibleProgressDonut'));
    expect(source, contains('final readingAccent = palette.primaryDeep'));
    expect(source, contains('colors: [surfaceTop, surfaceBottom]'));
    expect(source, contains('color: readingAccent'));
    expect(source, contains('CircularProgressIndicator'));
    expect(source, contains('dimension: largeText ? 38 : 44'));
    expect(source, contains('strokeWidth: 4.6'));
    expect(source, contains('completedToday'));
    expect(source, contains('palette.successBottom'));
    expect(source, contains('chapterReferenceText'));
    expect(source, contains("'이어읽기'"));
    expect(source, contains('darkSurface ? 0.16 : 0.07'));
    expect(source, isNot(contains('PulseHighlight')));
    expect(
      companionSource,
      isNot(contains("import '../pulse_highlight.dart';")),
    );
    expect(companionSource, contains('clipBehavior: Clip.none'));
    expect(companionSource, contains('EdgeInsets.fromLTRB(5, 3, 5, 4)'));
    expect(companionSource, contains('BorderRadius.circular(12)'));
    expect(companionSource, isNot(contains('final pulseColor')));
    expect(companionSource, isNot(contains('auraColor')));
    expect(companionSource, isNot(contains('ringColor')));
    expect(companionSource, contains('AppColors.greenTint1'));
    expect(companionSource, contains('diaryTitle'));
    expect(companionSource, contains('diaryBody'));
    expect(
      companionSource,
      contains('constraints: BoxConstraints(minHeight: minHeight)'),
    );
    expect(companionSource, contains('maxLines: 3'));
    expect(companionSource, contains('FadingHorizontalTextScroll'));
    expect(companionSource, isNot(contains('오늘 적은 다이어리')));
    expect(source, isNot(contains('_DiaryLinkedTabSection')));
    expect(source, isNot(contains('_DiaryContentTab')));
  });

  _companionDiaryWidgetTests();

  testWidgets('통독 카드는 진행률 표와 이어 읽기 콜백을 분리한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    var openedProgress = 0;
    var continuedReading = 0;

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        onOpenBibleProgress: () => openedProgress++,
        onContinueBibleReading: () => continuedReading++,
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bible-progress-feature-card')));
    await tester.pump();

    expect(openedProgress, 1);
    expect(continuedReading, 0);

    await tester.tap(
      find.byKey(const ValueKey('bible-progress-continue-button')),
    );
    await tester.pump();

    expect(openedProgress, 1);
    expect(continuedReading, 1);
  });

  testWidgets('통독 카드는 마지막 통독 완료 장을 권과 장으로 표시한다', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const <String, EventEmotionMark>{},
        bibleProgress: const ProfileBibleProgressSummary(
          completed: 12,
          total: 1189,
          fraction: 12 / 1189,
          lastCompletedBookNo: 43,
          lastCompletedChapterNo: 3,
        ),
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('요한복음 3장'), findsOneWidget);
    expect(find.text('요한복음 3:16'), findsNothing);
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

  testWidgets('감정 리스트는 날짜와 이야기 정보를 최신순으로 보여준다', (tester) async {
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '구원의 기쁨을 기억합니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileEmotionMarksList(
            marks: [mark],
            eventById: {event.id: event},
            onOpenEventDetail: (_) {},
            loading: false,
            hasError: false,
            emptyMessage: '감정이 없습니다.',
            showTimestamp: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홍해를 건너다'), findsOneWidget);
    expect(find.text('6월 10일'), findsOneWidget);
    expect(find.textContaining('01:00'), findsNothing);
    expect(find.textContaining('· 기쁨'), findsNothing);
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
    final diaryTitleTop = tester.getTopLeft(find.text('다이어리')).dy;
    final previousWeekHeight = currentWeekTop - previousWeekTop;
    final currentWeekHeight = diaryTitleTop - currentWeekTop;

    expect(previousWeekHeight, lessThan(currentWeekHeight));
  });

  testWidgets('감정 개수와 무관하게 기록이 있는 주는 한 줄 높이를 사용한다', (tester) async {
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

    final previousWeekCell = find.byKey(
      const ValueKey('emotion-calendar-day-2026-6-2'),
    );
    final currentWeekCell = find.byKey(
      const ValueKey('emotion-calendar-day-2026-6-10'),
    );
    expect(tester.getSize(previousWeekCell).height, 56);
    expect(tester.getSize(currentWeekCell).height, 56);
  });

  testWidgets('하루에 감정을 여러 개 새겨도 달력에는 웃는 얼굴 하나만 보여준다', (tester) async {
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

    expect(
      find.byKey(const ValueKey('calendar-emotion-marker-2026-6-10')),
      findsOneWidget,
    );
    expect(find.text('+2'), findsNothing);
  });

  testWidgets('감정 통독 다이어리를 모두 한 날은 큰 체크 하나만 보여준다', (tester) async {
    final repository = _MockStoryRepository();
    final event = _event(id: 'all_action_event', title: '세 가지를 마친 날');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '기쁨을 새겼습니다.',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [event]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: {event.id: mark},
        companionDiaryEntries: [_diaryEntry(entryDate: DateTime(2026, 6, 10))],
        completedBibleChapterReadAts: {'1:1': DateTime.utc(2026, 6, 9, 16)},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-all-actions-marker-2026-6-10')),
      findsOneWidget,
    );
    final allActionsMarker = tester.widget<Container>(
      find.byKey(const ValueKey('calendar-all-actions-marker-2026-6-10')),
    );
    final allActionsDecoration = allActionsMarker.decoration! as BoxDecoration;
    expect(allActionsDecoration.shape, BoxShape.circle);
    expect(allActionsDecoration.color, AppColorPalette.classic.successBottom);
    final allActionsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-all-actions-marker-2026-6-10')),
        matching: find.byIcon(Icons.check_rounded),
      ),
    );
    expect(allActionsIcon.color, AppColors.fgOnDark);
    expect(
      find.byKey(const ValueKey('calendar-emotion-marker-2026-6-10')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bible-reading-marker-2026-6-10')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-10')),
      findsNothing,
    );
  });

  testWidgets('통독과 다이어리만 한 날은 날짜 아래 한 줄에 원형 아이콘을 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MockStoryRepository();
    when(
      () => repository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    await tester.pumpWidget(
      _wrap(
        repository: repository,
        marks: const {},
        width: 350,
        companionDiaryEntries: [_diaryEntry(entryDate: DateTime(2026, 6, 10))],
        completedBibleChapterReadAts: {'1:1': DateTime.utc(2026, 6, 9, 16)},
        now: DateTime.utc(2026, 6, 10),
      ),
    );
    await tester.pumpAndSettle();

    final diaryMarker = find.byKey(
      const ValueKey('companion-diary-marker-2026-6-10'),
    );
    final bibleMarker = find.byKey(
      const ValueKey('bible-reading-marker-2026-6-10'),
    );
    expect(diaryMarker, findsOneWidget);
    expect(bibleMarker, findsOneWidget);
    final diaryDecoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: diaryMarker,
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    final bibleDecoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: bibleMarker,
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(diaryDecoration.shape, BoxShape.circle);
    expect(bibleDecoration.shape, BoxShape.circle);
    expect(tester.getSize(diaryMarker), tester.getSize(bibleMarker));
    expect(
      tester.getTopLeft(diaryMarker).dy,
      moreOrLessEquals(tester.getTopLeft(bibleMarker).dy, epsilon: 0.1),
    );
    final dayRect = tester.getRect(
      find.byKey(const ValueKey('emotion-calendar-day-2026-6-10')),
    );
    for (final marker in [diaryMarker, bibleMarker]) {
      final markerRect = tester.getRect(marker);
      expect(markerRect.left, greaterThanOrEqualTo(dayRect.left));
      expect(markerRect.right, lessThanOrEqualTo(dayRect.right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('감정 row를 누르면 상세 이동 콜백을 호출한다', (tester) async {
    final event = _event(id: 'event_1', title: '홍해를 건너다');
    final mark = _mark(
      event: event,
      emotionKey: 'joy',
      emotionLabel: '기쁨',
      note: '',
      updatedAt: DateTime.utc(2026, 6, 9, 16),
    );
    var openCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileEmotionMarksList(
            marks: [mark],
            eventById: {event.id: event},
            onOpenEventDetail: (_) => openCount++,
            loading: false,
            hasError: false,
            emptyMessage: '감정이 없습니다.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홍해를 건너다'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('홍해를 건너다'));
    await tester.pump();

    expect(find.text('기쁨'), findsNothing);
    expect(find.text('기쁨으로 새겼어요.'), findsNothing);
    expect(openCount, 1);
  });

  testWidgets('날짜를 선택해도 감정 기록 리스트는 달력 아래에 직접 노출하지 않는다', (tester) async {
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

    expect(find.text('만나를 먹다'), findsNothing);
    expect(find.text('오늘 필요한 만큼 채워주심을 봅니다.'), findsNothing);
    expect(find.byIcon(Icons.sentiment_satisfied_alt_rounded), findsOneWidget);
  });

  testWidgets('선택한 날짜는 팔레트 날짜색과 칸 배경으로 표시된다', (tester) async {
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
    expect(decoration?.color, AppColorPalette.classic.selectionFill);

    final dayText = tester.widget<Text>(find.text('8'));
    expect(dayText.style?.color, AppColorPalette.classic.text);
  });
}
