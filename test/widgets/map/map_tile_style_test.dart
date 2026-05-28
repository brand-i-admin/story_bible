import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/map/map_tile_style.dart';

void main() {
  group('StoryMapTileStyles', () {
    tearDown(() {
      dotenv = DotEnv();
    });

    test('keeps watercolor and Esri terrain available without secrets', () {
      final styles = StoryMapTileStyles.availableStyles();

      expect(styles.first, StoryMapTileStyle.watercolor);
      expect(styles, contains(StoryMapTileStyle.esriTopo));
      if (StoryMapTileStyles.mapTilerApiKey.isEmpty) {
        for (final style in StoryMapTileStyles.mapTilerCandidateStyles) {
          expect(styles, isNot(contains(style)));
        }
      } else {
        for (final style in StoryMapTileStyles.mapTilerCandidateStyles) {
          expect(styles, contains(style));
        }
      }
    });

    test(
      'normalizes MapTiler styles to watercolor when the API key is absent',
      () {
        final normalized = StoryMapTileStyles.normalize(
          StoryMapTileStyle.mapTilerLandscape,
        );

        if (StoryMapTileStyles.mapTilerApiKey.isEmpty) {
          expect(normalized, StoryMapTileStyle.watercolor);
        } else {
          expect(normalized, StoryMapTileStyle.mapTilerLandscape);
        }
      },
    );

    test('Esri topographic source uses ArcGIS XYZ tile order', () {
      final source = StoryMapTileStyles.sourceFor(StoryMapTileStyle.esriTopo);

      expect(source.label, '지형(Esri)');
      expect(source.urlTemplate, contains('World_Topo_Map/MapServer'));
      expect(source.urlTemplate, endsWith('/tile/{z}/{y}/{x}'));
      expect(source.textureStrength, lessThan(0.20));
    });

    test(
      'MapTiler landscape source is key-backed and keeps terrain legible',
      () {
        final source = StoryMapTileStyles.sourceFor(
          StoryMapTileStyle.mapTilerLandscape,
        );

        if (StoryMapTileStyles.mapTilerApiKey.isEmpty) {
          expect(source.style, StoryMapTileStyle.watercolor);
        } else {
          expect(source.urlTemplate, contains('api.maptiler.com/maps/'));
          expect(source.urlTemplate, contains('/maps/landscape-v4/'));
          expect(source.urlTemplate, contains('key='));
          expect(source.textureStrength, lessThan(0.10));
        }
      },
    );

    test('enables MapTiler candidates from loaded dotenv values', () {
      dotenv.testLoad(
        fileInput: [
          'MAPTILER_API_KEY=demo-maptiler-key',
          'MAPTILER_MAP_ID=topo-v4',
        ].join('\n'),
      );

      final styles = StoryMapTileStyles.availableStyles();
      final source = StoryMapTileStyles.sourceFor(
        StoryMapTileStyle.mapTilerOutdoor,
      );

      expect(styles, contains(StoryMapTileStyle.mapTilerAquarelle));
      expect(styles, contains(StoryMapTileStyle.mapTilerLandscape));
      expect(styles, contains(StoryMapTileStyle.mapTilerOutdoor));
      expect(styles, contains(StoryMapTileStyle.mapTilerOcean));
      expect(styles, contains(StoryMapTileStyle.mapTilerDataviz));
      expect(styles, contains(StoryMapTileStyle.mapTilerSatellitePlain));
      expect(styles, contains(StoryMapTileStyle.mapTilerSatelliteHybrid));
      expect(source.style, StoryMapTileStyle.mapTilerOutdoor);
      expect(source.urlTemplate, contains('/maps/outdoor-v4/'));
      expect(source.urlTemplate, contains('key=demo-maptiler-key'));
    });

    test('cycles through only enabled styles', () {
      final first = StoryMapTileStyles.nextStyle(StoryMapTileStyle.watercolor);
      expect(first, StoryMapTileStyle.esriTopo);

      final second = StoryMapTileStyles.nextStyle(first);
      if (StoryMapTileStyles.mapTilerApiKey.isEmpty) {
        expect(second, StoryMapTileStyle.watercolor);
      } else {
        expect(second, StoryMapTileStyle.mapTilerAquarelle);
        expect(
          StoryMapTileStyles.nextStyle(StoryMapTileStyle.mapTilerBase),
          StoryMapTileStyle.watercolor,
        );
      }
    });

    test('satellite sources use MapTiler raster ids that separate labels', () {
      dotenv.testLoad(fileInput: 'MAPTILER_API_KEY=demo-maptiler-key');

      final plain = StoryMapTileStyles.sourceFor(
        StoryMapTileStyle.mapTilerSatellitePlain,
      );
      final hybrid = StoryMapTileStyles.sourceFor(
        StoryMapTileStyle.mapTilerSatelliteHybrid,
      );

      expect(plain.urlTemplate, contains('/maps/satellite/'));
      expect(hybrid.urlTemplate, contains('/maps/hybrid/'));
    });
  });
}
