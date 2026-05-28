import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Story map base tile styles.
///
/// The app keeps `flutter_map` as the rendering surface and swaps only the
/// raster tile source. MapTiler is opt-in because it requires an API key:
///
///   MAPTILER_API_KEY=... in .env
///   flutter run --dart-define=MAPTILER_API_KEY=...
///   flutter run --dart-define=STORY_MAP_TILE_STYLE=mapTilerLandscape
enum StoryMapTileStyle {
  watercolor,
  esriTopo,
  mapTilerAquarelle,
  mapTilerLandscape,
  mapTilerOutdoor,
  mapTilerOcean,
  mapTilerDataviz,
  mapTilerSatellitePlain,
  mapTilerSatelliteHybrid,
  mapTilerBackdrop,
  mapTilerBase,
}

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
    required this.icon,
    required this.urlTemplate,
    required this.attributionLines,
    required this.textureStrength,
  });

  final StoryMapTileStyle style;
  final String label;
  final String shortLabel;
  final IconData icon;
  final String urlTemplate;
  final List<MapAttributionLineData> attributionLines;

  /// Parchment grain opacity over the base map.
  ///
  /// The watercolor map benefits from a strong atlas texture. Terrain maps need
  /// a lighter overlay so hillshade and contour details remain legible.
  final double textureStrength;
}

class StoryMapTileStyles {
  const StoryMapTileStyles._();

  static const defaultStyle = StoryMapTileStyle.watercolor;
  static const _mapTilerApiKeyFromDefine = String.fromEnvironment(
    'MAPTILER_API_KEY',
  );
  static const _initialStyleFromDefine = String.fromEnvironment(
    'STORY_MAP_TILE_STYLE',
  );

  /// MapTiler public key.
  ///
  /// `--dart-define` wins for CI/release builds; `.env` keeps local
  /// `flutter run` easy because `main.dart` already loads it before the map
  /// screen is built.
  static String get mapTilerApiKey {
    if (_mapTilerApiKeyFromDefine.isNotEmpty) {
      return _mapTilerApiKeyFromDefine;
    }
    return _dotenvValue('MAPTILER_API_KEY');
  }

  static StoryMapTileStyle get initialStyle {
    final override = _initialStyleFromDefine.isNotEmpty
        ? _initialStyleFromDefine
        : _dotenvValue('STORY_MAP_TILE_STYLE');
    return normalize(_styleFromKey(override) ?? defaultStyle);
  }

  static String _dotenvValue(String key) {
    if (!dotenv.isInitialized) {
      return '';
    }
    return dotenv.maybeGet(key, fallback: '')?.trim() ?? '';
  }

  static bool get hasMapTilerKey => mapTilerApiKey.isNotEmpty;

  static List<StoryMapTileStyle> availableStyles() {
    return <StoryMapTileStyle>[
      StoryMapTileStyle.watercolor,
      StoryMapTileStyle.esriTopo,
      if (hasMapTilerKey) ...mapTilerCandidateStyles,
    ];
  }

  static const mapTilerCandidateStyles = <StoryMapTileStyle>[
    StoryMapTileStyle.mapTilerAquarelle,
    StoryMapTileStyle.mapTilerLandscape,
    StoryMapTileStyle.mapTilerOutdoor,
    StoryMapTileStyle.mapTilerOcean,
    StoryMapTileStyle.mapTilerDataviz,
    StoryMapTileStyle.mapTilerSatellitePlain,
    StoryMapTileStyle.mapTilerSatelliteHybrid,
    StoryMapTileStyle.mapTilerBackdrop,
    StoryMapTileStyle.mapTilerBase,
  ];

  static bool isMapTilerStyle(StoryMapTileStyle style) {
    return mapTilerCandidateStyles.contains(style);
  }

  static StoryMapTileStyle normalize(StoryMapTileStyle style) {
    if (isMapTilerStyle(style) && !hasMapTilerKey) {
      return defaultStyle;
    }
    return style;
  }

  static StoryMapTileStyle nextStyle(StoryMapTileStyle current) {
    final styles = availableStyles();
    final normalized = normalize(current);
    final index = styles.indexOf(normalized);
    if (index < 0 || index == styles.length - 1) {
      return styles.first;
    }
    return styles[index + 1];
  }

  static StoryMapTileStyle? _styleFromKey(String raw) {
    final normalized = raw
        .trim()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final style in StoryMapTileStyle.values) {
      final name = style.name.toLowerCase();
      if (normalized == name ||
          normalized == name.replaceFirst('maptiler', '') ||
          normalized == _mapTilerMapId(style).replaceAll('-', '')) {
        return style;
      }
    }
    return null;
  }

  static StoryMapTileSource sourceFor(StoryMapTileStyle style) {
    switch (normalize(style)) {
      case StoryMapTileStyle.watercolor:
        return const StoryMapTileSource(
          style: StoryMapTileStyle.watercolor,
          label: '고지도',
          shortLabel: '고지도',
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
      case StoryMapTileStyle.esriTopo:
        return const StoryMapTileSource(
          style: StoryMapTileStyle.esriTopo,
          label: '지형(Esri)',
          shortLabel: '지형',
          icon: Icons.terrain_rounded,
          urlTemplate:
              'https://services.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
          textureStrength: 0.14,
          attributionLines: [
            MapAttributionLineData(source: 'Esri World Topographic Map'),
            MapAttributionLineData(
              source: 'Esri, HERE, Garmin, FAO, NOAA, USGS',
            ),
            MapAttributionLineData(source: 'OpenStreetMap contributors'),
            MapAttributionLineData(
              source: '국경/수계 보조: Natural Earth',
              license: 'Public Domain',
            ),
          ],
        );
      case StoryMapTileStyle.mapTilerAquarelle:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerAquarelle,
          label: '수채화(MapTiler)',
          shortLabel: '수채화',
          icon: Icons.brush_rounded,
          textureStrength: 0.08,
        );
      case StoryMapTileStyle.mapTilerLandscape:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerLandscape,
          label: '여정 지형(MapTiler)',
          shortLabel: '여정',
          icon: Icons.landscape_rounded,
          textureStrength: 0.06,
        );
      case StoryMapTileStyle.mapTilerOutdoor:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerOutdoor,
          label: '야외 지형(MapTiler)',
          shortLabel: '야외',
          icon: Icons.hiking_rounded,
          textureStrength: 0.06,
        );
      case StoryMapTileStyle.mapTilerOcean:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerOcean,
          label: '해안/바다(MapTiler)',
          shortLabel: '해안',
          icon: Icons.water_rounded,
          textureStrength: 0.04,
        );
      case StoryMapTileStyle.mapTilerDataviz:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerDataviz,
          label: '담백 수계(MapTiler)',
          shortLabel: '수계',
          icon: Icons.blur_on_rounded,
          textureStrength: 0.05,
        );
      case StoryMapTileStyle.mapTilerSatellitePlain:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerSatellitePlain,
          label: '위성 원본(MapTiler)',
          shortLabel: '위성',
          icon: Icons.satellite_alt_rounded,
          textureStrength: 0.02,
        );
      case StoryMapTileStyle.mapTilerSatelliteHybrid:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerSatelliteHybrid,
          label: '위성 라벨(MapTiler)',
          shortLabel: '위성+',
          icon: Icons.satellite_alt_rounded,
          textureStrength: 0.02,
        );
      case StoryMapTileStyle.mapTilerBackdrop:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerBackdrop,
          label: '담백 지형(MapTiler)',
          shortLabel: '담백',
          icon: Icons.filter_hdr_rounded,
          textureStrength: 0.08,
        );
      case StoryMapTileStyle.mapTilerBase:
        return _mapTilerSource(
          style: StoryMapTileStyle.mapTilerBase,
          label: '기본 지도(MapTiler)',
          shortLabel: '기본',
          icon: Icons.public_rounded,
          textureStrength: 0.08,
        );
    }
  }

  static StoryMapTileSource _mapTilerSource({
    required StoryMapTileStyle style,
    required String label,
    required String shortLabel,
    required IconData icon,
    required double textureStrength,
  }) {
    final mapId = _mapTilerMapId(style);
    return StoryMapTileSource(
      style: style,
      label: label,
      shortLabel: shortLabel,
      icon: icon,
      urlTemplate:
          'https://api.maptiler.com/maps/$mapId/256/{z}/{x}/{y}.png?key=$mapTilerApiKey',
      textureStrength: textureStrength,
      attributionLines: [
        MapAttributionLineData(source: 'MapTiler $shortLabel'),
        const MapAttributionLineData(source: 'OpenStreetMap contributors'),
        const MapAttributionLineData(
          source: '국경/수계 보조: Natural Earth',
          license: 'Public Domain',
        ),
      ],
    );
  }

  static String _mapTilerMapId(StoryMapTileStyle style) {
    switch (style) {
      case StoryMapTileStyle.mapTilerAquarelle:
        return 'aquarelle-v4';
      case StoryMapTileStyle.mapTilerLandscape:
        return 'landscape-v4';
      case StoryMapTileStyle.mapTilerOutdoor:
        return 'outdoor-v4';
      case StoryMapTileStyle.mapTilerOcean:
        return 'ocean-v4';
      case StoryMapTileStyle.mapTilerDataviz:
        return 'dataviz-v4';
      case StoryMapTileStyle.mapTilerSatellitePlain:
        return 'satellite';
      case StoryMapTileStyle.mapTilerSatelliteHybrid:
        return 'hybrid';
      case StoryMapTileStyle.mapTilerBackdrop:
        return 'backdrop-v4';
      case StoryMapTileStyle.mapTilerBase:
        return 'base-v4';
      case StoryMapTileStyle.watercolor:
      case StoryMapTileStyle.esriTopo:
        return '';
    }
  }
}
