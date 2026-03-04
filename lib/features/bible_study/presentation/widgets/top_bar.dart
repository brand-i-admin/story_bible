import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/game_ui_skin.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, this.height = 46, this.onListMenuTap});
  final double height;
  final VoidCallback? onListMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: tabBarDecoration().copyWith(
        color: const Color(0xFF3A1E06),
        border: const Border(
          bottom: BorderSide(color: AppColors.woodDark, width: 2.5),
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: _TitleBadge(height: height),
          ),
          if (onListMenuTap != null)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(child: _ListMenuButton(onTap: onListMenuTap!)),
            ),
        ],
      ),
    );
  }
}

class _TitleBadge extends StatelessWidget {
  const _TitleBadge({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final badgeHeight = (height * 0.70).clamp(28.0, 36.0).toDouble();
    return SizedBox(
      width: 170,
      height: badgeHeight,
      child: DecoratedBox(
        decoration: headerBadgeDecoration(),
        child: Center(
          child: Text(
            '강해 / 성경',
            style: GoogleFonts.nanumMyeongjo(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF3E240E),
              shadows: const [
                Shadow(
                  color: Color(0x55FFFFFF),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListMenuButton extends StatelessWidget {
  const _ListMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xAA2B1508),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.goldDim.withValues(alpha: 0.65)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [_MenuLine(), _MenuLine(), _MenuLine()],
        ),
      ),
    );
  }
}

class _MenuLine extends StatelessWidget {
  const _MenuLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.7,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3DEB2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
