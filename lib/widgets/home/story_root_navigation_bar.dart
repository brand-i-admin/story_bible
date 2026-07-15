import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';

enum StoryRootTab { today, bible, map, profile }

Color storyRootNavigationSurfaceColor(AppColorPalette palette) {
  return Color.alphaBlend(palette.panelSurface, palette.pageBottom);
}

class StoryRootNavigationBar extends StatelessWidget {
  const StoryRootNavigationBar({
    super.key,
    required this.selectedTab,
    required this.onSelect,
  });

  final StoryRootTab selectedTab;
  final ValueChanged<StoryRootTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final surfaceColor = storyRootNavigationSurfaceColor(palette);
    return Container(
      key: const ValueKey('root-navigation-surface'),
      decoration: BoxDecoration(color: surfaceColor),
      child: SafeArea(
        top: false,
        child: Container(
          key: const ValueKey('root-navigation-content'),
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: surfaceColor),
          child: Row(
            children: [
              _RootNavigationItem(
                tab: StoryRootTab.today,
                label: '오늘',
                icon: Icons.home_rounded,
                selected: selectedTab == StoryRootTab.today,
                onTap: onSelect,
              ),
              _RootNavigationItem(
                tab: StoryRootTab.bible,
                label: '성경',
                icon: Icons.menu_book_rounded,
                selected: selectedTab == StoryRootTab.bible,
                onTap: onSelect,
              ),
              _RootNavigationItem(
                tab: StoryRootTab.map,
                label: '지도',
                icon: Icons.map_rounded,
                selected: selectedTab == StoryRootTab.map,
                onTap: onSelect,
              ),
              _RootNavigationItem(
                tab: StoryRootTab.profile,
                label: '내정보',
                icon: Icons.person_rounded,
                selected: selectedTab == StoryRootTab.profile,
                onTap: onSelect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootNavigationItem extends StatelessWidget {
  const _RootNavigationItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final StoryRootTab tab;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<StoryRootTab> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final foreground = selected ? palette.currentAccentDeep : palette.mutedText;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(tab),
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  key: selected
                      ? ValueKey('root-navigation-${tab.name}-selected')
                      : null,
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.currentFill.withValues(alpha: 0.82)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: foreground, size: 22),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11.4,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
