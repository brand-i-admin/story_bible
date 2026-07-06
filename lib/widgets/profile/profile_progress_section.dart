// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// "진행률 표시" 섹션 — 좌측 상단 제목 + 세 탭 (다이어리 / 인물과걷기 / 장소로시작) +
// 그 아래 컨텐츠. 넓은 화면은 섹션 내부 스크롤, 좁은 화면은 프로필 페이지 전체
// 스크롤이 본문 끝까지 담당한다.
part of '../profile_tab_page.dart';

extension ProfileProgressSectionExt on ProfileTabPageState {
  Widget _buildProfileProgressSection({
    required List<Character> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
    bool scrollBody = true,
  }) {
    final palette = AppPaletteTheme.of(context);
    final selectedAccent = _profileProgressTabAccent(palette);
    final body = Container(
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      decoration: _profileLinkedTabBodyDecoration(
        context,
        accent: selectedAccent,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: scrollBody
            ? SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _profileProgressBody(
                  people: people,
                  completedEventIds: completedEventIds,
                  selectedTestament: selectedTestament,
                  onSelectTestament: onSelectTestament,
                ),
              )
            : _profileProgressBody(
                people: people,
                completedEventIds: completedEventIds,
                selectedTestament: selectedTestament,
                onSelectTestament: onSelectTestament,
              ),
      ),
    );
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: _profileLinkedTabGroupDecoration(
        context,
        accent: palette.currentAccentDeep,
      ),
      child: Column(
        mainAxisSize: scrollBody ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 탭 바를 섹션 최상단에 pinned. 제목은 제거 — 탭 라벨이 자체 설명.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: _profileProgressTabBar(),
          ),
          if (scrollBody) Expanded(child: body) else body,
        ],
      ),
    );
  }

  Widget _profileProgressBody({
    required List<Character> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return switch (_profileProgressTab) {
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
    };
  }

  /// 세 탭 토글 — "다이어리" / "인물과걷기" / "장소로시작".
  Widget _profileProgressTabBar() {
    final palette = AppPaletteTheme.of(context);
    return SizedBox(
      height: _profileIconTabHeight,
      child: Row(
        children: [
          Expanded(
            child: _progressTabButton(
              icon: Icons.calendar_month_rounded,
              label: '다이어리',
              selected: _profileProgressTab == _ProfileProgressTab.life,
              accent: palette.currentAccentDeep,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.life);
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _progressTabButton(
              icon: Icons.directions_walk_rounded,
              label: '인물과걷기',
              selected: _profileProgressTab == _ProfileProgressTab.walk,
              accent: palette.characterAccent,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.walk);
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _progressTabButton(
              icon: Icons.place_rounded,
              label: '장소로시작',
              selected: _profileProgressTab == _ProfileProgressTab.place,
              accent: palette.regionAccent,
              onTap: () {
                // ignore: invalid_use_of_protected_member
                setState(() => _profileProgressTab = _ProfileProgressTab.place);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressTabButton({
    required IconData icon,
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return _ProfileIconTabButton(
      icon: icon,
      label: label,
      selected: selected,
      accent: accent,
      onTap: onTap,
    );
  }

  Color _profileProgressTabAccent(AppColorPalette palette) {
    return switch (_profileProgressTab) {
      _ProfileProgressTab.life => palette.currentAccentDeep,
      _ProfileProgressTab.walk => palette.characterAccent,
      _ProfileProgressTab.place => palette.regionAccent,
    };
  }

  // ───────────────────────── 다이어리 탭 본문 ─────────────────────────
  Widget _profileProgressLifeBody() {
    final state = ref.watch(storyControllerProvider);
    final emotionStats = buildProfileEmotionStats(state.eventEmotionMarks);
    return ProfileEmotionDiary(
      eventEmotionMarks: state.eventEmotionMarks,
      companionDiaryEntries: _profileCompanionDiaryEntries,
      companionDiaryLoading: _profileCompanionDiaryLoading,
      companionDiaryError: _profileCompanionDiaryError,
      onSaveCompanionDiary: _saveCompanionDiaryEntry,
      onDeleteCompanionDiary: _deleteCompanionDiaryEntry,
      emotionStats: emotionStats,
      onTapEmotion: (option) {
        _openProfileReviewDialog(
          title: '${option.label} 이야기',
          eventIds: emotionStats.eventIdsFor(option.key),
          emptyText: '${option.label}으로 새긴 이야기가 없습니다.',
        );
      },
      onOpenEventDetail: (event) {
        widget.onOpenEventDetail(
          event,
          source: ProfileEventOpenSource.detailOnly,
        );
      },
    );
  }

  // ──────────────────────── 인물과걷기 탭 본문 ────────────────────────
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
                style: TextStyle(
                  color: AppPaletteTheme.of(context).mutedText,
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

  // ──────────────────────── 장소로시작 탭 본문 ────────────────────────
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
            onOpenEventDetail: (event, {regionLandmarkId}) {
              widget.onOpenEventDetail(
                event,
                source: ProfileEventOpenSource.place,
                sourceId: regionLandmarkId,
              );
            },
          ),
      ],
    );
  }

  Widget _placeEmptyState() {
    final palette = AppPaletteTheme.of(context);
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.subtleBorder, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 36,
            color: palette.regionAccent.withValues(alpha: 0.86),
          ),
          const SizedBox(height: 8),
          Text(
            '시대를 골라보세요',
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '구약/신약 칩에서 시대를 누르면\n그 시대의 지역 진행도가 지도에 표시됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
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
