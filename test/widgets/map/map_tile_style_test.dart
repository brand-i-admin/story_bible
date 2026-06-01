import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/map/map_tile_style.dart';

void main() {
  group('StoryMapTileStyles', () {
    test('keeps only the free 3D production map style available', () {
      final styles = StoryMapTileStyles.availableStyles();

      expect(styles, [StoryMapTileStyle.openFreeMap3dLiberty]);
    });

    test('OpenFreeMap 3D terrain is free and keyless', () {
      final source = StoryMapTileStyles.sourceFor(
        StoryMapTileStyle.openFreeMap3dLiberty,
      );

      expect(source.style, StoryMapTileStyle.openFreeMap3dLiberty);
      expect(source.label, contains('OpenFreeMap'));
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

    test('defaults to OpenFreeMap 3D', () {
      expect(
        StoryMapTileStyles.initialStyle,
        StoryMapTileStyle.openFreeMap3dLiberty,
      );
    });
  });
}
