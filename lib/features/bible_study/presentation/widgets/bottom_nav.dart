import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/game_ui_skin.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, this.onMapTap, this.height = 44});

  final VoidCallback? onMapTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: tabBarDecoration().copyWith(
        color: const Color(0xFF3A1E06),
        border: const Border(
          top: BorderSide(color: AppColors.woodDark, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _navItem(
              label: '지도',
              onTap: onMapTap,
              selected: false,
              icon: const Icon(
                Icons.map_rounded,
                size: 16,
                color: Color(0xFFFDF8EE),
              ),
              labelFontSize: 10.8,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: _navItem(
              label: '성경',
              selected: true,
              icon: Image.asset(kBookButtonAsset, fit: BoxFit.contain),
              labelFontSize: 10.8,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _iconOnlyItem(
              icon: Image.asset(kCalendarButtonAsset, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _iconOnlyItem(
              icon: Image.asset(kProfileButtonAsset, fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required String? label,
    required Widget icon,
    bool selected = false,
    VoidCallback? onTap,
    double labelFontSize = 9.2,
  }) {
    final hasLabel = label != null && label.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 34,
        child: DecoratedBox(
          decoration: tabItemDecoration(selected: selected),
          child: hasLabel
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: icon),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: GoogleFonts.notoSerifKr(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? const Color(0xFFFDF8EE)
                            : AppColors.goldDim,
                      ),
                    ),
                  ],
                )
              : Center(child: SizedBox(width: 18, height: 18, child: icon)),
        ),
      ),
    );
  }

  Widget _iconOnlyItem({required Widget icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Center(child: SizedBox(width: 22, height: 22, child: icon)),
    );
  }
}
