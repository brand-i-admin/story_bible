// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 중보기도(intercessory prayer) 카드 빌더 모음.
part of '../profile_tab_page.dart';

extension ProfileIntercessoryPrayerCardsExt on ProfileTabPageState {
  Widget _buildIntercessoryPrayerErrorCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x18A63F2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66A63F2D), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _intercessoryPrayerError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7E3426),
              fontSize: 13.0,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _profileMiniActionButton(
            label: '다시 불러오기',
            onTap: _loadIntercessoryPrayerPage,
          ),
        ],
      ),
    );
  }

  Widget _buildIntercessoryPrayerEmptyCard({required bool enabled}) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? _promptAddIntercessoryPrayer : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _profilePrayerEmptyAddButton(
                enabled: enabled,
                onTap: _promptAddIntercessoryPrayer,
              ),
              const SizedBox(height: 8),
              Text(
                enabled
                    ? '다른 사람의 기도제목을 공유 받아\n함께 기도해요'
                    : '로그인하면 다른 사람의 기도제목을\n함께 볼 수 있어요',
                textAlign: TextAlign.center,
                maxLines: largeText ? null : 2,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: largeText ? 11.0 : 12.1,
                  fontWeight: FontWeight.w800,
                  height: 1.24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profilePrayerEmptyAddButton({
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final palette = AppPaletteTheme.of(context);
    return ProfileGlowingAddButton(
      tooltip: '기도 연결 추가',
      onTap: enabled ? onTap : null,
      disabledBackgroundColor: palette.mutedSurface,
      disabledForegroundColor: palette.mutedText,
    );
  }

  Widget _buildIntercessoryPrayerItemCard(IntercessoryPrayerItem item) {
    final prayerText = (item.prayerRequest ?? '').trim().isEmpty
        ? '아직 등록된 기도제목이 없어요.'
        : item.prayerRequest!.trim();
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xC9F1E3CB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderCard, width: 1.0),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileNetworkAvatar(
            nickname: item.nickname,
            photoUrl: item.photoUrl,
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nickname,
                        maxLines: largeText ? 2 : 1,
                        overflow: largeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        softWrap: true,
                        style: const TextStyle(
                          color: Color(0xFF452F1A),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.shareId,
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.ink200,
                        fontSize: 10.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  prayerText,
                  maxLines: largeText ? null : 4,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.6,
                    height: 1.34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _profileTinyIconButton(
            tooltip: '삭제',
            onTap: () => _confirmDeleteIntercessoryPrayer(item),
            icon: Icons.delete_outline_rounded,
          ),
        ],
      ),
    );
  }

  Widget _intercessoryPrayerFab({required bool enabled}) {
    return Material(
      color: Colors.transparent,
      elevation: 10,
      shadowColor: const Color(0x33000000),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? _promptAddIntercessoryPrayer : null,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD99F4A), Color(0xFFB26B28)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD7CCB9), Color(0xFFB6A38A)],
                  ),
            border: Border.all(color: AppColors.goldHi, width: 1.1),
          ),
          child: const Icon(
            Icons.add_rounded,
            color: AppColors.parchmentCream,
            size: 21,
          ),
        ),
      ),
    );
  }
}
