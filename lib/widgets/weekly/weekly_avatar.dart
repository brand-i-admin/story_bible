// 부모 라이브러리: lib/widgets/weekly_tab_page.dart
//
// 주간 페이지 인물 아바타 빌더.
part of '../weekly_tab_page.dart';

extension _WeeklyAvatarExt on _WeeklyTabPageState {
  Widget _weeklyCharacterAvatar({
    required Character character,
    double size = 32,
  }) {
    final avatarPath = character.avatarAssetPath.trim();
    final fallbackText = character.name.trim().isEmpty
        ? '?'
        : character.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF3E7CC), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _weeklyAvatarFallback(fallbackText, fontSize: fallbackFontSize)
            : ColoredBox(
                color: Colors.white,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size,
                    height: size * 2,
                    child: Image.asset(
                      avatarPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => _weeklyAvatarFallback(
                        fallbackText,
                        fontSize: fallbackFontSize,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _weeklyAvatarFallback(String text, {double fontSize = 11}) {
    return Container(
      color: const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFFF3EAD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
