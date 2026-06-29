// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 좌측 패널 (아바타/헤더/콘텐츠 탭/기록·기도·저장·말씀 미리보기).
part of '../profile_tab_page.dart';

bool _profileUsesLargeTextLayout(BuildContext context) {
  return MediaQuery.textScalerOf(context).scale(1) >= 1.3;
}

extension ProfileLeftPanelExt on ProfileTabPageState {
  Widget _buildProfileLeftPanel({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredCardHeight = _profileLeftCardHeight(
          isAuthenticated: isAuthenticated,
        );
        final cardHeight = constraints.hasBoundedHeight
            ? math.min(
                desiredCardHeight,
                math.max(180.0, constraints.maxHeight - _profileHeaderBlock),
              )
            : desiredCardHeight;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileHeader(profile: profile),
            const SizedBox(height: 8),
            SizedBox(
              height: cardHeight,
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: floatingPanelDecoration(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProfileContentTabs(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _buildProfileContentPanel(
                          profile: profile,
                          isAuthenticated: isAuthenticated,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const double _profileHeaderBlock = 56;
  static const double _profileLeftCardChromeHeight = 74;

  double _profileLeftPanelDesiredHeight({required bool isAuthenticated}) {
    return _profileHeaderBlock +
        _profileLeftCardHeight(isAuthenticated: isAuthenticated);
  }

  double _profileLeftCardHeight({required bool isAuthenticated}) {
    return _profileLeftCardChromeHeight +
        switch (_profileContentTab) {
          _ProfileContentTab.records => _profileRecordsContentHeight(),
          _ProfileContentTab.prayer => _profilePrayerContentHeight(
            isAuthenticated: isAuthenticated,
          ),
          _ProfileContentTab.saved => _profileSavedStoriesContentHeight(),
          _ProfileContentTab.verses => _profileSavedVersesContentHeight(),
        };
  }

  double _profileRecordsContentHeight() {
    final state = ref.read(storyControllerProvider);
    final stats = buildProfileQuizStats(state.quizAttemptSummaries);
    return stats.total == 0 ? 188 : 168;
  }

  double _profilePrayerContentHeight({required bool isAuthenticated}) {
    if (_intercessoryPrayerLoading && _intercessoryPrayerItems.isEmpty) {
      return 244;
    }
    if (_intercessoryPrayerError != null && _intercessoryPrayerItems.isEmpty) {
      return 258;
    }
    if (_intercessoryPrayerItems.isEmpty) {
      return isAuthenticated ? 258 : 236;
    }
    final visibleItems = math.min(_intercessoryPrayerItems.length, 3);
    return (184 + visibleItems * 74).clamp(292.0, 408.0).toDouble();
  }

  double _profileSavedStoriesContentHeight() {
    if (_profileSavedEventsLoading ||
        _profileSavedEventsError != null ||
        _profileSavedEventsPreview.isEmpty) {
      return 104;
    }
    return 228;
  }

  double _profileSavedVersesContentHeight() {
    if (_profileSavedVersesLoading ||
        _profileSavedVersesError != null ||
        _profileSavedVersesPreview.isEmpty) {
      return 104;
    }
    final visibleVerses = math.min(_profileSavedVersesPreview.length, 3);
    return (86 + visibleVerses * 52).clamp(154.0, 236.0).toDouble();
  }

  Widget _buildProfileHeader({required AppUserProfile profile}) {
    final largeText = _profileUsesLargeTextLayout(context);
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Tooltip(
              message: '프로필 수정',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openProfileEditor,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        _buildCurrentUserAvatar(profile: profile, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            profile.nickname,
                            maxLines: largeText ? 2 : 1,
                            overflow: largeText
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            softWrap: true,
                            style: const TextStyle(
                              color: AppColors.ink500,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _profileTinyIconButton(
            tooltip: '프로필 수정',
            onTap: _openProfileEditor,
            icon: Icons.edit_rounded,
          ),
          const SizedBox(width: 4),
          _profileTinyIconButton(
            tooltip: '설정',
            onTap: _openProfileSettingsSheet,
            icon: Icons.settings_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContentTabs() {
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
            child: _profileContentTabButton(
              label: '기록',
              tab: _ProfileContentTab.records,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              label: '기도',
              tab: _ProfileContentTab.prayer,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              label: '저장',
              tab: _ProfileContentTab.saved,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              label: '말씀',
              tab: _ProfileContentTab.verses,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileContentTabButton({
    required String label,
    required _ProfileContentTab tab,
  }) {
    final selected = _profileContentTab == tab;
    final largeText = _profileUsesLargeTextLayout(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectProfileContentTab(tab);
        },
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brownWarm : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? AppShadows.sm : null,
          ),
          child: Text(
            label,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.ink350,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContentPanel({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: switch (_profileContentTab) {
        _ProfileContentTab.records => _buildProfileRecordsTabBody(),
        _ProfileContentTab.saved => _buildProfileSavedStoriesTabBody(),
        _ProfileContentTab.verses => _buildProfileVersesTabBody(),
        _ProfileContentTab.prayer => _buildProfilePrayerTabBody(
          profile: profile,
          isAuthenticated: isAuthenticated,
        ),
      },
    );
  }

  ({int completed, int total, double fraction}) _profileStoryProgress(
    StoryState state,
  ) {
    final events = _profileAllEvents.isNotEmpty
        ? _profileAllEvents
        : state.events;
    final total = events.length;
    if (total == 0) {
      return (completed: 0, total: 0, fraction: 0);
    }
    final completed = events
        .where((event) => state.completedEventIds.contains(event.id))
        .length;
    return (
      completed: completed,
      total: total,
      fraction: (completed / total).clamp(0.0, 1.0).toDouble(),
    );
  }

  ({int completed, int total, double fraction}) _profileBibleProgress(
    StoryState state,
  ) {
    final total = _bibleChapterTotalCount();
    final completed = state.completedBibleChapterKeys.length
        .clamp(0, total)
        .toInt();
    return (
      completed: completed,
      total: total,
      fraction: total == 0
          ? 0.0
          : (completed / total).clamp(0.0, 1.0).toDouble(),
    );
  }

  int _bibleChapterTotalCount() {
    return bibleBooks.fold<int>(0, (sum, book) => sum + book.chapters);
  }

  Widget _buildProfileRecordsTabBody() {
    final state = ref.watch(storyControllerProvider);
    final stats = buildProfileQuizStats(state.quizAttemptSummaries);
    final storyProgress = _profileStoryProgress(state);
    final bibleProgress = _profileBibleProgress(state);

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileOverallProgressRow(
            storyProgress: storyProgress,
            bibleProgress: bibleProgress,
            onTapStory: _openStoryProgressDialog,
            onTapBible: _openBibleProgressDialog,
          ),
          const SizedBox(height: 9),
          _ProfileRecordsStatsPanel(
            quizStats: stats,
            selectedQuizFilter: null,
            onTapWrong: () {
              _openProfileQuizReviewDialog(
                filter: _ProfileQuizReviewFilter.wrong,
                eventIds: stats.wrongEventIds,
              );
            },
            onTapConfused: () {
              _openProfileQuizReviewDialog(
                filter: _ProfileQuizReviewFilter.confused,
                eventIds: stats.confusedEventIds,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSavedStoriesTabBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileTabSectionHeader(
          title: '저장한 이야기',
          actionLabel: '전체 보기',
          onAction: _openSavedStoriesOverview,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _profileSavedEventsLoading
              ? const Center(child: CircularProgressIndicator())
              : _profileSavedEventsError != null
              ? _buildProfileTabMessage(
                  _profileSavedEventsError!,
                  textColor: const Color(0xFF7E3426),
                )
              : _profileSavedEventsPreview.isEmpty
              ? _buildProfileTabMessage(
                  '아직 저장한 이야기가 없습니다.\n사건 상세에서 별표를 눌러 저장해 보세요.',
                )
              : _buildSavedStoryCarousel(_profileSavedEventsPreview),
        ),
      ],
    );
  }

  Widget _buildProfileVersesTabBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '저장한 말씀',
          maxLines: 2,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: Color(0xFF452F1A),
            fontWeight: FontWeight.w900,
            fontSize: 15.2,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _profileSavedVersesLoading
              ? const Center(child: CircularProgressIndicator())
              : _profileSavedVersesError != null
              ? _buildProfileTabMessage(
                  _profileSavedVersesError!,
                  textColor: const Color(0xFF7E3426),
                )
              : _profileSavedVersesPreview.isEmpty
              ? _buildProfileTabMessage(
                  '아직 저장한 말씀이 없습니다.\n성경 화면에서 구절을 눌러 저장해 보세요.',
                )
              : _buildProfileSavedVersesPreview(),
        ),
      ],
    );
  }

  Widget _buildProfilePrayerTabBody({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    final prayerText = (profile.prayerRequest ?? '').trim().isNotEmpty
        ? profile.prayerRequest!.trim()
        : '오늘의 기도제목을 적어 보세요.';
    final hasItems = _intercessoryPrayerItems.isNotEmpty;
    final largeText = _profileUsesLargeTextLayout(context);
    const sectionTitleStyle = TextStyle(
      color: Color(0xFF452F1A),
      fontWeight: FontWeight.w900,
      fontSize: 14.7,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '내 기도',
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: sectionTitleStyle,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openProfilePrayerPreview(prayerText),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.open_in_full_rounded,
                    size: 16,
                    color: AppColors.ink200,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0x448E6F48)),
        const SizedBox(height: 7),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openProfileEditor,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.only(right: 2, bottom: 2),
              child: Text(
                prayerText,
                maxLines: largeText ? null : 2,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  color: Color(0xFF5A4326),
                  fontWeight: FontWeight.w400,
                  fontSize: 13.4,
                  height: 1.34,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Expanded(
              child: Text(
                '중보 기도',
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: sectionTitleStyle,
              ),
            ),
            if (isAuthenticated)
              _profileShareIdChip(
                shareId: profile.shareId,
                enabled: true,
                onTap: () => _copyProfileShareId(profile.shareId),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0x448E6F48)),
        const SizedBox(height: 7),
        // 중보 기도 리스트 — 탭 카드의 남은 높이를 채움. 항목이 많으면
        // 내부에서만 스크롤해 다른 프로필 섹션 높이를 밀어내지 않는다.
        Expanded(
          child: _intercessoryPrayerLoading && !hasItems
              ? const Center(child: CircularProgressIndicator())
              : _intercessoryPrayerError != null && !hasItems
              ? _buildIntercessoryPrayerErrorCard()
              : !hasItems
              ? _buildIntercessoryPrayerEmptyCard(enabled: isAuthenticated)
              : Stack(
                  children: [
                    ListView.separated(
                      controller: _intercessoryPrayerScrollController,
                      padding: const EdgeInsets.only(bottom: 52),
                      itemCount:
                          _intercessoryPrayerItems.length +
                          (_intercessoryPrayerLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index >= _intercessoryPrayerItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                          );
                        }
                        final item = _intercessoryPrayerItems[index];
                        return _buildIntercessoryPrayerItemCard(item);
                      },
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _intercessoryPrayerFab(enabled: isAuthenticated),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _profileTabSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final largeText = _profileUsesLargeTextLayout(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            style: const TextStyle(
              color: Color(0xFF452F1A),
              fontWeight: FontWeight.w900,
              fontSize: 15.2,
            ),
          ),
        ),
        _profileInlineTextButton(label: actionLabel, onTap: onAction),
      ],
    );
  }

  Widget _profileInlineTextButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xDDF7E9D2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6C4C28),
              fontSize: 11.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTabMessage(
    String text, {
    Color textColor = const Color(0xFF6D5231),
    double fontSize = 12.4,
    bool scaleDownSingleLine = false,
  }) {
    final textWidget = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: scaleDownSingleLine ? 1 : null,
      style: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        height: scaleDownSingleLine ? 1.05 : 1.45,
      ),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: scaleDownSingleLine
            ? FittedBox(fit: BoxFit.scaleDown, child: textWidget)
            : textWidget,
      ),
    );
  }

  Widget _buildProfileSavedVersesPreview() {
    final preview = _profileSavedVersesPreview.take(3).toList();
    final hasMore = _profileSavedVersesPreview.length > preview.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < preview.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  SavedVerseRow(
                    verse: preview[index],
                    compact: true,
                    onTap: () => widget.onOpenBibleReader(
                      initialBookNo: preview[index].bookNo,
                      initialChapterNo: preview[index].chapterNo,
                      initialVerseNo: preview[index].verseNo,
                    ),
                  ),
                ],
                if (hasMore) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink200,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: _profileInlineTextButton(
            label: '전체 보기',
            onTap: _openSavedVersesPage,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileReviewEventList({
    required Set<String> eventIds,
    required String emptyText,
    ValueChanged<StoryEvent>? onOpenEventDetail,
  }) {
    if (eventIds.isEmpty) {
      return _buildProfileTabMessage(emptyText);
    }
    return FutureBuilder<List<StoryEvent>>(
      future: ref.read(storyRepositoryProvider).fetchEventsByIds(eventIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildProfileTabMessage(
            '복습할 이야기를 불러오지 못했습니다.\n${snapshot.error}',
            textColor: const Color(0xFF7E3426),
          );
        }
        final state = ref.read(storyControllerProvider);
        final events = _sortEventsByEraThenIndex(
          snapshot.data ?? const <StoryEvent>[],
          state.eras,
        );
        if (events.isEmpty) {
          return _buildProfileTabMessage(emptyText);
        }
        final charactersByCode = <String, Character>{
          for (final character in _profileAllPeople) character.code: character,
          for (final character in state.characters) character.code: character,
        };
        return ProfileEventReviewGrid(
          events: events,
          eras: state.eras,
          charactersByCode: charactersByCode,
          completedEventIds: state.completedEventIds,
          eventEmotionMarks: state.eventEmotionMarks,
          quizAttemptSummaries: state.quizAttemptSummaries,
          emptyText: emptyText,
          onOpenEventDetail: onOpenEventDetail ?? widget.onOpenEventDetail,
        );
      },
    );
  }

  Future<void> _openProfileQuizReviewDialog({
    required _ProfileQuizReviewFilter filter,
    required Set<String> eventIds,
  }) async {
    final title = switch (filter) {
      _ProfileQuizReviewFilter.wrong => '오답 이야기',
      _ProfileQuizReviewFilter.confused => '헷갈려요 이야기',
    };
    final emptyText = switch (filter) {
      _ProfileQuizReviewFilter.wrong => '틀린 이야기가 없습니다.',
      _ProfileQuizReviewFilter.confused => '헷갈렸던 이야기가 없습니다.',
    };
    await _openProfileReviewDialog(
      title: title,
      eventIds: eventIds,
      emptyText: emptyText,
    );
  }

  Future<void> _openStoryProgressDialog() async {
    final state = ref.read(storyControllerProvider);
    final events = _profileAllEvents.isNotEmpty
        ? _profileAllEvents
        : state.events;
    final eraIdsWithEvents = events.map((event) => event.eraId).toSet();
    final eras = state.eras
        .where((era) => eraIdsWithEvents.contains(era.id))
        .toList(growable: false);
    var selectedEraId = eras.firstOrNull?.id;
    final charactersByCode = <String, Character>{
      for (final character in _profileAllPeople) character.code: character,
      for (final character in state.characters) character.code: character,
    };

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedEra = eras
                .where((era) => era.id == selectedEraId)
                .firstOrNull;
            final selectedEvents = selectedEra == null
                ? const <StoryEvent>[]
                : events
                      .where((event) => event.eraId == selectedEra.id)
                      .toList(growable: false);
            final selectedCompletedCount = selectedEvents
                .where((event) => state.completedEventIds.contains(event.id))
                .length;
            final selectedFraction = selectedEvents.isEmpty
                ? 0.0
                : (selectedCompletedCount / selectedEvents.length)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 880,
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
                  minWidth: 320,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: modalSurfaceDecoration(),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '이야기 진행률',
                                  style: TextStyle(
                                    color: Color(0xFF3A2B15),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                EraPickRows(
                                  eras: eras,
                                  selectedEraId: selectedEraId,
                                  onSelectEra: (eraId) {
                                    setDialogState(() {
                                      selectedEraId = eraId;
                                    });
                                  },
                                  trailingScrollPadding: 8,
                                ),
                                const SizedBox(height: 10),
                                _StoryProgressSelectedEraMeter(
                                  eraName: selectedEra?.name ?? '시대',
                                  completed: selectedCompletedCount,
                                  total: selectedEvents.length,
                                  fraction: selectedFraction,
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: ProfileEventReviewGrid(
                                    events: selectedEvents,
                                    eras: state.eras,
                                    charactersByCode: charactersByCode,
                                    completedEventIds: state.completedEventIds,
                                    eventEmotionMarks: state.eventEmotionMarks,
                                    quizAttemptSummaries:
                                        state.quizAttemptSummaries,
                                    emptyText: '이 시대의 이야기가 없습니다.',
                                    onOpenEventDetail: (event) {
                                      Navigator.of(dialogContext).pop();
                                      widget.onOpenEventDetail(event);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: modalCloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              size: 32,
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
      },
    );
  }

  Future<void> _openBibleProgressDialog() async {
    final state = ref.read(storyControllerProvider);
    var selectedTestament = 'old';
    var selectedBookNo = oldTestamentFirstBookNo;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bookNumbers = _profileBookNumbersForTestament(
              selectedTestament,
            );
            if (!bookNumbers.contains(selectedBookNo)) {
              selectedBookNo = bookNumbers.first;
            }
            final book = bibleBooks[selectedBookNo - 1];
            final completedChapters = {
              for (var chapter = 1; chapter <= book.chapters; chapter += 1)
                if (state.completedBibleChapterKeys.contains(
                  bibleChapterProgressKey(
                    bookNo: selectedBookNo,
                    chapterNo: chapter,
                  ),
                ))
                  chapter,
            };
            final fraction = book.chapters == 0
                ? 0.0
                : (completedChapters.length / book.chapters)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.82,
                  minWidth: 320,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: modalSurfaceDecoration(),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '통독 진행률',
                                  style: TextStyle(
                                    color: Color(0xFF3A2B15),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _BibleProgressPickerRow(
                                  selectedTestament: selectedTestament,
                                  selectedBookNo: selectedBookNo,
                                  bookNumbers: bookNumbers,
                                  onTestamentChanged: (testament) {
                                    setDialogState(() {
                                      selectedTestament = testament;
                                      selectedBookNo =
                                          _profileBookNumbersForTestament(
                                            testament,
                                          ).first;
                                    });
                                  },
                                  onBookChanged: (bookNo) {
                                    setDialogState(() {
                                      selectedBookNo = bookNo;
                                    });
                                  },
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _BibleChapterProgressGrid(
                                          chapterCount: book.chapters,
                                          completedChapters: completedChapters,
                                          onChapterTap: (chapter) async {
                                            final bookNo = selectedBookNo;
                                            Navigator.of(dialogContext).pop();
                                            await widget.onOpenBibleReader(
                                              initialBookNo: bookNo,
                                              initialChapterNo: chapter,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        _BibleBookProgressFooter(
                                          bookName: book.name,
                                          completed: completedChapters.length,
                                          total: book.chapters,
                                          fraction: fraction,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: modalCloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              size: 32,
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
      },
    );
  }

  Future<void> _openProfileReviewDialog({
    required String title,
    required Set<String> eventIds,
    required String emptyText,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 820,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
              minWidth: 320,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: modalSurfaceDecoration(),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF3A2B15),
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _buildProfileReviewEventList(
                                eventIds: eventIds,
                                emptyText: emptyText,
                                onOpenEventDetail: (event) {
                                  Navigator.of(dialogContext).pop();
                                  widget.onOpenEventDetail(event);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: modalCloseButton(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          size: 32,
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

  Widget _buildSavedStoryCarousel(List<StoryEvent> events) {
    final state = ref.watch(storyControllerProvider);
    final charactersByCode = <String, Character>{
      for (final character in _profileAllPeople) character.code: character,
      for (final character in state.characters) character.code: character,
    };
    final loader = SceneAssetLoader();
    final eraById = {for (final era in state.eras) era.id: era};
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0.0, 0.88, 1.0],
        colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 8, 20, 8),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final event = events[index];
          return SizedBox(
            width: 128,
            child: StoryEventThumbCard(
              event: event,
              era: eraById[event.eraId],
              charactersByCode: charactersByCode,
              selected: false,
              completed: state.completedEventIds.contains(event.id),
              emotionKey: state.eventEmotionMarks[event.id]?.emotionKey,
              attemptSummary: state.quizAttemptSummaries[event.id],
              orderNumber: event.storyIndex,
              showSummary: false,
              loader: loader,
              onTap: () => widget.onOpenEventDetail(event),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventGroupsByEra({
    required List<StoryEvent> events,
    required StoryState state,
    bool compact = false,
  }) {
    final charactersByCode = <String, Character>{
      for (final character in _profileAllPeople) character.code: character,
      for (final character in state.characters) character.code: character,
    };
    final loader = SceneAssetLoader();
    final eventsByEra = <String, List<StoryEvent>>{};
    for (final event in events) {
      eventsByEra.putIfAbsent(event.eraId, () => <StoryEvent>[]).add(event);
    }
    for (final eraEvents in eventsByEra.values) {
      eraEvents.sort((a, b) {
        final storyOrder = a.storyIndex.compareTo(b.storyIndex);
        if (storyOrder != 0) {
          return storyOrder;
        }
        return a.globalRank.compareTo(b.globalRank);
      });
    }
    final orderedEraIds = eventsByEra.keys.toList()
      ..sort((a, b) {
        final ao = state.eras
            .where((era) => era.id == a)
            .map((era) => era.displayOrder)
            .firstOrNull;
        final bo = state.eras
            .where((era) => era.id == b)
            .map((era) => era.displayOrder)
            .firstOrNull;
        return (ao ?? 1 << 30).compareTo(bo ?? 1 << 30);
      });

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(2, compact ? 0 : 6, 2, 12),
      itemCount: orderedEraIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final eraId = orderedEraIds[index];
        final era = state.eras.where((entry) => entry.id == eraId).firstOrNull;
        final eraEvents = eventsByEra[eraId] ?? const <StoryEvent>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileEraSectionLabel(
              label: era == null ? '시대 미상' : era.name,
              count: eraEvents.length,
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(4, compact ? 4 : 8, 4, 2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: compact ? 226 : 242,
              ),
              itemCount: eraEvents.length,
              itemBuilder: (context, eventIndex) {
                final event = eraEvents[eventIndex];
                return StoryEventThumbCard(
                  event: event,
                  era: era,
                  charactersByCode: charactersByCode,
                  selected: false,
                  completed: state.completedEventIds.contains(event.id),
                  emotionKey: state.eventEmotionMarks[event.id]?.emotionKey,
                  attemptSummary: state.quizAttemptSummaries[event.id],
                  loader: loader,
                  onTap: () => widget.onOpenEventDetail(event),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSavedStoriesOverview() async {
    if (_profileSavedEventsPreview.isEmpty) {
      return;
    }
    final state = ref.read(storyControllerProvider);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 820,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
              minWidth: 320,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: modalSurfaceDecoration(),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '저장한 이야기',
                              style: TextStyle(
                                color: Color(0xFF3A2B15),
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _buildEventGroupsByEra(
                                events: _profileSavedEventsPreview,
                                state: state,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: modalCloseButton(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          size: 32,
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

  Widget _buildCurrentUserAvatar({
    required AppUserProfile profile,
    required double size,
    Uint8List? previewBytes,
  }) {
    final initials = profile.nickname.trim().isEmpty
        ? '?'
        : profile.nickname.trim().substring(0, 1);
    final ImageProvider? imageProvider = previewBytes != null
        ? MemoryImage(previewBytes)
        : ((profile.photoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(profile.photoUrl!.trim())
              : null);

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
        border: Border.all(color: const Color(0xFF8C6743), width: 1.4),
      ),
      child: ClipOval(
        child: imageProvider == null
            ? Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: AppColors.ink500,
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : Image(
                image: imageProvider,
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
              ),
      ),
    );
  }
}

class _ProfileRecordsStatsPanel extends StatelessWidget {
  const _ProfileRecordsStatsPanel({
    required this.quizStats,
    required this.selectedQuizFilter,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ProfileQuizStats quizStats;
  final _ProfileQuizReviewFilter? selectedQuizFilter;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55A8834D), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileQuizStatsStrip(
            stats: quizStats,
            selected: selectedQuizFilter,
            onTapWrong: onTapWrong,
            onTapConfused: onTapConfused,
          ),
        ],
      ),
    );
  }
}

class _ProfileOverallProgressRow extends StatelessWidget {
  const _ProfileOverallProgressRow({
    required this.storyProgress,
    required this.bibleProgress,
    required this.onTapStory,
    required this.onTapBible,
  });

  final ({int completed, int total, double fraction}) storyProgress;
  final ({int completed, int total, double fraction}) bibleProgress;
  final VoidCallback onTapStory;
  final VoidCallback onTapBible;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProfileOverallProgressButton(
            icon: Icons.auto_stories_rounded,
            label: '이야기 진행률',
            completed: storyProgress.completed,
            total: storyProgress.total,
            fraction: storyProgress.fraction,
            color: AppColors.greenTop,
            onTap: onTapStory,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _ProfileOverallProgressButton(
            icon: Icons.menu_book_rounded,
            label: '통독 진행률',
            completed: bibleProgress.completed,
            total: bibleProgress.total,
            fraction: bibleProgress.fraction,
            color: const Color(0xFFC7923D),
            onTap: onTapBible,
          ),
        ),
      ],
    );
  }
}

class _ProfileOverallProgressButton extends StatelessWidget {
  const _ProfileOverallProgressButton({
    required this.icon,
    required this.label,
    required this.completed,
    required this.total,
    required this.fraction,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int completed;
  final int total;
  final double fraction;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final valueLabel = '$completed/$total';
    final largeText = _profileUsesLargeTextLayout(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xEFFFF8E9),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x55A8834D), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 7,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                      style: const TextStyle(
                        color: Color(0xFF5A4326),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 13,
                      value: fraction.clamp(0.0, 1.0).toDouble(),
                      backgroundColor: const Color(0xFFE4D3AF),
                      color: color,
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          valueLabel,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFF4E3B21),
                            fontSize: 9.4,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryProgressSelectedEraMeter extends StatelessWidget {
  const _StoryProgressSelectedEraMeter({
    required this.eraName,
    required this.completed,
    required this.total,
    required this.fraction,
  });

  final String eraName;
  final int completed;
  final int total;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    final largeText = _profileUsesLargeTextLayout(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x55A8834D), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  eraName,
                  maxLines: largeText ? 2 : 1,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontSize: 12.4,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
              Text(
                '$percent%',
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.greenBot,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: fraction.clamp(0.0, 1.0).toDouble(),
              backgroundColor: const Color(0xFFE4D3AF),
              color: AppColors.greenTop,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$completed / $total',
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.ink300,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleProgressPickerRow extends StatelessWidget {
  const _BibleProgressPickerRow({
    required this.selectedTestament,
    required this.selectedBookNo,
    required this.bookNumbers,
    required this.onTestamentChanged,
    required this.onBookChanged,
  });

  final String selectedTestament;
  final int selectedBookNo;
  final List<int> bookNumbers;
  final ValueChanged<String> onTestamentChanged;
  final ValueChanged<int> onBookChanged;

  @override
  Widget build(BuildContext context) {
    final safeBookNo = bookNumbers.contains(selectedBookNo)
        ? selectedBookNo
        : bookNumbers.first;
    final largeText = _profileUsesLargeTextLayout(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: bibleDropdownFrame<String>(
              value: selectedTestament,
              items: const [
                DropdownMenuItem(value: 'old', child: Text('구약')),
                DropdownMenuItem(value: 'new', child: Text('신약')),
              ],
              onChanged: (v) => v != null ? onTestamentChanged(v) : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 148,
            child: bibleDropdownFrame<int>(
              value: safeBookNo,
              items: [
                for (final bookNo in bookNumbers)
                  DropdownMenuItem<int>(
                    value: bookNo,
                    child: Text(
                      bibleBooks[bookNo - 1].name,
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
              ],
              onChanged: (v) => v != null ? onBookChanged(v) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleChapterProgressGrid extends StatelessWidget {
  const _BibleChapterProgressGrid({
    required this.chapterCount,
    required this.completedChapters,
    required this.onChapterTap,
  });

  final int chapterCount;
  final Set<int> completedChapters;
  final ValueChanged<int> onChapterTap;

  @override
  Widget build(BuildContext context) {
    if (chapterCount <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 10
            : (constraints.maxWidth >= 460 ? 8 : 6);
        final rowCount = (chapterCount / columns).ceil();
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.parchmentCream.withValues(alpha: 0.54),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: const Color(0x228E6F48)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) ...[
                  if (rowIndex > 0) const _BibleChapterHorizontalDivider(),
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        for (
                          var colIndex = 0;
                          colIndex < columns;
                          colIndex++
                        ) ...[
                          Expanded(
                            child: _BibleChapterGridCell(
                              chapter: rowIndex * columns + colIndex + 1,
                              chapterCount: chapterCount,
                              completedChapters: completedChapters,
                              onTap: onChapterTap,
                            ),
                          ),
                          if (colIndex < columns - 1)
                            const _BibleChapterVerticalDivider(),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BibleChapterGridCell extends StatelessWidget {
  const _BibleChapterGridCell({
    required this.chapter,
    required this.chapterCount,
    required this.completedChapters,
    required this.onTap,
  });

  final int chapter;
  final int chapterCount;
  final Set<int> completedChapters;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (chapter > chapterCount) {
      return const SizedBox.shrink();
    }
    final completed = completedChapters.contains(chapter);
    return Semantics(
      button: true,
      label: '$chapter장 성경 열기',
      child: Tooltip(
        message: '$chapter장 읽기',
        child: InkWell(
          key: ValueKey('bible-progress-chapter-$chapter'),
          onTap: () => onTap(chapter),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            alignment: Alignment.center,
            color: completed
                ? AppColors.greenTint1.withValues(alpha: 0.86)
                : Colors.transparent,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$chapter',
                    maxLines: 1,
                    style: TextStyle(
                      color: completed ? AppColors.greenBot : AppColors.ink500,
                      fontSize: AppFontSizes.body,
                      fontWeight: completed ? FontWeight.w900 : FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.greenBot,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BibleBookProgressFooter extends StatelessWidget {
  const _BibleBookProgressFooter({
    required this.bookName,
    required this.completed,
    required this.total,
    required this.fraction,
  });

  final String bookName;
  final int completed;
  final int total;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    final largeText = _profileUsesLargeTextLayout(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55A8834D), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$bookName 통독',
                  maxLines: largeText ? 2 : 1,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: AppColors.greenBot,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: fraction.clamp(0.0, 1.0).toDouble(),
              backgroundColor: const Color(0xFFE4D3AF),
              color: AppColors.greenTop,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '$completed / $total장',
            style: const TextStyle(
              color: AppColors.ink300,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleChapterHorizontalDivider extends StatelessWidget {
  const _BibleChapterHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: const Color(0x228E6F48)),
    );
  }
}

class _BibleChapterVerticalDivider extends StatelessWidget {
  const _BibleChapterVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: const Color(0x228E6F48),
      ),
    );
  }
}

class _ProfileQuizStatsStrip extends StatelessWidget {
  const _ProfileQuizStatsStrip({
    required this.stats,
    required this.selected,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ProfileQuizStats stats;
  final _ProfileQuizReviewFilter? selected;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProfileQuizStatItem(
            icon: Icons.check_rounded,
            label: '정답',
            count: stats.correct,
            eventCount: stats.correctEventCount,
            color: const Color(0xFF4BA36A),
            selected: false,
            onTap: null,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _ProfileQuizStatItem(
            icon: Icons.close_rounded,
            label: '오답',
            count: stats.wrong,
            eventCount: stats.wrongEventCount,
            color: const Color(0xFFC75245),
            selected: selected == _ProfileQuizReviewFilter.wrong,
            onTap: onTapWrong,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _ProfileQuizStatItem(
            icon: Icons.question_mark_rounded,
            label: '헷갈려요',
            count: stats.confused,
            eventCount: stats.confusedEventCount,
            color: const Color(0xFFC7923D),
            selected: selected == _ProfileQuizReviewFilter.confused,
            onTap: onTapConfused,
          ),
        ),
      ],
    );
  }
}

class _ProfileQuizStatItem extends StatelessWidget {
  const _ProfileQuizStatItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.eventCount,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final int eventCount;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.14)
            : AppColors.parchmentCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? color.withValues(alpha: 0.58)
              : const Color(0x66A8834D),
          width: selected ? 1.1 : 0.8,
        ),
        boxShadow: onTap == null
            ? null
            : const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontSize: 12.6,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              profileQuizCountLabel(quizCount: count, storyCount: eventCount),
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF2E2114),
                fontSize: 11.2,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

class _ProfileEraSectionLabel extends StatelessWidget {
  const _ProfileEraSectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAD6AE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x998E6F48), width: 1),
      ),
      child: Text(
        '$label · $count개',
        style: const TextStyle(
          color: Color(0xFF5A4326),
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

List<int> _profileBookNumbersForTestament(String testament) {
  final firstBookNo = testament == 'new'
      ? newTestamentFirstBookNo
      : oldTestamentFirstBookNo;
  final lastBookNo = testament == 'new'
      ? newTestamentLastBookNo
      : oldTestamentLastBookNo;
  return List<int>.generate(
    lastBookNo - firstBookNo + 1,
    (index) => firstBookNo + index,
  );
}
