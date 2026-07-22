// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 작은 재사용 헬퍼 위젯 모음:
// _profileNetworkAvatar, _profileTinyIconButton.
part of '../profile_tab_page.dart';

extension ProfileHelpersExt on ProfileTabPageState {
  Widget _profileNetworkAvatar({
    required String nickname,
    required String? photoUrl,
    double size = 42,
  }) {
    final palette = AppPaletteTheme.of(context);
    final initials = nickname.trim().isEmpty ? '?' : nickname.trim()[0];
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.currentFill, palette.currentAccent],
        ),
        border: Border.all(color: palette.currentAccentDeep, width: 1.2),
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl!.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _profileTinyIconButton({
    required String tooltip,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final palette = AppPaletteTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                palette.primary.withValues(alpha: 0.06),
                palette.cardSurface,
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: palette.subtleBorder, width: 1),
            ),
            child: Icon(icon, size: 17, color: palette.text),
          ),
        ),
      ),
    );
  }
}
