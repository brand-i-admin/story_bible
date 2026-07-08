import 'package:flutter/material.dart';

import 'app_color_palette.dart';
import 'tokens.dart';

// 전역 ThemeData. app.dart에서 한 번만 호출.
class AppTheme {
  AppTheme._();

  static ThemeData light({AppColorPalette palette = AppColorPalette.classic}) {
    final darkPalette = palette == AppColorPalette.blackMap;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: palette.seedColor).copyWith(
        primary: palette.primary,
        onPrimary: AppColors.fgOnDark,
        primaryContainer: palette.selectedSurface,
        onPrimaryContainer: palette.text,
        secondary: palette.primaryDeep,
        tertiary: palette.currentAccent,
        onTertiary: AppColors.fgOnDark,
        outline: palette.selectedBorder,
        outlineVariant: palette.utilityBorder,
        surface: darkPalette ? palette.cardSurface : AppColors.parchmentLight,
        onSurface: palette.text,
        onSurfaceVariant: palette.mutedText,
      ),
      scaffoldBackgroundColor: darkPalette
          ? palette.pageMiddle
          : AppColors.parchmentBg,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.pageMiddle,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: palette.primaryDeep),
        actionsIconTheme: IconThemeData(color: palette.primaryDeep),
        titleTextStyle: TextStyle(
          color: palette.text,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.subtleBorder, thickness: 1),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: palette.text, fontWeight: FontWeight.w800),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: palette.primaryDeep),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.selectionFill,
        circularTrackColor: palette.selectionFill,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      extensions: [AppPaletteTheme(palette)],
    );
  }
}
