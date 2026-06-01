import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/event_emotion_mark.dart';
import '../../models/landmark.dart';
import '../../models/story_event.dart';
import '../../utils/map_math.dart' as map_math;
import 'map_tile_style.dart';

class StoryTerrain3dMap extends StatefulWidget {
  const StoryTerrain3dMap({
    super.key,
    this.controller,
    required this.source,
    required this.center,
    required this.zoom,
    required this.events,
    required this.selectedEventId,
    required this.colorForCharacter,
    required this.selectedCharacterCodes,
    required this.regionLandmarks,
    required this.activeLandmarks,
    required this.selectedLandmarkId,
    required this.eventCountByLandmarkId,
    required this.visibleEventCount,
    required this.orderedEventsActive,
    required this.eventEmotionMarks,
    required this.regionPickerMode,
    this.countryBorderLines = const [],
    this.countryLabels = const [],
    this.onEventTap,
    this.onLandmarkTap,
    this.onMapInteraction,
    this.onMapReady,
  });

  final StoryTerrain3dMapController? controller;
  final StoryMapTileSource source;
  final LatLng center;
  final double zoom;
  final List<StoryEvent> events;
  final String? selectedEventId;
  final Color Function(String characterCode) colorForCharacter;
  final Set<String> selectedCharacterCodes;
  final List<Landmark> regionLandmarks;
  final List<Landmark> activeLandmarks;
  final String? selectedLandmarkId;
  final Map<String, int>? eventCountByLandmarkId;
  final int visibleEventCount;
  final bool orderedEventsActive;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final bool regionPickerMode;
  final List<List<LatLng>> countryBorderLines;
  final List<StoryTerrainCountryLabel> countryLabels;
  final ValueChanged<String>? onEventTap;
  final ValueChanged<String>? onLandmarkTap;
  final VoidCallback? onMapInteraction;
  final VoidCallback? onMapReady;

  @override
  State<StoryTerrain3dMap> createState() => _StoryTerrain3dMapState();
}

class StoryTerrainCountryLabel {
  const StoryTerrainCountryLabel({required this.name, required this.point});

  final String name;
  final LatLng point;
}

class StoryTerrain3dMapController {
  _StoryTerrain3dMapState? _state;

  void _bind(_StoryTerrain3dMapState state) {
    _state = state;
  }

  void _unbind(_StoryTerrain3dMapState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void zoomIn() => _state?._zoomBy(0.7);

  void zoomOut() => _state?._zoomBy(-0.7);

  void suppressTapFor([
    Duration duration = const Duration(milliseconds: 650),
  ]) => _state?._suppressTapFor(duration);

  void clearTapSuppression() => _state?._clearTapSuppression();

  void moveTo(
    LatLng center,
    double zoom, {
    Duration duration = const Duration(milliseconds: 420),
  }) {
    _state?._moveTo(center, zoom, duration: duration);
  }

  void fitBounds(
    LatLngBounds bounds, {
    required EdgeInsets padding,
    double? maxZoom,
    Duration duration = const Duration(milliseconds: 420),
  }) {
    _state?._fitBounds(
      bounds,
      padding: padding,
      maxZoom: maxZoom,
      duration: duration,
    );
  }

  Future<void> playEventTransition({
    required LatLng fromPoint,
    required LatLng toPoint,
    Duration duration = const Duration(seconds: 2),
  }) {
    return _state?._playEventTransition(
          fromPoint: fromPoint,
          toPoint: toPoint,
          duration: duration,
        ) ??
        Future.value();
  }
}

class _StoryTerrain3dMapState extends State<StoryTerrain3dMap> {
  static const _minZoom = 2.7;
  static const _maxZoom = 12.4;
  static const double _eventSpreadRadiusDeg = 0.018;
  static const double _eventSpreadThresholdDeg = 0.028;
  static const _boundsWest = 4.0;
  static const _boundsSouth = -8.0;
  static const _boundsEast = 64.0;
  static const _boundsNorth = 50.5;

  late final WebViewController _controller;
  String? _lastRendererSignature;
  String? _lastCameraSignature;
  String? _lastOverlaySignature;
  String? _pendingCameraPayload;
  String? _pendingOverlayPayload;
  bool _mapReady = false;
  bool _hasError = false;

  bool get _useTopDownRegionCamera =>
      widget.regionLandmarks.isNotEmpty &&
      (widget.regionPickerMode || widget.selectedLandmarkId != null);

  double get _effectivePitch =>
      _useTopDownRegionCamera ? 0.0 : widget.source.initialPitch;

  double get _effectiveBearing =>
      _useTopDownRegionCamera ? 0.0 : widget.source.initialBearing;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFE5D2B5))
      ..addJavaScriptChannel(
        'StoryBibleMap',
        onMessageReceived: _handleJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint(
              '[Map3D] resource error ${error.errorCode}: ${error.description}',
            );
            if (mounted) {
              setState(() => _hasError = true);
            }
          },
        ),
      );
    _loadHtmlIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant StoryTerrain3dMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind(this);
      widget.controller?._bind(this);
    }
    _loadHtmlIfNeeded();
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.source.styleJsonUrl.isEmpty ||
        !_hasTerrainSource(widget.source)) {
      return const ColoredBox(color: Color(0xFFE5D2B5));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_hasError)
          const _Map3dStatusOverlay(
            title: '3D 지도를 불러오지 못했어요',
            message: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
          ),
      ],
    );
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    final raw = message.message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      switch (decoded['type']) {
        case 'mapInteraction':
          widget.onMapInteraction?.call();
          break;
        case 'eventTap':
          final id = decoded['id']?.toString();
          if (id != null && id.isNotEmpty) {
            widget.onEventTap?.call(id);
          }
          break;
        case 'landmarkTap':
          final id = decoded['id']?.toString();
          if (id != null && id.isNotEmpty) {
            widget.onLandmarkTap?.call(id);
          }
          break;
        case 'ready':
          debugPrint('[Map3D] ready: ${widget.source.label}');
          _mapReady = true;
          widget.onMapReady?.call();
          _flushPendingCameraPayload();
          _flushPendingOverlayPayload();
          break;
      }
    } catch (error) {
      debugPrint('[Map3D] message parse failed: $error');
    }
  }

  void _loadHtmlIfNeeded({bool force = false}) {
    final rendererSignature = jsonEncode({
      'style': widget.source.style.name,
      'styleJsonUrl': widget.source.styleJsonUrl,
      'terrainTileJsonUrl': widget.source.terrainTileJsonUrl,
      'terrainTiles': widget.source.terrainTiles,
      'terrainEncoding': widget.source.terrainEncoding,
      'hideBaseLabels': widget.source.hideBaseLabels,
      'terrainExaggeration': widget.source.terrainExaggeration,
    });
    final cameraPayload = _cameraPayload();
    final cameraSignature = jsonEncode(cameraPayload);
    final overlayPayload = _overlayPayload();
    final overlaySignature = jsonEncode({
      'events': widget.events.map((event) => event.id).toList(growable: false),
      'selectedEventId': widget.selectedEventId,
      'selectedLandmarkId': widget.selectedLandmarkId,
      'regions': widget.regionLandmarks
          .map((landmark) => landmark.id)
          .toList(growable: false),
      'counts': widget.eventCountByLandmarkId,
      'activeLandmarks': widget.activeLandmarks
          .map(
            (landmark) =>
                '${landmark.id}:${landmark.name}:${landmark.emoji}:${landmark.lat}:${landmark.lng}',
          )
          .toList(growable: false),
      'countryBorders': widget.countryBorderLines.length,
      'countryLabels': widget.countryLabels
          .map((label) => label.name)
          .toList(growable: false),
      'visibleEventCount': widget.visibleEventCount,
      'orderedEventsActive': widget.orderedEventsActive,
      'regionPickerMode': widget.regionPickerMode,
      'selectedCharacters': widget.selectedCharacterCodes.toList()..sort(),
      'selectedCharacterColors':
          (widget.selectedCharacterCodes.toList()..sort())
              .map(
                (code) => '$code:${_cssColor(widget.colorForCharacter(code))}',
              )
              .toList(growable: false),
      'emotions':
          widget.eventEmotionMarks.entries
              .map(
                (entry) =>
                    '${entry.key}:${entry.value.emotionKey}:${entry.value.emotionEmoji}',
              )
              .toList()
            ..sort(),
    });
    if (!force && rendererSignature == _lastRendererSignature) {
      if (cameraSignature != _lastCameraSignature) {
        _lastCameraSignature = cameraSignature;
        _syncCamera(cameraPayload);
      }
      if (overlaySignature != _lastOverlaySignature) {
        _lastOverlaySignature = overlaySignature;
        _syncOverlayData(overlayPayload);
      }
      return;
    }
    _lastRendererSignature = rendererSignature;
    _lastCameraSignature = cameraSignature;
    _lastOverlaySignature = overlaySignature;
    _pendingCameraPayload = jsonEncode(cameraPayload);
    _pendingOverlayPayload = jsonEncode(overlayPayload);
    _mapReady = false;
    _hasError = false;
    _controller.loadHtmlString(
      _buildHtml(),
      baseUrl: 'https://story-bible.local',
    );
  }

  static bool _hasTerrainSource(StoryMapTileSource source) {
    return source.terrainTileJsonUrl.isNotEmpty ||
        source.terrainTiles.isNotEmpty;
  }

  void _zoomBy(double delta) {
    final encodedDelta = jsonEncode(delta);
    _controller.runJavaScript('''
      if (window.storyBibleMap) {
        if (window.storyBibleSuppressMapTap) {
          window.storyBibleSuppressMapTap(650);
        }
        const nextZoom = Math.max($_minZoom, Math.min($_maxZoom, window.storyBibleMap.getZoom() + $encodedDelta));
        window.storyBibleMap.easeTo({ zoom: nextZoom, duration: 420 });
      }
    ''');
  }

  void _suppressTapFor(Duration duration) {
    if (!_mapReady) {
      return;
    }
    final millis = duration.inMilliseconds;
    _controller.runJavaScript('''
      if (window.storyBibleSuppressMapTap) {
        window.storyBibleSuppressMapTap($millis);
      }
    ''');
  }

  void _clearTapSuppression() {
    if (!_mapReady) {
      return;
    }
    _controller.runJavaScript('''
      if (window.storyBibleClearMapTapSuppression) {
        window.storyBibleClearMapTapSuppression();
      }
    ''');
  }

  void _moveTo(
    LatLng center,
    double zoom, {
    Duration duration = const Duration(milliseconds: 420),
  }) {
    final payload = <String, Object>{
      'center': [center.longitude, center.latitude],
      'zoom': zoom.clamp(_minZoom, _maxZoom).toDouble(),
      'pitch': _effectivePitch,
      'bearing': _effectiveBearing,
      'duration': duration.inMilliseconds,
    };
    _syncCamera(payload);
  }

  void _fitBounds(
    LatLngBounds bounds, {
    required EdgeInsets padding,
    double? maxZoom,
    Duration duration = const Duration(milliseconds: 420),
  }) {
    if (!_mapReady) {
      return;
    }
    final payload = jsonEncode({
      'bounds': [
        [bounds.west, bounds.south],
        [bounds.east, bounds.north],
      ],
      'padding': {
        'top': padding.top,
        'right': padding.right,
        'bottom': padding.bottom,
        'left': padding.left,
      },
      'maxZoom': (maxZoom ?? _maxZoom).clamp(_minZoom, _maxZoom).toDouble(),
      'pitch': _effectivePitch,
      'bearing': _effectiveBearing,
      'duration': duration.inMilliseconds,
    });
    _controller.runJavaScript('''
      if (window.storyBibleFitBounds) {
        window.storyBibleFitBounds($payload);
      }
    ''');
  }

  Future<void> _playEventTransition({
    required LatLng fromPoint,
    required LatLng toPoint,
    required Duration duration,
  }) async {
    if (!_mapReady) {
      return;
    }
    final payload = jsonEncode({
      'from': [fromPoint.longitude, fromPoint.latitude],
      'to': [toPoint.longitude, toPoint.latitude],
      'duration': duration.inMilliseconds,
    });
    await _controller.runJavaScript('''
      if (window.storyBiblePlayTransition) {
        window.storyBiblePlayTransition($payload);
      }
    ''');
    await Future<void>.delayed(duration);
  }

  Map<String, Object> _cameraPayload() {
    return {
      'center': [widget.center.longitude, widget.center.latitude],
      'zoom': widget.zoom.clamp(_minZoom, _maxZoom).toDouble(),
      'pitch': _effectivePitch,
      'bearing': _effectiveBearing,
      'duration': 360,
    };
  }

  void _syncCamera(Map<String, Object> cameraPayload) {
    final encoded = jsonEncode(cameraPayload);
    if (!_mapReady) {
      _pendingCameraPayload = encoded;
      return;
    }
    _controller.runJavaScript('''
      if (window.storyBibleSetCamera) {
        window.storyBibleSetCamera($encoded);
      }
    ''');
  }

  void _syncOverlayData(Map<String, Object> overlayPayload) {
    final encoded = jsonEncode(overlayPayload);
    if (!_mapReady) {
      _pendingOverlayPayload = encoded;
      return;
    }
    _controller.runJavaScript('''
      if (window.storyBibleSetOverlayData) {
        window.storyBibleSetOverlayData($encoded);
      }
    ''');
  }

  void _flushPendingOverlayPayload() {
    final payload = _pendingOverlayPayload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    _pendingOverlayPayload = null;
    _controller.runJavaScript('''
      if (window.storyBibleSetOverlayData) {
        window.storyBibleSetOverlayData($payload);
      }
    ''');
  }

  void _flushPendingCameraPayload() {
    final payload = _pendingCameraPayload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    _pendingCameraPayload = null;
    _controller.runJavaScript('''
      if (window.storyBibleSetCamera) {
        window.storyBibleSetCamera($payload);
      }
    ''');
  }

  String _buildHtml() {
    final initialCenter = [widget.center.longitude, widget.center.latitude];
    final payload = jsonEncode({
      'styleJsonUrl': widget.source.styleJsonUrl,
      'terrainTileJsonUrl': widget.source.terrainTileJsonUrl,
      'terrainTiles': widget.source.terrainTiles,
      'terrainEncoding': widget.source.terrainEncoding,
      'hideBaseLabels': widget.source.hideBaseLabels,
      'terrainExaggeration': widget.source.terrainExaggeration,
      'pitch': _effectivePitch,
      'bearing': _effectiveBearing,
      'zoom': widget.zoom.clamp(_minZoom, _maxZoom).toDouble(),
      'center': initialCenter,
      'minZoom': _minZoom,
      'maxZoom': _maxZoom,
      'maxBounds': [
        [_boundsWest, _boundsSouth],
        [_boundsEast, _boundsNorth],
      ],
      'styleLabel': widget.source.label,
    });
    final overlayPayload = jsonEncode(_overlayPayload());

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <link rel="stylesheet" href="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.css">
  <script src="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.js"></script>
  <style>
    html, body, #map {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #e5d2b5;
      touch-action: none;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Segoe UI", sans-serif;
    }
    .maplibregl-ctrl-logo,
    .maplibregl-ctrl-attrib {
      display: none !important;
    }
    #loading {
      position: absolute;
      inset: 0;
      z-index: 3;
      display: grid;
      place-items: center;
      color: #3e2d1e;
      background: linear-gradient(180deg, #eadcc4, #d7c3a2);
      font-weight: 800;
      transition: opacity 260ms ease;
    }
    body.ready #loading {
      opacity: 0;
      pointer-events: none;
    }
    .story-event-marker {
      width: 23px;
      height: 23px;
      padding: 0;
      border-radius: 999px;
      display: grid;
      place-items: center;
      position: relative;
      box-sizing: border-box;
      color: #fffaf0;
      background: #6b4a2a;
      border: 2px solid rgba(252, 248, 236, 0.96);
      appearance: none;
      outline: none;
      box-shadow: 0 3px 8px rgba(39, 32, 20, 0.34), 0 0 0 4px rgba(250, 239, 216, 0.55);
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Segoe UI", sans-serif;
      font-size: 10.5px;
      font-weight: 900;
      line-height: 1;
      user-select: none;
      pointer-events: auto;
      touch-action: manipulation;
      cursor: pointer;
      will-change: transform;
    }
    .story-event-marker-root {
      display: inline-block;
      line-height: 0;
    }
    .story-landmark-marker-root {
      display: inline-block;
      line-height: 0;
    }
    .story-event-marker.selected {
      width: 25px;
      height: 25px;
      background: #d6a23b;
      border-color: #fff1b8;
      box-shadow: 0 4px 10px rgba(39, 32, 20, 0.38), 0 0 0 5px rgba(250, 239, 216, 0.68);
    }
    .story-event-marker.emotion {
      width: 28px;
      height: 28px;
      background: #f8dfa3;
      border-color: #a06a2f;
      color: #402918;
      font-size: 15px;
      box-shadow: 0 4px 10px rgba(39, 32, 20, 0.32), 0 0 0 5px rgba(250, 239, 216, 0.62);
    }
    .story-event-marker .order-badge {
      position: absolute;
      right: -4px;
      bottom: -4px;
      width: 13px;
      height: 13px;
      border-radius: 999px;
      display: grid;
      place-items: center;
      color: white;
      background: #2f9462;
      border: 1px solid #d8e9be;
      font-size: 7.5px;
      font-weight: 900;
      line-height: 1;
      box-shadow: 0 1px 3px rgba(39, 32, 20, 0.26);
    }
    .story-landmark-marker {
      width: 70px;
      height: 48px;
      padding: 0;
      border: 0;
      display: grid;
      place-items: center;
      background: transparent;
      appearance: none;
      outline: none;
      pointer-events: auto;
      touch-action: manipulation;
      cursor: pointer;
      user-select: none;
      opacity: 0.64;
    }
    .story-landmark-content {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 0;
      transform-origin: center center;
      will-change: transform;
    }
    .story-landmark-emoji {
      font-size: 14px;
      line-height: 1;
      opacity: 0.72;
      filter: drop-shadow(0 1px 2px rgba(41, 32, 20, 0.22));
    }
    .story-landmark-name {
      max-width: 72px;
      color: rgba(55, 40, 24, 0.68);
      font-size: 7.5px;
      font-weight: 750;
      line-height: 1.05;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      text-shadow:
        0 0 2px rgba(252, 248, 236, 0.78),
        0 0 3px rgba(252, 248, 236, 0.66);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div id="loading">3D 지형을 여는 중...</div>
  <script>
    const config = $payload;
    const post = (message) => {
      try {
        window.StoryBibleMap.postMessage(JSON.stringify(message));
      } catch (_) {}
    };

    const map = new maplibregl.Map({
      container: 'map',
      style: config.styleJsonUrl,
      center: config.center,
      zoom: config.zoom,
      pitch: config.pitch,
      bearing: config.bearing,
      antialias: true,
      attributionControl: false,
      renderWorldCopies: false,
      maxPitch: 85,
      minZoom: config.minZoom,
      maxZoom: config.maxZoom,
      maxBounds: config.maxBounds
    });
    window.storyBibleMap = map;

    window.storyBibleSetCamera = (nextCamera) => {
      const nextZoom = Math.max(config.minZoom, Math.min(config.maxZoom, Number(nextCamera.zoom || map.getZoom())));
      const nextCenter = Array.isArray(nextCamera.center) ? nextCamera.center : map.getCenter();
      const nextPitch = Number.isFinite(Number(nextCamera.pitch)) ? Number(nextCamera.pitch) : map.getPitch();
      const nextBearing = Number.isFinite(Number(nextCamera.bearing)) ? Number(nextCamera.bearing) : map.getBearing();
      const duration = Number(nextCamera.duration || 360);
      map.easeTo({
        center: nextCenter,
        zoom: nextZoom,
        pitch: nextPitch,
        bearing: nextBearing,
        duration
      });
    };

    window.storyBibleFitBounds = (request) => {
      const bounds = Array.isArray(request.bounds) ? request.bounds : null;
      if (!bounds || bounds.length !== 2) return;
      const padding = request.padding || {};
      const nextPitch = Number.isFinite(Number(request.pitch)) ? Number(request.pitch) : map.getPitch();
      const nextBearing = Number.isFinite(Number(request.bearing)) ? Number(request.bearing) : map.getBearing();
      const maxZoom = Math.max(config.minZoom, Math.min(config.maxZoom, Number(request.maxZoom || config.maxZoom)));
      const duration = Number(request.duration || 420);
      map.fitBounds(bounds, {
        padding: {
          top: Number(padding.top || 0),
          right: Number(padding.right || 0),
          bottom: Number(padding.bottom || 0),
          left: Number(padding.left || 0)
        },
        maxZoom,
        pitch: nextPitch,
        bearing: nextBearing,
        duration
      });
    };

    const addLayerSafely = (layer) => {
      if (!map.getLayer(layer.id)) {
        map.addLayer(layer);
      }
    };
    const hideBaseLabelLayers = () => {
      if (!config.hideBaseLabels) return;
      for (const layer of map.getStyle().layers || []) {
        if (layer.type !== 'symbol') continue;
        if (layer.id.startsWith('story-bible-')) continue;
        try {
          map.setLayoutProperty(layer.id, 'visibility', 'none');
        } catch (_) {}
      }
    };
    map.on('styledata', hideBaseLabelLayers);

    const sendInteraction = () => post({ type: 'mapInteraction' });
    let lastPointerInteractionAt = 0;
    const sendPointerInteraction = () => {
      const now = performance.now();
      if (now - lastPointerInteractionAt < 180) return;
      lastPointerInteractionAt = now;
      sendInteraction();
    };
    let suppressMapTapUntil = 0;
    let suppressMapTapReason = 'external';
    const isMapTapSuppressed = () => performance.now() < suppressMapTapUntil;
    const suppressMapTap = (durationMs = 650, reason = 'external') => {
      const duration = Number.isFinite(Number(durationMs)) ? Number(durationMs) : 650;
      const nextUntil = performance.now() + duration;
      const active = isMapTapSuppressed();
      if (!active || nextUntil >= suppressMapTapUntil || reason !== 'mapGesture') {
        suppressMapTapReason = reason;
      }
      suppressMapTapUntil = Math.max(suppressMapTapUntil, nextUntil);
    };
    const isMapTapExternallySuppressed = () => {
      return isMapTapSuppressed() && suppressMapTapReason !== 'mapGesture';
    };
    window.storyBibleSuppressMapTap = suppressMapTap;
    window.storyBibleClearMapTapSuppression = () => {
      suppressMapTapUntil = 0;
      suppressMapTapReason = 'external';
    };
    const eventUsesModifierKey = (event) => {
      const source = event && (event.originalEvent || event);
      return Boolean(source && (source.altKey || source.metaKey || source.ctrlKey || source.shiftKey));
    };
    const isMapControlTarget = (target) => {
      return Boolean(target && target.closest && target.closest('.maplibregl-ctrl'));
    };
    const sendGestureInteraction = (event) => {
      suppressMapTap(eventUsesModifierKey(event) ? 950 : 650, 'mapGesture');
      if (event && event.originalEvent) {
        sendInteraction();
      }
    };
    map.on('dragstart', sendGestureInteraction);
    map.on('zoomstart', sendGestureInteraction);
    map.on('rotatestart', sendGestureInteraction);
    map.on('pitchstart', sendGestureInteraction);
    map.on('boxzoomstart', sendGestureInteraction);
    map.getContainer().addEventListener('pointerdown', (event) => {
      if (!isMapTapExternallySuppressed()) {
        sendPointerInteraction();
      }
      if (eventUsesModifierKey(event) || isMapControlTarget(event.target)) {
        suppressMapTap(950, 'mapControl');
      }
    }, { capture: true, passive: true });
    map.getCanvas().addEventListener('wheel', (event) => {
      suppressMapTap(eventUsesModifierKey(event) ? 950 : 650, 'mapGesture');
    }, { passive: true });

    const overlay = $overlayPayload;
    const eventMarkers = new Map();
    const landmarkMarkers = new Map();
    let lastDomEventTapAt = 0;
    let lastDomLandmarkTapAt = 0;

    const setSourceData = (id, data) => {
      const source = map.getSource(id);
      if (source && source.setData) {
        source.setData(data);
      }
    };

    const emptyFeatureCollection = () => ({
      type: 'FeatureCollection',
      features: []
    });

    const addCircleImage = (id, fill, stroke, halo) => {
      if (map.hasImage(id)) return;
      const pixelRatio = 3;
      const logicalSize = 34;
      const size = logicalSize * pixelRatio;
      const center = size / 2;
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');
      ctx.clearRect(0, 0, size, size);
      ctx.shadowColor = 'rgba(34, 35, 23, 0.35)';
      ctx.shadowBlur = 7 * pixelRatio;
      ctx.shadowOffsetY = 2 * pixelRatio;
      ctx.fillStyle = halo;
      ctx.beginPath();
      ctx.arc(center, center, 14.2 * pixelRatio, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowColor = 'transparent';
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(center, center, 10.9 * pixelRatio, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = stroke;
      ctx.lineWidth = 1.35 * pixelRatio;
      ctx.beginPath();
      ctx.arc(center, center, 10.9 * pixelRatio, 0, Math.PI * 2);
      ctx.stroke();
      map.addImage(id, ctx.getImageData(0, 0, size, size), { pixelRatio });
    };

    const ensureEventPinImages = () => {
      addCircleImage(
        'story-event-pin-normal',
        '#6B4A2A',
        '#FCF8EC',
        'rgba(247, 235, 216, 0.72)'
      );
      addCircleImage(
        'story-event-pin-selected',
        '#D6A23B',
        '#FFF3BF',
        'rgba(247, 235, 216, 0.86)'
      );
      addCircleImage(
        'story-event-pin-emotion',
        '#F8DFA3',
        '#9B6A2B',
        'rgba(247, 235, 216, 0.82)'
      );
    };

    window.storyBibleSetOverlayData = (nextOverlay) => {
      overlay.countryBorders = nextOverlay.countryBorders;
      overlay.countryLabels = nextOverlay.countryLabels;
      overlay.regions = nextOverlay.regions;
      overlay.regionLabels = nextOverlay.regionLabels;
      overlay.events = nextOverlay.events;
      overlay.eventPath = nextOverlay.eventPath;
      overlay.landmarks = nextOverlay.landmarks;
      setSourceData('story-bible-country-borders', overlay.countryBorders);
      setSourceData('story-bible-country-labels', overlay.countryLabels);
      setSourceData('story-bible-regions', overlay.regions);
      setSourceData('story-bible-region-labels', overlay.regionLabels);
      setSourceData('story-bible-events', overlay.events);
      setSourceData('story-bible-event-path', overlay.eventPath);
      setSourceData('story-bible-landmarks', overlay.landmarks);
      syncEventDomMarkers();
      syncLandmarkDomMarkers();
    };

    const clearElement = (element) => {
      while (element.firstChild) {
        element.removeChild(element.firstChild);
      }
    };
    const postEventMarkerTap = (id) => {
      sendInteraction();
      if (isMapTapSuppressed()) return;
      const now = performance.now();
      if (now - lastDomEventTapAt < 280) return;
      lastDomEventTapAt = now;
      post({ type: 'eventTap', id });
    };
    const postLandmarkMarkerTap = (id) => {
      sendInteraction();
      if (isMapTapSuppressed()) return;
      const now = performance.now();
      if (now - lastDomLandmarkTapAt < 280) return;
      lastDomLandmarkTapAt = now;
      post({ type: 'landmarkTap', id });
    };
    const setEventMarkerElement = (element, properties) => {
      const selected = Boolean(properties.selected);
      const hasEmotion = Boolean(properties.hasEmotion);
      element.className = [
        'story-event-marker',
        selected ? 'selected' : '',
        hasEmotion ? 'emotion' : ''
      ].filter(Boolean).join(' ');
      clearElement(element);
      if (hasEmotion && properties.emotionEmoji) {
        const emotion = document.createElement('span');
        emotion.textContent = properties.emotionEmoji;
        element.appendChild(emotion);
        const badge = document.createElement('span');
        badge.className = 'order-badge';
        badge.textContent = String(properties.label || '');
        element.appendChild(badge);
      } else {
        element.textContent = String(properties.label || '');
      }
    };
    function syncEventDomMarkers() {
      if (!overlay.events || !Array.isArray(overlay.events.features)) return;
      const nextIds = new Set();
      for (const feature of overlay.events.features) {
        if (!feature || !feature.properties || !feature.geometry) continue;
        if (feature.geometry.type !== 'Point') continue;
        const coordinates = feature.geometry.coordinates;
        if (!Array.isArray(coordinates) || coordinates.length < 2) continue;
        const id = String(feature.properties.id || '');
        if (!id) continue;
        nextIds.add(id);
        let record = eventMarkers.get(id);
        if (!record) {
          const root = document.createElement('div');
          root.className = 'story-event-marker-root';
          const element = document.createElement('button');
          element.type = 'button';
          root.appendChild(element);
          element.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            postEventMarkerTap(id);
          });
          element.addEventListener('touchend', (event) => {
            event.preventDefault();
            event.stopPropagation();
            postEventMarkerTap(id);
          }, { passive: false });
          const marker = new maplibregl.Marker({
            element: root,
            anchor: 'center'
          }).setLngLat(coordinates).addTo(map);
          record = { element, marker };
          eventMarkers.set(id, record);
        }
        record.element.setAttribute('aria-label', feature.properties.title || '사건');
        setEventMarkerElement(record.element, feature.properties);
        record.marker.setLngLat(coordinates);
      }
      for (const [id, record] of eventMarkers.entries()) {
        if (nextIds.has(id)) continue;
        record.marker.remove();
        eventMarkers.delete(id);
      }
    }
    const landmarkScaleForZoom = () => {
      const raw = 0.24 + (map.getZoom() - config.minZoom) * 0.12;
      return Math.max(0.24, Math.min(1.0, raw));
    };
    const syncLandmarkMarkerScale = (element) => {
      const content = element.querySelector('.story-landmark-content');
      if (!content) return;
      content.style.transform = `scale(\${landmarkScaleForZoom().toFixed(3)})`;
    };
    const syncLandmarkMarkerScales = () => {
      for (const record of landmarkMarkers.values()) {
        syncLandmarkMarkerScale(record.element);
      }
    };
    const setLandmarkMarkerElement = (element, properties) => {
      const name = String(properties.name || '');
      const emoji = String(properties.emoji || '📍');
      element.setAttribute('aria-label', name || '랜드마크');
      let content = element.querySelector('.story-landmark-content');
      if (!content) {
        clearElement(element);
        content = document.createElement('span');
        content.className = 'story-landmark-content';
        const emojiNode = document.createElement('span');
        emojiNode.className = 'story-landmark-emoji';
        const nameNode = document.createElement('span');
        nameNode.className = 'story-landmark-name';
        content.appendChild(emojiNode);
        content.appendChild(nameNode);
        element.appendChild(content);
      }
      content.querySelector('.story-landmark-emoji').textContent = emoji;
      content.querySelector('.story-landmark-name').textContent = name;
      const priority = Number(properties.displayPriority || 0);
      element.style.zIndex = String(500 + priority);
      syncLandmarkMarkerScale(element);
    };
    function syncLandmarkDomMarkers() {
      if (!overlay.landmarks || !Array.isArray(overlay.landmarks.features)) return;
      const nextIds = new Set();
      for (const feature of overlay.landmarks.features) {
        if (!feature || !feature.properties || !feature.geometry) continue;
        if (feature.geometry.type !== 'Point') continue;
        const coordinates = feature.geometry.coordinates;
        if (!Array.isArray(coordinates) || coordinates.length < 2) continue;
        const id = String(feature.properties.id || '');
        if (!id) continue;
        nextIds.add(id);
        let record = landmarkMarkers.get(id);
        if (!record) {
          const root = document.createElement('div');
          root.className = 'story-landmark-marker-root';
          const element = document.createElement('button');
          element.type = 'button';
          root.appendChild(element);
          element.className = 'story-landmark-marker';
          element.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            postLandmarkMarkerTap(id);
          });
          element.addEventListener('touchend', (event) => {
            event.preventDefault();
            event.stopPropagation();
            postLandmarkMarkerTap(id);
          }, { passive: false });
          const marker = new maplibregl.Marker({
            element: root,
            anchor: 'center'
          }).setLngLat(coordinates).addTo(map);
          record = { element, marker };
          landmarkMarkers.set(id, record);
        }
        setLandmarkMarkerElement(record.element, feature.properties);
        record.marker.setLngLat(coordinates);
      }
      for (const [id, record] of landmarkMarkers.entries()) {
        if (nextIds.has(id)) continue;
        record.marker.remove();
        landmarkMarkers.delete(id);
      }
    }

    window.storyBiblePlayTransition = (transition) => {
      const source = map.getSource('story-bible-transition');
      if (!source) return;
      const from = transition.from;
      const to = transition.to;
      if (!Array.isArray(from) || !Array.isArray(to)) return;
      const duration = Math.max(240, Number(transition.duration || 2000));
      const startAt = performance.now();
      const animate = (now) => {
        const progress = Math.min(1, (now - startAt) / duration);
        const pulse = Math.sin(progress * Math.PI);
        source.setData({
          type: 'FeatureCollection',
          features: [
            {
              type: 'Feature',
              geometry: { type: 'Point', coordinates: from },
              properties: { progress, pulse, role: 'from' }
            },
            {
              type: 'Feature',
              geometry: { type: 'Point', coordinates: to },
              properties: { progress, pulse, role: 'to' }
            }
          ]
        });
        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          setTimeout(() => source.setData(emptyFeatureCollection()), 60);
        }
      };
      requestAnimationFrame(animate);
    };

    map.on('load', () => {
      hideBaseLabelLayers();
      ensureEventPinImages();
      const terrainSource = {
        type: 'raster-dem',
        tileSize: 256,
        maxzoom: 14
      };
      if (config.terrainTileJsonUrl && config.terrainTileJsonUrl.length > 0) {
        terrainSource.url = config.terrainTileJsonUrl;
      } else {
        terrainSource.tiles = config.terrainTiles;
      }
      if (config.terrainEncoding && config.terrainEncoding.length > 0) {
        terrainSource.encoding = config.terrainEncoding;
      }
      map.addSource('story-bible-terrain', terrainSource);
      map.setTerrain({
        source: 'story-bible-terrain',
        exaggeration: config.terrainExaggeration
      });

      map.addSource('story-bible-country-borders', {
        type: 'geojson',
        data: overlay.countryBorders
      });
      addLayerSafely({
        id: 'story-bible-country-border-line',
        type: 'line',
        source: 'story-bible-country-borders',
        paint: {
          'line-color': '#7B7656',
          'line-opacity': 0.58,
          'line-width': ['interpolate', ['linear'], ['zoom'], 4, 0.7, 7, 1.2, 10, 2.0],
          'line-dasharray': [1.2, 0.8]
        }
      });
      map.addSource('story-bible-country-labels', {
        type: 'geojson',
        data: overlay.countryLabels
      });
      addLayerSafely({
        id: 'story-bible-country-label',
        type: 'symbol',
        source: 'story-bible-country-labels',
        minzoom: 3.0,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Bold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 2.7, 7.2, 5.5, 9.0, 8.0, 10.4, 11.0, 11.2],
          'text-allow-overlap': false,
          'text-ignore-placement': false,
          'text-padding': 2
        },
        paint: {
          'text-color': '#302616',
          'text-opacity': 0.92,
          'text-halo-color': '#F8F1DD',
          'text-halo-width': 1.85,
          'text-halo-blur': 0.28
        }
      });

      map.addSource('story-bible-regions', {
        type: 'geojson',
        data: overlay.regions
      });
      addLayerSafely({
        id: 'story-bible-region-fill',
        type: 'fill',
        source: 'story-bible-regions',
        paint: {
          'fill-color': ['get', 'fillColor'],
          'fill-opacity': ['get', 'fillOpacity']
        }
      });
      addLayerSafely({
        id: 'story-bible-region-line',
        type: 'line',
        source: 'story-bible-regions',
        paint: {
          'line-color': ['get', 'lineColor'],
          'line-opacity': ['get', 'lineOpacity'],
          'line-width': ['case', ['get', 'selected'], 3.0, ['get', 'pickerMode'], 2.0, 1.7]
        }
      });
      addLayerSafely({
        id: 'story-bible-region-hit',
        type: 'fill',
        source: 'story-bible-regions',
        paint: {
          'fill-color': '#ffffff',
          'fill-opacity': 0.01
        }
      });
      map.addSource('story-bible-region-labels', {
        type: 'geojson',
        data: overlay.regionLabels
      });
      addLayerSafely({
        id: 'story-bible-region-label-anchor',
        type: 'circle',
        source: 'story-bible-region-labels',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 2.7, 3.4, 5.5, 4.4, 8.0, 5.2, 11.0, 6.0],
          'circle-color': ['case', ['get', 'selected'], '#5E8C4A', '#B57A1C'],
          'circle-opacity': ['case', ['get', 'selected'], 0.88, 0.78],
          'circle-stroke-color': '#F8F1DD',
          'circle-stroke-opacity': 0.86,
          'circle-stroke-width': 1.15
        }
      });
      addLayerSafely({
        id: 'story-bible-region-label',
        type: 'symbol',
        source: 'story-bible-region-labels',
        layout: {
          'text-field': ['get', 'label'],
          'text-font': ['Noto Sans Bold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 2.7, 10.0, 5.5, 11.8, 8.0, 13.2, 11.0, 14.0],
          'text-variable-anchor': ['top', 'bottom', 'left', 'right'],
          'text-radial-offset': 0.72,
          'text-justify': 'auto',
          'text-allow-overlap': false,
          'text-ignore-placement': false,
          'text-optional': true,
          'text-padding': 2,
          'symbol-sort-key': ['-', 1000, ['get', 'eventCount']]
        },
        paint: {
          'text-color': ['case', ['get', 'selected'], '#2F6B45', '#8A5F16'],
          'text-opacity': ['case', ['get', 'selected'], 0.98, 0.94],
          'text-halo-color': '#FFF7E2',
          'text-halo-width': ['case', ['get', 'selected'], 1.65, 1.45],
          'text-halo-blur': 0.12
        }
      });

      map.addSource('story-bible-landmarks', {
        type: 'geojson',
        data: overlay.landmarks
      });
      addLayerSafely({
        id: 'story-bible-landmark-hit',
        type: 'circle',
        source: 'story-bible-landmarks',
        paint: {
          'circle-radius': 18,
          'circle-color': '#ffffff',
          'circle-opacity': 0.01
        }
      });

      map.addSource('story-bible-events', {
        type: 'geojson',
        data: overlay.events
      });
      map.addSource('story-bible-event-path', {
        type: 'geojson',
        data: overlay.eventPath
      });
      map.addSource('story-bible-transition', {
        type: 'geojson',
        data: emptyFeatureCollection()
      });
      addLayerSafely({
        id: 'story-bible-event-path-line',
        type: 'line',
        source: 'story-bible-event-path',
        layout: {
          'line-cap': 'round',
          'line-join': 'round'
        },
        paint: {
          'line-color': ['case', ['has', 'color'], ['get', 'color'], '#776243'],
          'line-opacity': ['case', ['has', 'opacity'], ['get', 'opacity'], 0.82],
          'line-width': ['interpolate', ['linear'], ['zoom'], 3, 2.2, 8, 3.0, 12, 3.8],
          'line-offset': ['case', ['has', 'offset'], ['get', 'offset'], 0],
          'line-dasharray': [1.2, 0.95]
        }
      });
      addLayerSafely({
        id: 'story-bible-transition-glow',
        type: 'circle',
        source: 'story-bible-transition',
        paint: {
          'circle-radius': ['+', 14, ['*', ['get', 'pulse'], 22]],
          'circle-color': '#C69B3F',
          'circle-opacity': ['*', ['get', 'pulse'], 0.55],
          'circle-stroke-color': '#F8F3D0',
          'circle-stroke-width': 2.2
        }
      });
      addLayerSafely({
        id: 'story-bible-event-halo',
        type: 'circle',
        source: 'story-bible-events',
        paint: {
          'circle-radius': ['case', ['get', 'hasEmotion'], 18, ['get', 'selected'], 15, 13],
          'circle-color': '#FFF4D8',
          'circle-opacity': 0,
          'circle-stroke-color': '#6B4A2A',
          'circle-stroke-width': ['case', ['get', 'selected'], 2.2, 1.5],
          'circle-stroke-opacity': 0
        }
      });
      addLayerSafely({
        id: 'story-bible-event-dot',
        type: 'circle',
        source: 'story-bible-events',
        paint: {
          'circle-radius': ['case', ['get', 'hasEmotion'], 14, ['get', 'selected'], 11, 10],
          'circle-color': [
            'case',
            ['get', 'hasEmotion'],
            '#F8DFA3',
            ['get', 'selected'],
            '#D6A23B',
            ['get', 'color']
          ],
          'circle-opacity': 0,
          'circle-stroke-color': ['case', ['get', 'hasEmotion'], '#9B6A2B', '#FCF8EC'],
          'circle-stroke-width': ['case', ['get', 'hasEmotion'], 2.0, 1.4],
          'circle-stroke-opacity': 0
        }
      });
      addLayerSafely({
        id: 'story-bible-event-icon',
        type: 'symbol',
        source: 'story-bible-events',
        layout: {
          'icon-image': [
            'case',
            ['get', 'hasEmotion'],
            'story-event-pin-emotion',
            ['get', 'selected'],
            'story-event-pin-selected',
            'story-event-pin-normal'
          ],
          'icon-size': ['case', ['get', 'hasEmotion'], 1.02, ['get', 'selected'], 0.96, 0.86],
          'icon-pitch-alignment': 'viewport',
          'icon-rotation-alignment': 'viewport',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true
        },
        paint: {
          'icon-opacity': 0
        }
      });
      addLayerSafely({
        id: 'story-bible-event-number',
        type: 'symbol',
        source: 'story-bible-events',
        layout: {
          'text-field': ['get', 'label'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 10,
          'text-allow-overlap': true,
          'text-ignore-placement': true
        },
        paint: {
          'text-color': '#ffffff',
          'text-halo-color': '#47442d',
          'text-halo-width': 0.8,
          'text-opacity': 0
        }
      });
      addLayerSafely({
        id: 'story-bible-event-emotion',
        type: 'symbol',
        source: 'story-bible-events',
        layout: {
          'text-field': ['get', 'emotionEmoji'],
          'text-size': 16,
          'text-allow-overlap': true,
          'text-ignore-placement': true
        },
        paint: {
          'text-opacity': 0
        }
      });
      addLayerSafely({
        id: 'story-bible-event-order-badge',
        type: 'circle',
        source: 'story-bible-events',
        paint: {
          'circle-radius': 6.5,
          'circle-color': '#3F8F62',
          'circle-opacity': 0,
          'circle-stroke-color': '#D8E9BE',
          'circle-stroke-width': 1.0,
          'circle-stroke-opacity': 0,
          'circle-translate': [9, 9],
          'circle-translate-anchor': 'viewport'
        }
      });
      addLayerSafely({
        id: 'story-bible-event-order-badge-number',
        type: 'symbol',
        source: 'story-bible-events',
        layout: {
          'text-field': ['get', 'label'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 7,
          'text-allow-overlap': true,
          'text-ignore-placement': true
        },
        paint: {
          'text-color': '#ffffff',
          'text-opacity': 0,
          'text-translate': [9, 9],
          'text-translate-anchor': 'viewport'
        }
      });
      addLayerSafely({
        id: 'story-bible-event-hit',
        type: 'circle',
        source: 'story-bible-events',
        paint: {
          'circle-radius': 23,
          'circle-color': '#ffffff',
          'circle-opacity': 0.01
        }
      });
      syncEventDomMarkers();
      syncLandmarkDomMarkers();
      map.on('zoom', syncLandmarkMarkerScales);

      const pickSmallestRegionFeature = (features) => {
        let pick = null;
        let pickArea = Number.POSITIVE_INFINITY;
        for (const feature of features || []) {
          if (!feature || !feature.properties) continue;
          if (!feature.properties.id) continue;
          if (Number(feature.properties.eventCount || 0) <= 0) continue;
          const area = Number(feature.properties.bboxArea || Number.POSITIVE_INFINITY);
          if (!pick || area < pickArea) {
            pick = feature;
            pickArea = area;
          }
        }
        return pick;
      };
      const postRegionFeature = (feature) => {
        if (!feature || !feature.properties) return false;
        if (!feature.properties.id) return false;
        if (Number(feature.properties.eventCount || 0) <= 0) return false;
        post({ type: 'landmarkTap', id: feature.properties.id });
        return true;
      };
      const postEventFeature = (feature) => {
        if (!feature || !feature.properties) return false;
        if (!feature.properties.id) return false;
        post({ type: 'eventTap', id: feature.properties.id });
        return true;
      };
      const postLandmarkFeature = (feature) => {
        if (!feature || !feature.properties) return false;
        if (!feature.properties.id) return false;
        post({ type: 'landmarkTap', id: feature.properties.id });
        return true;
      };
      const pointInPolygonRing = (lngLat, ring) => {
        if (!Array.isArray(ring) || ring.length < 3) return false;
        const lng = Number(lngLat.lng);
        const lat = Number(lngLat.lat);
        let inside = false;
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          const pi = ring[i] || [];
          const pj = ring[j] || [];
          const xi = Number(pi[0]);
          const yi = Number(pi[1]);
          const xj = Number(pj[0]);
          const yj = Number(pj[1]);
          if (![xi, yi, xj, yj].every(Number.isFinite)) continue;
          const intersects = ((yi > lat) !== (yj > lat)) &&
            (lng < ((xj - xi) * (lat - yi)) / ((yj - yi) || 1e-12) + xi);
          if (intersects) inside = !inside;
        }
        return inside;
      };
      const pickRegionByLngLat = (lngLat) => {
        if (!lngLat || !overlay.regions || !Array.isArray(overlay.regions.features)) return null;
        let pick = null;
        let pickArea = Number.POSITIVE_INFINITY;
        for (const feature of overlay.regions.features) {
          if (!feature || !feature.properties || !feature.geometry) continue;
          if (!feature.properties.id) continue;
          if (Number(feature.properties.eventCount || 0) <= 0) continue;
          if (feature.geometry.type !== 'Polygon') continue;
          const rings = feature.geometry.coordinates;
          const outer = Array.isArray(rings) ? rings[0] : null;
          if (!pointInPolygonRing(lngLat, outer)) continue;
          const area = Number(feature.properties.bboxArea || Number.POSITIVE_INFINITY);
          if (!pick || area < pickArea) {
            pick = feature;
            pickArea = area;
          }
        }
        return pick;
      };
      const isRegionPickerActive = () => {
        return Boolean(overlay.regions && Array.isArray(overlay.regions.features) &&
          overlay.regions.features.some((feature) => Boolean(feature && feature.properties && feature.properties.pickerMode)));
      };
      const pickRegionAtPoint = (point, lngLat) => {
        const renderedRegion = pickSmallestRegionFeature(
          map.queryRenderedFeatures(point, {
            layers: ['story-bible-region-hit']
          })
        );
        return renderedRegion || pickRegionByLngLat(lngLat || map.unproject(point));
      };
      const handleMapTapPoint = (point, lngLat, options = {}) => {
        if (!options.ignoreSuppression && isMapTapSuppressed()) return;
        if (isRegionPickerActive() && postRegionFeature(pickRegionAtPoint(point, lngLat))) {
          return;
        }
        const eventFeature = map.queryRenderedFeatures(point, {
          layers: ['story-bible-event-hit']
        })[0];
        if (postEventFeature(eventFeature)) return;
        const landmarkFeature = map.queryRenderedFeatures(point, {
          layers: ['story-bible-landmark-hit']
        })[0];
        if (postLandmarkFeature(landmarkFeature)) return;
        postRegionFeature(pickRegionAtPoint(point, lngLat));
      };
      const canvasPointFromPointerEvent = (event) => {
        const rect = map.getCanvas().getBoundingClientRect();
        return [event.clientX - rect.left, event.clientY - rect.top];
      };
      let lastPointerTapAt = 0;
      map.on('click', (event) => {
        if (eventUsesModifierKey(event) || isMapControlTarget(event.originalEvent && event.originalEvent.target)) {
          suppressMapTap(950, 'mapControl');
          return;
        }
        const regionPickerClick = isRegionPickerActive();
        if (isMapTapSuppressed()) return;
        if (performance.now() - lastPointerTapAt < 320) return;
        sendInteraction();
        handleMapTapPoint(event.point, event.lngLat, { ignoreSuppression: regionPickerClick });
      });
      let pointerDownPoint = null;
      map.getCanvas().addEventListener('pointerdown', (event) => {
        if (eventUsesModifierKey(event)) {
          pointerDownPoint = null;
          suppressMapTap(950, 'mapGesture');
          return;
        }
        pointerDownPoint = {
          x: event.clientX,
          y: event.clientY,
          suppressed: isMapTapSuppressed()
        };
      }, { passive: true });
      map.getCanvas().addEventListener('pointermove', (event) => {
        if (!pointerDownPoint) return;
        const dx = event.clientX - pointerDownPoint.x;
        const dy = event.clientY - pointerDownPoint.y;
        if (Math.sqrt(dx * dx + dy * dy) > 18) {
          suppressMapTap(650, 'mapGesture');
        }
      }, { passive: true });
      map.getCanvas().addEventListener('pointerup', (event) => {
        if (!pointerDownPoint) return;
        const dx = event.clientX - pointerDownPoint.x;
        const dy = event.clientY - pointerDownPoint.y;
        const pointerStartedSuppressed = Boolean(pointerDownPoint.suppressed);
        pointerDownPoint = null;
        sendInteraction();
        const regionPickerPointerTap = isRegionPickerActive();
        if (eventUsesModifierKey(event) ||
            (isMapTapExternallySuppressed() && !regionPickerPointerTap) ||
            (pointerStartedSuppressed && isMapTapSuppressed() && !regionPickerPointerTap)) {
          suppressMapTap(950, 'mapGesture');
          return;
        }
        if (Math.sqrt(dx * dx + dy * dy) > 18) {
          suppressMapTap(650, 'mapGesture');
          return;
        }
        lastPointerTapAt = performance.now();
        const point = canvasPointFromPointerEvent(event);
        handleMapTapPoint(point, map.unproject(point), {
          ignoreSuppression: !pointerStartedSuppressed || regionPickerPointerTap
        });
      }, { passive: true });
      map.getCanvas().addEventListener('pointercancel', () => {
        pointerDownPoint = null;
        suppressMapTap(650, 'mapGesture');
      }, { passive: true });
      map.on('mouseenter', 'story-bible-region-hit', () => map.getCanvas().style.cursor = 'pointer');
      map.on('mouseleave', 'story-bible-region-hit', () => map.getCanvas().style.cursor = '');
      map.on('mouseenter', 'story-bible-event-hit', () => map.getCanvas().style.cursor = 'pointer');
      map.on('mouseleave', 'story-bible-event-hit', () => map.getCanvas().style.cursor = '');
      map.on('mouseenter', 'story-bible-landmark-hit', () => map.getCanvas().style.cursor = 'pointer');
      map.on('mouseleave', 'story-bible-landmark-hit', () => map.getCanvas().style.cursor = '');

      let readyPosted = false;
      const markReady = () => {
        if (readyPosted) return;
        readyPosted = true;
        document.body.classList.add('ready');
        post({ type: 'ready' });
      };
      map.once('idle', markReady);
      setTimeout(markReady, 900);
    });
  </script>
</body>
</html>
''';
  }

  Map<String, Object> _overlayPayload() {
    return {
      'countryBorders': _countryBorderFeatureCollection(),
      'countryLabels': _countryLabelFeatureCollection(),
      'regions': _regionFeatureCollection(),
      'regionLabels': _regionLabelFeatureCollection(),
      'events': _eventFeatureCollection(),
      'eventPath': _eventPathFeatureCollection(),
      'landmarks': _landmarkFeatureCollection(),
    };
  }

  Map<String, Object> _countryBorderFeatureCollection() {
    final features = <Map<String, Object>>[];
    for (final line in widget.countryBorderLines) {
      if (line.length < 2 || !line.any(_isInBibleBounds)) {
        continue;
      }
      final coordinates = line
          .map((point) => [point.longitude, point.latitude])
          .toList(growable: false);
      features.add({
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': coordinates},
        'properties': const {},
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  Map<String, Object> _countryLabelFeatureCollection() {
    final features = <Map<String, Object>>[];
    for (final label in widget.countryLabels) {
      if (!_isInBibleBounds(label.point)) {
        continue;
      }
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [label.point.longitude, label.point.latitude],
        },
        'properties': {'name': label.name},
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  bool _isInBibleBounds(LatLng point) {
    return point.longitude >= _boundsWest &&
        point.longitude <= _boundsEast &&
        point.latitude >= _boundsSouth &&
        point.latitude <= _boundsNorth;
  }

  Map<String, Object> _regionFeatureCollection() {
    final features = <Map<String, Object>>[];
    for (final landmark in widget.regionLandmarks) {
      final polygon = landmark.polygon;
      if (polygon.length < 3) {
        continue;
      }
      final selected = landmark.id == widget.selectedLandmarkId;
      final eventCount = widget.eventCountByLandmarkId?[landmark.id] ?? 0;
      if (eventCount <= 0) {
        continue;
      }
      final coords = polygon
          .map((point) => [point.longitude, point.latitude])
          .toList(growable: true);
      if (coords.isNotEmpty &&
          (coords.first[0] != coords.last[0] ||
              coords.first[1] != coords.last[1])) {
        coords.add(coords.first);
      }
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coords],
        },
        'properties': {
          'id': landmark.id,
          'name': landmark.name,
          'selected': selected,
          'eventCount': eventCount,
          'bboxArea': _polygonBboxArea(polygon),
          'pickerMode': widget.regionPickerMode,
          'fillColor': selected ? '#A9C982' : '#D7B75A',
          'lineColor': selected ? '#7B9D53' : '#B89235',
          'lineOpacity': widget.regionPickerMode || selected ? 0.76 : 0.68,
          'fillOpacity': selected
              ? 0.28
              : widget.regionPickerMode
              ? 0.16
              : 0.14,
        },
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  Map<String, Object> _regionLabelFeatureCollection() {
    final features = <Map<String, Object>>[];
    final shouldShowLabels =
        widget.regionPickerMode || widget.selectedLandmarkId != null;
    if (!shouldShowLabels) {
      return {'type': 'FeatureCollection', 'features': features};
    }
    for (final landmark in widget.regionLandmarks) {
      final polygon = landmark.polygon;
      if (!landmark.isRegion || polygon.length < 3) {
        continue;
      }
      final selected = landmark.id == widget.selectedLandmarkId;
      if (widget.selectedLandmarkId != null && !selected) {
        continue;
      }
      final eventCount = widget.eventCountByLandmarkId?[landmark.id] ?? 0;
      if (eventCount <= 0) {
        continue;
      }
      final labelPoint = _polygonLabelPoint(polygon);
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [labelPoint.longitude, labelPoint.latitude],
        },
        'properties': {
          'id': landmark.id,
          'name': landmark.name,
          'label': landmark.name,
          'eventCount': eventCount,
          'selected': selected,
        },
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  double _polygonBboxArea(List<LatLng> polygon) {
    if (polygon.length < 3) {
      return double.maxFinite;
    }
    var minLat = polygon.first.latitude;
    var maxLat = minLat;
    var minLng = polygon.first.longitude;
    var maxLng = minLng;
    for (final point in polygon) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return (maxLat - minLat) * (maxLng - minLng);
  }

  LatLng _polygonLabelPoint(List<LatLng> polygon) {
    final centroid = _polygonCentroid(polygon);
    if (_pointInPolygon(centroid, polygon)) {
      return centroid;
    }
    var minLat = polygon.first.latitude;
    var maxLat = minLat;
    var minLng = polygon.first.longitude;
    var maxLng = minLng;
    for (final point in polygon) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    final bboxCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    if (_pointInPolygon(bboxCenter, polygon)) {
      return bboxCenter;
    }
    return centroid;
  }

  LatLng _polygonCentroid(List<LatLng> polygon) {
    var twiceArea = 0.0;
    var latSum = 0.0;
    var lngSum = 0.0;
    for (var i = 0; i < polygon.length; i += 1) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final cross = (a.longitude * b.latitude) - (b.longitude * a.latitude);
      twiceArea += cross;
      lngSum += (a.longitude + b.longitude) * cross;
      latSum += (a.latitude + b.latitude) * cross;
    }
    if (twiceArea.abs() < 0.000001) {
      var lat = 0.0;
      var lng = 0.0;
      for (final point in polygon) {
        lat += point.latitude;
        lng += point.longitude;
      }
      return LatLng(lat / polygon.length, lng / polygon.length);
    }
    return LatLng(latSum / (3 * twiceArea), lngSum / (3 * twiceArea));
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      final intersects =
          ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
          (point.longitude <
              (pj.longitude - pi.longitude) *
                      (point.latitude - pi.latitude) /
                      (pj.latitude - pi.latitude) +
                  pi.longitude);
      if (intersects) {
        inside = !inside;
      }
    }
    return inside;
  }

  Map<String, Object> _eventFeatureCollection() {
    final features = <Map<String, Object>>[];
    final visibleEvents = _visibleCoordinateEvents();
    final points = _eventPointMap(includeHidden: false);
    for (var i = 0; i < visibleEvents.length; i += 1) {
      final event = visibleEvents[i];
      final selected = event.id == widget.selectedEventId;
      final point = points[event.id] ?? event.latLng;
      final emotionMark = widget.eventEmotionMarks[event.id];
      final hasEmotion =
          emotionMark != null && emotionMark.emotionKey.isNotEmpty;
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
        'properties': {
          'id': event.id,
          'title': event.title,
          'label': '${i + 1}',
          'selected': selected,
          'color': _eventColor(event),
          'hasEmotion': hasEmotion,
          'emotionKey': emotionMark?.emotionKey ?? '',
          'emotionEmoji': emotionMark?.emotionEmoji ?? '',
        },
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  Map<String, Object> _eventPathFeatureCollection() {
    if (!widget.orderedEventsActive) {
      return {'type': 'FeatureCollection', 'features': const []};
    }
    final visibleEvents = _visibleCoordinateEvents();
    if (visibleEvents.length < 2) {
      return {'type': 'FeatureCollection', 'features': const []};
    }
    final points = _eventPointMap(includeHidden: false);
    List<List<double>> coordinatesFor(List<StoryEvent> events) => events
        .map((event) {
          final point = points[event.id] ?? event.latLng;
          return [point.longitude, point.latitude];
        })
        .toList(growable: false);

    Map<String, Object> featureFor({
      required List<StoryEvent> events,
      required Map<String, Object> properties,
    }) {
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': coordinatesFor(events),
        },
        'properties': properties,
      };
    }

    final selectedCodes = widget.selectedCharacterCodes.toList()..sort();
    final features = <Map<String, Object>>[];
    if (selectedCodes.isNotEmpty) {
      final characterEventPaths = <MapEntry<String, List<StoryEvent>>>[];
      for (final code in selectedCodes) {
        final characterEvents = visibleEvents
            .where((event) => event.characterCodes.contains(code))
            .toList(growable: false);
        if (characterEvents.length < 2) {
          continue;
        }
        characterEventPaths.add(MapEntry(code, characterEvents));
      }
      final midpoint = (characterEventPaths.length - 1) / 2;
      for (var i = 0; i < characterEventPaths.length; i += 1) {
        final path = characterEventPaths[i];
        features.add(
          featureFor(
            events: path.value,
            properties: {
              'characterCode': path.key,
              'color': _cssColor(widget.colorForCharacter(path.key)),
              'opacity': 0.84,
              'offset': (i - midpoint) * 2.8,
            },
          ),
        );
      }
    }
    if (features.isEmpty) {
      features.add(
        featureFor(
          events: visibleEvents,
          properties: const {
            'characterCode': '',
            'color': '#776243',
            'opacity': 0.82,
            'offset': 0.0,
          },
        ),
      );
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  Map<String, Object> _landmarkFeatureCollection() {
    // 지역 선택 단계에서는 폴리곤 자체가 클릭 대상이다. 세부 랜드마크 DOM
    // 마커는 보이는 크기보다 hit box 가 커서 폴리곤 탭을 가로챌 수 있다.
    if (widget.regionPickerMode) {
      return {'type': 'FeatureCollection', 'features': const []};
    }
    final landmarks =
        widget.activeLandmarks
            .where(
              (landmark) =>
                  !landmark.isRegion && _isInBibleBounds(landmark.latLng),
            )
            .toList(growable: true)
          ..sort((a, b) => a.displayPriority.compareTo(b.displayPriority));
    final features = <Map<String, Object>>[];
    for (final landmark in landmarks) {
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [landmark.lng, landmark.lat],
        },
        'properties': {
          'id': landmark.id,
          'name': landmark.name,
          'emoji': landmark.emoji,
          'displayPriority': landmark.displayPriority,
        },
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  List<StoryEvent> _visibleCoordinateEvents() {
    final coordinateEvents = widget.events
        .where((event) => event.hasCoordinate)
        .toList(growable: false);
    final ordered = widget.orderedEventsActive
        ? (coordinateEvents.toList()
            ..sort((a, b) => a.globalRank.compareTo(b.globalRank)))
        : coordinateEvents;
    final visibleLimit = widget.visibleEventCount
        .clamp(0, ordered.length)
        .toInt();
    final visible = ordered.take(visibleLimit).toList(growable: true);
    final selectedEventId = widget.selectedEventId;
    if (selectedEventId != null &&
        !visible.any((event) => event.id == selectedEventId)) {
      StoryEvent? selectedEvent;
      for (final event in ordered) {
        if (event.id == selectedEventId) {
          selectedEvent = event;
          break;
        }
      }
      if (selectedEvent != null && !widget.orderedEventsActive) {
        visible.add(selectedEvent);
      }
    }
    return visible;
  }

  Map<String, LatLng> _eventPointMap({required bool includeHidden}) {
    if (widget.orderedEventsActive) {
      return map_math.buildRankedEventPointMap(
        widget.events,
        visibleCount: null,
        radiusDeg: _eventSpreadRadiusDeg,
        thresholdDeg: _eventSpreadThresholdDeg,
      );
    }
    final coordinateEvents = widget.events
        .where((event) => event.hasCoordinate)
        .toList(growable: false);
    return map_math.buildRankedEventPointMap(
      coordinateEvents,
      radiusDeg: _eventSpreadRadiusDeg,
      thresholdDeg: _eventSpreadThresholdDeg,
    );
  }

  String _eventColor(StoryEvent event) {
    final codes = event.characterCodes;
    if (codes.isEmpty || widget.selectedCharacterCodes.isEmpty) {
      return '#7B5D43';
    }
    final selectedCode = codes
        .where(widget.selectedCharacterCodes.contains)
        .firstOrNull;
    if (selectedCode == null) {
      return '#7B5D43';
    }
    return _cssColor(widget.colorForCharacter(selectedCode));
  }

  String _cssColor(Color color) {
    // ignore: deprecated_member_use
    final value = color.value;
    final red = (value >> 16) & 0xFF;
    final green = (value >> 8) & 0xFF;
    final blue = value & 0xFF;
    String hex(int channel) => channel.toRadixString(16).padLeft(2, '0');
    return '#${hex(red)}${hex(green)}${hex(blue)}';
  }
}

class _Map3dStatusOverlay extends StatelessWidget {
  const _Map3dStatusOverlay({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xEEFFF4DE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBDA076)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF3E2723),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6D5643),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
