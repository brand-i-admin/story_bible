import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era_boundary.dart';

void main() {
  group('EraBoundary.fromMap', () {
    test('jsonb 폴리곤 배열을 LatLng 리스트로 파싱한다', () {
      final map = <String, dynamic>{
        'id': 'eb-1',
        'era_id': 'era-1',
        'polygon_index': 0,
        'polygon': [
          [31.5, 35.2],
          [32.0, 35.5],
          [31.8, 36.0],
        ],
        'color': '#F4A261',
        'fill_opacity': 0.18,
        'display_order': 2,
      };

      final boundary = EraBoundary.fromMap(map);

      expect(boundary.id, 'eb-1');
      expect(boundary.eraId, 'era-1');
      expect(boundary.polygonIndex, 0);
      expect(boundary.polygon, hasLength(3));
      expect(boundary.polygon.first.latitude, 31.5);
      expect(boundary.polygon.first.longitude, 35.2);
      expect(boundary.fillOpacity, 0.18);
      expect(boundary.displayOrder, 2);
    });

    test('#RRGGBB 색을 alpha=FF 로 보강해 파싱한다', () {
      final boundary = EraBoundary.fromMap(<String, dynamic>{
        'id': 'id',
        'era_id': 'era-1',
        'polygon_index': 0,
        'polygon': [
          [0, 0],
          [1, 0],
          [1, 1],
        ],
        'color': '#F4A261',
      });

      expect(boundary.color, const Color(0xFFF4A261));
    });

    test('잘못된 색 문자열은 기본값으로 폴백한다', () {
      final boundary = EraBoundary.fromMap(<String, dynamic>{
        'id': 'id',
        'era_id': 'era-1',
        'polygon_index': 0,
        'polygon': [
          [0, 0],
          [1, 0],
          [1, 1],
        ],
        'color': 'not-a-hex',
      });

      expect(boundary.color, const Color(0xFFFF8800));
    });

    test('폴리곤 정점이 num/double 혼합이어도 모두 double 로 변환한다', () {
      final boundary = EraBoundary.fromMap(<String, dynamic>{
        'id': 'id',
        'era_id': 'era-1',
        'polygon_index': 0,
        'polygon': [
          [31, 35],
          [32.0, 35.5],
        ],
      });

      expect(boundary.polygon.first.latitude, 31.0);
      expect(boundary.polygon.first.longitude, 35.0);
      expect(boundary.polygon.last.latitude, 32.0);
      expect(boundary.polygon.last.longitude, 35.5);
    });

    test('polygon 이 null/잘못된 형태면 빈 리스트', () {
      final boundary = EraBoundary.fromMap(<String, dynamic>{
        'id': 'id',
        'era_id': 'era-1',
        'polygon_index': 0,
        'polygon': null,
      });

      expect(boundary.polygon, isEmpty);
    });
  });
}
