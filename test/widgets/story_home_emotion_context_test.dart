import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emotion stamp restores the detail entry map filter before fallback prep',
    () {
      final source = File(
        'lib/screens/story_home_screen_state.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('_HomeMapFilterSnapshot? _captureHomeMapFilterSnapshot('),
      );
      expect(
        source,
        contains(
          'final filterSnapshot = _captureHomeMapFilterSnapshot(event);',
        ),
      );

      final methodStart = source.indexOf(
        'Future<void> _showEmotionCelebrationOnMap',
      );
      final methodEnd = source.indexOf(
        'Future<void> _navigateDetailThroughMap',
        methodStart,
      );
      final body = source.substring(methodStart, methodEnd);
      final restoreIndex = body.indexOf(
        'final restoredFilter = _restoreHomeMapFilterSnapshot(',
      );
      final fallbackIndex = body.indexOf(
        'await _prepareHomeMapForProfileEvent(',
      );

      expect(restoreIndex, greaterThan(0));
      expect(fallbackIndex, greaterThan(restoreIndex));
      expect(body, contains('if (!restoredFilter) {'));
      expect(body, contains('source: ProfileEventOpenSource.general'));
    },
  );
}
