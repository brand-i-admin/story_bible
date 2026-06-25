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

    test('skip animation completes ordered event reveal', () {
      final source = File(
        'lib/widgets/story_map_panel_state.dart',
      ).readAsStringSync();
      final match = RegExp(
        r'void skipAnimation\(\) \{([\s\S]*?)\n  \}',
      ).firstMatch(source);

      expect(match, isNotNull);
      final methodBody = match!.group(1)!;
      expect(methodBody, contains('_eventRevealTimer?.cancel();'));
      expect(methodBody, contains('_eventRevealCount = count;'));
      expect(methodBody, contains('widget.onRevealComplete?.call();'));
    });

    test('home shows a map reveal skip button while waiting for pins', () {
      final homeSource = File(
        'lib/screens/story_home_screen_state.dart',
      ).readAsStringSync();
      final widgetSource = File(
        'lib/screens/story_home_screen_widgets.dart',
      ).readAsStringSync();

      expect(homeSource, contains('void _skipMapReveal()'));
      expect(homeSource, contains('_mapPanelController.skipAnimation();'));
      expect(homeSource, contains('final showRevealSkip ='));
      expect(homeSource, contains('_awaitingRevealComplete &&'));
      expect(homeSource, contains('_MapRevealSkipButton('));
      expect(
        widgetSource,
        contains("ValueKey<String>('map-reveal-skip-button')"),
      );
      expect(
        widgetSource,
        contains('Icons.keyboard_double_arrow_right_rounded'),
      );
      final skipButtonStart = widgetSource.indexOf(
        'class _MapRevealSkipButton',
      );
      final skipButtonEnd = widgetSource.indexOf(
        'enum _PanelFloatingActionTone',
        skipButtonStart,
      );
      final skipButtonSource = widgetSource.substring(
        skipButtonStart,
        skipButtonEnd,
      );
      expect(skipButtonSource, contains('ClipOval('));
      expect(skipButtonSource, contains('ColoredBox('));
      expect(skipButtonSource, isNot(contains('InkWell(')));
      expect(skipButtonSource, isNot(contains('Ink(')));
    });

    test('home intro plays a short zoom and pitch affordance animation', () {
      final homeSource = File(
        'lib/screens/story_home_screen_state.dart',
      ).readAsStringSync();
      final panelSource = File(
        'lib/widgets/story_map_panel.dart',
      ).readAsStringSync();
      final panelStateSource = File(
        'lib/widgets/story_map_panel_state.dart',
      ).readAsStringSync();
      final terrainSource = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(homeSource, contains('void _scheduleHomeIntroMapAffordance()'));
      expect(
        homeSource,
        contains('_mapPanelController.playHomeIntroCameraHint();'),
      );
      expect(panelSource, contains('void playHomeIntroCameraHint()'));
      expect(panelStateSource, contains('_pendingHomeIntroCameraHint = true;'));
      expect(
        panelStateSource,
        contains('duration: const Duration(milliseconds: 1000)'),
      );
      expect(terrainSource, contains('void playHomeIntroCameraHint({'));
      expect(terrainSource, contains('_homeIntroZoomOutDelta = 0.72'));
      expect(terrainSource, contains('zoom + _homeIntroZoomOutDelta'));
      expect(terrainSource, contains('targetPitch\': 0.0'));
      expect(terrainSource, contains('window.storyBibleMap.jumpTo({'));
      expect(terrainSource, contains('window.storyBibleMap.easeTo({'));
      expect(terrainSource, contains('duration + 180'));
    });

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
          'if (performance.now() - lastPointerTapAt < 700) return;\n        sendInteraction();',
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
      expect(homeSource, contains('WebPointerInterceptor('));
      expect(homeSource, contains('_handleMapInteraction();'));
      expect(homeSource, contains('_suppressMapTaps();'));
      expect(homeSource, contains('child: IgnorePointer('));
      expect(mapSource, contains('window.storyBibleClearMapTapSuppression'));
      expect(panelSource, contains('void _clearMapTapSuppression()'));
      expect(homeSource, contains('clearMapTapSuppression();'));
      expect(homeSource, contains('const Duration(milliseconds: 1200)'));
      expect(homeSource, contains('onPointerUp: (_) =>'));
      expect(homeSource, contains('onPointerCancel: (_) =>'));
      expect(homeSource, contains('builder: (ctx) =>'));
      expect(homeSource, contains('Listener('));
      expect(homeSource, contains('onPointerDown: (_) => _suppressMapTaps(),'));
      expect(homeSource, contains('onPointerUp: (_) => _suppressMapTaps(),'));
      expect(
        homeSource,
        contains('onClose: () {\n            _suppressMapTaps();'),
      );
    });

    test('home map no longer renders floating zoom or info controls', () {
      final homeSource = File(
        'lib/screens/story_home_screen_state.dart',
      ).readAsStringSync();

      expect(homeSource, isNot(contains("tooltip: '확대'")));
      expect(homeSource, isNot(contains("tooltip: '축소'")));
      expect(homeSource, isNot(contains("tooltip: '지도 출처'")));
      expect(homeSource, isNot(contains('_showMapAttributionDialog')));
    });

    test(
      'Android WebView map owns touch gestures and uses lighter renderer',
      () {
        final source = File(
          'lib/widgets/map/story_terrain_3d_map.dart',
        ).readAsStringSync();

        expect(source, contains("import 'package:flutter/gestures.dart';"));
        expect(source, contains('EagerGestureRecognizer'));
        expect(source, contains('gestureRecognizers: _mapGestureRecognizers'));
        expect(
          source,
          contains('defaultTargetPlatform == TargetPlatform.android'),
        );
        expect(source, contains("'enableTerrain': _enableTerrain"));
        expect(source, contains("'antialias': !_useReducedAndroidRenderer"));
        expect(
          source,
          contains("'refreshExpiredTiles': !_useReducedAndroidRenderer"),
        );
        expect(
          source,
          contains("'workerCount': _useReducedAndroidRenderer ? 1"),
        );
        expect(
          source,
          contains('maplibregl.workerCount = requestedWorkerCount'),
        );
        expect(source, contains('map.touchZoomRotate.enable();'));
        expect(source, contains('map.dragPan.enable();'));
        expect(source, contains('if (config.enableTerrain) {'));
      },
    );

    test('Flutter Web uses an iframe bridge instead of WebViewController', () {
      final terrainSource = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();
      final webSource = File(
        'lib/widgets/map/story_terrain_web_view_web.dart',
      ).readAsStringSync();

      expect(
        terrainSource,
        contains(
          "import 'story_terrain_web_view_stub.dart'\n"
          "    if (dart.library.html) 'story_terrain_web_view_web.dart';",
        ),
      );
      expect(
        terrainSource,
        contains(
          'if (kIsWeb) {\n'
          '      _loadHtmlIfNeeded(force: true);\n'
          '      return;\n'
          '    }\n'
          '    _controller = WebViewController()',
        ),
      );
      expect(terrainSource, contains('return Stack('));
      expect(terrainSource, contains('StoryTerrainWebView('));
      expect(terrainSource, contains('return _webController.runJavaScript'));
      expect(
        terrainSource,
        contains("window.parent.postMessage(encoded, '*')"),
      );
      expect(terrainSource, contains("data.type !== 'storyBibleEval'"));

      expect(webSource, contains('html.IFrameElement()'));
      expect(webSource, contains('html.Blob([htmlText], \'text/html\')'));
      expect(webSource, contains('_iframe.src = nextUrl'));
      expect(webSource, contains('html.Url.revokeObjectUrl(objectUrl)'));
      expect(webSource, contains('ui_web.platformViewRegistry'));
      expect(webSource, contains('html.window.onMessage.listen'));
      expect(webSource, contains('decoded[\'bridgeId\'] != widget.bridgeId'));
      expect(webSource, contains('HtmlElementView(viewType: _viewType)'));
    });

    test(
      'Flutter overlays above web map are pointer-intercepted on web only',
      () {
        final interceptorExport = File(
          'lib/widgets/web_pointer_interceptor.dart',
        ).readAsStringSync();
        final interceptorStub = File(
          'lib/widgets/web_pointer_interceptor_stub.dart',
        ).readAsStringSync();
        final interceptorWeb = File(
          'lib/widgets/web_pointer_interceptor_web.dart',
        ).readAsStringSync();
        final homeSource = File(
          'lib/screens/story_home_screen_state.dart',
        ).readAsStringSync();
        final panelSource = File(
          'lib/widgets/story_map_panel_state.dart',
        ).readAsStringSync();
        final notificationSource = File(
          'lib/widgets/notification/notification_bell_button.dart',
        ).readAsStringSync();
        final fontScaleSource = File(
          'lib/widgets/font_scale_bottom_sheet.dart',
        ).readAsStringSync();
        final pastorGateSource = File(
          'lib/widgets/proposal/pastor_gate_dialog.dart',
        ).readAsStringSync();

        expect(
          interceptorExport,
          contains(
            "export 'web_pointer_interceptor_stub.dart'\n"
            "    if (dart.library.html) 'web_pointer_interceptor_web.dart';",
          ),
        );
        expect(
          interceptorStub,
          contains('Widget build(BuildContext context) => child;'),
        );
        expect(interceptorWeb, contains('html.DivElement()'));
        expect(interceptorWeb, contains('style.pointerEvents'));
        expect(
          interceptorWeb,
          contains('HtmlElementView(viewType: _viewType)'),
        );
        expect(interceptorWeb, contains('isVisible: false'));
        expect(homeSource, contains('WebPointerInterceptor('));
        expect(homeSource, contains("ValueKey<String>('selection-sheet')"));
        expect(
          panelSource,
          contains('WebPointerInterceptor(child: widget.bottomOverlay!)'),
        );
        expect(notificationSource, contains('WebPointerInterceptor('));
        expect(
          fontScaleSource,
          contains(
            'builder: (_) => const WebPointerInterceptor(child: FontScaleBottomSheet())',
          ),
        );
        expect(pastorGateSource, contains('return WebPointerInterceptor('));
      },
    );

    test('map JavaScript calls do not return MapLibre objects to WebView', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains('Future<void> _runMapJavaScript(String script)'));
      expect(source, contains('return null;'));
      expect(
        source,
        isNot(contains("_controller.runJavaScript('''\n      if")),
      );
      expect(
        source,
        isNot(contains("_controller.runJavaScript('''\n      window")),
      );
    });

    test('Android activity handles WebView renderer exits', () {
      final source = File(
        'android/app/src/main/kotlin/com/storybible/app/MainActivity.kt',
      ).readAsStringSync();

      expect(source, contains('installWebViewRenderGuards'));
      expect(source, contains('RenderGuardWebViewClient'));
      expect(source, contains('override fun onRenderProcessGone'));
      expect(source, contains('delegate.onRenderProcessGone(view, detail)'));
      expect(source, contains('(view.parent as? ViewGroup)?.removeView(view)'));
      expect(source, contains('view.destroy()'));
      expect(source, contains('return true'));
    });

    test('subresource errors do not show the 3D map failure overlay', () {
      final source = File(
        'lib/widgets/map/story_terrain_3d_map.dart',
      ).readAsStringSync();

      expect(source, contains('void _handleWebResourceError'));
      expect(
        source,
        contains('if (_mapReady || error.isForMainFrame != true)'),
      );
      expect(source, contains('[Map3D] main-frame resource error'));
      expect(source, contains('url: \${error.url ?? '));
      expect(source, contains('if (mounted) {'));
      expect(source, contains('void _armInitialLoadTimeout()'));
      expect(source, contains('_initialLoadTimeoutDuration'));
      expect(source, contains('if (!mounted || _mapReady)'));
      expect(source, contains("setState(() => _hasError = false);"));
    });
  });
}
