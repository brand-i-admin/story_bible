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
    label: '네이비',
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
    currentAccent: AppColors.ink500,
    currentAccentDeep: AppColors.ink800,
    stepStart: AppColors.oceanBot,
    stepSelect: AppColors.ink500,
    stepStory: AppColors.oceanDeep,
    timelineAccent: AppColors.ink600,
    characterAccent: AppColors.oceanBot,
    regionAccent: AppColors.oceanDeep,
  ),
  colorfulMap(
    storageKey: 'colorfulMap',
    label: '파스텔',
    description: '파스텔 보라, 청록, 오렌지, 핑크 조합',
    seedColor: Color(0xFFAA96F2),
    primary: Color(0xFFAA96F2),
    primaryDeep: Color(0xFF7359B8),
    text: Color(0xFF14324A),
    mutedText: Color(0xFF596E70),
    actionTop: Color(0xEAC9BCFF),
    actionBottom: Color(0xDD7359B8),
    actionBorder: Color(0xD8E4D8FF),
    utilityBackground: Color(0xDA5E4A9A),
    utilitySelectedBackground: Color(0xF07359B8),
    utilityBorder: Color(0xD8E4D8FF),
    selectedSurface: Color(0x2AAA96F2),
    selectedBorder: Color(0xB07359B8),
    verseBadge: Color(0xE07359B8),
    verseBadgeSelected: Color(0xF014324A),
    verseRail: Color(0x337359B8),
    completedSurface: Color(0xBFEAF7EC),
    completedBorder: Color(0x958DCA9C),
    successTop: Color(0xFF5DBB82),
    successBottom: Color(0xFF2D8E63),
    currentAccent: Color(0xFFFFB13B),
    currentAccentDeep: Color(0xFFE77E20),
    stepStart: Color(0xFF13A7B1),
    stepSelect: Color(0xFFE77E20),
    stepStory: Color(0xFFD65AA0),
    timelineAccent: Color(0xFFFFB13B),
    characterAccent: Color(0xFF13A7B1),
    regionAccent: Color(0xFFD65AA0),
  ),
  blackMap(
    storageKey: 'blackMap',
    label: '다크',
    description: '검은 지도 톤과 금빛 포인트',
    seedColor: Color(0xFF111827),
    primary: Color(0xFF38BDF8),
    primaryDeep: Color(0xFF7DD3FC),
    text: Color(0xFFEAF2F7),
    mutedText: Color(0xFFC2CAD8),
    actionTop: Color(0xF235445E),
    actionBottom: Color(0xF2111828),
    actionBorder: Color(0xB8F59E0B),
    utilityBackground: Color(0xE6050710),
    utilitySelectedBackground: Color(0xF21F2937),
    utilityBorder: Color(0xAA8492A6),
    selectedSurface: Color(0x5538BDF8),
    selectedBorder: Color(0xCC38BDF8),
    verseBadge: Color(0xE2111828),
    verseBadgeSelected: Color(0xF2F59E0B),
    verseRail: Color(0x5538BDF8),
    completedSurface: Color(0xB8142F27),
    completedBorder: Color(0xAA34D399),
    successTop: Color(0xFF34D399),
    successBottom: Color(0xFF14B8A6),
    currentAccent: Color(0xFFF59E0B),
    currentAccentDeep: Color(0xFFD97706),
    stepStart: Color(0xFF38BDF8),
    stepSelect: Color(0xFFF59E0B),
    stepStory: Color(0xFFA78BFA),
    timelineAccent: Color(0xFFF59E0B),
    characterAccent: Color(0xFF38BDF8),
    regionAccent: Color(0xFFA78BFA),
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
    AppColorPalette.colorfulMap => const Color(0xFFFFF6E7),
    AppColorPalette.blackMap => const Color(0xFF111827),
    _ => _tint(AppColors.parchmentLight, primary, 0.035),
  };

  Color get pageMiddle => switch (this) {
    AppColorPalette.classic => const Color(0xFFEDE7D6),
    AppColorPalette.colorfulMap => const Color(0xFFEAF9F6),
    AppColorPalette.blackMap => const Color(0xFF0B1120),
    _ => _tint(AppColors.parchmentMid, primary, 0.055),
  };

  Color get pageBottom => switch (this) {
    AppColorPalette.classic => const Color(0xFFE6D9BF),
    AppColorPalette.colorfulMap => const Color(0xFFF9E8F1),
    AppColorPalette.blackMap => const Color(0xFF05070B),
    _ => _tint(AppColors.parchmentWarm, currentAccent, 0.05),
  };

  Color get panelSurface => switch (this) {
    AppColorPalette.classic => const Color(0xF5F3EBD9),
    AppColorPalette.colorfulMap => const Color(0xF8F2FCF7),
    AppColorPalette.blackMap => const Color(0xFF141C2F),
    _ => _tint(AppColors.floatingSurfaceDefault, primary, 0.045),
  };

  Color get cardSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFF2EAD8),
    AppColorPalette.colorfulMap => const Color(0xFFFFF7E8),
    AppColorPalette.blackMap => const Color(0xFF1A253A),
    _ => _tint(AppColors.parchmentCard, primary, 0.035),
  };

  Color get softSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFFCF8EC),
    AppColorPalette.colorfulMap => const Color(0xFFFFEEF7),
    AppColorPalette.blackMap => const Color(0xFF243149),
    _ => _tint(AppColors.parchmentCream, primary, 0.06),
  };

  Color get mutedSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFEAE4D3),
    AppColorPalette.colorfulMap => const Color(0xFFE2F5F2),
    AppColorPalette.blackMap => const Color(0xFF111A2E),
    _ => _tint(AppColors.parchmentCream, mutedText, 0.045),
  };
  Color get disabledSurface => switch (this) {
    AppColorPalette.classic => const Color(0xFFE1DED6),
    AppColorPalette.colorfulMap => const Color(0xFFE7E7EA),
    AppColorPalette.blackMap => const Color(0xFF171B24),
    _ => _tint(AppColors.parchmentMid, mutedText, 0.09),
  };
  Color get disabledText => switch (this) {
    AppColorPalette.blackMap => const Color(0xFF7D8795),
    _ => const Color(0xFF80838A),
  };
  Color get disabledBorder => disabledText.withValues(alpha: 0.42);
  Color get panelBorder => selectedBorder.withValues(alpha: 0.68);
  Color get subtleBorder => selectedBorder.withValues(alpha: 0.42);
  Color get activeTextOnAccent => AppColors.fgOnDark;
  Color get selectionFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFE7F0DB),
    AppColorPalette.colorfulMap => const Color(0xFFDDF5F1),
    AppColorPalette.blackMap => const Color(0xFF2A3850),
    _ => _tint(AppColors.parchmentCream, primary, 0.16),
  };

  Color get currentFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFE7D8A2),
    AppColorPalette.colorfulMap => const Color(0xFFFFE3BD),
    AppColorPalette.blackMap => const Color(0xFF36281A),
    _ => _tint(AppColors.parchmentCream, currentAccent, 0.18),
  };

  Color get successFill => switch (this) {
    AppColorPalette.classic => const Color(0xFFD9E8C7),
    AppColorPalette.colorfulMap => const Color(0xFFE8F6DD),
    AppColorPalette.blackMap => const Color(0xFF153127),
    _ => _tint(AppColors.parchmentCream, successBottom, 0.14),
  };

  Color get cardSelectedTop => switch (this) {
    AppColorPalette.colorfulMap => primary,
    AppColorPalette.blackMap => const Color(0xFF2D3C56),
    _ => actionTop,
  };

  Color get cardSelectedBottom => switch (this) {
    AppColorPalette.colorfulMap => primaryDeep,
    AppColorPalette.blackMap => const Color(0xFF10182A),
    _ => actionBottom,
  };

  Color get cardUnselectedTop => switch (this) {
    AppColorPalette.colorfulMap => const Color(0xFFFFFBEE),
    AppColorPalette.blackMap => const Color(0xFF1A253A),
    _ => cardSurface,
  };

  Color get cardUnselectedBottom => switch (this) {
    AppColorPalette.colorfulMap => const Color(0xFFEAF7F4),
    AppColorPalette.blackMap => const Color(0xFF111A2E),
    _ => mutedSurface,
  };

  List<Color> get pageGradient => [pageTop, pageMiddle, pageBottom];

  static AppColorPalette fromStorage(String? raw) {
    for (final palette in values) {
      if (palette.storageKey == raw) {
        return palette;
      }
    }
    return AppColorPalette.atlasNavy;
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
