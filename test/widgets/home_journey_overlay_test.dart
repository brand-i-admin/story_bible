import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/home/home_journey_overlay.dart';
import 'package:story_bible/widgets/pulse_highlight.dart';

void main() {
  final events = [
    _event(id: 'previous', title: '이전 이야기', rank: 1),
    _event(id: 'recommended', title: '오늘의 추천 이야기', rank: 2),
    _event(id: 'next', title: '다음 이야기', rank: 3),
  ];

  test('오늘과 지도 타임라인은 같은 이야기 카드에 표현 모드만 다르게 전달한다', () {
    final todaySource = File(
      'lib/widgets/home/home_journey_overlay.dart',
    ).readAsStringSync();
    final timelineSource = File(
      'lib/widgets/event_timeline_row.dart',
    ).readAsStringSync();

    expect(todaySource, contains('StoryEventThumbCard('));
    expect(timelineSource, contains('StoryEventThumbCard('));
    expect(todaySource, contains('StoryEventCardPresentation.todayCurrent'));
    expect(todaySource, contains('StoryEventCardPresentation.todayAdjacent'));
    expect(timelineSource, contains('StoryEventCardPresentation.mapTimeline'));
  });

  testWidgets('별도 패널 없이 추천 전후 이야기 3개와 낮은 퀵 액션을 렌더한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            currentEraDividerAnchorKey: const ValueKey(
              'current-era-divider-anchor',
            ),
            events: events,
            recommendedEventId: 'recommended',
            currentEventId: 'recommended',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: true,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 14장',
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: _discardDiarySave,
            onDeleteDiary: _discardDiaryDelete,
            onContinueBibleReading: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('신앙 다이어리 & 통독'), findsNothing);
    expect(find.text('이전 이야기'), findsWidgets);
    expect(find.text('오늘의 추천 이야기'), findsOneWidget);
    expect(find.text('오늘의 이야기'), findsOneWidget);
    expect(find.text('현재 이야기'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-current-era-divider-era-1')),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('current-era-divider-anchor'))),
      tester.getRect(
        find.byKey(const ValueKey('home-current-era-divider-era-1')),
      ),
    );
    final previousRect = tester.getRect(
      find.byKey(const ValueKey('home-journey-card-surface-frame-previous')),
    );
    final currentRect = tester.getRect(
      find.byKey(const ValueKey('home-journey-card-surface-frame-recommended')),
    );
    final nextRect = tester.getRect(
      find.byKey(const ValueKey('home-journey-card-surface-frame-next')),
    );
    expect(previousRect.bottom, closeTo(currentRect.bottom, 0.1));
    expect(nextRect.bottom, closeTo(currentRect.bottom, 0.1));
    expect(currentRect.left - previousRect.right, inInclusiveRange(3, 5));
    expect(nextRect.left - currentRect.right, inInclusiveRange(3, 5));
    expect(find.text('다음 이야기'), findsWidgets);
    expect(
      find.byKey(const ValueKey('home-story-section-header')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-story-page-view'))).dy,
      lessThan(8),
    );
    expect(
      find.byKey(const ValueKey('home-journey-panel-toggle')),
      findsNothing,
    );
    expect(find.text('다이어리'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.text('기록하기'), findsOneWidget);
    expect(find.text('통독'), findsOneWidget);
    expect(find.text('창세기 14장'), findsOneWidget);
    expect(find.text('이어읽기'), findsOneWidget);
    expect(
      tester
          .widget<PulseHighlight>(
            find.byKey(const ValueKey('home-story-task-highlight-recommended')),
          )
          .active,
      isTrue,
    );
    expect(
      tester
          .widget<PulseHighlight>(
            find.byKey(const ValueKey('home-diary-quick-action-cta-glow')),
          )
          .active,
      isTrue,
    );
    expect(
      tester
          .widget<PulseHighlight>(
            find.byKey(const ValueKey('home-bible-quick-action-cta-glow')),
          )
          .active,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('home-diary-quick-action-ripple')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-bible-quick-action-ripple')),
      findsNothing,
    );
    for (final effectId in ['diary', 'bible']) {
      final cta = tester.widget<Container>(
        find.byKey(ValueKey('home-$effectId-quick-action-cta')),
      );
      final decoration = cta.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.pill));
      expect(decoration.border, isNotNull);

      final symbolRing = tester.widget<Container>(
        find.byKey(ValueKey('home-$effectId-quick-action-symbol-ring')),
      );
      final symbolDecoration = symbolRing.decoration! as BoxDecoration;
      expect(symbolDecoration.shape, BoxShape.circle);
      expect(symbolDecoration.border, isNotNull);
      final symbol = find.descendant(
        of: find.byKey(ValueKey('home-$effectId-quick-action-symbol-ring')),
        matching: find.byType(Icon),
      );
      expect(symbol, findsOneWidget);
      expect(
        tester.getCenter(symbol),
        tester.getCenter(
          find.byKey(ValueKey('home-$effectId-quick-action-symbol-ring')),
        ),
      );
    }
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home-diary-quick-action')),
        matching: find.byType(PulseHighlight),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home-bible-quick-action')),
        matching: find.byType(PulseHighlight),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('현재 카드는 직사각형 썸네일, 양옆 카드는 꽉 찬 정사각형 썸네일을 쓴다', (tester) async {
    final detailedEvents = [
      _event(
        id: 'previous',
        title: '이전 이야기',
        rank: 1,
        characterCodes: const ['noah'],
      ),
      _event(
        id: 'recommended',
        title: '오늘의 추천 이야기',
        rank: 2,
        characterCodes: const ['noah'],
      ),
      _event(
        id: 'next',
        title: '다음 이야기',
        rank: 3,
        characterCodes: const ['noah'],
      ),
    ];
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 445,
            child: HomeJourneyOverlay(
              events: detailedEvents,
              recommendedEventId: 'recommended',
              currentEventId: 'recommended',
              eras: const [_era],
              charactersByCode: const {'noah': _noah},
              eventEmotionMarks: const {},
              quizAttemptSummaries: const {},
              isAuthenticated: true,
              todayDiary: null,
              diaryLoading: false,
              diaryError: null,
              bibleTargetLabel: '창세기 14장',
              onOpenStory: (_) {},
              onCurrentStoryChanged: (_) {},
              onSaveDiary: _discardDiarySave,
              onDeleteDiary: _discardDiaryDelete,
              onContinueBibleReading: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final pageRect = tester.getRect(
      find.byKey(const ValueKey('home-story-page-view')),
    );
    final previousRect = tester.getRect(
      find.byKey(const ValueKey('home-story-task-highlight-previous')),
    );
    final currentRect = tester.getRect(
      find.byKey(const ValueKey('home-story-task-highlight-recommended')),
    );
    final nextRect = tester.getRect(
      find.byKey(const ValueKey('home-story-task-highlight-next')),
    );
    final previousThumbnailRect = tester.getRect(
      find.byKey(
        const ValueKey('story-thumbnail-frame-todayAdjacent-previous'),
      ),
    );
    final currentThumbnailRect = tester.getRect(
      find.byKey(
        const ValueKey('story-thumbnail-frame-todayCurrent-recommended'),
      ),
    );
    final nextThumbnailRect = tester.getRect(
      find.byKey(const ValueKey('story-thumbnail-frame-todayAdjacent-next')),
    );

    expect(currentRect.width, closeTo(172, 2));
    expect(currentRect.width / previousRect.width, greaterThan(1.6));
    expect(nextRect.width, closeTo(previousRect.width, 0.5));
    final previousVisibleFraction =
        previousRect.intersect(pageRect).width / previousRect.width;
    final nextVisibleFraction =
        nextRect.intersect(pageRect).width / nextRect.width;
    expect(previousVisibleFraction, greaterThan(0.7));
    expect(nextVisibleFraction, greaterThan(0.7));
    expect(currentRect.left - previousRect.right, inInclusiveRange(0, 12));
    expect(nextRect.left - currentRect.right, inInclusiveRange(0, 12));
    expect(previousRect.height / currentRect.height, closeTo(0.7, 0.03));
    expect(nextRect.height / currentRect.height, closeTo(0.7, 0.03));

    final previousTitle = tester.widget<Text>(
      find.byKey(const ValueKey('story-card-title-todayAdjacent-previous')),
    );
    final currentTitle = tester.widget<Text>(
      find.byKey(const ValueKey('story-card-title-todayCurrent-recommended')),
    );
    final nextTitle = tester.widget<Text>(
      find.byKey(const ValueKey('story-card-title-todayAdjacent-next')),
    );
    expect(
      currentTitle.style!.fontSize,
      greaterThan(previousTitle.style!.fontSize!),
    );
    expect(
      currentTitle.style!.fontSize,
      greaterThan(nextTitle.style!.fontSize!),
    );
    expect(previousTitle.maxLines, 1);
    expect(previousTitle.overflow, TextOverflow.ellipsis);
    expect(previousTitle.softWrap, isFalse);
    expect(nextTitle.maxLines, 1);
    expect(nextTitle.overflow, TextOverflow.ellipsis);
    expect(nextTitle.softWrap, isFalse);
    expect(currentTitle.maxLines, 1);
    expect(currentTitle.softWrap, isFalse);
    expect(
      find.byKey(
        const ValueKey('story-card-title-scroll-todayCurrent-recommended'),
      ),
      findsOneWidget,
    );
    final currentMetaScroll = tester.widget<SingleChildScrollView>(
      find.byKey(
        const ValueKey('story-card-meta-scroll-todayCurrent-recommended'),
      ),
    );
    expect(currentMetaScroll.scrollDirection, Axis.horizontal);
    expect(
      find.byKey(
        const ValueKey('story-card-characters-scroll-todayCurrent-recommended'),
      ),
      findsOneWidget,
    );
    for (final eventId in ['previous', 'next']) {
      final meta = tester.widget<Text>(
        find.byKey(ValueKey('story-card-meta-ellipsis-todayAdjacent-$eventId')),
      );
      expect(meta.maxLines, 1);
      expect(meta.overflow, TextOverflow.ellipsis);
      expect(
        find.byKey(
          ValueKey('story-card-characters-scroll-todayAdjacent-$eventId'),
        ),
        findsOneWidget,
      );
    }

    for (final (presentation, eventId) in [
      ('todayAdjacent', 'previous'),
      ('todayCurrent', 'recommended'),
      ('todayAdjacent', 'next'),
    ]) {
      final surface = tester.widget<Container>(
        find.byKey(ValueKey('story-card-surface-$presentation-$eventId')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
    }
    expect(
      previousThumbnailRect.width / previousThumbnailRect.height,
      closeTo(8 / 5, 0.06),
    );
    expect(
      nextThumbnailRect.width / nextThumbnailRect.height,
      closeTo(8 / 5, 0.06),
    );
    expect(
      currentThumbnailRect.width / currentThumbnailRect.height,
      closeTo(8 / 5, 0.06),
    );
    expect(currentRect.width - currentThumbnailRect.width, greaterThan(20));
    expect(find.text('이전 이야기 요약'), findsNothing);
    expect(find.text('오늘의 추천 이야기 요약'), findsNothing);
    expect(find.text('다음 이야기 요약'), findsNothing);
    for (final eventId in ['previous', 'recommended', 'next']) {
      final cardFinder = find.byKey(
        ValueKey('home-story-task-highlight-$eventId'),
      );
      final characterFinder = find.descendant(
        of: cardFinder,
        matching: find.text('노아'),
      );
      expect(characterFinder, findsOneWidget);
      expect(
        tester.getRect(characterFinder).bottom,
        lessThanOrEqualTo(tester.getRect(cardFinder).bottom),
      );
    }
    expect(currentRect.height, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('긴 제목과 지역과 인물은 세 글자 크기에서 카드 밖으로 넘치지 않는다', (tester) async {
    const screenSize = Size(390, 780);
    final longEvents = [
      _event(
        id: 'previous-long',
        title: '이전 이야기의 아주 긴 제목도 한 줄에서 정리됩니다',
        rank: 1,
        placeName: '갈릴리와 가버나움과 데가볼리 일대의 아주 긴 지역 이름',
        characterCodes: const ['noah', 'abraham', 'isaac', 'jacob'],
      ),
      _event(
        id: 'recommended-long',
        title: '현재 이야기의 아주 긴 제목은 천천히 끝까지 자동으로 이동합니다',
        rank: 2,
        placeName: '예루살렘과 베다니와 감람산을 잇는 아주 긴 지역 이름',
        characterCodes: const ['noah', 'abraham', 'isaac', 'jacob'],
      ),
      _event(
        id: 'next-long',
        title: '다음 이야기의 아주 긴 제목도 한 줄에서 정리됩니다',
        rank: 3,
        placeName: '유대와 사마리아와 땅끝까지 이어지는 아주 긴 지역 이름',
        characterCodes: const ['noah', 'abraham', 'isaac', 'jacob'],
      ),
    ];
    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final textScale in [1.0, 1.2, 1.4]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: screenSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SizedBox(
                height: 445,
                child: HomeJourneyOverlay(
                  events: longEvents,
                  recommendedEventId: 'recommended-long',
                  currentEventId: 'recommended-long',
                  eras: const [_era],
                  charactersByCode: const {'noah': _noah},
                  eventEmotionMarks: const {},
                  quizAttemptSummaries: const {},
                  isAuthenticated: true,
                  todayDiary: null,
                  diaryLoading: false,
                  diaryError: null,
                  bibleTargetLabel: '창세기 14장',
                  onOpenStory: (_) {},
                  onCurrentStoryChanged: (_) {},
                  onSaveDiary: _discardDiarySave,
                  onDeleteDiary: _discardDiaryDelete,
                  onContinueBibleReading: () {},
                  onOpenProfile: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final currentCard = tester.getRect(
        find.byKey(
          const ValueKey('home-story-task-highlight-recommended-long'),
        ),
      );
      for (final key in [
        'story-card-title-scroll-todayCurrent-recommended-long',
        'story-card-meta-scroll-todayCurrent-recommended-long',
        'story-card-characters-scroll-todayCurrent-recommended-long',
      ]) {
        final childRect = tester.getRect(find.byKey(ValueKey(key)));
        expect(
          childRect.left,
          greaterThanOrEqualTo(currentCard.left),
          reason: 'textScale=$textScale, key=$key',
        );
        expect(
          childRect.right,
          lessThanOrEqualTo(currentCard.right),
          reason: 'textScale=$textScale, key=$key',
        );
        expect(
          childRect.bottom,
          lessThanOrEqualTo(currentCard.bottom),
          reason: 'textScale=$textScale, key=$key',
        );
      }
      expect(tester.takeException(), isNull, reason: 'textScale=$textScale');
    }

    final orderBadgeTexts = tester.widgetList<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            const {'1', '2', '3'}.contains(widget.data) &&
            widget.style?.fontSize == 12,
      ),
    );
    expect(orderBadgeTexts, isNotEmpty);
    for (final badgeText in orderBadgeTexts) {
      expect(badgeText.textScaler, TextScaler.noScaling);
      expect(badgeText.textAlign, TextAlign.center);
    }

    final titleScroll = find.byKey(
      const ValueKey('story-card-title-scroll-todayCurrent-recommended-long'),
    );
    final titleScrollable = find.descendant(
      of: titleScroll,
      matching: find.byType(Scrollable),
    );
    final titlePosition = tester
        .state<ScrollableState>(titleScrollable)
        .position;
    expect(titlePosition.maxScrollExtent, greaterThan(0));
    final titleAnimationDuration = Duration(
      milliseconds: (titlePosition.maxScrollExtent * 26).round().clamp(
        2400,
        7200,
      ),
    );
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(titleAnimationDuration);
    expect(titlePosition.pixels, closeTo(titlePosition.maxScrollExtent, 0.5));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(titlePosition.pixels, lessThan(titlePosition.maxScrollExtent / 2));
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      titlePosition.pixels,
      greaterThan(0),
      reason: '처음으로 돌아온 제목은 다음 자동 스크롤을 다시 시작해야 한다.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('비로그인 다이어리 탭은 내정보 이동 버튼이 있는 안내 팝업을 연다', (tester) async {
    var profileOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: events,
            recommendedEventId: 'recommended',
            currentEventId: 'recommended',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: false,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 1장',
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: null,
            onDeleteDiary: null,
            onContinueBibleReading: () {},
            onOpenProfile: () => profileOpened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-diary-quick-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('내정보로 이동'), findsOneWidget);
    expect(find.text('내정보 화면에서 로그인한 뒤 다시 이용해 주세요.'), findsOneWidget);

    await tester.tap(find.text('내정보로 이동'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(profileOpened, isTrue);
  });

  testWidgets('비로그인 통독 탭도 같은 로그인 안내 팝업을 연다', (tester) async {
    var profileOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: events,
            recommendedEventId: 'recommended',
            currentEventId: 'recommended',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: false,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 1장',
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: null,
            onDeleteDiary: null,
            onContinueBibleReading: () {},
            onOpenProfile: () => profileOpened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-bible-quick-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('내정보로 이동'), findsOneWidget);
    expect(find.text('내정보 화면에서 로그인한 뒤 다시 이용해 주세요.'), findsOneWidget);

    await tester.tap(find.text('내정보로 이동'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(profileOpened, isTrue);
  });

  testWidgets('오늘 다이어리가 있으면 작성 정보를 표시하고 상세 팝업을 연다', (tester) async {
    final now = DateTime(2026, 7, 14);
    final entry = UserCompanionDiaryEntry(
      id: 'diary-today',
      userId: 'user-1',
      entryDate: now,
      title: '오늘의 감사',
      body: '함께하심을 기억합니다.',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: events,
            recommendedEventId: 'recommended',
            currentEventId: 'recommended',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: true,
            todayDiary: entry,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 14장',
            todayStoryCompleted: true,
            bibleReadingCompleted: true,
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: _discardDiarySave,
            onDeleteDiary: _discardDiaryDelete,
            onContinueBibleReading: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<PulseHighlight>(
            find.byKey(const ValueKey('home-story-task-highlight-recommended')),
          )
          .active,
      isFalse,
    );
    expect(find.text('오늘의 이야기'), findsNothing);
    expect(find.text('현재 이야기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-diary-quick-action-cta-glow')),
      findsNothing,
    );
    expect(
      tester
          .widget<PulseHighlight>(
            find.byKey(const ValueKey('home-bible-quick-action-cta-glow')),
          )
          .active,
      isFalse,
    );
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.text('오늘의 감사'), findsOneWidget);
    expect(find.text('함께하심을 기억합니다.'), findsOneWidget);
    expect(find.text('기록하기'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-diary-quick-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('다이어리 상세'), findsOneWidget);
    expect(find.text('오늘의 감사'), findsNWidgets(2));
    expect(find.text('함께하심을 기억합니다.'), findsNWidgets(2));
    expect(find.text('수정'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('아주크게에서도 오늘 다이어리 제목은 한 줄 수동 스크롤이고 본문은 세 줄로 제한한다', (tester) async {
    final now = DateTime(2026, 7, 14);
    final entry = UserCompanionDiaryEntry(
      id: 'diary-today-long-title',
      userId: 'user-1',
      entryDate: now,
      title: '은혜를 오래 기억하며 오늘의 걸음을 천천히 돌아보는 다이어리 제목',
      body: '말씀을 묵상하며 하루의 모든 순간에 함께하신 은혜를 차분히 되새겼습니다.',
      createdAt: now,
      updatedAt: now,
    );
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: HomeJourneyOverlay(
              events: events,
              recommendedEventId: 'recommended',
              currentEventId: 'recommended',
              eras: const [_era],
              charactersByCode: const {},
              eventEmotionMarks: const {},
              quizAttemptSummaries: const {},
              isAuthenticated: true,
              todayDiary: entry,
              diaryLoading: false,
              diaryError: null,
              bibleTargetLabel: '창세기 14장',
              onOpenStory: (_) {},
              onCurrentStoryChanged: (_) {},
              onSaveDiary: _discardDiarySave,
              onDeleteDiary: _discardDiaryDelete,
              onContinueBibleReading: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('home-diary-entry-title')),
    );
    final body = tester.widget<Text>(
      find.byKey(const ValueKey('home-diary-entry-body')),
    );
    expect(title.maxLines, 1);
    expect(title.softWrap, isFalse);
    expect(title.textScaler, isNotNull);
    expect(title.textScaler!.scale(1), 1.4);
    expect(title.style?.fontWeight, FontWeight.w900);
    expect(body.maxLines, 3);
    expect(body.overflow, TextOverflow.ellipsis);
    expect(
      find.byKey(const ValueKey('home-diary-entry-title-scroll')),
      findsOneWidget,
    );
    final titleScroll = find.byKey(
      const ValueKey('home-diary-entry-title-scroll'),
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

  testWidgets('이야기 덱을 옆으로 넘기면 현재 이야기가 다음 이야기로 바뀐다', (tester) async {
    StoryEvent? currentEvent;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HomeJourneyOverlay(
              events: events,
              recommendedEventId: 'recommended',
              currentEventId: currentEvent?.id ?? 'recommended',
              eras: const [_era],
              charactersByCode: const {},
              eventEmotionMarks: const {},
              quizAttemptSummaries: const {},
              isAuthenticated: true,
              todayDiary: null,
              diaryLoading: false,
              diaryError: null,
              bibleTargetLabel: '창세기 14장',
              onOpenStory: (_) {},
              onCurrentStoryChanged: (event) {
                setState(() => currentEvent = event);
              },
              onSaveDiary: _discardDiarySave,
              onDeleteDiary: _discardDiaryDelete,
              onContinueBibleReading: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    );

    final pageView = find.byKey(const ValueKey('home-story-page-view'));
    expect(pageView, findsOneWidget);

    await tester.drag(pageView, const Offset(-420, 0));
    await tester.pump(const Duration(milliseconds: 350));

    expect(currentEvent?.id, 'next');
    expect(find.text('현재 이야기'), findsOneWidget);
  });

  testWidgets('전체 첫 이야기 앞에는 없음 라벨과 탐험 정렬 안내 카드가 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: events,
            recommendedEventId: 'previous',
            currentEventId: 'previous',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: true,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 1장',
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: _discardDiarySave,
            onDeleteDiary: _discardDiaryDelete,
            onContinueBibleReading: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('이야기\n없음'), findsOneWidget);
    expect(find.text('사건에 감정을 새기면\n그 사건 기준으로\n이야기 정렬이 바뀌어요'), findsWidgets);
  });

  testWidgets('마지막 이야기를 완료하면 마지막 카드가 현재로 남고 안내 카드와 하단이 맞는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: events,
            recommendedEventId: 'next',
            currentEventId: 'next',
            eras: const [_era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: true,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 14장',
            todayStoryCompleted: true,
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: _discardDiarySave,
            onDeleteDiary: _discardDiaryDelete,
            onContinueBibleReading: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('오늘의 이야기'), findsNothing);
    expect(find.text('현재 이야기'), findsOneWidget);
    expect(find.text('이야기\n없음'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-journey-right-boundary-overlay')),
        matching: find.byKey(
          const ValueKey('home-journey-missing-boundary-badge'),
        ),
      ),
      findsOneWidget,
    );
    final currentCard = tester.getRect(
      find.byKey(const ValueKey('home-journey-card-surface-frame-next')),
    );
    final adjacentHintCard = tester.getRect(
      find.byKey(const ValueKey('home-exploration-sort-hint-card')),
    );
    expect(adjacentHintCard.bottom, closeTo(currentCard.bottom, 0.1));

    await tester.drag(
      find.byKey(const ValueKey('home-story-page-view')),
      const Offset(-420, 0),
    );
    await tester.pump(const Duration(milliseconds: 350));

    final currentHintCard = tester.getRect(
      find.byKey(const ValueKey('home-exploration-sort-hint-card')),
    );
    final adjacentLastCard = tester.getRect(
      find.byKey(const ValueKey('home-journey-card-surface-frame-next')),
    );
    expect(
      find.byKey(const ValueKey('home-exploration-sort-hint-current')),
      findsOneWidget,
    );
    expect(currentHintCard.width, greaterThan(adjacentHintCard.width * 1.4));
    expect(currentHintCard.width, greaterThan(adjacentLastCard.width * 1.4));
  });

  testWidgets('좁은 실제 기기 폭에서 보통과 아주큰 탐험 정렬 안내가 넘치지 않는다', (tester) async {
    const screenSize = Size(390, 900);
    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final textScale in [1.0, 1.4]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: screenSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SizedBox(
                height: 445,
                child: HomeJourneyOverlay(
                  events: events,
                  recommendedEventId: 'previous',
                  currentEventId: 'previous',
                  eras: const [_era],
                  charactersByCode: const {},
                  eventEmotionMarks: const {},
                  quizAttemptSummaries: const {},
                  isAuthenticated: true,
                  todayDiary: null,
                  diaryLoading: false,
                  diaryError: null,
                  bibleTargetLabel: '창세기 14장',
                  onOpenStory: (_) {},
                  onCurrentStoryChanged: (_) {},
                  onSaveDiary: _discardDiarySave,
                  onDeleteDiary: _discardDiaryDelete,
                  onContinueBibleReading: () {},
                  onOpenProfile: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final hintCard = find.byKey(
        const ValueKey('home-exploration-sort-hint-card'),
      );
      final hintBody = find.byKey(
        const ValueKey('home-exploration-sort-hint-body'),
      );
      expect(hintCard, findsOneWidget);
      expect(hintBody, findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-exploration-sort-hint-fit')),
        findsOneWidget,
      );
      expect(
        tester.getRect(hintBody).bottom,
        lessThanOrEqualTo(tester.getRect(hintCard).bottom),
        reason: 'textScale=$textScale',
      );
      expect(tester.takeException(), isNull, reason: 'textScale=$textScale');
    }
  });

  testWidgets('다른 시대로 넘어가는 카드 사이에는 시대 이동 라벨이 보인다', (tester) async {
    final boundaryEvents = [
      _event(
        id: 'primeval-last',
        title: '원역사 마지막',
        rank: 1,
        eraId: 'era-primeval',
      ),
      _event(
        id: 'patriarch-first',
        title: '족장 시대 첫 이야기',
        rank: 2,
        eraId: 'era-patriarch',
      ),
    ];
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(palette: AppColorPalette.blackMap),
        home: Scaffold(
          body: HomeJourneyOverlay(
            events: boundaryEvents,
            recommendedEventId: 'patriarch-first',
            currentEventId: 'patriarch-first',
            eras: const [_primevalEra, _era],
            charactersByCode: const {},
            eventEmotionMarks: const {},
            quizAttemptSummaries: const {},
            isAuthenticated: true,
            todayDiary: null,
            diaryLoading: false,
            diaryError: null,
            bibleTargetLabel: '창세기 12장',
            onOpenStory: (_) {},
            onCurrentStoryChanged: (_) {},
            onSaveDiary: _discardDiarySave,
            onDeleteDiary: _discardDiaryDelete,
            onContinueBibleReading: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );

    expect(find.text('원역사\n이동'), findsOneWidget);
    expect(find.text('이야기\n없음'), findsOneWidget);
    final boundaryBadge = tester.widget<Container>(
      find.byKey(const ValueKey('home-journey-era-boundary-badge')),
    );
    final boundaryDecoration = boundaryBadge.decoration! as BoxDecoration;
    expect(
      boundaryDecoration.color,
      AppColorPalette.blackMap.utilitySelectedBackground.withValues(alpha: 1),
    );
    expect(
      tester.widget<Text>(find.text('원역사\n이동')).style?.color,
      AppColors.fgOnDark,
    );
    final missingBadge = tester.widget<Container>(
      find.byKey(const ValueKey('home-journey-missing-boundary-badge')),
    );
    final missingDecoration = missingBadge.decoration! as BoxDecoration;
    expect(
      missingDecoration.color,
      AppColorPalette.blackMap.utilitySelectedBackground.withValues(alpha: 1),
    );
    expect(
      tester.widget<Text>(find.text('이야기\n없음')).style?.color,
      AppColors.fgOnDark,
    );
  });

  testWidgets('이야기 덱은 하단 패널 표면이나 접기 핸들을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: HomeJourneyOverlay(
              events: events,
              recommendedEventId: 'recommended',
              currentEventId: 'recommended',
              eras: const [_era],
              charactersByCode: const {},
              eventEmotionMarks: const {},
              quizAttemptSummaries: const {},
              isAuthenticated: true,
              todayDiary: null,
              diaryLoading: false,
              diaryError: null,
              bibleTargetLabel: '창세기 14장',
              onOpenStory: (_) {},
              onCurrentStoryChanged: (_) {},
              onSaveDiary: _discardDiarySave,
              onDeleteDiary: _discardDiaryDelete,
              onContinueBibleReading: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey('home-journey-panel-toggle')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 아주큰 글자에서도 두 섹션과 퀴 액션이 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 780),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(
            body: SizedBox(
              height: 445,
              child: HomeJourneyOverlay(
                events: events,
                recommendedEventId: 'recommended',
                currentEventId: 'recommended',
                eras: const [_era],
                charactersByCode: const {},
                eventEmotionMarks: const {},
                quizAttemptSummaries: const {},
                isAuthenticated: true,
                todayDiary: null,
                diaryLoading: false,
                diaryError: null,
                bibleTargetLabel: '창세기 14장',
                onOpenStory: (_) {},
                onCurrentStoryChanged: (_) {},
                onSaveDiary: _discardDiarySave,
                onDeleteDiary: _discardDiaryDelete,
                onContinueBibleReading: () {},
                onOpenProfile: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('home-story-page-view')), findsOneWidget);
    expect(find.text('신앙 다이어리 & 통독'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-diary-quick-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-bible-quick-action')),
      findsOneWidget,
    );
    final diarySubtitle = tester.widget<Text>(find.text('오늘을 기록'));
    expect(diarySubtitle.overflow, TextOverflow.ellipsis);
    expect(diarySubtitle.maxLines, 3);
    final diaryCard = find.byKey(const ValueKey('home-diary-quick-action'));
    expect(
      tester.getRect(find.text('오늘을 기록')).bottom,
      lessThanOrEqualTo(tester.getRect(diaryCard).bottom),
    );
    for (final (effectId, label) in [('diary', '기록하기'), ('bible', '이어읽기')]) {
      final card = find.byKey(ValueKey('home-$effectId-quick-action'));
      final cta = find.byKey(ValueKey('home-$effectId-quick-action-cta'));
      final labelFinder = find.descendant(of: cta, matching: find.text(label));
      expect(labelFinder, findsOneWidget);
      final cardRect = tester.getRect(card);
      final ctaRect = tester.getRect(cta);
      final labelRect = tester.getRect(labelFinder);
      expect(
        ctaRect.center.dx,
        closeTo(cardRect.center.dx, 0.5),
        reason: '$label CTA는 카드 가로 중앙에 있어야 한다.',
      );
      expect(
        labelRect.left,
        greaterThanOrEqualTo(ctaRect.left),
        reason: '$label 왼쪽이 CTA 밖으로 나가면 안 된다.',
      );
      expect(
        labelRect.right,
        lessThanOrEqualTo(ctaRect.right),
        reason: '$label 오른쪽이 CTA 밖으로 나가면 안 된다.',
      );
    }
    expect(tester.takeException(), isNull);
  });
}

const _era = Era(
  id: 'era-1',
  code: 'era-patriarch',
  testament: 'old',
  name: '족장 시대',
  displayOrder: 1,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _primevalEra = Era(
  id: 'era-primeval',
  code: 'era-primeval',
  testament: 'old',
  name: '원역사 시대',
  displayOrder: 0,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

StoryEvent _event({
  required String id,
  required String title,
  required int rank,
  String eraId = 'era-1',
  String placeName = '테스트 장소',
  List<String> characterCodes = const [],
}) {
  return StoryEvent(
    id: id,
    eraId: eraId,
    title: title,
    summary: '$title 요약',
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: rank,
    rankInEra: rank,
    globalRank: rank,
    landmarkId: 'landmark-$id',
    placeName: placeName,
    lat: 31 + rank.toDouble(),
    lng: 35 + rank.toDouble(),
    characterCodes: characterCodes,
    bibleRefs: const [],
  );
}

const _noah = Character(
  id: 'character-noah',
  code: 'noah',
  name: '노아',
  tagline: null,
  description: null,
  avatarUrl: null,
  displayOrder: 1,
);

Future<UserCompanionDiaryEntry> _discardDiarySave({
  required DateTime entryDate,
  required String title,
  required String body,
}) async {
  final now = DateTime(2026, 7, 14);
  return UserCompanionDiaryEntry(
    id: 'saved',
    userId: 'user',
    entryDate: entryDate,
    title: title,
    body: body,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _discardDiaryDelete(UserCompanionDiaryEntry _) async {}
