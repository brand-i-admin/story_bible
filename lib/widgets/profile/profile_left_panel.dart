// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 좌측 패널 (아바타/헤더/콘텐츠 탭/기록·기도·저장·말씀 미리보기).
part of '../profile_tab_page.dart';

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
    return stats.total == 0 ? 116 : 96;
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    final selectedIndex = switch (_profileContentTab) {
      _ProfileContentTab.records => 0,
      _ProfileContentTab.prayer => 1,
      _ProfileContentTab.saved => 2,
      _ProfileContentTab.verses => 3,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabBarWidth = math.min(constraints.maxWidth, 336.0);
        final segmentWidth = tabBarWidth / 4;
        final indicatorWidth = math.min(54.0, segmentWidth - 14);
        final indicatorLeft =
            segmentWidth * selectedIndex +
            ((segmentWidth - indicatorWidth) / 2);

        return SizedBox(
          height: 34,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: tabBarWidth,
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Color(0x338E6F48),
                      child: SizedBox(height: 2),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    left: indicatorLeft,
                    bottom: 0,
                    child: Container(
                      width: indicatorWidth,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB26B28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: _profileContentTabButton(
                            label: '기록',
                            tab: _ProfileContentTab.records,
                          ),
                        ),
                        Expanded(
                          child: _profileContentTabButton(
                            label: '기도',
                            tab: _ProfileContentTab.prayer,
                          ),
                        ),
                        Expanded(
                          child: _profileContentTabButton(
                            label: '저장',
                            tab: _ProfileContentTab.saved,
                          ),
                        ),
                        Expanded(
                          child: _profileContentTabButton(
                            label: '말씀',
                            tab: _ProfileContentTab.verses,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profileContentTabButton({
    required String label,
    required _ProfileContentTab tab,
  }) {
    final selected = _profileContentTab == tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectProfileContentTab(tab);
        },
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // "내 기도/중보 기도" 섹션 타이틀과 동일한 14.7pt 통일.
              style: TextStyle(
                color: selected
                    ? const Color(0xFFB26B28)
                    : const Color(0xFF7E735F),
                fontSize: 14.7,
                fontWeight: FontWeight.w900,
              ),
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

  Widget _buildProfileRecordsTabBody() {
    final state = ref.watch(storyControllerProvider);
    final stats = buildProfileQuizStats(state.quizAttemptSummaries);

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          if (stats.total == 0) ...[
            const SizedBox(height: 6),
            _buildProfileTabMessage(
              '퀴즈를 풀면 기록이 쌓여요.',
              fontSize: 10.8,
              scaleDownSingleLine: true,
            ),
          ],
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
