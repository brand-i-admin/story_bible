import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/map/map_tile_style.dart';

void main() {
  group('StoryMapTileStyles', () {
    tearDown(() {
      dotenv = DotEnv();
    });

    test('keeps only free production map styles available', () {
      final styles = StoryMapTileStyles.availableStyles();

      expect(styles, [
        StoryMapTileStyle.openFreeMap3dLiberty,
        StoryMapTileStyle.watercolor,
      ]);
    });

    test('cycles through 3D first and fallback 2D style', () {
      expect(
        StoryMapTileStyles.nextStyle(StoryMapTileStyle.openFreeMap3dLiberty),
        StoryMapTileStyle.watercolor,
      );
      expect(
        StoryMapTileStyles.nextStyle(StoryMapTileStyle.watercolor),
        StoryMapTileStyle.openFreeMap3dLiberty,
      );
    });

    test('OpenFreeMap 3D terrain is free and keyless', () {
      final source = StoryMapTileStyles.sourceFor(
        StoryMapTileStyle.openFreeMap3dLiberty,
      );

      expect(source.style, StoryMapTileStyle.openFreeMap3dLiberty);
      expect(source.providerLabel, 'OpenFreeMap');
      expect(source.isThreeDimensional, isTrue);
      expect(source.urlTemplate, isEmpty);
      expect(
        source.styleJsonUrl,
        'https://tiles.openfreemap.org/styles/liberty',
      );
      expect(source.terrainTiles.single, contains('elevation-tiles-prod'));
      expect(source.terrainEncoding, 'terrarium');
      expect(source.hideBaseLabels, isTrue);
      expect(source.terrainExaggeration, greaterThan(1.0));
      expect(source.initialPitch, greaterThan(0));
    });

    test('defaults to OpenFreeMap 3D when no override is set', () {
      expect(
        StoryMapTileStyles.initialStyle,
        StoryMapTileStyle.openFreeMap3dLiberty,
      );
    });

    test('initial style can be selected from dotenv aliases', () {
      dotenv.testLoad(fileInput: 'STORY_MAP_TILE_STYLE=고지도');

      expect(StoryMapTileStyles.initialStyle, StoryMapTileStyle.watercolor);
    });
  });
}
