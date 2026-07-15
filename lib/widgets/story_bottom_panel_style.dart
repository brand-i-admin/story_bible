import 'package:flutter/material.dart';

import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';

const storyBottomPanelBorderRadius = BorderRadius.vertical(
  top: Radius.circular(26),
);

double storyBottomPanelHorizontalMargin(double viewportWidth) {
  return viewportWidth < 900 ? 0 : 18;
}

BoxDecoration storyBottomPanelDecoration(
  BuildContext context, {
  Color? accentColor,
  bool includeBottomBorder = false,
}) {
  final palette = AppPaletteTheme.of(context);
  final darkPanel = palette == AppColorPalette.blackMap;
  final borderColor = accentColor == null
      ? palette.panelBorder
      : darkPanel
      ? palette.utilityBorder.withValues(alpha: 0.44)
      : Color.lerp(AppColors.borderFloating, accentColor, 0.52)!;
  final borderSide = BorderSide(color: borderColor, width: 1.15);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [palette.softSurface, palette.panelSurface, palette.mutedSurface],
    ),
    borderRadius: storyBottomPanelBorderRadius,
    border: includeBottomBorder
        ? Border.fromBorderSide(borderSide)
        : Border(top: borderSide, left: borderSide, right: borderSide),
    boxShadow: const [
      BoxShadow(
        color: Color(0x38000000),
        blurRadius: 16,
        offset: Offset(0, -2),
      ),
    ],
  );
}
