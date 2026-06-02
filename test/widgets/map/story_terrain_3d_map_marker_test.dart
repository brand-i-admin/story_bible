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

    test('event detail transitions frame pins above the bottom sheet', () {
      final source = File(
        'lib/widgets/story_map_panel_state.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf('Future<void> _playEventTransition');
      final methodEnd = source.indexOf('Future<void> _playEmotionStamp');

      expect(methodStart, isNonNegative);
      expect(methodEnd, greaterThan(methodStart));
      final methodBody = source.substring(methodStart, methodEnd);
      expect(source, contains('_eventTransitionZoomOut = 0.72'));
      expect(source, contains('_eventTransitionMaxZoom = 8.2'));
      expect(methodBody, contains('widget.bottomObscuredFraction'));
      expect(methodBody, contains('bottomGap + 28.0'));
      expect(methodBody, contains('map_math.eventFitTopPadding'));
      expect(methodBody, contains('_terrain3dController.fitBounds'));
      expect(methodBody, contains('maxZoom: targetZoom.toDouble()'));
    });

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

    test('event DOM pins stay compact', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains('width: 23px;'));
      expect(source, contains('height: 23px;'));
      expect(source, contains('font-size: 10.5px;'));
      expect(source, contains('width: 25px;'));
      expect(source, contains('height: 25px;'));
      expect(source, contains('width: 28px;'));
      expect(source, contains('height: 28px;'));
      expect(source, contains('font-size: 15px;'));
      expect(source, contains('width: 13px;'));
      expect(source, contains('height: 13px;'));
    });

    test('region picker labels stay subtle and centered', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains("id: 'story-bible-region-label-anchor'"));
      expect(source, contains("'text-field': ['get', 'label']"));
      expect(
        source,
        contains(
          "'text-color': ['case', ['get', 'selected'], '#2F6B45', '#8A5F16']",
        ),
      );
      expect(
        source,
        contains(
          "'circle-color': ['case', ['get', 'selected'], '#5E8C4A', '#B57A1C']",
        ),
      );
      expect(source, contains("'text-allow-overlap': false"));
      expect(
        source,
        contains("'text-variable-anchor': ['top', 'bottom', 'left', 'right']"),
      );
      expect(source, contains("'label': landmark.name"));
      expect(
        source,
        contains('final labelPoint = _polygonLabelPoint(polygon);'),
      );
      expect(source, contains("'pickerMode': widget.regionPickerMode"));
    });

    test('region picker taps prefer polygon hits over child markers', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains('const isRegionPickerActive = () => {'));
      expect(
        source,
        contains('const pickRegionAtPoint = (point, lngLat) => {'),
      );
      expect(
        source,
        contains(
          'if (isRegionPickerActive() && postRegionFeature(pickRegionAtPoint(point, lngLat)))',
        ),
      );
      expect(
        source,
        contains('const canvasPointFromPointerEvent = (event) => {'),
      );
      expect(source, contains('Math.sqrt(dx * dx + dy * dy) > 18'));
      expect(source, contains('if (widget.regionPickerMode) {'));
      expect(
        source,
        contains("return {'type': 'FeatureCollection', 'features': const []};"),
      );
      expect(
        source,
        contains('const regionPickerPointerTap = isRegionPickerActive();'),
      );
      expect(
        source,
        contains(
          'ignoreSuppression: !pointerStartedSuppressed || regionPickerPointerTap',
        ),
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
      expect(mapSource, contains('const sendPointerInteraction = () => {'));
      expect(mapSource, contains('sendPointerInteraction();'));
      expect(mapSource, contains("let suppressMapTapReason = 'external';"));
      expect(mapSource, contains('const isMapTapSuppressed'));
      expect(mapSource, contains('const isMapTapExternallySuppressed'));
      expect(mapSource, contains('eventUsesModifierKey(event)'));
      expect(mapSource, contains("target.closest('.maplibregl-ctrl')"));
      expect(
        mapSource,
        contains(
          "suppressMapTap(eventUsesModifierKey(event) ? 950 : 650, 'mapGesture')",
        ),
      );
      expect(
        mapSource,
        contains(
          'if (event && event.originalEvent) {\n        sendInteraction();',
        ),
      );
      expect(
        mapSource,
        contains(
          'const regionPickerClick = isRegionPickerActive();\n        if (isMapTapSuppressed()) return;',
        ),
      );
      expect(
        mapSource,
        contains(
          'if (performance.now() - lastPointerTapAt < 320) return;\n        sendInteraction();',
        ),
      );
      expect(
        mapSource,
        contains(
          'handleMapTapPoint(event.point, event.lngLat, { ignoreSuppression: regionPickerClick });',
        ),
      );
      expect(
        mapSource,
        contains(
          'sendInteraction();\n        const regionPickerPointerTap = isRegionPickerActive();',
        ),
      );
      expect(
        mapSource,
        contains('handleMapTapPoint(point, map.unproject(point), {'),
      );
      expect(mapSource, contains('isMapTapExternallySuppressed()'));
      expect(mapSource, contains("suppressMapTap(950, 'mapControl');"));
      expect(panelSource, contains('const Duration(milliseconds: 1200)'));
      expect(panelSource, contains('onPointerUp: (_) =>'));
      expect(panelSource, contains('onPointerCancel: (_) =>'));
      expect(homeSource, contains('void _suppressMapTaps(['));
      expect(
        homeSource,
        contains("key: const ValueKey<String>('selection-sheet')"),
      );
      expect(
        homeSource,
        contains(
          'onPointerDown: (_) {\n                          _handleMapInteraction();',
        ),
      );
      expect(homeSource, contains('child: IgnorePointer('));
      expect(mapSource, contains('window.storyBibleClearMapTapSuppression'));
      expect(panelSource, contains('void _clearMapTapSuppression()'));
      expect(homeSource, contains('clearMapTapSuppression();'));
      expect(homeSource, contains('const Duration(milliseconds: 1200)'));
      expect(homeSource, contains('onPointerUp: (_) =>'));
      expect(homeSource, contains('onPointerCancel: (_) =>'));
      expect(homeSource, contains('builder: (ctx) => Listener('));
      expect(homeSource, contains('onPointerDown: (_) => _suppressMapTaps(),'));
      expect(homeSource, contains('onPointerUp: (_) => _suppressMapTaps(),'));
      expect(
        homeSource,
        contains('onClose: () {\n            _suppressMapTaps();'),
      );
    });

    test('subresource errors do not show the 3D map failure overlay', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains('void _handleWebResourceError'));
      expect(source, contains('mainFrame: \${error.isForMainFrame}'));
      expect(source, contains('url: \${error.url ?? '));
      expect(source, contains('if (_mapReady) {'));
      expect(source, contains('if (error.isForMainFrame == true && mounted)'));
      expect(source, contains('void _armInitialLoadTimeout()'));
      expect(source, contains('_initialLoadTimeoutDuration'));
      expect(source, contains('if (!mounted || _mapReady)'));
      expect(source, contains("setState(() => _hasError = false);"));
    });
  });
}
