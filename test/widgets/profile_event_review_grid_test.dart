import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/widgets/profile/profile_event_review_grid.dart';

void main() {
  testWidgets('공용 이야기 그리드는 2열과 한 줄 수동 스크롤을 세 글자 크기에서 유지한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const characterCodes = ['one', 'two', 'three', 'four', 'five'];
    final charactersByCode = {
      for (final code in characterCodes)
        code: Character(
          id: code,
          code: code,
          name: '$code 등장인물 이름',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 1,
        ),
    };
    final events = [
      _event(
        'a',
        '카드 폭보다 훨씬 긴 첫 번째 이야기 제목을 끝까지 확인합니다',
        'era-a',
        1,
        placeName: '아주 긴 지역 이름과 주변 일대 전체',
        characterCodes: characterCodes,
      ),
      _event(
        'b',
        '둘째 이야기',
        'era-a',
        2,
        placeName: '두 번째 장소',
        characterCodes: characterCodes,
      ),
      _event(
        'c',
        '셋째 이야기',
        'era-a',
        3,
        placeName: '세 번째 장소',
        characterCodes: characterCodes,
      ),
      _event(
        'd',
        '다음 시대 이야기',
        'era-b',
        4,
        placeName: '네 번째 장소',
        characterCodes: characterCodes,
      ),
    ];
    for (final textScale in [1.0, 1.2, 1.4]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ProfileEventReviewGrid(
                  events: events,
                  eras: const [
                    Era(
                      id: 'era-a',
                      code: 'era_a',
                      testament: 'old',
                      name: '첫 시대',
                      startYear: -1000,
                      endYear: -500,
                      mapCenterLat: null,
                      mapCenterLng: null,
                      mapZoom: null,
                      displayOrder: 1,
                    ),
                    Era(
                      id: 'era-b',
                      code: 'era_b',
                      testament: 'new',
                      name: '다음 시대',
                      startYear: 1,
                      endYear: 100,
                      mapCenterLat: null,
                      mapCenterLng: null,
                      mapZoom: null,
                      displayOrder: 2,
                    ),
                  ],
                  charactersByCode: charactersByCode,
                  completedEventIds: const {},
                  eventEmotionMarks: const {},
                  quizAttemptSummaries: const {},
                  scrollable: false,
                  onOpenEventDetail: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('카드에서 숨길 이야기 요약'), findsNothing);
      final first = tester.getRect(
        find.byKey(const ValueKey('story-card-surface-reviewGrid-a')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('story-card-surface-reviewGrid-b')),
      );
      final third = tester.getRect(
        find.byKey(const ValueKey('story-card-surface-reviewGrid-c')),
      );
      expect(second.top, closeTo(first.top, 0.1));
      expect(third.top, greaterThan(first.bottom));
      expect(first.width, greaterThan(150));

      final thumbnailFinder = find.byKey(
        const ValueKey('story-thumbnail-frame-reviewGrid-a'),
      );
      expect(tester.widget(thumbnailFinder), isA<ClipOval>());
      final thumbnailSize = tester.getSize(thumbnailFinder);
      expect(thumbnailSize.width, closeTo((first.width - 20) * 0.5, 1.0));
      expect(thumbnailSize.height, closeTo(thumbnailSize.width, 0.1));
      expect(first.height, lessThan(190));

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('story-card-title-reviewGrid-a')),
      );
      expect(title.maxLines, 1);
      expect(title.softWrap, isFalse);
      expect(
        find.byKey(const ValueKey('story-card-title-scroll-reviewGrid-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-card-title-fade-reviewGrid-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-card-meta-scroll-reviewGrid-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-card-meta-fade-reviewGrid-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-card-characters-scroll-reviewGrid-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-card-characters-fade-reviewGrid-a')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    final titleScroll = find.byKey(
      const ValueKey('story-card-title-scroll-reviewGrid-a'),
    );
    await tester.drag(titleScroll, const Offset(-90, 0));
    await tester.pump();
    final titleScrollable = find.descendant(
      of: titleScroll,
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(titleScrollable).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('좁은 검색 결과 열에서도 긴 시대명이 오버플로하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 96,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileEventEraDivider(
                      eraId: 'era_nt_public_ministry',
                      label: '예수님의 공생애',
                    ),
                    ProfileEventEraDivider(
                      eraId: 'era_exile_return',
                      label: '포로 및 포로 후기',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('예수님의 공생애'), findsOneWidget);
    expect(find.text('포로 및 포로 후기'), findsOneWidget);
  });
}

StoryEvent _event(
  String id,
  String title,
  String eraId,
  int storyIndex, {
  String? placeName,
  List<String> characterCodes = const [],
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'landmark-$id',
    eraId: eraId,
    title: title,
    summary: '카드에서 숨길 이야기 요약',
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    rankInEra: storyIndex,
    globalRank: storyIndex,
    placeName: placeName,
    lat: null,
    lng: null,
    characterCodes: characterCodes,
    bibleRefs: const [],
  );
}
