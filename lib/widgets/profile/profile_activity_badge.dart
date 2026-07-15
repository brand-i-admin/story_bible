import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';

enum ProfileActivityBadgeType { emotion, companionDiary, bibleReading }

class ProfileActivityBadge extends StatelessWidget {
  const ProfileActivityBadge({
    super.key,
    required this.type,
    this.size = 28,
    this.iconSize = 16,
  });

  final ProfileActivityBadgeType type;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final (icon, accent) = switch (type) {
      ProfileActivityBadgeType.emotion => (
        Icons.sentiment_satisfied_alt_rounded,
        palette.currentAccentDeep,
      ),
      ProfileActivityBadgeType.companionDiary => (
        Icons.edit_note_rounded,
        palette.successBottom,
      ),
      ProfileActivityBadgeType.bibleReading => (
        Icons.menu_book_rounded,
        palette.primaryDeep,
      ),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.12),
          palette.cardSurface,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.58), width: 1),
      ),
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}
