import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoryTerrain3dMap event markers', () {
    test('MapLibre marker root is separate from the circular pin button', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains("const root = document.createElement('div');"));
      expect(source, contains("root.className = 'story-event-marker-root';"));
      expect(source, contains('root.appendChild(element);'));
      expect(source, contains('element: root,'));
      expect(
        source,
        isNot(contains('new maplibregl.Marker({\n            element,\n')),
      );
    });

    test(
      'ordered reveal count is synced when all pins are shown immediately',
      () {
        final source = File(
          'lib/widgets/story_map_panel_state.dart',
        ).readAsStringSync();
        final match = RegExp(
          r'void _showAllPinsImmediately\(\) \{([\s\S]*?)\n  \}',
        ).firstMatch(source);

        expect(match, isNotNull);
        final methodBody = match!.group(1)!;
        expect(methodBody, contains('_eventRevealTimer?.cancel();'));
        expect(methodBody, contains('_eventRevealCount = count;'));
      },
    );

    test('event path uses selected character colors', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains("'line-color': ['case', ['has', 'color']"));
      expect(source, contains("'line-offset': ['case', ['has', 'offset']"));
      expect(source, contains("'characterCode': path.key"));
      expect(
        source,
        contains("'color': _cssColor(widget.colorForCharacter(path.key))"),
      );
    });

    test('map taps are suppressed during gestures and panel touches', () {
      final mapSource = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();
      final panelSource = File(
        'lib/widgets/story_map_panel_state.dart',
      ).readAsStringSync();
      final homeSource = File(
        'lib/screens/story_home_screen_state.dart',
      ).readAsStringSync();

      expect(mapSource, contains('window.storyBibleSuppressMapTap'));
      expect(mapSource, contains('const isMapTapSuppressed'));
      expect(mapSource, contains('eventUsesModifierKey(event)'));
      expect(mapSource, contains("target.closest('.maplibregl-ctrl')"));
      expect(panelSource, contains('onPointerDown: (_) => _suppressMapTaps()'));
      expect(
        panelSource,
        contains('onPointerSignal: (_) => _suppressMapTaps()'),
      );
      expect(homeSource, contains('void _suppressMapTaps(['));
      expect(
        homeSource,
        contains("key: const ValueKey<String>('selection-sheet')"),
      );
      expect(
        homeSource,
        contains('onPointerSignal: (_) => _suppressMapTaps()'),
      );
    });
  });
}
