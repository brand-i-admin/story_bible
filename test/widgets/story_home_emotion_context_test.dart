import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emotion stamp restores map filters only for map-origin details', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('_HomeMapFilterSnapshot? _captureHomeMapFilterSnapshot('),
    );
    expect(source, contains('final mapRootTab = backContext.mapRootTab;'));
    expect(source, contains('mapRootTab == StoryRootTab.map'));
    expect(
      source,
      contains('_todayCelebrationEventId = mapRootTab == StoryRootTab.today'),
    );

    final methodStart = source.indexOf(
      'Future<void> _showEmotionCelebrationOnMap',
    );
    final methodEnd = source.indexOf(
      'Future<void> _navigateDetailThroughMap',
      methodStart,
    );
    final body = source.substring(methodStart, methodEnd);
    final restoreIndex = body.indexOf('final restoredFilter =');
    final fallbackIndex = body.indexOf('await _prepareHomeMapForProfileEvent(');

    expect(restoreIndex, greaterThan(0));
    expect(fallbackIndex, greaterThan(restoreIndex));
    expect(
      body,
      contains('_restoreHomeMapFilterSnapshot(filterSnapshot, event)'),
    );
    expect(body, contains('if (!restoredFilter) {'));
    expect(body, contains('source: ProfileEventOpenSource.general'));
  });

  test('today story keeps its stamp and back destination on the today map', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    final methodStart = homeSource.indexOf('Future<void> _openTodayStory');
    final methodEnd = homeSource.indexOf('Widget _buildMapTab', methodStart);
    final method = homeSource.substring(methodStart, methodEnd);

    expect(method, contains('mapRootTab: StoryRootTab.today'));
    expect(homeSource, contains('currentEventOverrideId:'));
    expect(todaySource, contains('final String? currentEventOverrideId;'));
    expect(todaySource, contains('widget.currentEventOverrideId ??'));
  });
}
