import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/landmark.dart';

void main() {
  group('Landmark.fromMap', () {
    test('필수 필드와 선택 필드를 모두 파싱한다', () {
      final map = <String, dynamic>{
        'id': 'landmark-id-1',
        'code': 'jerusalem_temple',
        'name': '예루살렘 성전',
        'description': '솔로몬이 세운 성전 자리.',
        'emoji': '🏛️',
        'category': 'temple',
        'lat': 31.778,
        'lng': 35.2354,
        'display_priority': 0,
        'era_codes': <String>['era_monarchy', 'era_nt_public_ministry'],
        'related_event_codes': <String>['solomon', 'david'],
      };

      final lm = Landmark.fromMap(map);

      expect(lm.id, 'landmark-id-1');
      expect(lm.code, 'jerusalem_temple');
      expect(lm.name, '예루살렘 성전');
      expect(lm.description, '솔로몬이 세운 성전 자리.');
      expect(lm.emoji, '🏛️');
      expect(lm.category, 'temple');
      expect(lm.lat, 31.778);
      expect(lm.lng, 35.2354);
      expect(lm.displayPriority, 0);
      expect(lm.eraCodes, ['era_monarchy', 'era_nt_public_ministry']);
      expect(lm.relatedEventCodes, ['solomon', 'david']);
    });

    test('emoji 가 null 이면 기본값 📍 을 사용한다', () {
      final map = <String, dynamic>{
        'id': 'id',
        'code': 'no_emoji',
        'name': '이름',
        'lat': 30.0,
        'lng': 40.0,
      };

      final lm = Landmark.fromMap(map);

      expect(lm.emoji, '📍');
    });

    test('era_codes 가 비어 있으면 빈 리스트를 반환한다', () {
      final map = <String, dynamic>{
        'id': 'id',
        'code': 'no_era',
        'name': '시대 미정',
        'lat': 0.0,
        'lng': 0.0,
      };

      final lm = Landmark.fromMap(map);

      expect(lm.eraCodes, isEmpty);
      expect(lm.relatedEventCodes, isEmpty);
    });

    test('int 타입 좌표를 double 로 변환한다', () {
      final map = <String, dynamic>{
        'id': 'id',
        'code': 'int_coords',
        'name': '정수좌표',
        'lat': 31,
        'lng': 35,
      };

      final lm = Landmark.fromMap(map);

      expect(lm.lat, 31.0);
      expect(lm.lng, 35.0);
    });

    test('latLng getter 가 위경도를 LatLng 으로 묶어 반환한다', () {
      final lm = Landmark.fromMap(const <String, dynamic>{
        'id': 'id',
        'code': 'sinai',
        'name': '시내산',
        'lat': 28.5392,
        'lng': 33.9756,
      });

      expect(lm.latLng.latitude, 28.5392);
      expect(lm.latLng.longitude, 33.9756);
    });
  });
}
