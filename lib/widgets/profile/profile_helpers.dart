// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 작은 재사용 헬퍼 위젯 모음:
// _profileNetworkAvatar, _profileTinyIconButton, _profileTestamentToggleButton,
// _profileCharacterProgressRow.
part of '../profile_tab_page.dart';

extension ProfileHelpersExt on ProfileTabPageState {
  Widget _profileNetworkAvatar({
    required String nickname,
    required String? photoUrl,
    double size = 42,
  }) {
    final initials = nickname.trim().isEmpty ? '?' : nickname.trim()[0];
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFD79B), Color(0xFFC88A3D)],
        ),
        border: Border.all(color: const Color(0xFF8C6743), width: 1.2),
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl!.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: AppColors.ink500,
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
                    color: AppColors.ink500,
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
              color: const Color(0xCCF7E9D2),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xAA8E6F48), width: 1),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF7A552C)),
          ),
        ),
      ),
    );
  }

  Widget _profileTestamentToggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: double.infinity,
          alignment: Alignment.center,
          decoration: softButtonDecoration(selected: selected),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? AppColors.parchmentCream : AppColors.ink500,
              fontSize: 13.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileCharacterProgressRow({
    required List<Character> rowPeople,
    required Set<String> completedEventIds,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x88F5E8CF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
      ),
      child: Row(
        children: List.generate(rowPeople.length, (index) {
          final character = rowPeople[index];
          final progressData =
              _profileStudyProgressByCharacterCode[character.code];
          final progress = progressData?.fraction ?? 0.0;
          return Expanded(
            // 좌우 균등 패딩 — 마지막 셀만 right:0 으로 두면 그 셀의 inner 폭이
            // 더 넓어져 ringSize 가 커지는 문제 발생. 모든 셀을 동일 폭으로.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openProfileCharacterOverview(
                    character: character,
                    completedEventIds: completedEventIds,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final compact = width < 62;
                        final stacked = width < 108;

                        // 이름은 ring 안쪽 하단에 오버레이로 표시 → 외부 텍스트
                        // 라인 제거하고 그만큼 아바타 키움. 셀 폭에 맞춰 ring 사이즈
                        // 동적 결정 (clamp 으로 너무 좁은 폭에서도 overflow 방지).
                        final ringSize = math.min(
                          width - 4,
                          compact ? 52.0 : (stacked ? 62.0 : 72.0),
                        );

                        return Center(
                          child: AvatarProgressRing(
                            character: character,
                            size: ringSize,
                            progress: progress,
                            name: character.name,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
