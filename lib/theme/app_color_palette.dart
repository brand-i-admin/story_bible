import 'package:flutter/material.dart';

import 'tokens.dart';

enum AppColorPalette {
  classic(
    storageKey: 'classic',
    label: '클래식',
    description: '기존 양피지와 올리브 톤',
    seedColor: Color(0xFF5F7040),
    primary: Color(0xFF5F7040),
    primaryDeep: Color(0xFF526F3F),
    text: Color(0xFF33331F),
    mutedText: Color(0xFF70684B),
    actionTop: Color(0xFF7B9155),
    actionBottom: Color(0xFF526F3F),
    actionBorder: Color(0xFFDDE8BD),
    utilityBackground: Color(0xC222271D),
    utilitySelectedBackground: Color(0xEB526F3F),
    utilityBorder: Color(0xFFD7C8A6),
    selectedSurface: Color(0x225F7040),
    selectedBorder: Color(0xAA7B9155),
    verseBadge: Color(0xDD477D52),
    verseBadgeSelected: Color(0xF2526F3F),
    verseRail: Color(0x33477D52),
    completedSurface: Color(0xBFE7F0DB),
    completedBorder: Color(0xB08EAD72),
    successTop: Color(0xFF77A963),
    successBottom: Color(0xFF4E7E50),
    currentAccent: Color(0xFFE8A33D),
    currentAccentDeep: Color(0xFFA2702C),
    stepStart: Color(0xFF77A85A),
    stepSelect: Color(0xFFD2873E),
    stepStory: Color(0xFF7B5D43),
    timelineAccent: Color(0xFFD2873E),
    characterAccent: Color(0xFF5F7040),
    regionAccent: Color(0xFF7B5D43),
  ),
  atlasNavy(
    storageKey: 'atlasNavy',
    label: '지도 남색',
    description: '또렷한 남색과 부드러운 청록',
    seedColor: AppColors.seed,
    primary: AppColors.oceanBot,
    primaryDeep: AppColors.oceanDeep,
    text: AppColors.ink900,
    mutedText: AppColors.ink500,
    actionTop: Color(0xE0365F80),
    actionBottom: Color(0xC2153E67),
    actionBorder: Color(0xCCB8E7E4),
    utilityBackground: Color(0xD6073D5A),
    utilitySelectedBackground: Color(0xEF087986),
    utilityBorder: Color(0xD8B8E7E4),
    selectedSurface: Color(0x1F087986),
    selectedBorder: Color(0xA6087986),
    verseBadge: Color(0xD6153E67),
    verseBadgeSelected: Color(0xE60C315E),
    verseRail: Color(0x33153E67),
    completedSurface: Color(0xBFEAF7EC),
    completedBorder: Color(0x9A8DCA9C),
    successTop: Color(0xFF5DBB82),
    successBottom: Color(0xFF2C8A62),
    currentAccent: AppColors.gold,
    currentAccentDeep: AppColors.goldDeep,
    stepStart: AppColors.oceanBot,
    stepSelect: AppColors.gold,
    stepStory: AppColors.oceanDeep,
    timelineAccent: AppColors.goldDeep,
    characterAccent: AppColors.oceanBot,
    regionAccent: AppColors.oceanDeep,
  ),
  brightCoast(
    storageKey: 'brightCoast',
    label: '밝은 해안',
    description: '파스텔 초록, 주황, 노랑, 보라',
    seedColor: Color(0xFF7AAA6D),
    primary: Color(0xFF7AAA6D),
    primaryDeep: Color(0xFF4F7F5D),
    text: Color(0xFF34432E),
    mutedText: Color(0xFF747566),
    actionTop: Color(0xE88DBE7E),
    actionBottom: Color(0xD64F7F5D),
    actionBorder: Color(0xE6DDECC2),
    utilityBackground: Color(0xDA5C7051),
    utilitySelectedBackground: Color(0xEE7AAA6D),
    utilityBorder: Color(0xE8E9D99B),
    selectedSurface: Color(0x2A7AAA6D),
    selectedBorder: Color(0xB07AAA6D),
    verseBadge: Color(0xE04F7F5D),
    verseBadgeSelected: Color(0xF05B4A6D),
    verseRail: Color(0x334F7F5D),
    completedSurface: Color(0xBFEAF4DD),
    completedBorder: Color(0xA79CC987),
    successTop: Color(0xFF8DBE7E),
    successBottom: Color(0xFF4F8D60),
    currentAccent: Color(0xFFE9A85D),
    currentAccentDeep: Color(0xFFC97B37),
    stepStart: Color(0xFF7AAA6D),
    stepSelect: Color(0xFFE9A85D),
    stepStory: Color(0xFFA982B8),
    timelineAccent: Color(0xFFD6B94F),
    characterAccent: Color(0xFF7AAA6D),
    regionAccent: Color(0xFFA982B8),
  ),
  colorfulMap(
    storageKey: 'colorfulMap',
    label: '알록 지도',
    description: '청록, 오렌지, 핑크가 또렷한 조합',
    seedColor: Color(0xFF0B8F95),
    primary: Color(0xFF0B8F95),
    primaryDeep: Color(0xFF0C566E),
    text: Color(0xFF153A52),
    mutedText: Color(0xFF64706A),
    actionTop: Color(0xE80B8F95),
    actionBottom: Color(0xD60C566E),
    actionBorder: Color(0xD7C8E7E3),
    utilityBackground: Color(0xDA0C566E),
    utilitySelectedBackground: Color(0xF00B8F95),
    utilityBorder: Color(0xD7C8E7E3),
    selectedSurface: Color(0x220B8F95),
    selectedBorder: Color(0xAA0B8F95),
    verseBadge: Color(0xE00C566E),
    verseBadgeSelected: Color(0xF0153A52),
    verseRail: Color(0x330C566E),
    completedSurface: Color(0xBFEAF7EC),
    completedBorder: Color(0x958DCA9C),
    successTop: Color(0xFF5DBB82),
    successBottom: Color(0xFF2D8E63),
    currentAccent: Color(0xFFF5A623),
    currentAccentDeep: Color(0xFFE9822E),
    stepStart: Color(0xFF0B8F95),
    stepSelect: Color(0xFFE99B58),
    stepStory: Color(0xFFC0669C),
    timelineAccent: Color(0xFFF5A623),
    characterAccent: Color(0xFF2FA6A7),
    regionAccent: Color(0xFFC0669C),
  );

  const AppColorPalette({
    required this.storageKey,
    required this.label,
    required this.description,
    required this.seedColor,
    required this.primary,
    required this.primaryDeep,
    required this.text,
    required this.mutedText,
    required this.actionTop,
    required this.actionBottom,
    required this.actionBorder,
    required this.utilityBackground,
    required this.utilitySelectedBackground,
    required this.utilityBorder,
    required this.selectedSurface,
    required this.selectedBorder,
    required this.verseBadge,
    required this.verseBadgeSelected,
    required this.verseRail,
    required this.completedSurface,
    required this.completedBorder,
    required this.successTop,
    required this.successBottom,
    required this.currentAccent,
    required this.currentAccentDeep,
    required this.stepStart,
    required this.stepSelect,
    required this.stepStory,
    required this.timelineAccent,
    required this.characterAccent,
    required this.regionAccent,
  });

  final String storageKey;
  final String label;
  final String description;
  final Color seedColor;
  final Color primary;
  final Color primaryDeep;
  final Color text;
  final Color mutedText;
  final Color actionTop;
  final Color actionBottom;
  final Color actionBorder;
  final Color utilityBackground;
  final Color utilitySelectedBackground;
  final Color utilityBorder;
  final Color selectedSurface;
  final Color selectedBorder;
  final Color verseBadge;
  final Color verseBadgeSelected;
  final Color verseRail;
  final Color completedSurface;
  final Color completedBorder;
  final Color successTop;
  final Color successBottom;
  final Color currentAccent;
  final Color currentAccentDeep;
  final Color stepStart;
  final Color stepSelect;
  final Color stepStory;
  final Color timelineAccent;
  final Color characterAccent;
  final Color regionAccent;

  Color get pageTop => switch (this) {
    AppColorPalette.classic => const Color(0xFFF8F4E7),
    AppColorPalette.brightCoast => const Color(0xFFFFFCF0),
    _ => _tint(AppColors.parchmentLight, primary, 0.035),
  };

  Color get pageMiddle => switch (this) {
    AppColorPalette.classic => const Color(0xFFEDE7D6),
    AppColorPalette.brightCoast => const Color(0xFFF6F0DC),
    _ => _tint(AppColors.parchmentMid, primary, 0.055),
  };

  Color get pageBottom => switch (this) {
    AppColorPalette.classic => const Color(0xFFE6D9BF),
    AppColorPalette.brightCoast => const Color(0xFFEDE6CF),
    _ => _tint(AppColors.parchmentWarm, currentAccent, 0.05),
  };

  Color get panelSurface => switch (this) {
    AppColorPalette.classic => const Color(0xF5F3EBD9),
    AppColorPalette.brightCoast => const Color(0xF8F5F0DE),
    _ => _tint(AppColors.floatingSurfaceDefault, primary, 0.045),
  };

  Color get cardSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFF2EAD8),
    AppColorPalette.brightCoast => const Color(0xFFFFF8E8),
    _ => _tint(AppColors.parchmentCard, primary, 0.035),
  };

  Color get softSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFFCF8EC),
    AppColorPalette.brightCoast => const Color(0xFFF5F2E0),
    _ => _tint(AppColors.parchmentCream, primary, 0.06),
  };

  Color get mutedSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFEAE4D3),
    AppColorPalette.brightCoast => const Color(0xFFECE4C9),
    _ => _tint(AppColors.parchmentCream, mutedText, 0.045),
  };
  Color get panelBorder => selectedBorder.withValues(alpha: 0.68);
  Color get subtleBorder => selectedBorder.withValues(alpha: 0.42);
  Color get activeTextOnAccent => AppColors.fgOnDark;
  Color get selectionFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFE7F0DB),
    AppColorPalette.brightCoast => const Color(0xFFEAF3DE),
    _ => _tint(AppColors.parchmentCream, primary, 0.16),
  };

  Color get currentFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFE7D8A2),
    AppColorPalette.brightCoast => const Color(0xFFF7E7C8),
    _ => _tint(AppColors.parchmentCream, currentAccent, 0.18),
  };

  Color get successFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFD9E8C7),
    AppColorPalette.brightCoast => const Color(0xFFE1F0D8),
    _ => _tint(AppColors.parchmentCream, successBottom, 0.14),
  };

  Color get cardSelectedTop => switch (this) {
    AppColorPalette.brightCoast => primary,
    _ => actionTop,
  };

  Color get cardSelectedBottom => switch (this) {
    AppColorPalette.brightCoast => regionAccent,
    _ => actionBottom,
  };

  Color get cardUnselectedTop => switch (this) {
    AppColorPalette.brightCoast => const Color(0xFFFFFBEE),
    _ => cardSurface,
  };

  Color get cardUnselectedBottom => switch (this) {
    AppColorPalette.brightCoast => const Color(0xFFF1E9CF),
    _ => mutedSurface,
  };

  List<Color> get pageGradient => [pageTop, pageMiddle, pageBottom];

  static AppColorPalette fromStorage(String? raw) {
    for (final palette in values) {
      if (palette.storageKey == raw) {
        return palette;
      }
    }
    return AppColorPalette.classic;
  }
}

Color _tint(Color base, Color tint, double alpha) {
  return Color.alphaBlend(tint.withValues(alpha: alpha), base);
}

@immutable
class AppPaletteTheme extends ThemeExtension<AppPaletteTheme> {
  const AppPaletteTheme(this.palette);

  final AppColorPalette palette;

  static AppColorPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPaletteTheme>()?.palette ??
        AppColorPalette.classic;
  }

  @override
  AppPaletteTheme copyWith({AppColorPalette? palette}) {
    return AppPaletteTheme(palette ?? this.palette);
  }

  @override
  AppPaletteTheme lerp(ThemeExtension<AppPaletteTheme>? other, double t) {
    if (other is! AppPaletteTheme) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}
