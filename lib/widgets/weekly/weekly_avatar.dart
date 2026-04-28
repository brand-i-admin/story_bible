// 부모 라이브러리: lib/widgets/weekly_tab_page.dart
//
// 주간 페이지 인물 아바타 빌더.
part of '../weekly_tab_page.dart';

extension _WeeklyAvatarExt on _WeeklyTabPageState {
  Widget _weeklyCharacterAvatar({
    required Character character,
    double size = 32,
  }) {
    // 하이브리드: 로컬 번들 → Storage → 이니셜 fallback. CharacterAvatar 와
    // 동일한 정책이지만 주간 탭 전용 외곽선/그림자 톤(F3E7CC)을 유지하기
    // 위해 별도 빌더로 둔다.
    final hasLocal = character.hasLocalAvatar;
    final avatarPath = hasLocal ? character.avatarAssetPath.trim() : '';
    final storagePath = character.avatarStoragePath?.trim();
    final fallbackText = character.name.trim().isEmpty
        ? '?'
        : character.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();

    String? storageUrl;
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        final client = ref.read(supabaseClientProvider);
        final slash = storagePath.indexOf('/');
        if (slash < 0) {
          storageUrl = client.storage
              .from('characters')
              .getPublicUrl(storagePath);
        } else {
          storageUrl = client.storage
              .from(storagePath.substring(0, slash))
              .getPublicUrl(storagePath.substring(slash + 1));
        }
      } catch (_) {
        storageUrl = null;
      }
    }

    final fallback = _weeklyAvatarFallback(
      fallbackText,
      fontSize: fallbackFontSize,
    );

    Widget child;
    if (avatarPath.isNotEmpty) {
      // canonical thumb (인물 머리 상단 1/3) → topCenter 자르기
      child = ColoredBox(
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
              errorBuilder: (_, _, _) {
                if (storageUrl == null) return fallback;
                return _weeklyStorageImage(storageUrl, fallback);
              },
            ),
          ),
        ),
      );
    } else if (storageUrl != null) {
      // 로컬 번들 미흡수 (제안 단계 또는 승인 직후) → storage 원본은 정사각 cover.
      child = _weeklyStorageImage(storageUrl, fallback);
    } else {
      child = fallback;
    }

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
      child: ClipOval(child: child),
    );
  }

  Widget _weeklyStorageImage(String url, Widget fallback) {
    // Imagen 1024×1024 정중앙 인물 → 상반신 위주로 보이도록 topCenter 1.5× 확대.
    // 부모 ClipOval 이 외곽 클립.
    return ColoredBox(
      color: Colors.white,
      child: Transform.scale(
        scale: 1.5,
        alignment: Alignment.topCenter,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, w, p) =>
              p == null ? w : const ColoredBox(color: Color(0xFFE7D2B2)),
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
