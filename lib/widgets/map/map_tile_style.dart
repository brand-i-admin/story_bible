import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Story map base tile styles.
///
/// Keep the production picker intentionally small:
/// - 3D 무료 지형: OpenFreeMap Liberty + public Terrarium DEM
/// - 2D 고지도: Stamen Watercolor archive
///
/// `STORY_MAP_TILE_STYLE` can be set in `.env` or via `--dart-define`.
enum StoryMapTileStyle { openFreeMap3dLiberty, watercolor }

class MapAttributionLineData {
  const MapAttributionLineData({required this.source, this.license});

  final String source;
  final String? license;
}

class StoryMapTileSource {
  const StoryMapTileSource({
    required this.style,
    required this.label,
    required this.shortLabel,
    required this.providerLabel,
    required this.icon,
    required this.urlTemplate,
    required this.attributionLines,
    required this.textureStrength,
    this.isThreeDimensional = false,
    this.styleJsonUrl = '',
    this.terrainTileJsonUrl = '',
    this.terrainTiles = const [],
    this.terrainEncoding,
    this.hideBaseLabels = false,
    this.terrainExaggeration = 1.0,
    this.initialPitch = 0.0,
    this.initialBearing = 0.0,
    this.tileDimension = 256,
    this.zoomOffset = 0,
  });

  final StoryMapTileStyle style;
  final String label;
  final String shortLabel;
  final String providerLabel;
  final IconData icon;
  final String urlTemplate;
  final List<MapAttributionLineData> attributionLines;
  final bool isThreeDimensional;
  final String styleJsonUrl;
  final String terrainTileJsonUrl;
  final List<String> terrainTiles;
  final String? terrainEncoding;
  final bool hideBaseLabels;
  final double terrainExaggeration;
  final double initialPitch;
  final double initialBearing;
  final int tileDimension;
  final double zoomOffset;

  /// Parchment grain opacity over the base map.
  ///
  /// The watercolor map benefits from a strong atlas texture. Terrain maps need
  /// a lighter overlay so hillshade and contour details remain legible.
  final double textureStrength;
}

class StoryMapTileStyles {
  const StoryMapTileStyles._();

  static const defaultStyle = StoryMapTileStyle.openFreeMap3dLiberty;
  static const _initialStyleFromDefine = String.fromEnvironment(
    'STORY_MAP_TILE_STYLE',
  );

  static StoryMapTileStyle get initialStyle {
    final override = _initialStyleFromDefine.isNotEmpty
        ? _initialStyleFromDefine
        : _dotenvValue('STORY_MAP_TILE_STYLE');
    return _styleFromKey(override) ?? defaultStyle;
  }

  static String _dotenvValue(String key) {
    if (!dotenv.isInitialized) {
      return '';
    }
    return dotenv.maybeGet(key, fallback: '')?.trim() ?? '';
  }

  static List<StoryMapTileStyle> availableStyles() {
    return const <StoryMapTileStyle>[
      StoryMapTileStyle.openFreeMap3dLiberty,
      StoryMapTileStyle.watercolor,
    ];
  }

  static StoryMapTileStyle normalize(StoryMapTileStyle style) => style;

  static bool isOpenFreeMapStyle(StoryMapTileStyle style) {
    return style == StoryMapTileStyle.openFreeMap3dLiberty;
  }

  static StoryMapTileStyle nextStyle(StoryMapTileStyle current) {
    final styles = availableStyles();
    final index = styles.indexOf(normalize(current));
    if (index < 0 || index == styles.length - 1) {
      return styles.first;
    }
    return styles[index + 1];
  }

  static StoryMapTileStyle? _styleFromKey(String raw) {
    final normalized = _normalizedStyleKey(raw);
    if (normalized.isEmpty) {
      return null;
    }
    for (final style in StoryMapTileStyle.values) {
      final aliases = _styleAliases(style).map(_normalizedStyleKey);
      if (aliases.contains(normalized)) {
        return style;
      }
    }
    return null;
  }

  static String _normalizedStyleKey(String raw) {
    return raw.trim().replaceAll('_', '').replaceAll('-', '').toLowerCase();
  }

  static Iterable<String> _styleAliases(StoryMapTileStyle style) sync* {
    yield style.name;
    switch (style) {
      case StoryMapTileStyle.watercolor:
        yield 'stamen';
        yield '고지도';
        break;
      case StoryMapTileStyle.openFreeMap3dLiberty:
        yield 'openfreemap';
        yield 'openfree';
        yield 'liberty';
        yield 'liberty3d';
        yield 'free3d';
        yield '3d';
        break;
    }
  }

  static StoryMapTileSource sourceFor(StoryMapTileStyle style) {
    switch (normalize(style)) {
      case StoryMapTileStyle.watercolor:
        return const StoryMapTileSource(
          style: StoryMapTileStyle.watercolor,
          label: '고지도',
          shortLabel: '고지도',
          providerLabel: 'Stamen',
          icon: Icons.map_outlined,
          urlTemplate:
              'https://watercolormaps.collection.cooperhewitt.org/tile/watercolor/{z}/{x}/{y}.jpg',
          textureStrength: 0.32,
          attributionLines: [
            MapAttributionLineData(
              source: 'Stamen Watercolor 타일',
              license: 'CC BY 4.0',
            ),
            MapAttributionLineData(
              source: 'OpenStreetMap 데이터',
              license: 'ODbL',
            ),
            MapAttributionLineData(
              source: '아카이브 호스팅: Cooper Hewitt, Smithsonian Design Museum',
            ),
            MapAttributionLineData(
              source: '국경/수계 보조: Natural Earth',
              license: 'Public Domain',
            ),
          ],
        );
      case StoryMapTileStyle.openFreeMap3dLiberty:
        return const StoryMapTileSource(
          style: StoryMapTileStyle.openFreeMap3dLiberty,
          label: '3D 무료 지형(OpenFreeMap)',
          shortLabel: '3D Free',
          providerLabel: 'OpenFreeMap',
          icon: Icons.public_rounded,
          urlTemplate: '',
          isThreeDimensional: true,
          styleJsonUrl: 'https://tiles.openfreemap.org/styles/liberty',
          terrainTiles: [
            'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png',
          ],
          terrainEncoding: 'terrarium',
          hideBaseLabels: true,
          terrainExaggeration: 1.35,
          initialPitch: 20,
          initialBearing: 0,
          textureStrength: 0.0,
          attributionLines: [
            MapAttributionLineData(source: 'OpenFreeMap Liberty style'),
            MapAttributionLineData(source: 'OpenStreetMap contributors'),
            MapAttributionLineData(source: 'Mapzen Terrain Tiles on AWS'),
            MapAttributionLineData(source: 'MapLibre GL JS'),
            MapAttributionLineData(
              source: '국경/수계 보조: Natural Earth',
              license: 'Public Domain',
            ),
          ],
        );
    }
  }
}
