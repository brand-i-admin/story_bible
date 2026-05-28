import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/font_scale_repository.dart';

/// 앱 전역 글자 크기 배율.
///
/// `MediaQuery.textScaler`에 주입되어 모든 `Text` 위젯에 자동 적용된다.
/// SharedPreferences에는 [storageKey] 문자열로 저장한다.
enum FontScale {
  normal(1.0, '보통'),
  large(1.2, '크게'),
  veryLarge(1.4, '아주크게');

  const FontScale(this.ratio, this.label);

  final double ratio;
  final String label;

  String get storageKey => name;

  static FontScale fromStorage(String? raw) => switch (raw) {
    'large' => FontScale.large,
    'veryLarge' => FontScale.veryLarge,
    _ => FontScale.normal,
  };
}

/// `main.dart`에서 `overrideWithValue`로 실제 인스턴스를 주입한다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart',
  ),
);

final fontScaleRepositoryProvider = Provider<FontScaleRepository>(
  (ref) => FontScaleRepository(ref.watch(sharedPreferencesProvider)),
);

final fontScaleProvider = NotifierProvider<FontScaleNotifier, FontScale>(
  FontScaleNotifier.new,
);

class FontScaleNotifier extends Notifier<FontScale> {
  @override
  FontScale build() => ref.read(fontScaleRepositoryProvider).read();

  Future<void> set(FontScale scale) async {
    if (state == scale) {
      return;
    }
    state = scale;
    await ref.read(fontScaleRepositoryProvider).write(scale);
  }
}
