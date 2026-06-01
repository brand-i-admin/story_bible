/// Story map base tile style.
///
/// The production map is fixed to the free, keyless 3D terrain stack:
/// OpenFreeMap Liberty style + public Mapzen Terrarium DEM.
enum StoryMapTileStyle { openFreeMap3dLiberty }

class MapAttributionLineData {
  const MapAttributionLineData({required this.source, this.license});

  final String source;
  final String? license;
}

class StoryMapTileSource {
  const StoryMapTileSource({
    required this.style,
    required this.label,
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

  /// Parchment grain opacity over a legacy 2D fallback map.
  ///
  /// The production 3D terrain map keeps this at 0 so hillshade and contour
  /// details remain legible.
  final double textureStrength;
}

class StoryMapTileStyles {
  const StoryMapTileStyles._();

  static const defaultStyle = StoryMapTileStyle.openFreeMap3dLiberty;

  static StoryMapTileStyle get initialStyle => defaultStyle;

  static List<StoryMapTileStyle> availableStyles() {
    return const <StoryMapTileStyle>[StoryMapTileStyle.openFreeMap3dLiberty];
  }

  static StoryMapTileStyle normalize(StoryMapTileStyle style) => style;

  static bool isOpenFreeMapStyle(StoryMapTileStyle style) {
    return style == StoryMapTileStyle.openFreeMap3dLiberty;
  }

  static StoryMapTileSource sourceFor(StoryMapTileStyle style) {
    switch (normalize(style)) {
      case StoryMapTileStyle.openFreeMap3dLiberty:
        return const StoryMapTileSource(
          style: StoryMapTileStyle.openFreeMap3dLiberty,
          label: '3D 무료 지형(OpenFreeMap)',
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
