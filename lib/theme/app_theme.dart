import 'package:flutter/material.dart';

import 'tokens.dart';

// 전역 ThemeData. app.dart에서 한 번만 호출.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
      scaffoldBackgroundColor: AppColors.parchmentBg,
    );
  }
}
