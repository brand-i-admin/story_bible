import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/data/color_palette_repository.dart';
import 'package:story_bible/theme/app_color_palette.dart';

void main() {
  group('ColorPaletteRepository', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('저장값이 없으면 classic을 반환한다', () {
      final repo = ColorPaletteRepository(prefs);

      expect(repo.read(), AppColorPalette.classic);
    });

    test('선택한 팔레트를 같은 키로 저장한다', () async {
      final repo = ColorPaletteRepository(prefs);

      await repo.write(AppColorPalette.blackMap);

      expect(prefs.getString(ColorPaletteRepository.key), 'blackMap');
      expect(repo.read(), AppColorPalette.blackMap);
    });

    test('알 수 없는 저장값은 classic으로 보정한다', () async {
      await prefs.setString(ColorPaletteRepository.key, 'bogus');
      final repo = ColorPaletteRepository(prefs);

      expect(repo.read(), AppColorPalette.classic);
    });

    test('제거된 brightCoast 저장값은 classic으로 보정한다', () async {
      await prefs.setString(ColorPaletteRepository.key, 'brightCoast');
      final repo = ColorPaletteRepository(prefs);

      expect(repo.read(), AppColorPalette.classic);
    });
  });
}
