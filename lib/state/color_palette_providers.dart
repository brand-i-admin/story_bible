import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/color_palette_repository.dart';
import '../theme/app_color_palette.dart';
import 'font_scale_providers.dart';

final colorPaletteRepositoryProvider = Provider<ColorPaletteRepository>(
  (ref) => ColorPaletteRepository(ref.watch(sharedPreferencesProvider)),
);

final colorPaletteProvider =
    NotifierProvider<ColorPaletteNotifier, AppColorPalette>(
      ColorPaletteNotifier.new,
    );

class ColorPaletteNotifier extends Notifier<AppColorPalette> {
  @override
  AppColorPalette build() => ref.read(colorPaletteRepositoryProvider).read();

  Future<void> set(AppColorPalette palette) async {
    if (state == palette) {
      return;
    }
    state = palette;
    await ref.read(colorPaletteRepositoryProvider).write(palette);
  }
}
