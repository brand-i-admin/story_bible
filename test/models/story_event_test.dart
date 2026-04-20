import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/story_event.dart';

void main() {
  group('StoryEvent', () {
    StoryEvent buildEvent({
      String? summary,
      String? story,
      String? shortStory,
      double? lat,
      double? lng,
    }) {
      return StoryEvent(
        id: 'e1',
        code: 'evt_001',
        displayNumber: '001',
        eraId: 'era_primeval',
        title: '001 창조: 7일과 안식',
        summary: summary,
        story: story,
        shortStory: shortStory,
        storyScenes: null,
        timelineRank: 1.0,
        startYear: -4000,
        endYear: -4000,
        timeSortKey: -4000000,
        placeName: '메소포타미아',
        lat: lat,
        lng: lng,
        personIds: const ['god'],
        bibleRefs: const ['창 1:1-2:3'],
        thumbUrl: null,
        storyAssetDir: null,
        storyThumbnailDir: null,
        storySceneCount: 0,
      );
    }

    group('shortSummary', () {
      test('shortStory가 우선순위 1이다', () {
        final event = buildEvent(
          shortStory: 'short',
          story: 'long',
          summary: 'summary',
        );
        expect(event.shortSummary, 'short');
      });

      test('shortStory가 없으면 story를 사용한다', () {
        final event = buildEvent(story: 'long', summary: 'summary');
        expect(event.shortSummary, 'long');
      });

      test('모두 없으면 기본 메시지를 반환한다', () {
        final event = buildEvent();
        expect(event.shortSummary, '요약 정보가 없습니다.');
      });
    });

    group('hasCoordinate / latLng', () {
      test('lat/lng이 모두 있으면 hasCoordinate는 true', () {
        final event = buildEvent(lat: 31.0, lng: 47.0);
        expect(event.hasCoordinate, isTrue);
        expect(event.latLng.latitude, 31.0);
        expect(event.latLng.longitude, 47.0);
      });

      test('lat이 null이면 hasCoordinate는 false', () {
        final event = buildEvent(lng: 47.0);
        expect(event.hasCoordinate, isFalse);
      });

      test('lng이 null이면 hasCoordinate는 false', () {
        final event = buildEvent(lat: 31.0);
        expect(event.hasCoordinate, isFalse);
      });
    });
  });
}
