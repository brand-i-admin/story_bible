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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryCompact = constraints.maxHeight < 150;
        final isCompact = constraints.maxHeight < 180;
        final buttonSize = isVeryCompact ? 32.0 : (isCompact ? 38.0 : 44.0);
        final iconSize = isVeryCompact ? 20.0 : (isCompact ? 24.0 : 26.0);
        final spacing = isVeryCompact ? 4.0 : (isCompact ? 6.0 : 8.0);
        final fontSize = isVeryCompact ? 10.4 : (isCompact ? 11.2 : 12.3);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? _promptAddIntercessoryPrayer : null,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: enabled
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFD99F4A),
                                    Color(0xFFB26B28),
                                  ],
                                )
                              : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFD7CCB9),
                                    Color(0xFFB6A38A),
                                  ],
                                ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 7,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: AppColors.parchmentCream,
                          size: iconSize,
                        ),
                      ),
                      SizedBox(height: spacing),
                      Text(
                        enabled
                            ? '다른 사람의 기도제목을 공유 받아\n함께 기도해요'
                            : '로그인하면 다른 사람의 기도제목을\n함께 볼 수 있어요',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF5A4326),
                          fontSize: fontSize,
                          fontWeight: FontWeight.w800,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntercessoryPrayerItemCard(IntercessoryPrayerItem item) {
    final prayerText = (item.prayerRequest ?? '').trim().isEmpty
        ? '아직 등록된 기도제목이 없어요.'
        : item.prayerRequest!.trim();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xC9F1E3CB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
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
