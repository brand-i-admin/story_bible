import 'package:shared_preferences/shared_preferences.dart';

import '../state/font_scale_providers.dart';

/// 글자 크기 설정을 SharedPreferences에 영속화한다.
class FontScaleRepository {
  FontScaleRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'font_scale';

  FontScale read() => FontScale.fromStorage(_prefs.getString(_key));

  Future<void> write(FontScale scale) =>
      _prefs.setString(_key, scale.storageKey);
}
