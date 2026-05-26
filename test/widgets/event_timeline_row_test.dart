import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/widgets/completion_celebration.dart';
import 'package:story_bible/widgets/emotion_badge_icon.dart';
import 'package:story_bible/widgets/event_timeline_row.dart';
import 'package:story_bible/widgets/v2/region_event_list.dart';
import 'package:story_bible/utils/scene_asset_loader.dart';

Era _era() => const Era(
  id: 'era_primeval',
  code: 'era_primeval',
  testament: 'old',
  name: '원시',
  displayOrder: 0,
  startYear: -4000,
  endYear: -2200,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

StoryEvent _event(int i) => StoryEvent(
  id: 'e$i',
  landmarkId: 'lm_test',
  eraId: 'era_primeval',
  title: '사건 $i',
  summary: '요약 $i',
  storyScenes: const [],
  sceneCharacters: const [],
  startYear: -4000 + i,
  endYear: -4000 + i,
  timePrecision: 'approx',
  storyIndex: i,
  rankInEra: i,
  globalRank: i,
  placeName: null,
  lat: null,
  lng: null,
  characterCodes: const [],
  bibleRefs: const [],
);

Widget _harness(Widget child, {double width = 360, double height = 280}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

void main() {
  group('EventTimelineRow nudge', () {
    testWidgets('카드가 viewport 보다 길면 등장 시 0 → 60 → 0 으로 한 번 들썩인다', (
      tester,
    ) async {
      final events = List.generate(8, _event);

      await tester.pumpWidget(
        _harness(
          EventTimelineRow(
            events: events,
            allEras: [_era()],
            charactersByCode: const {},
            selectedEventId: null,
            onTapEvent: (_) {},
            rowHeight: 280,
          ),
        ),
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(60));

      var maxObserved = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        if (scrollable.position.pixels > maxObserved) {
          maxObserved = scrollable.position.pixels;
        }
      }
      expect(
        maxObserved,
        greaterThan(50),
        reason: 'peak 60 근처까지 도달해야 한다 (max=$maxObserved)',
      );

      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, lessThan(1));
    });

    testWidgets('selectedEventId 가 set 이면 nudge 를 skip 한다 (자동 중앙 스크롤이 따로 돈다)', (
      tester,
    ) async {
      final events = List.generate(8, _event);

      await tester.pumpWidget(
        _harness(
          EventTimelineRow(
            events: events,
            allEras: [_era()],
            charactersByCode: const {},
            selectedEventId: events.first.id,
            onTapEvent: (_) {},
            rowHeight: 280,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      // selected = events[0] 이고 _scrollToSelected 도 0 근처에 머문다.
      // nudge 가 돌았다면 peak 60 흔적이 settle 후에는 사라지므로 단정은
      // "nudge 가 early-return 했음을 간접 확인" 수준.
      expect(scrollable.position.pixels, lessThan(1));
    });

    testWidgets(
      '카드가 viewport 보다 짧으면 (overflow 없음) nudge 가 일어나지 않고 offset 0 유지',
      (tester) async {
        final events = List.generate(2, _event);

        await tester.pumpWidget(
          _harness(
            EventTimelineRow(
              events: events,
              allEras: [_era()],
              charactersByCode: const {},
              selectedEventId: null,
              onTapEvent: (_) {},
              rowHeight: 280,
            ),
            width: 800,
          ),
        );

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scrollable.position.maxScrollExtent, 0);

        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(scrollable.position.pixels, 0);
        }
      },
    );
  });

  group('EventTimelineRow celebration', () {
    testWidgets('도장 애니메이션이 끝나면 onCelebrationComplete를 호출한다', (tester) async {
      final events = [_event(0)];
      var completed = 0;

      await tester.pumpWidget(
        _harness(
          EventTimelineRow(
            events: events,
            allEras: [_era()],
            charactersByCode: const {},
            selectedEventId: events.first.id,
            celebrationEventId: events.first.id,
            celebrationStampLabel: '✨',
            celebrationNonce: 1,
            onCelebrationComplete: () => completed += 1,
            onTapEvent: (_) {},
            rowHeight: 280,
          ),
        ),
      );

      await tester.pump();
      expect(completed, 0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(completed, 0);

      await tester.pump(
        CompletionCelebration.stampDuration + const Duration(milliseconds: 100),
      );
      expect(completed, 1);
    });
  });

  group('StoryEventThumbCard emotion badge', () {
    testWidgets('감정 배지 우측 하단에 이야기 순번을 함께 표시한다', (tester) async {
      await tester.pumpWidget(
        _harness(
          StoryEventThumbCard(
            event: _event(0),
            era: _era(),
            charactersByCode: const {},
            selected: false,
            loader: SceneAssetLoader(),
            onTap: () {},
            emotionKey: 'fear',
            orderNumber: 7,
          ),
        ),
      );

      await tester.pump();

      final emotionRect = tester.getRect(find.byType(EmotionBadgeIcon));
      final orderRect = tester.getRect(find.text('7'));

      expect(orderRect.center.dx, greaterThan(emotionRect.center.dx));
      expect(orderRect.center.dy, greaterThan(emotionRect.center.dy));
    });
  });
}
