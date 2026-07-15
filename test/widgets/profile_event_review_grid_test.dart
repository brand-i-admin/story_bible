import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/widgets/profile/profile_event_review_grid.dart';

void main() {
  testWidgets('공용 이야기 그리드는 3열로 요약 없이 시대 사이를 촘촘하게 배치한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final events = [
      _event('a', '첫 이야기', 'era-a', 1),
      _event('b', '둘째 이야기', 'era-a', 2),
      _event('c', '셋째 이야기', 'era-a', 3),
      _event('d', '다음 시대 이야기', 'era-b', 4),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
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
              charactersByCode: const {},
              completedEventIds: const {},
              eventEmotionMarks: const {},
              quizAttemptSummaries: const {},
              scrollable: false,
              onOpenEventDetail: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('카드에서 숨길 이야기 요약'), findsNothing);
    final first = tester.getRect(
      find.byKey(const ValueKey('story-card-surface-mapTimeline-a')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('story-card-surface-mapTimeline-b')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('story-card-surface-mapTimeline-c')),
    );
    expect(second.top, closeTo(first.top, 0.1));
    expect(third.top, closeTo(first.top, 0.1));

    final nextDivider = tester.getRect(
      find.byKey(const ValueKey('profile-event-era-divider-era-b')),
    );
    expect(nextDivider.top - first.bottom, lessThanOrEqualTo(14));
  });
}

StoryEvent _event(String id, String title, String eraId, int storyIndex) {
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
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const [],
    bibleRefs: const [],
  );
}
