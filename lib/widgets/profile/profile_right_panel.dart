// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필에서 공유되는 헬퍼 (구약/신약 토글, 공유 ID 칩, mini action button).
// "진행률 표시" 섹션 도입 후 우측 패널 자체는 사라졌지만, 헬퍼들은 다른
// part 파일에서 재사용된다.
part of '../profile_tab_page.dart';

extension ProfileRightPanelExt on ProfileTabPageState {
  Widget _profileTestamentToggle({
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Container(
      constraints: BoxConstraints(minHeight: largeText ? 58 : 50),
      padding: const EdgeInsets.all(4),
      decoration: floatingPanelDecoration(
        color: palette.panelSurface,
        shadowOpacity: 0.08,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _profileTestamentToggleButton(
            label: '구약',
            selected: selectedTestament != 'new',
            onTap: () => onSelectTestament('old'),
          ),
          const SizedBox(width: 4),
          _profileTestamentToggleButton(
            label: '신약',
            selected: selectedTestament == 'new',
            onTap: () => onSelectTestament('new'),
          ),
        ],
      ),
    );
  }

  Widget _profileMiniActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(minHeight: largeText ? 58 : 48),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: largeText ? 8 : 0,
          ),
          decoration: BoxDecoration(
            color: palette.cardSurface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 15.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileShareIdChip({
    required String shareId,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final palette = AppPaletteTheme.of(context);
    final visibleId = shareId.trim().isEmpty ? '-------' : shareId.trim();
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: enabled ? palette.cardSurface : palette.mutedSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                visibleId,
                maxLines: largeText ? 2 : 1,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  color: enabled
                      ? palette.primary
                      : palette.mutedText.withValues(alpha: 0.72),
                  fontSize: 9.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 2),
                Icon(Icons.copy_rounded, size: 10, color: palette.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
