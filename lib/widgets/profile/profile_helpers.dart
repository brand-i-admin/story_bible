// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 작은 재사용 헬퍼 위젯 모음:
// _profileNetworkAvatar, _profileTinyIconButton, _profileTestamentToggleButton,
// _profileTopStatCard, _profileCharacterProgressRow.
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

  Widget _profileTopStatCard({required String title, required String value}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: floatingPanelDecoration(
        color: const Color(0xFFF7E9D2),
        shadowOpacity: 0.08,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6A4C2E),
              fontWeight: FontWeight.w800,
              fontSize: 13.2,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB06B25),
              fontWeight: FontWeight.w900,
              fontSize: 16.8,
            ),
          ),
        ],
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
            child: Padding(
              padding: EdgeInsets.only(
                right: index == rowPeople.length - 1 ? 0 : 6,
              ),
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

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stacked)
                              Column(
                                children: [
                                  CharacterAvatar(
                                    character: character,
                                    size: compact ? 24 : 26,
                                  ),
                                  SizedBox(height: compact ? 4 : 5),
                                  Text(
                                    character.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.ink500,
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 10.2 : 11.8,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  CharacterAvatar(
                                    character: character,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      character.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.ink500,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: compact ? 7 : 8,
                                value: progress,
                                backgroundColor: const Color(0x664E3A26),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFC6922D),
                                ),
                              ),
                            ),
                          ],
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
