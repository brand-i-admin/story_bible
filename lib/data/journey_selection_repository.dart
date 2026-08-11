import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journey_selection.dart';

/// 사용자가 고른 홈 여정을 기기 로컬에 영속화한다.
class JourneySelectionRepository {
  JourneySelectionRepository(this._preferences);

  final SharedPreferences _preferences;

  static const String key = 'home_journey_selection_v1';

  JourneySelection read() {
    final raw = _preferences.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return const JourneySelection.all();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const JourneySelection.all();
      }
      return JourneySelection.fromMap(decoded);
    } catch (_) {
      return const JourneySelection.all();
    }
  }

  Future<void> write(JourneySelection selection) {
    return _preferences.setString(key, jsonEncode(selection.toMap()));
  }
}
