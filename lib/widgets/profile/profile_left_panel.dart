// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 좌측 패널 (아바타/헤더/콘텐츠 탭/기록·기도·저장·말씀 미리보기).
part of '../profile_tab_page.dart';

bool _profileUsesLargeTextLayout(BuildContext context) {
  return MediaQuery.textScalerOf(context).scale(1) >= 1.3;
}

BoxDecoration _profileTabRailDecoration(
  BuildContext context, {
  required Color accent,
  Color? secondaryAccent,
}) {
  final palette = AppPaletteTheme.of(context);
  final endAccent = secondaryAccent ?? accent;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          accent.withValues(alpha: 0.12),
          palette.cardUnselectedTop,
        ),
        Color.alphaBlend(
          endAccent.withValues(alpha: 0.10),
          palette.cardUnselectedBottom,
        ),
      ],
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: accent.withValues(alpha: 0.28), width: 0.9),
  );
}

BoxDecoration _profileLinkedTabGroupDecoration(
  BuildContext context, {
  required Color accent,
  Color? secondaryAccent,
}) {
  return _profileTabRailDecoration(
    context,
    accent: accent,
    secondaryAccent: secondaryAccent,
  );
}

Color _profileSelectedTabSurface(
  BuildContext context, {
  required Color accent,
}) {
  final palette = AppPaletteTheme.of(context);
  return Color.alphaBlend(accent.withValues(alpha: 0.24), palette.cardSurface);
}

Color _profileSelectedTabButtonSurface(Color accent) {
  return accent;
}

const double _profileIconTabHeight = 44;

BoxDecoration _profileLinkedTabBodyDecoration(
  BuildContext context, {
  required Color accent,
}) {
  return BoxDecoration(
    color: _profileSelectedTabSurface(context, accent: accent),
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(10),
      topRight: Radius.circular(10),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
    border: Border.all(color: accent.withValues(alpha: 0.28), width: 0.7),
  );
}

extension ProfileLeftPanelExt on ProfileTabPageState {
  Widget _buildProfileActivitySection({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    final palette = AppPaletteTheme.of(context);
    final railAccent = palette.primary;
    final contentAccent = _profileContentTabAccent(palette);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: _profileLinkedTabGroupDecoration(context, accent: railAccent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: _buildProfileContentTabs(),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              decoration: _profileLinkedTabBodyDecoration(
                context,
                accent: contentAccent,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: _buildProfileContentPanel(
                  profile: profile,
                  isAuthenticated: isAuthenticated,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const double _profileLeftCardChromeHeight = 90;

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
    return 122;
  }

  double _profilePrayerContentHeight({required bool isAuthenticated}) {
    final largeText = _profileUsesLargeTextLayout(context);
    if (_intercessoryPrayerLoading && _intercessoryPrayerItems.isEmpty) {
      return largeText ? 226 : 196;
    }
    if (_intercessoryPrayerError != null && _intercessoryPrayerItems.isEmpty) {
      return largeText ? 236 : 206;
    }
    if (_intercessoryPrayerItems.isEmpty) {
      return isAuthenticated
          ? (largeText ? 236 : 208)
          : (largeText ? 228 : 198);
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
    final palette = AppPaletteTheme.of(context);
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
                        _buildCurrentUserAvatar(profile: profile, size: 56),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '샬롬! 🙌 ',
                                      style: TextStyle(
                                        color: palette.mutedText,
                                        fontSize: largeText ? 11.4 : 12.0,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    TextSpan(
                                      text: profile.nickname,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: largeText ? 17.2 : 18.4,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '님',
                                      style: TextStyle(
                                        color: palette.mutedText,
                                        fontSize: largeText ? 11.4 : 12.0,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: largeText ? 2 : 1,
                                overflow: largeText
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                softWrap: true,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '오늘도 말씀 안에서\n승리하는 하루 되세요!',
                                maxLines: 2,
                                overflow: largeText
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                softWrap: true,
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: largeText ? 11.0 : 11.6,
                                  fontWeight: FontWeight.w700,
                                  height: 1.18,
                                ),
                              ),
                            ],
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
    final palette = AppPaletteTheme.of(context);
    return SizedBox(
      height: _profileIconTabHeight,
      child: Row(
        children: [
          Expanded(
            child: _profileContentTabButton(
              icon: Icons.edit_note_rounded,
              label: '기록',
              tab: _ProfileContentTab.records,
              accent: palette.regionAccent,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              icon: Icons.self_improvement_rounded,
              label: '기도',
              tab: _ProfileContentTab.prayer,
              accent: palette.characterAccent,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              icon: Icons.bookmark_rounded,
              label: '저장',
              tab: _ProfileContentTab.saved,
              accent: palette.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _profileContentTabButton(
              icon: Icons.menu_book_rounded,
              label: '말씀',
              tab: _ProfileContentTab.verses,
              accent: palette.currentAccentDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileContentTabButton({
    required IconData icon,
    required String label,
    required _ProfileContentTab tab,
    required Color accent,
  }) {
    final selected = _profileContentTab == tab;
    return _ProfileIconTabButton(
      icon: icon,
      label: label,
      selected: selected,
      accent: accent,
      onTap: () {
        _selectProfileContentTab(tab);
      },
    );
  }

  Color _profileContentTabAccent(AppColorPalette palette) {
    return switch (_profileContentTab) {
      _ProfileContentTab.records => palette.regionAccent,
      _ProfileContentTab.prayer => palette.characterAccent,
      _ProfileContentTab.saved => palette.primary,
      _ProfileContentTab.verses => palette.currentAccentDeep,
    };
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
      child: _ProfileRecordsDashboard(
        storyProgress: storyProgress,
        bibleProgress: bibleProgress,
        quizStats: stats,
        onTapStory: _openStoryProgressDialog,
        onTapBible: _openBibleProgressDialog,
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
    final palette = AppPaletteTheme.of(context);
    final prayerText = (profile.prayerRequest ?? '').trim().isNotEmpty
        ? profile.prayerRequest!.trim()
        : '오늘의 기도제목을 적어 보세요.';
    final hasItems = _intercessoryPrayerItems.isNotEmpty;
    final largeText = _profileUsesLargeTextLayout(context);
    final sectionTitleStyle = TextStyle(
      color: palette.text,
      fontWeight: FontWeight.w900,
      fontSize: 14.7,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
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
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.open_in_full_rounded,
                    size: 16,
                    color: palette.mutedText,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: palette.subtleBorder),
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
                style: TextStyle(
                  color: palette.mutedText,
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
            Expanded(
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
        Container(height: 1, color: palette.subtleBorder),
        const SizedBox(height: 7),
        // 중보 기도 리스트 — 탭 카드의 남은 높이를 채움. 항목이 많으면
        // 내부에서만 스크롤해 다른 프로필 섹션 높이를 밀어내지 않는다.
        if (_intercessoryPrayerLoading && !hasItems)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_intercessoryPrayerError != null && !hasItems)
          Expanded(child: _buildIntercessoryPrayerErrorCard())
        else if (!hasItems)
          _buildIntercessoryPrayerEmptyCard(enabled: isAuthenticated)
        else
          Expanded(
            child: Stack(
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
                          child: CircularProgressIndicator(strokeWidth: 2.2),
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
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              color: palette.text,
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
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: palette.cardSurface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: palette.primaryDeep,
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
    Color? textColor,
    double fontSize = 12.4,
    bool scaleDownSingleLine = false,
  }) {
    final palette = AppPaletteTheme.of(context);
    final textWidget = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: scaleDownSingleLine ? 1 : null,
      style: TextStyle(
        color: textColor ?? palette.mutedText,
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
                  Text(
                    '...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppPaletteTheme.of(context).mutedText,
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
    var storyFilter = _StoryProgressFilter.all;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final palette = AppPaletteTheme.of(context);
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
            final filteredEvents = switch (storyFilter) {
              _StoryProgressFilter.all => selectedEvents,
              _StoryProgressFilter.completed =>
                selectedEvents
                    .where(
                      (event) => state.completedEventIds.contains(event.id),
                    )
                    .toList(growable: false),
              _StoryProgressFilter.incomplete =>
                selectedEvents
                    .where(
                      (event) => !state.completedEventIds.contains(event.id),
                    )
                    .toList(growable: false),
            };
            final filteredEmptyText = switch (storyFilter) {
              _StoryProgressFilter.all => '이 시대의 이야기가 없습니다.',
              _StoryProgressFilter.completed => '완료한 이야기가 없습니다.',
              _StoryProgressFilter.incomplete => '미완료 이야기가 없습니다.',
            };
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
                                Text(
                                  '이야기 진행률',
                                  style: TextStyle(
                                    color: palette.text,
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
                                _StoryProgressFilterTabs(
                                  selectedFilter: storyFilter,
                                  onChanged: (filter) {
                                    setDialogState(() {
                                      storyFilter = filter;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: ProfileEventReviewGrid(
                                    events: filteredEvents,
                                    eras: state.eras,
                                    charactersByCode: charactersByCode,
                                    completedEventIds: state.completedEventIds,
                                    eventEmotionMarks: state.eventEmotionMarks,
                                    quizAttemptSummaries:
                                        state.quizAttemptSummaries,
                                    emptyText: filteredEmptyText,
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
            final palette = AppPaletteTheme.of(context);
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
                                Text(
                                  '통독 진행률',
                                  style: TextStyle(
                                    color: palette.text,
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
                                color: AppColors.ink900,
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
                                color: AppColors.ink900,
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
          colors: [AppColors.goldHi, AppColors.gold],
        ),
        border: Border.all(color: AppColors.goldDeep, width: 1.4),
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

class _ProfileIconTabButton extends StatelessWidget {
  const _ProfileIconTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: SizedBox.expand(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: selected
                    ? _profileSelectedTabButtonSurface(accent)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: selected
                    ? Border.all(
                        color: AppColors.fgOnDark.withValues(alpha: 0.38),
                      )
                    : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    width: largeText ? 26 : 28,
                    height: largeText ? 26 : 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.fgOnDark.withValues(alpha: 0.88)
                          : Color.alphaBlend(
                              accent.withValues(alpha: 0.08),
                              AppColors.parchmentCream,
                            ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.fgOnDark.withValues(alpha: 0.48)
                            : palette.subtleBorder.withValues(alpha: 0.58),
                        width: selected ? 1.0 : 0.7,
                      ),
                    ),
                    child: Icon(icon, color: accent, size: 16.5),
                  ),
                  SizedBox(width: largeText ? 3 : 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? AppColors.fgOnDark : palette.text,
                          fontSize: largeText ? 11.0 : 11.6,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRecordsDashboard extends StatelessWidget {
  const _ProfileRecordsDashboard({
    required this.storyProgress,
    required this.bibleProgress,
    required this.quizStats,
    required this.onTapStory,
    required this.onTapBible,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ({int completed, int total, double fraction}) storyProgress;
  final ({int completed, int total, double fraction}) bibleProgress;
  final ProfileQuizStats quizStats;
  final VoidCallback onTapStory;
  final VoidCallback onTapBible;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 136,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _ProfileOverallProgressButton(
                  icon: Icons.menu_book_rounded,
                  label: '통독 진행률',
                  completed: bibleProgress.completed,
                  total: bibleProgress.total,
                  fraction: bibleProgress.fraction,
                  color: AppPaletteTheme.of(context).primary,
                  onTap: onTapBible,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: _ProfileStoryQuizProgressPanel(
                  storyProgress: storyProgress,
                  quizStats: quizStats,
                  onTapStory: onTapStory,
                  onTapWrong: onTapWrong,
                  onTapConfused: onTapConfused,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileStoryQuizProgressPanel extends StatelessWidget {
  const _ProfileStoryQuizProgressPanel({
    required this.storyProgress,
    required this.quizStats,
    required this.onTapStory,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ({int completed, int total, double fraction}) storyProgress;
  final ProfileQuizStats quizStats;
  final VoidCallback onTapStory;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final storyColor = palette.regionAccent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final statsWidth = (constraints.maxWidth * 0.48)
            .clamp(102.0, 128.0)
            .toDouble();
        return Container(
          padding: EdgeInsets.all(largeText ? 6 : 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              storyColor.withValues(alpha: 0.052),
              AppColors.parchmentCream,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.subtleBorder, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTapStory,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: largeText ? 1 : 2,
                      ),
                      child: _ProfileProgressSummaryContent(
                        icon: Icons.auto_stories_rounded,
                        label: '이야기 진행률',
                        completed: storyProgress.completed,
                        total: storyProgress.total,
                        fraction: storyProgress.fraction,
                        color: storyColor,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                margin: EdgeInsets.symmetric(
                  horizontal: largeText ? 5 : 7,
                  vertical: 4,
                ),
                color: palette.subtleBorder.withValues(alpha: 0.78),
              ),
              SizedBox(
                width: statsWidth,
                child: _ProfileQuizStatsColumn(
                  stats: quizStats,
                  onTapWrong: onTapWrong,
                  onTapConfused: onTapConfused,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileQuizStatsColumn extends StatelessWidget {
  const _ProfileQuizStatsColumn({
    required this.stats,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ProfileQuizStats stats;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final itemGap = largeText ? 2.0 : 5.0;
    final items = [
      _ProfileQuizStatItem(
        icon: Icons.check_rounded,
        label: '정답',
        count: stats.correct,
        eventCount: stats.correctEventCount,
        color: palette.successBottom,
        onTap: null,
      ),
      _ProfileQuizStatItem(
        icon: Icons.close_rounded,
        label: '오답',
        count: stats.wrong,
        eventCount: stats.wrongEventCount,
        color: AppColors.dangerBot,
        onTap: onTapWrong,
      ),
      _ProfileQuizStatItem(
        icon: Icons.question_mark_rounded,
        label: '헷갈려요',
        count: stats.confused,
        eventCount: stats.confusedEventCount,
        color: palette.currentAccentDeep,
        onTap: onTapConfused,
      ),
    ];
    return Flex(
      direction: Axis.vertical,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: items[i]),
          if (i != items.length - 1) SizedBox(height: itemGap),
        ],
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
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 124),
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.045),
              AppColors.parchmentCream,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.subtleBorder, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: _ProfileProgressSummaryContent(
            icon: icon,
            label: label,
            completed: completed,
            total: total,
            fraction: fraction,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ProfileProgressSummaryContent extends StatelessWidget {
  const _ProfileProgressSummaryContent({
    required this.icon,
    required this.label,
    required this.completed,
    required this.total,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int completed;
  final int total;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11.6,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _ProfileProgressDonut(
          completed: completed,
          total: total,
          fraction: fraction,
          color: color,
        ),
      ],
    );
  }
}

class _ProfileProgressDonut extends StatelessWidget {
  const _ProfileProgressDonut({
    required this.completed,
    required this.total,
    required this.fraction,
    required this.color,
  });

  final int completed;
  final int total;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: fraction.clamp(0.0, 1.0).toDouble(),
              strokeWidth: 6,
              backgroundColor: color.withValues(alpha: 0.18),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$completed',
                  maxLines: 1,
                  style: TextStyle(
                    color: palette.successBottom,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: palette.successBottom.withValues(alpha: 0.18),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                '/$total',
                maxLines: 1,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 9.4,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCompletedRatioText extends StatelessWidget {
  const _ProfileCompletedRatioText({
    required this.completed,
    required this.totalLabel,
    this.fontSize = 11,
  });

  final int completed;
  final String totalLabel;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$completed',
            style: TextStyle(
              color: palette.successBottom,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(text: ' / $totalLabel'),
        ],
      ),
      maxLines: 1,
      style: TextStyle(
        color: palette.mutedText,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.0,
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
    final palette = AppPaletteTheme.of(context);
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    final largeText = _profileUsesLargeTextLayout(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.subtleBorder, width: 1),
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
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12.4,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
              Text(
                '$percent%',
                maxLines: 1,
                style: TextStyle(
                  color: palette.successBottom,
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
              backgroundColor: palette.successFill,
              color: palette.successBottom,
            ),
          ),
          const SizedBox(height: 6),
          _ProfileCompletedRatioText(
            completed: completed,
            totalLabel: '$total',
            fontSize: 11,
          ),
        ],
      ),
    );
  }
}

class _StoryProgressFilterTabs extends StatelessWidget {
  const _StoryProgressFilterTabs({
    required this.selectedFilter,
    required this.onChanged,
  });

  final _StoryProgressFilter selectedFilter;
  final ValueChanged<_StoryProgressFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final tabs = [
      (filter: _StoryProgressFilter.all, label: '전체'),
      (filter: _StoryProgressFilter.completed, label: '완료'),
      (filter: _StoryProgressFilter.incomplete, label: '미완료'),
    ];
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.subtleBorder, width: 1),
      ),
      child: Row(
        children: [
          for (final tab in tabs) ...[
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('story-progress-filter-${tab.label}'),
                  onTap: () => onChanged(tab.filter),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selectedFilter == tab.filter
                          ? palette.successBottom
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: selectedFilter == tab.filter
                            ? AppColors.fgOnDark
                            : palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (tab != tabs.last) const SizedBox(width: 3),
          ],
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
        final palette = AppPaletteTheme.of(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.softSurface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: palette.subtleBorder),
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
    final palette = AppPaletteTheme.of(context);
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
            color: completed ? palette.successFill : Colors.transparent,
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
                      color: completed
                          ? palette.successBottom
                          : palette.mutedText,
                      fontSize: AppFontSizes.body,
                      fontWeight: completed ? FontWeight.w900 : FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: palette.successBottom,
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
    final palette = AppPaletteTheme.of(context);
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    final largeText = _profileUsesLargeTextLayout(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleBorder, width: 1),
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
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: palette.successBottom,
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
              backgroundColor: palette.successFill,
              color: palette.successBottom,
            ),
          ),
          const SizedBox(height: 7),
          _ProfileCompletedRatioText(
            completed: completed,
            totalLabel: '$total장',
            fontSize: 11.5,
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
      child: Container(
        height: 1,
        color: AppColors.borderCard.withValues(alpha: 0.42),
      ),
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
        color: AppColors.borderCard.withValues(alpha: 0.42),
      ),
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
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final int eventCount;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final iconBoxSize = largeText ? 19.0 : 24.0;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 32),
      padding: EdgeInsets.symmetric(
        horizontal: largeText ? 4 : 6,
        vertical: largeText ? 1 : 4,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          AppColors.parchmentCream,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: onTap == null ? 0.26 : 0.34),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.parchmentCream.withValues(alpha: 0.84),
              border: Border.all(color: color.withValues(alpha: 0.72)),
            ),
            child: Icon(icon, size: largeText ? 12.5 : 15, color: color),
          ),
          SizedBox(width: largeText ? 3 : 5),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: largeText ? 11.0 : 12.2,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: largeText ? 1 : 2),
                  Text(
                    profileQuizCountLabel(
                      quizCount: count,
                      storyCount: eventCount,
                    ),
                    maxLines: 1,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: largeText ? 9.5 : 10.4,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ],
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
        borderRadius: BorderRadius.circular(18),
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
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: palette.selectionFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.subtleBorder, width: 1),
      ),
      child: Text(
        '$label · $count개',
        style: TextStyle(
          color: palette.text,
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
