import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/data/font_scale_repository.dart';
import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  group('FontScaleRepository', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('빈 저장소에서는 기본값(normal)을 반환한다', () {
      final repo = FontScaleRepository(prefs);
      expect(repo.read(), FontScale.normal);
    });

    test('write 후 read하면 저장된 값을 반환한다', () async {
      final repo = FontScaleRepository(prefs);
      await repo.write(FontScale.large);
      expect(repo.read(), FontScale.large);
    });

    test('저장소에 잘못된 값이 있어도 normal로 복원된다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'font_scale': 'bogus',
      });
      prefs = await SharedPreferences.getInstance();
      final repo = FontScaleRepository(prefs);
      expect(repo.read(), FontScale.normal);
    });

    test('write는 동일 키(font_scale)를 사용한다', () async {
      final repo = FontScaleRepository(prefs);
      await repo.write(FontScale.small);
      expect(prefs.getString('font_scale'), 'small');
    });
  });
}
