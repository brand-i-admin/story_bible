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
import 'package:story_bible/widgets/emotion_badge_icon.dart';
import 'package:story_bible/widgets/parchment_page_scaffold.dart';
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
    expect(find.text('신앙 다이어리'), findsOneWidget);
    expect(find.text('오늘 하나님과 함께한 순간을 기록해 보세요!'), findsOneWidget);
    final diaryTitle = tester.widget<Text>(find.text('신앙 다이어리'));
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
    expect(find.text('이어 읽기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companion-diary-add-button')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('companion-diary-add-button')))
          .dy,
      greaterThan(tester.getTopLeft(find.text('오늘 하나님과 함께한 순간을 기록해 보세요!')).dy),
    );
    expect(find.textContaining('오늘 새긴 감정이 없습니다'), findsNothing);
  });

  testWidgets('남색 테마의 기록하기 버튼과 통독 도넛은 충분한 대비를 갖는다', (tester) async {
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
    final writeLabel = tester.widget<Text>(find.text('기록하기'));
    final donut = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('bible-progress-donut-indicator')),
    );

    expect(writePill.color, isNot(AppColorPalette.atlasNavy.cardSurface));
    expect(writeLabel.style?.color, AppColorPalette.atlasNavy.successBottom);
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

    expect(find.text('신앙 다이어리'), findsOneWidget);
    expect(find.text('통독 진행률'), findsOneWidget);
    expect(find.text('이어 읽기'), findsOneWidget);
    expect(find.byKey(const ValueKey('diary-content-tab-bar')), findsNothing);
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
    expect(find.text('이어 읽기'), findsOneWidget);
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
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(savedEntryDate, DateTime(2026, 6, 10));
  });

  testWidgets('오늘 신앙 다이어리가 있으면 작성 버튼을 숨기고 카드에서 상세를 연다', (tester) async {
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
    expect(
      find.byKey(const ValueKey('companion-diary-marker-2026-6-10')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('companion-diary-feature-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(find.text('갈릴리의 하루'), findsOneWidget);
    expect(find.text('말씀을 묵상하며 차분히 걸었습니다.'), findsOneWidget);

    await tester.tap(find.text('갈릴리의 하루'));
    await tester.pumpAndSettle();

    expect(find.text('신앙 다이어리 상세'), findsOneWidget);
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

    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(tester.getTopLeft(find.byType(ParchmentCard).last).dx, lessThan(24));
    expect(find.text('6월 9일'), findsOneWidget);
    expect(find.text('광야의 감사'), findsOneWidget);
    expect(find.text('작은 공급을 놓치지 않기로 했습니다.'), findsOneWidget);
    expect(find.byType(CompanionDiaryEntryPreviewCard), findsOneWidget);

    await tester.tap(find.text('광야의 감사'));
    await tester.pumpAndSettle();

    expect(find.text('신앙 다이어리 상세'), findsOneWidget);
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
    expect(source, contains("'이어 읽기'"));
    expect(
      source,
      contains('color: darkSurface ? AppColors.goldLight : AppColors.goldHi'),
    );
    expect(companionSource, contains("import '../pulse_highlight.dart';"));
    expect(
      companionSource,
      contains('duration: const Duration(milliseconds: 2100)'),
    );
    expect(companionSource, contains('clipBehavior: Clip.none'));
    expect(companionSource, contains('EdgeInsets.fromLTRB(8, 7, 8, 9)'));
    expect(
      companionSource,
      contains('color: darkSurface ? palette.successTop : AppColors.greenRim'),
    );
    expect(companionSource, contains('AppColors.greenTint1'));
    expect(companionSource, contains('diaryTitle'));
    expect(companionSource, contains('diaryBody'));
    expect(
      companionSource,
      contains('constraints: const BoxConstraints(minHeight: 158)'),
    );
    expect(companionSource, contains('maxLines: 3'));
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
    final diaryTitleTop = tester.getTopLeft(find.text('신앙 다이어리')).dy;
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
    final diaryTitleTop = tester.getTopLeft(find.text('신앙 다이어리')).dy;
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
    expect(find.byType(EmotionBadgeIcon), findsWidgets);
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
