import 'package:flutter_test/flutter_test.dart';
import 'package:story_bible/models/era.dart';

void main() {
  group('Era.fromMap', () {
    test('유효한 map에서 모든 필드를 파싱한다', () {
      final map = <String, dynamic>{
        'id': 'era-id-1',
        'code': 'era_primeval',
        'testament': 'old',
        'name': '태초',
        'display_order': 1,
        'start_year': -4000,
        'end_year': -2000,
        'map_center_lat': 31.0,
        'map_center_lng': 47.0,
        'map_zoom': 5.5,
      };

      final era = Era.fromMap(map);

      expect(era.id, 'era-id-1');
      expect(era.code, 'era_primeval');
      expect(era.testament, 'old');
      expect(era.name, '태초');
      expect(era.displayOrder, 1);
      expect(era.startYear, -4000);
      expect(era.endYear, -2000);
      expect(era.mapCenterLat, 31.0);
      expect(era.mapCenterLng, 47.0);
      expect(era.mapZoom, 5.5);
    });

    test('testament가 null이면 기본값으로 old를 사용한다', () {
      final map = <String, dynamic>{
        'id': 'era-id-1',
        'code': 'era_test',
        'name': '테스트',
        'display_order': 1,
      };

      final era = Era.fromMap(map);

      expect(era.testament, 'old');
    });

    test('선택적 필드는 null을 허용한다', () {
      final map = <String, dynamic>{
        'id': 'era-id-1',
        'code': 'era_test',
        'testament': 'new',
        'name': '테스트',
        'display_order': 1,
      };

      final era = Era.fromMap(map);

      expect(era.startYear, isNull);
      expect(era.endYear, isNull);
      expect(era.mapCenterLat, isNull);
      expect(era.mapCenterLng, isNull);
      expect(era.mapZoom, isNull);
    });

    test('num 타입 좌표를 double로 변환한다', () {
      final map = <String, dynamic>{
        'id': 'era-id-1',
        'code': 'era_test',
        'testament': 'new',
        'name': '테스트',
        'display_order': 1,
        'map_center_lat': 31, // int
        'map_center_lng': 47, // int
        'map_zoom': 5, // int
      };

      final era = Era.fromMap(map);

      expect(era.mapCenterLat, 31.0);
      expect(era.mapCenterLng, 47.0);
      expect(era.mapZoom, 5.0);
    });
  });
}
