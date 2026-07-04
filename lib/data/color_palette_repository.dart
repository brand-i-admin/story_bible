import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_color_palette.dart';

/// 앱 색 조합 설정을 SharedPreferences에 영속화한다.
class ColorPaletteRepository {
  ColorPaletteRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String key = 'color_palette';

  AppColorPalette read() => AppColorPalette.fromStorage(_prefs.getString(key));

  Future<void> write(AppColorPalette palette) =>
      _prefs.setString(key, palette.storageKey);
}
