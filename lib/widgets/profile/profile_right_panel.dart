
// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 우측 패널 (인물 진행도 + 구약/신약 토글 + 공유 ID).
part of '../profile_tab_page.dart';

extension ProfileRightPanelExt on ProfileTabPageState {
  Widget _buildProfileRightPanel({
    required List<Person> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader = constraints.maxWidth < 400;
        final headerStats = Row(
          children: [
            Expanded(
              child: _profileTopStatCard(
                title: '연속 출석일',
                value: '$_profileAttendanceStreak일',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _profileTopStatCard(
                title: '연속 인물 공부',
                value: '$_profileStudyStreak일',
              ),
            ),
          ],
        );

        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: floatingPanelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stackHeader) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _profileTestamentToggle(
                      selectedTestament: selectedTestament,
                      onSelectTestament: onSelectTestament,
                    ),
                  ),
                  const SizedBox(height: 8),
                  headerStats,
                ] else
                  Row(
                    children: [
                      _profileTestamentToggle(
                        selectedTestament: selectedTestament,
                        onSelectTestament: onSelectTestament,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: headerStats),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: people.isEmpty
                      ? Center(
                          child: Text(
                            selectedTestament == 'new'
                                ? '신약 인물 데이터가 없습니다.'
                                : '구약 인물 데이터가 없습니다.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6D5231),
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                              fontSize: 13.2,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: (people.length / 5).ceil(),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, rowIndex) {
                            final start = rowIndex * 5;
                            final end = math.min(start + 5, people.length);
                            final rowPeople = people.sublist(start, end);
                            return _profilePersonProgressRow(
                              rowPeople: rowPeople,
                              completedEventIds: completedEventIds,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profileTestamentToggle({
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: floatingPanelDecoration(
        color: const Color(0xFFF7E9D2),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: softButtonDecoration(selected: false),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.ink500,
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
    final visibleId = shareId.trim().isEmpty ? '-------' : shareId.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xDDF7E9D2) : const Color(0x9BEEDFC4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                visibleId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF6C4C28)
                      : const Color(0xAA6C4C28),
                  fontSize: 9.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.copy_rounded,
                  size: 10,
                  color: Color(0xFF7A552C),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
