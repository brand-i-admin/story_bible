// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// "진행률 표시" 섹션 — 좌측 상단 제목 + 세 탭 (내 삶의 지도 / 장소로 시작 / 인물과 걷기) +
// 그 아래 스크롤 가능한 컨텐츠. 탭 바는 섹션 최상단에 고정(pinned), 컨텐츠만
// 스크롤되도록 Column[Header, Expanded(SingleChildScrollView)] 구조.
part of '../profile_tab_page.dart';

extension ProfileProgressSectionExt on ProfileTabPageState {
  Widget _buildProfileProgressSection({
    required List<Character> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: floatingPanelDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 탭 바를 섹션 최상단에 pinned. 제목은 제거 — 탭 라벨이 자체 설명.
            _profileProgressTabBar(),
            const SizedBox(height: 10),
            // ── 컨텐츠 (이 영역만 스크롤)
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: switch (_profileProgressTab) {
                  _ProfileProgressTab.life => _profileProgressLifeBody(),
                  _ProfileProgressTab.walk => _profileProgressWalkBody(
                    people: people,
                    completedEventIds: completedEventIds,
                    selectedTestament: selectedTestament,
                    onSelectTestament: onSelectTestament,
                  ),
                  _ProfileProgressTab.place => _profileProgressPlaceBody(
                    completedEventIds: completedEventIds,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 세 탭 토글 — "내 삶의 지도" / "장소로 시작" / "인물과 걷기".
  Widget _profileProgressTabBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E1C0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xAA8E6F48), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _progressTabButton(
              label: '내 삶의 지도',
              selected: _profileProgressTab == _ProfileProgressTab.life,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.life);
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _progressTabButton(
              label: '장소로 시작',
              selected: _profileProgressTab == _ProfileProgressTab.place,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.place);
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _progressTabButton(
              label: '인물과 걷기',
              selected: _profileProgressTab == _ProfileProgressTab.walk,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.walk);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brownWarm : const Color(0x00000000),
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF6A4C2E),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────── 내 삶의 지도 탭 본문 ────────────────────────
  Widget _profileProgressLifeBody() {
    final state = ref.watch(storyControllerProvider);
    return ProfileLifeMap(
      eventEmotionMarks: state.eventEmotionMarks,
      quizAttemptSummaries: state.quizAttemptSummaries,
      onOpenEventDetail: widget.onOpenEventDetail,
    );
  }

  // ──────────────────────── 인물과 걷기 탭 본문 ────────────────────────
  Widget _profileProgressWalkBody({
    required List<Character> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    final filtered = people;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _profileTestamentToggle(
            selectedTestament: selectedTestament,
            onSelectTestament: onSelectTestament,
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
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
            ),
          )
        else
          // 5명씩 한 줄, 여러 줄로 쌓기. ListView 가 아닌 Column 사용 →
          // 부모 SingleChildScrollView 가 스크롤을 담당하므로 내부는 정적.
          for (
            var rowIndex = 0;
            rowIndex < (filtered.length / 5).ceil();
            rowIndex++
          ) ...[
            if (rowIndex > 0) const SizedBox(height: 8),
            _profileCharacterProgressRow(
              rowPeople: filtered.sublist(
                rowIndex * 5,
                math.min(rowIndex * 5 + 5, filtered.length),
              ),
              completedEventIds: completedEventIds,
            ),
          ],
      ],
    );
  }

  // ──────────────────────── 장소로 시작 탭 본문 ────────────────────────
  Widget _profileProgressPlaceBody({required Set<String> completedEventIds}) {
    final state = ref.watch(storyControllerProvider);
    final selectedEra = state.eras
        .where((e) => e.id == _profileProgressSelectedEraId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EraPickRows(
          eras: state.eras,
          selectedEraId: _profileProgressSelectedEraId,
          onSelectEra: (eraId) {
            // ignore: invalid_use_of_protected_member
            setState(() {
              _profileProgressSelectedEraId =
                  _profileProgressSelectedEraId == eraId ? null : eraId;
            });
          },
        ),
        const SizedBox(height: 12),
        if (selectedEra == null)
          _placeEmptyState()
        else
          ProfileMiniMap(
            era: selectedEra,
            landmarks: state.landmarks,
            completedEventIds: completedEventIds,
            eventEmotionMarks: state.eventEmotionMarks,
            quizAttemptSummaries: state.quizAttemptSummaries,
            onOpenEventDetail: widget.onOpenEventDetail,
          ),
      ],
    );
  }

  Widget _placeEmptyState() {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x55F1E1C0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x66B89A66), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 36,
            color: const Color(0xFF8C6743).withValues(alpha: 0.8),
          ),
          const SizedBox(height: 8),
          const Text(
            '시대를 골라보세요',
            style: TextStyle(
              color: Color(0xFF6A4C2E),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '구약/신약 칩에서 시대를 누르면\n그 시대의 지역 진행도가 지도에 표시됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8C6743),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
