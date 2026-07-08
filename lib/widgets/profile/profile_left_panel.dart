// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 좌측 패널 (아바타/헤더/기도 패널/이야기 탐험).
part of '../profile_tab_page.dart';

bool _profileUsesLargeTextLayout(BuildContext context) {
  return MediaQuery.textScalerOf(context).scale(1) >= 1.3;
}

DateTime _profileDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _profileSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime _profileMarkKstDate(EventEmotionMark mark) {
  final updatedAt = mark.updatedAt;
  if (updatedAt == null) {
    return _profileDateOnly(toKst(DateTime.now()));
  }
  return _profileDateOnly(kstDateForDisplay(updatedAt, now: DateTime.now()));
}

String _formatProfileDateLabel(DateTime date) {
  return '${date.month}월 ${date.day}일';
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

Color _profileIdentitySurface(AppColorPalette palette) {
  return switch (palette) {
    AppColorPalette.blackMap => palette.cardSurface,
    _ => Color.alphaBlend(
      palette.primary.withValues(alpha: 0.04),
      AppColors.parchmentCream,
    ),
  };
}

Color _profileStoryExplorationSurface(AppColorPalette palette) {
  final base = switch (palette) {
    AppColorPalette.blackMap => palette.cardSurface,
    _ => AppColors.parchmentCard,
  };
  return Color.alphaBlend(
    palette.currentAccent.withValues(
      alpha: palette == AppColorPalette.blackMap ? 0.12 : 0.08,
    ),
    base,
  );
}

Color _profileBodyShellSurface(AppColorPalette palette) {
  return switch (palette) {
    AppColorPalette.blackMap => const Color(0xFF05070B),
    _ => Colors.white,
  };
}

Color _profileOpaqueStoryCardSurface(AppColorPalette palette) {
  return switch (palette) {
    AppColorPalette.blackMap => palette.cardSurface,
    _ => Colors.white,
  };
}

Color _profileProgressPageSurface(AppColorPalette palette) {
  return switch (palette) {
    AppColorPalette.blackMap => palette.softSurface,
    _ => palette.softSurface,
  };
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
          _ProfileContentTab.prayer => _profilePrayerContentHeight(
            isAuthenticated: isAuthenticated,
          ),
          _ProfileContentTab.saved => _profileSavedStoriesContentHeight(),
          _ProfileContentTab.verses => _profileSavedVersesContentHeight(),
        };
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

  Widget _buildProfileHeader() {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '프로필',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.sectionTitle.copyWith(
                color: palette.text,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _profileTinyIconButton(
            tooltip: '공지사항과 사용법',
            onTap: widget.onOpenAppPublications,
            icon: Icons.campaign_rounded,
          ),
          const SizedBox(width: 4),
          NotificationBellButton(
            onNavigate: widget.onNavigateNotification,
            onOpenHistory: widget.onOpenNotificationHistory,
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

  Widget _buildProfileBodyShell({
    required AppUserProfile profile,
    required Widget child,
    required ({bool storyExploration, bool companionDiary, bool bibleReading})
    todayActions,
  }) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: _profileBodyShellSurface(palette),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.primaryDeep.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileIdentityCard(
              profile: profile,
              todayActions: todayActions,
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildProfileIdentityCard({
    required AppUserProfile profile,
    required ({bool storyExploration, bool companionDiary, bool bibleReading})
    todayActions,
  }) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    return Tooltip(
      message: '프로필 수정',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openProfileEditor,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: EdgeInsets.fromLTRB(
              largeText ? 14 : 16,
              largeText ? 14 : 16,
              largeText ? 14 : 16,
              largeText ? 13 : 15,
            ),
            decoration: BoxDecoration(
              color: _profileIdentitySurface(palette),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildCurrentUserAvatar(
                      profile: profile,
                      size: largeText ? 58 : 62,
                    ),
                    const SizedBox(width: 14),
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
                                    fontSize: largeText ? 11.8 : 12.6,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: profile.nickname,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: largeText ? 16.8 : 18.0,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: '님',
                                  style: TextStyle(
                                    color: palette.mutedText,
                                    fontSize: largeText ? 11.8 : 12.6,
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
                          const SizedBox(height: 5),
                          Text(
                            '오늘도 이야기 탐험, 신앙 다이어리 작성, 통독으로 하나님과 함께 해보아요!',
                            maxLines: 4,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: largeText ? 12.4 : 13.4,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.mutedText,
                      size: largeText ? 24 : 28,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildTodayProfileActionChecklist(actions: todayActions),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayActionCheck({
    required String id,
    required String label,
    required Color accent,
    required bool completed,
  }) {
    final palette = AppPaletteTheme.of(context);
    final foreground = completed ? palette.successBottom : palette.mutedText;
    final checkFill = completed
        ? palette.successBottom
        : Color.alphaBlend(
            accent.withValues(alpha: 0.07),
            palette == AppColorPalette.blackMap
                ? palette.mutedSurface
                : Colors.white,
          );
    final checkBorder = completed
        ? palette.successBottom
        : accent.withValues(alpha: 0.52);
    return AnimatedContainer(
      key: ValueKey('profile-today-action-$id-check'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: checkFill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: checkBorder, width: 1.1),
            ),
            child: completed
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                : null,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Color _todayActionAccent({
    required AppColorPalette palette,
    required bool completed,
    required Color fallback,
  }) {
    return completed ? palette.successBottom : fallback;
  }

  Widget _todayActionButton({
    required String id,
    required String label,
    required Color accent,
    required bool completed,
  }) {
    return _buildTodayActionCheck(
      id: id,
      label: label,
      accent: accent,
      completed: completed,
    );
  }

  Widget _buildTodayProfileActionChecklist({
    required ({bool storyExploration, bool companionDiary, bool bibleReading})
    actions,
  }) {
    final palette = AppPaletteTheme.of(context);
    return GestureDetector(
      key: const ValueKey('profile-today-action-checklist-info'),
      behavior: HitTestBehavior.opaque,
      onTap: _openTodayActionChecklistInfo,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '오늘 할 일:',
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 11.2,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              _todayActionButton(
                id: 'story',
                label: '이야기 탐험',
                accent: _todayActionAccent(
                  palette: palette,
                  completed: actions.storyExploration,
                  fallback: palette.currentAccentDeep,
                ),
                completed: actions.storyExploration,
              ),
              const SizedBox(width: 8),
              _todayActionButton(
                id: 'diary',
                label: '신앙 다이어리',
                accent: _todayActionAccent(
                  palette: palette,
                  completed: actions.companionDiary,
                  fallback: palette.successBottom,
                ),
                completed: actions.companionDiary,
              ),
              const SizedBox(width: 8),
              _todayActionButton(
                id: 'bible',
                label: '통독',
                accent: _todayActionAccent(
                  palette: palette,
                  completed: actions.bibleReading,
                  fallback: palette.currentAccentDeep,
                ),
                completed: actions.bibleReading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTodayActionChecklistInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final palette = AppPaletteTheme.of(dialogContext);
        return ParchmentDialog(
          title: '오늘의 할일',
          actions: [
            ParchmentDialogActionButton(
              label: '확인',
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: Text(
            '매일 이야기 탐험, 신앙 다이어리 작성, 통독 진행을 해봅시다!\n(완료 시 자동으로 체크 돼요)',
            style: TextStyle(
              color: palette.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
        );
      },
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
              icon: Icons.self_improvement_rounded,
              label: '기도',
              tab: _ProfileContentTab.prayer,
              accent: palette.characterAccent,
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

  StoryEvent? _lastEmotionMarkedEvent({
    required List<StoryEvent> events,
    required Map<String, EventEmotionMark> marks,
  }) {
    if (events.isEmpty || marks.isEmpty) {
      return null;
    }
    final eventById = {for (final event in events) event.id: event};
    final sortedMarks = marks.values.toList()..sort(_compareEmotionMarksNewest);
    for (final mark in sortedMarks) {
      final event = eventById[mark.eventId];
      if (event != null) {
        return event;
      }
    }
    return null;
  }

  List<_StoryJourneyDeckEntry> _profileStoryJourneyEntries({
    required StoryEvent? current,
    required List<StoryEvent> events,
    required List<Era> eras,
  }) {
    final ordered = _sortEventsByEraThenIndex(events, eras);
    if (ordered.isEmpty) return const [];
    if (current == null) {
      return [
        for (final event in ordered) _StoryJourneyDeckEntry(event: event),
      ];
    }
    final index = ordered.indexWhere((event) => event.id == current.id);
    if (index < 0) return const [];
    return [for (final event in ordered) _StoryJourneyDeckEntry(event: event)];
  }

  int _compareEmotionMarksNewest(EventEmotionMark a, EventEmotionMark b) {
    final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeCompare = bTime.compareTo(aTime);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return a.eventId.compareTo(b.eventId);
  }

  Widget _buildProfileStoryExplorationDashboard({
    required bool todayStoryActionCompleted,
  }) {
    final state = ref.watch(storyControllerProvider);
    final events = _profileAllEvents.isNotEmpty
        ? _profileAllEvents
        : state.events;
    final orderedJourneyEvents = _sortEventsByEraThenIndex(events, state.eras);
    final lastEmotionEvent = _lastEmotionMarkedEvent(
      events: orderedJourneyEvents,
      marks: state.eventEmotionMarks,
    );
    final journeyEntries = _profileStoryJourneyEntries(
      current: lastEmotionEvent,
      events: orderedJourneyEvents,
      eras: state.eras,
    );
    final charactersByCode = <String, Character>{
      for (final character in _profileAllPeople) character.code: character,
      for (final character in state.characters) character.code: character,
    };

    return _ProfileStoryExplorationDashboard(
      entries: journeyEntries,
      initialSelectedEventId: lastEmotionEvent?.id,
      eras: state.eras,
      charactersByCode: charactersByCode,
      eventEmotionMarks: state.eventEmotionMarks,
      quizAttemptSummaries: state.quizAttemptSummaries,
      storyProgress: _profileStoryProgress(state),
      explorationLogCount:
          state.eventEmotionMarks.length + _profileCompanionDiaryEntries.length,
      savedStoryCount: state.savedEventIds.length,
      savedVerseCount: _profileSavedVersesCount,
      todayStoryActionCompleted: todayStoryActionCompleted,
      onExploreStoriesFromHome: widget.onExploreStoriesFromHome,
      onOpenStoryProgress: _openStoryProgressPage,
      onOpenExplorationLog: _openExplorationLogPage,
      onOpenSavedStories: _openSavedStoriesOverview,
      onOpenSavedVerses: _openSavedVersesPage,
      onOpenStory: (target) {
        widget.onOpenEventDetail(
          target,
          source: ProfileEventOpenSource.targetOnly,
        );
      },
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

  Future<void> _openStoryProgressPage() async {
    final state = ref.read(storyControllerProvider);
    final events = _profileAllEvents.isNotEmpty
        ? _profileAllEvents
        : state.events;
    final eraIdsWithEvents = events.map((event) => event.eraId).toSet();
    final eras = state.eras
        .where((era) => eraIdsWithEvents.contains(era.id))
        .toList(growable: false);
    final selectedEraId = eras.firstOrNull?.id;
    final charactersByCode = <String, Character>{
      for (final character in _profileAllPeople) character.code: character,
      for (final character in state.characters) character.code: character,
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileStoryProgressPage(
          events: events,
          eras: eras,
          selectedEraId: selectedEraId,
          charactersByCode: charactersByCode,
          completedEventIds: state.completedEventIds,
          eventEmotionMarks: state.eventEmotionMarks,
          quizAttemptSummaries: state.quizAttemptSummaries,
          onOpenEventDetail: widget.onOpenEventDetail,
        ),
      ),
    );
  }

  Future<void> _openExplorationLogPage() async {
    final state = ref.read(storyControllerProvider);
    final events = _profileAllEvents.isNotEmpty
        ? _profileAllEvents
        : state.events;
    final quizStats = buildProfileQuizStats(state.quizAttemptSummaries);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileExplorationLogPage(
          events: events,
          eras: state.eras,
          charactersByCode: {
            for (final character in _profileAllPeople)
              character.code: character,
            for (final character in state.characters) character.code: character,
          },
          completedEventIds: state.completedEventIds,
          eventEmotionMarks: state.eventEmotionMarks,
          quizAttemptSummaries: state.quizAttemptSummaries,
          quizStats: quizStats,
          companionDiaryEntries: _profileCompanionDiaryEntries,
          companionDiaryLoading: _profileCompanionDiaryLoading,
          companionDiaryError: _profileCompanionDiaryError,
          onOpenEventDetail: widget.onOpenEventDetail,
        ),
      ),
    );
  }

  Future<void> _openBibleProgressDialog() async {
    final state = ref.read(storyControllerProvider);
    final lastCompletedChapter = _profileLastCompletedBibleChapter(
      state.completedBibleChapterKeys,
    );
    var selectedBookNo =
        lastCompletedChapter?.bookNo.clamp(1, bibleBooks.length).toInt() ??
        oldTestamentFirstBookNo;
    var selectedTestament = isNewTestamentBook(selectedBookNo) ? 'new' : 'old';

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
                      decoration: modalSurfaceDecoration(palette: palette),
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

  Future<void> _openBibleReaderFromLastCompletedChapter() async {
    final state = ref.read(storyControllerProvider);
    final lastCompletedChapter = _profileLastCompletedBibleChapter(
      state.completedBibleChapterKeys,
    );
    if (lastCompletedChapter == null) {
      await widget.onOpenBibleReader(
        initialBookNo: oldTestamentFirstBookNo,
        initialChapterNo: 1,
      );
      return;
    }

    final target = _nextBibleChapterAfter(
      bookNo: lastCompletedChapter.bookNo,
      chapterNo: lastCompletedChapter.chapterNo,
    );
    if (target == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마지막 장이었습니다.')));
      return;
    }
    await widget.onOpenBibleReader(
      initialBookNo: target.bookNo,
      initialChapterNo: target.chapterNo,
    );
  }

  ({int bookNo, int chapterNo})? _nextBibleChapterAfter({
    required int bookNo,
    required int chapterNo,
  }) {
    final safeBookNo = bookNo.clamp(1, bibleBooks.length).toInt();
    final maxChapter = bibleBooks[safeBookNo - 1].chapters;
    final safeChapterNo = chapterNo.clamp(1, maxChapter).toInt();

    if (safeChapterNo < maxChapter) {
      return (bookNo: safeBookNo, chapterNo: safeChapterNo + 1);
    }
    if (safeBookNo < bibleBooks.length) {
      return (bookNo: safeBookNo + 1, chapterNo: 1);
    }
    return null;
  }

  ({int bookNo, int chapterNo})? _profileLastCompletedBibleChapter(
    Set<String> completedChapterKeys,
  ) {
    ({int bookNo, int chapterNo})? latest;
    for (var bookNo = 1; bookNo <= bibleBooks.length; bookNo += 1) {
      final maxChapter = bibleBooks[bookNo - 1].chapters;
      for (var chapterNo = 1; chapterNo <= maxChapter; chapterNo += 1) {
        final key = bibleChapterProgressKey(
          bookNo: bookNo,
          chapterNo: chapterNo,
        );
        if (completedChapterKeys.contains(key)) {
          latest = (bookNo: bookNo, chapterNo: chapterNo);
        }
      }
    }
    return latest;
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
    ProfileEventDetailCallback? onOpenEventDetail,
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
                  onTap: () {
                    final openDetail =
                        onOpenEventDetail ?? widget.onOpenEventDetail;
                    openDetail(event);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSavedStoriesOverview() async {
    final state = ref.read(storyControllerProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParchmentListPageScaffold(
          title: '저장한 이야기',
          child: ParchmentCard(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: _profileSavedEventsPreview.isEmpty
                ? const Center(
                    child: Text(
                      '아직 저장한 이야기가 없습니다.\n사건 상세에서 별표를 눌러 저장해 보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink300,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                        height: 1.55,
                      ),
                    ),
                  )
                : _buildEventGroupsByEra(
                    events: _profileSavedEventsPreview,
                    state: state,
                    onOpenEventDetail: (event, {source}) =>
                        widget.onOpenEventDetail(
                          event,
                          source: ProfileEventOpenSource.detailOnly,
                        ),
                  ),
          ),
        ),
      ),
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

class _ProfileStoryExplorationDashboard extends StatelessWidget {
  const _ProfileStoryExplorationDashboard({
    required this.entries,
    required this.initialSelectedEventId,
    required this.eras,
    required this.charactersByCode,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.storyProgress,
    required this.explorationLogCount,
    required this.savedStoryCount,
    required this.savedVerseCount,
    required this.todayStoryActionCompleted,
    required this.onExploreStoriesFromHome,
    required this.onOpenStoryProgress,
    required this.onOpenExplorationLog,
    required this.onOpenSavedStories,
    required this.onOpenSavedVerses,
    required this.onOpenStory,
  });

  final List<_StoryJourneyDeckEntry> entries;
  final String? initialSelectedEventId;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final ({int completed, int total, double fraction}) storyProgress;
  final int explorationLogCount;
  final int savedStoryCount;
  final int savedVerseCount;
  final bool todayStoryActionCompleted;
  final VoidCallback? onExploreStoriesFromHome;
  final VoidCallback onOpenStoryProgress;
  final VoidCallback onOpenExplorationLog;
  final VoidCallback onOpenSavedStories;
  final VoidCallback onOpenSavedVerses;
  final ValueChanged<StoryEvent> onOpenStory;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: _profileStoryExplorationSurface(palette),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StoryExplorationSummarySection(
            storyProgress: storyProgress,
            explorationLogCount: explorationLogCount,
            savedStoryCount: savedStoryCount,
            savedVerseCount: savedVerseCount,
            onOpenStoryProgress: onOpenStoryProgress,
            onOpenExplorationLog: onOpenExplorationLog,
            onOpenSavedStories: onOpenSavedStories,
            onOpenSavedVerses: onOpenSavedVerses,
          ),
          const SizedBox(height: 10),
          _ProfileStoryJourneyDeck(
            entries: entries,
            initialSelectedEventId: initialSelectedEventId,
            eras: eras,
            charactersByCode: charactersByCode,
            eventEmotionMarks: eventEmotionMarks,
            quizAttemptSummaries: quizAttemptSummaries,
            todayStoryActionCompleted: todayStoryActionCompleted,
            onExploreStoriesFromHome: onExploreStoriesFromHome,
            onOpenStory: onOpenStory,
          ),
          const SizedBox(height: 7),
          const _StoryJourneyGuideNote(),
        ],
      ),
    );
  }
}

class _StoryExplorationSummarySection extends StatelessWidget {
  const _StoryExplorationSummarySection({
    required this.storyProgress,
    required this.explorationLogCount,
    required this.savedStoryCount,
    required this.savedVerseCount,
    required this.onOpenStoryProgress,
    required this.onOpenExplorationLog,
    required this.onOpenSavedStories,
    required this.onOpenSavedVerses,
  });

  final ({int completed, int total, double fraction}) storyProgress;
  final int explorationLogCount;
  final int savedStoryCount;
  final int savedVerseCount;
  final VoidCallback onOpenStoryProgress;
  final VoidCallback onOpenExplorationLog;
  final VoidCallback onOpenSavedStories;
  final VoidCallback onOpenSavedVerses;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final totalLabel = math.max(storyProgress.total, 301);
    TextSpan countUnitSpan() {
      return TextSpan(
        text: '개',
        style: TextStyle(
          color: palette.mutedText,
          fontSize: 11.4,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    Widget countValue(int count, {InlineSpan? trailing}) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$count'),
            if (trailing != null) trailing,
            countUnitSpan(),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileDashboardTitle(
          icon: Icons.bar_chart_rounded,
          label: '이야기 탐험 요약',
          color: palette.currentAccentDeep,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _StoryExplorationSummaryCard(
                key: const ValueKey('profile-story-summary-explored'),
                label: '완료',
                icon: Icons.flag_rounded,
                color: palette.primary,
                onTap: onOpenStoryProgress,
                value: countValue(
                  storyProgress.completed,
                  trailing: TextSpan(
                    text: '/$totalLabel',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: _StoryExplorationSummaryCard(
                key: const ValueKey('profile-story-summary-exploration-log'),
                label: '기록',
                icon: Icons.history_rounded,
                color: palette.currentAccentDeep,
                onTap: onOpenExplorationLog,
                value: countValue(explorationLogCount),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: _StoryExplorationSummaryCard(
                key: const ValueKey('profile-story-summary-saved-stories'),
                label: '저장',
                icon: Icons.bookmark_rounded,
                color: palette.successBottom,
                onTap: onOpenSavedStories,
                value: countValue(savedStoryCount),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: _StoryExplorationSummaryCard(
                key: const ValueKey('profile-story-summary-saved-verses'),
                label: '말씀',
                icon: Icons.menu_book_rounded,
                color: palette.primaryDeep,
                onTap: onOpenSavedVerses,
                value: countValue(savedVerseCount),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StoryExplorationSummaryCard extends StatelessWidget {
  const _StoryExplorationSummaryCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final labelIconSize = largeText ? 15.6 : 17.4;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  color.withValues(alpha: 0.10),
                  palette.cardSurface,
                ),
                Color.alphaBlend(
                  color.withValues(alpha: 0.045),
                  palette.softSurface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.36),
              width: 1.0,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, largeText ? 7 : 8, 8, 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(icon, size: labelIconSize, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                          softWrap: true,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: largeText ? 11.2 : 12.1,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  DefaultTextStyle(
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: largeText ? 14.8 : 16.2,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                    child: FittedBox(fit: BoxFit.scaleDown, child: value),
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

class _StoryJourneyGuideNote extends StatelessWidget {
  const _StoryJourneyGuideNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.currentAccent.withValues(alpha: 0.055),
            palette.softSurface,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 3,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: palette.currentAccentDeep.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '참고',
                style: TextStyle(
                  color: palette.currentAccentDeep,
                  fontSize: 10.2,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            Text(
              '카드를 눌러 탐험하세요! (완료조건: 감정 새기기)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 10.6,
                fontWeight: FontWeight.w800,
                height: 1.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStoryProgressPage extends StatefulWidget {
  const _ProfileStoryProgressPage({
    required this.events,
    required this.eras,
    required this.selectedEraId,
    required this.charactersByCode,
    required this.completedEventIds,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.onOpenEventDetail,
  });

  final List<StoryEvent> events;
  final List<Era> eras;
  final String? selectedEraId;
  final Map<String, Character> charactersByCode;
  final Set<String> completedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final ProfileEventDetailCallback onOpenEventDetail;

  @override
  State<_ProfileStoryProgressPage> createState() =>
      _ProfileStoryProgressPageState();
}

class _ProfileStoryProgressPageState extends State<_ProfileStoryProgressPage> {
  String? _selectedEraId;
  _StoryProgressFilter _storyFilter = _StoryProgressFilter.all;

  @override
  void initState() {
    super.initState();
    _selectedEraId = widget.selectedEraId;
  }

  @override
  void didUpdateWidget(covariant _ProfileStoryProgressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasSelected = widget.eras.any((era) => era.id == _selectedEraId);
    if (!hasSelected || oldWidget.selectedEraId != widget.selectedEraId) {
      _selectedEraId = widget.selectedEraId;
    }
  }

  void _openEventDetail(StoryEvent event) {
    widget.onOpenEventDetail(event, source: ProfileEventOpenSource.detailOnly);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final selectedEra = widget.eras
        .where((era) => era.id == _selectedEraId)
        .firstOrNull;
    final selectedEvents = selectedEra == null
        ? const <StoryEvent>[]
        : widget.events
              .where((event) => event.eraId == selectedEra.id)
              .toList(growable: false);
    final selectedCompletedCount = selectedEvents
        .where((event) => widget.completedEventIds.contains(event.id))
        .length;
    final selectedFraction = selectedEvents.isEmpty
        ? 0.0
        : (selectedCompletedCount / selectedEvents.length)
              .clamp(0.0, 1.0)
              .toDouble();
    final filteredEvents = switch (_storyFilter) {
      _StoryProgressFilter.all => selectedEvents,
      _StoryProgressFilter.completed =>
        selectedEvents
            .where((event) => widget.completedEventIds.contains(event.id))
            .toList(growable: false),
      _StoryProgressFilter.incomplete =>
        selectedEvents
            .where((event) => !widget.completedEventIds.contains(event.id))
            .toList(growable: false),
    };
    final filteredEmptyText = switch (_storyFilter) {
      _StoryProgressFilter.all => '이 시대의 이야기가 없습니다.',
      _StoryProgressFilter.completed => '완료한 이야기가 없습니다.',
      _StoryProgressFilter.incomplete => '미완료 이야기가 없습니다.',
    };
    return ParchmentListPageScaffold(
      title: '탐험한 이야기',
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: _profileProgressPageSurface(palette),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ProfileProgressPageSectionTitle(label: '이야기 진행률'),
              const SizedBox(height: 10),
              EraPickRows(
                eras: widget.eras,
                selectedEraId: _selectedEraId,
                onSelectEra: (eraId) {
                  setState(() {
                    _selectedEraId = eraId;
                    _storyFilter = _StoryProgressFilter.all;
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
                selectedFilter: _storyFilter,
                onChanged: (filter) {
                  setState(() => _storyFilter = filter);
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 520,
                child: ProfileEventReviewGrid(
                  key: const ValueKey('story-progress-review-grid'),
                  events: filteredEvents,
                  eras: widget.eras,
                  charactersByCode: widget.charactersByCode,
                  completedEventIds: widget.completedEventIds,
                  eventEmotionMarks: widget.eventEmotionMarks,
                  quizAttemptSummaries: widget.quizAttemptSummaries,
                  emptyText: filteredEmptyText,
                  onOpenEventDetail: _openEventDetail,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProfileInlineReviewFilter { correct, wrong, confused }

class _ProfileExplorationLogPage extends StatefulWidget {
  const _ProfileExplorationLogPage({
    required this.events,
    required this.eras,
    required this.charactersByCode,
    required this.completedEventIds,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.quizStats,
    required this.companionDiaryEntries,
    required this.companionDiaryLoading,
    required this.companionDiaryError,
    required this.onOpenEventDetail,
  });

  final List<StoryEvent> events;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Set<String> completedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final ProfileQuizStats quizStats;
  final List<UserCompanionDiaryEntry> companionDiaryEntries;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final ProfileEventDetailCallback onOpenEventDetail;

  @override
  State<_ProfileExplorationLogPage> createState() =>
      _ProfileExplorationLogPageState();
}

class _ProfileExplorationLogPageState
    extends State<_ProfileExplorationLogPage> {
  DateTime _selectedLogDate = _profileDateOnly(toKst(DateTime.now()));
  _ProfileInlineReviewFilter? _selectedReviewFilter;

  void _openEventDetail(StoryEvent event) {
    widget.onOpenEventDetail(event, source: ProfileEventOpenSource.detailOnly);
  }

  Future<void> _openCompanionDiaryDetail(UserCompanionDiaryEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CompanionDiaryEntryDetailDialog(entry: entry),
    );
  }

  void _openEmotionMarksPopup({
    required String title,
    required List<EventEmotionMark> marks,
    required Map<String, StoryEvent> eventById,
    required String emptyMessage,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = AppPaletteTheme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.74;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.subtleBorder, width: 1),
                boxShadow: AppShadows.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: palette.mutedText,
                      ),
                    ],
                  ),
                  Divider(height: 10, color: palette.subtleBorder),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ProfileEmotionMarksList(
                        key: const ValueKey('emotion-marks-category-list'),
                        marks: marks,
                        eventById: eventById,
                        emptyMessage: emptyMessage,
                        loading: false,
                        hasError: false,
                        showTimestamp: true,
                        onOpenEventDetail: (event) {
                          Navigator.of(sheetContext).pop();
                          if (!mounted) return;
                          _openEventDetail(event);
                        },
                      ),
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

  void _openReviewEventsPopup({
    required String title,
    required List<StoryEvent> events,
    required String emptyText,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = AppPaletteTheme.of(sheetContext);
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.78;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.subtleBorder, width: 1),
                boxShadow: AppShadows.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: palette.mutedText,
                      ),
                    ],
                  ),
                  Divider(height: 10, color: palette.subtleBorder),
                  Expanded(
                    child: ProfileEventReviewGrid(
                      key: const ValueKey('exploration-log-review-all-grid'),
                      events: events,
                      eras: widget.eras,
                      charactersByCode: widget.charactersByCode,
                      completedEventIds: widget.completedEventIds,
                      eventEmotionMarks: widget.eventEmotionMarks,
                      quizAttemptSummaries: widget.quizAttemptSummaries,
                      emptyText: emptyText,
                      onOpenEventDetail: (event) {
                        Navigator.of(sheetContext).pop();
                        if (!mounted) return;
                        _openEventDetail(event);
                      },
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

  List<StoryEvent> _reviewEventsForFilter(_ProfileInlineReviewFilter? filter) {
    final selectedEventIds = switch (filter) {
      _ProfileInlineReviewFilter.correct => widget.quizStats.correctEventIds,
      _ProfileInlineReviewFilter.wrong => widget.quizStats.wrongEventIds,
      _ProfileInlineReviewFilter.confused => widget.quizStats.confusedEventIds,
      null => null,
    };
    if (selectedEventIds == null) {
      return const <StoryEvent>[];
    }
    return widget.events
        .where((event) => selectedEventIds.contains(event.id))
        .toList(growable: false);
  }

  String _reviewTitleForFilter(_ProfileInlineReviewFilter filter) {
    return switch (filter) {
      _ProfileInlineReviewFilter.correct => '정답 이야기',
      _ProfileInlineReviewFilter.wrong => '오답 이야기',
      _ProfileInlineReviewFilter.confused => '헷갈려요 이야기',
    };
  }

  String _emptyTextForReviewFilter(_ProfileInlineReviewFilter? filter) {
    return switch (filter) {
      _ProfileInlineReviewFilter.correct => '정답으로 기록된 이야기가 없습니다.',
      _ProfileInlineReviewFilter.wrong => '오답으로 기록된 이야기가 없습니다.',
      _ProfileInlineReviewFilter.confused => '헷갈려요로 기록된 이야기가 없습니다.',
      null => '오답이나 헷갈려요를 누르면 이야기 카드가 나타납니다.',
    };
  }

  List<EventEmotionMark> _marksForDate(
    List<EventEmotionMark> marks,
    DateTime date,
  ) {
    final targetDate = _profileDateOnly(date);
    return marks
        .where(
          (mark) => _profileSameDate(_profileMarkKstDate(mark), targetDate),
        )
        .toList(growable: false);
  }

  UserCompanionDiaryEntry? _companionDiaryForDate(DateTime date) {
    final targetDate = _profileDateOnly(date);
    UserCompanionDiaryEntry? selected;
    for (final entry in widget.companionDiaryEntries) {
      if (!_profileSameDate(entry.entryDate, targetDate)) {
        continue;
      }
      if (selected == null || entry.updatedAt.isAfter(selected.updatedAt)) {
        selected = entry;
      }
    }
    return selected;
  }

  void _toggleReviewFilter(_ProfileInlineReviewFilter filter) {
    if (filter == _ProfileInlineReviewFilter.correct) {
      return;
    }
    setState(() {
      _selectedReviewFilter = _selectedReviewFilter == filter ? null : filter;
    });
  }

  Widget _buildInlineReviewEvents() {
    final palette = AppPaletteTheme.of(context);
    final selectedFilter = _selectedReviewFilter;
    final selectedEvents = _reviewEventsForFilter(selectedFilter);
    final previewEvents = selectedEvents.take(9).toList(growable: false);
    final hasMore = selectedEvents.length > previewEvents.length;
    final emptyText = _emptyTextForReviewFilter(selectedFilter);
    return selectedFilter == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 12.6,
                fontWeight: FontWeight.w800,
                height: 1.45,
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileEventReviewGrid(
                key: ValueKey(
                  'exploration-log-review-grid-${selectedFilter.name}',
                ),
                events: previewEvents,
                eras: widget.eras,
                charactersByCode: widget.charactersByCode,
                completedEventIds: widget.completedEventIds,
                eventEmotionMarks: widget.eventEmotionMarks,
                quizAttemptSummaries: widget.quizAttemptSummaries,
                emptyText: emptyText,
                padding: EdgeInsets.zero,
                scrollable: false,
                onOpenEventDetail: _openEventDetail,
              ),
              if (hasMore) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    key: ValueKey(
                      'exploration-log-review-open-all-${selectedFilter.name}',
                    ),
                    onPressed: () => _openReviewEventsPopup(
                      title: _reviewTitleForFilter(selectedFilter),
                      events: selectedEvents,
                      emptyText: emptyText,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      foregroundColor: palette.currentAccentDeep,
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: const Text('전체 보기'),
                  ),
                ),
              ],
            ],
          );
  }

  Widget _buildReviewSection() {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: const ValueKey('exploration-log-review-events'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ProfileProgressPageSectionTitle(label: '복습 항목'),
          const SizedBox(height: 10),
          _ProfileQuizStatsColumn(
            stats: widget.quizStats,
            selectedFilter: _selectedReviewFilter,
            onTapWrong: () =>
                _toggleReviewFilter(_ProfileInlineReviewFilter.wrong),
            onTapConfused: () =>
                _toggleReviewFilter(_ProfileInlineReviewFilter.confused),
          ),
          Divider(height: 18, color: palette.subtleBorder),
          _buildInlineReviewEvents(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final eventById = {for (final event in widget.events) event.id: event};
    final marks = widget.eventEmotionMarks.values.toList()
      ..sort((a, b) {
        final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeCompare = bTime.compareTo(aTime);
        if (timeCompare != 0) {
          return timeCompare;
        }
        return a.eventId.compareTo(b.eventId);
      });
    final selectedDateMarks = _marksForDate(marks, _selectedLogDate);
    final selectedDateDiary = _companionDiaryForDate(_selectedLogDate);
    final emotionCountsByKey = {
      for (final option in EventEmotionOption.options)
        option.key: marks.where((mark) => mark.emotionKey == option.key).length,
    };

    return ParchmentListPageScaffold(
      title: '기록',
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: palette.cardSurface.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildReviewSection(),
              const _ProfileProgressPageDivider(),
              _ExplorationTracePanel(
                categoryRow: _EmotionCategoryRow(
                  countsByKey: emotionCountsByKey,
                  onOpenCategory: (option) {
                    final categoryMarks = marks
                        .where((mark) => mark.emotionKey == option.key)
                        .toList(growable: false);
                    _openEmotionMarksPopup(
                      title: '${option.emoji} ${option.label} 코멘트',
                      marks: categoryMarks,
                      eventById: eventById,
                      emptyMessage: '${option.label}로 새긴 코멘트가 없습니다.',
                    );
                  },
                ),
                calendar: ProfileEmotionDiary(
                  eventEmotionMarks: widget.eventEmotionMarks,
                  companionDiaryEntries: widget.companionDiaryEntries,
                  companionDiaryLoading: widget.companionDiaryLoading,
                  companionDiaryError: widget.companionDiaryError,
                  showFeatureCards: false,
                  onSelectedDateChanged: (date) {
                    setState(() => _selectedLogDate = _profileDateOnly(date));
                  },
                ),
                previewPanel: _EmotionMarksPreviewPanel(
                  selectedDate: _selectedLogDate,
                  marks: selectedDateMarks,
                  selectedDateDiary: selectedDateDiary,
                  companionDiaryLoading: widget.companionDiaryLoading,
                  companionDiaryError: widget.companionDiaryError,
                  eventById: eventById,
                  onOpenEventDetail: _openEventDetail,
                  onOpenCompanionDiaryDetail: _openCompanionDiaryDetail,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplorationTracePanel extends StatelessWidget {
  const _ExplorationTracePanel({
    required this.categoryRow,
    required this.calendar,
    required this.previewPanel,
  });

  final Widget categoryRow;
  final Widget calendar;
  final Widget previewPanel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ProfileProgressPageSectionTitle(label: '탐험 달력과 흔적들'),
          const SizedBox(height: 8),
          categoryRow,
          Divider(height: 18, color: palette.subtleBorder),
          calendar,
          const SizedBox(height: 10),
          previewPanel,
        ],
      ),
    );
  }
}

class _EmotionMarksPreviewPanel extends StatelessWidget {
  const _EmotionMarksPreviewPanel({
    required this.selectedDate,
    required this.marks,
    required this.selectedDateDiary,
    required this.companionDiaryLoading,
    required this.companionDiaryError,
    required this.eventById,
    required this.onOpenEventDetail,
    required this.onOpenCompanionDiaryDetail,
  });

  final DateTime selectedDate;
  final List<EventEmotionMark> marks;
  final UserCompanionDiaryEntry? selectedDateDiary;
  final bool companionDiaryLoading;
  final String? companionDiaryError;
  final Map<String, StoryEvent> eventById;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final ValueChanged<UserCompanionDiaryEntry> onOpenCompanionDiaryDetail;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final dateLabel = _formatProfileDateLabel(selectedDate);
    final hasEmotionMarks = marks.isNotEmpty;
    final hasDiary = selectedDateDiary != null;
    final hasDiaryMessage =
        companionDiaryLoading || companionDiaryError != null || hasDiary;
    return Column(
      key: const ValueKey('emotion-marks-review-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$dateLabel 기록',
          key: const ValueKey('emotion-marks-selected-date-label'),
          style: TextStyle(
            color: palette.text,
            fontSize: 12.2,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        if (!hasEmotionMarks && !hasDiaryMessage)
          const _ProfileLogEmptyMessage(
            message: '선택한 날짜에 새긴 감정과 코멘트 혹은 신앙 다이어리가 없습니다',
          )
        else ...[
          if (hasEmotionMarks)
            _SelectedDateEmotionSummary(
              marks: marks,
              eventById: eventById,
              onOpenEventDetail: onOpenEventDetail,
            ),
          if (hasEmotionMarks && hasDiaryMessage) const SizedBox(height: 8),
          if (hasDiaryMessage)
            _SelectedDateDiarySummary(
              entry: selectedDateDiary,
              loading: companionDiaryLoading,
              error: companionDiaryError,
              onTap: selectedDateDiary == null
                  ? null
                  : () => onOpenCompanionDiaryDetail(selectedDateDiary!),
            ),
        ],
      ],
    );
  }
}

class _SelectedDateEmotionSummary extends StatelessWidget {
  const _SelectedDateEmotionSummary({
    required this.marks,
    required this.eventById,
    required this.onOpenEventDetail,
  });

  final List<EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final ValueChanged<StoryEvent> onOpenEventDetail;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: const ValueKey('selected-date-emotion-comments'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.subtleBorder, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '감정과 코멘트',
            style: TextStyle(
              color: palette.currentAccentDeep,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 7),
          ProfileEmotionMarksList(
            marks: marks,
            eventById: eventById,
            emptyMessage: '선택한 날짜에 새긴 감정과 코멘트 혹은 신앙 다이어리가 없습니다',
            loading: false,
            hasError: false,
            showTimestamp: false,
            onOpenEventDetail: onOpenEventDetail,
          ),
        ],
      ),
    );
  }
}

class _EmotionCategoryRow extends StatelessWidget {
  const _EmotionCategoryRow({
    required this.countsByKey,
    required this.onOpenCategory,
  });

  final Map<String, int> countsByKey;
  final ValueChanged<EventEmotionOption> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < EventEmotionOption.options.length; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: index == 0 ? 0 : 2,
                right: index == EventEmotionOption.options.length - 1 ? 0 : 2,
              ),
              child: _EmotionCategoryButton(
                option: EventEmotionOption.options[index],
                count: countsByKey[EventEmotionOption.options[index].key] ?? 0,
                onTap: () => onOpenCategory(EventEmotionOption.options[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmotionCategoryButton extends StatelessWidget {
  const _EmotionCategoryButton({
    required this.option,
    required this.count,
    required this.onTap,
  });

  final EventEmotionOption option;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Tooltip(
      message: option.label,
      child: Material(
        color: Color.alphaBlend(
          palette.currentAccent.withValues(alpha: 0.06),
          palette.cardSurface,
        ),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('emotion-category-${option.key}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 45),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.subtleBorder, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    option.emoji,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 17, height: 1),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${option.label} $count',
                    maxLines: 1,
                    style: TextStyle(
                      color: palette.currentAccentDeep,
                      fontSize: 8.8,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedDateDiarySummary extends StatelessWidget {
  const _SelectedDateDiarySummary({
    required this.entry,
    required this.loading,
    required this.error,
    this.onTap,
  });

  final UserCompanionDiaryEntry? entry;
  final bool loading;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final currentEntry = entry;
    if (loading && currentEntry == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    if (currentEntry == null) {
      return _ProfileLogEmptyMessage(
        message: error ?? '선택한 날짜에 남긴 신앙 다이어리가 없습니다.',
      );
    }
    return Material(
      key: const ValueKey('selected-date-companion-diary'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: palette.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.subtleBorder, width: 0.9),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SelectedDateDiaryBadge(),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '신앙 다이어리',
                      style: TextStyle(
                        color: palette.successBottom,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      currentEntry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w900,
                        height: 1.24,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      currentEntry.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.38,
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
  }
}

class _SelectedDateDiaryBadge extends StatelessWidget {
  const _SelectedDateDiaryBadge();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.successFill,
        border: Border.all(
          color: palette.successBottom.withValues(alpha: 0.42),
        ),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('📝', style: TextStyle(fontSize: 17, height: 1)),
      ),
    );
  }
}

class _ProfileLogEmptyMessage extends StatelessWidget {
  const _ProfileLogEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.mutedText,
          fontSize: 12.4,
          fontWeight: FontWeight.w700,
          height: 1.42,
        ),
      ),
    );
  }
}

class _ProfileProgressPageDivider extends StatelessWidget {
  const _ProfileProgressPageDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppPaletteTheme.of(context).subtleBorder.withValues(alpha: 0.72),
      ),
    );
  }
}

class _ProfileProgressPageSectionTitle extends StatelessWidget {
  const _ProfileProgressPageSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.sectionTitle.copyWith(
        color: palette.text,
        fontSize: 14.8,
      ),
    );
  }
}

class _ProfileDashboardTitle extends StatelessWidget {
  const _ProfileDashboardTitle({
    required this.icon,
    required this.label,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, size: 14.5, color: color),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionTitle.copyWith(
              color: palette.text,
              fontSize: AppFontSizes.input,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _StoryJourneyDeckEntry {
  const _StoryJourneyDeckEntry({required this.event});

  final StoryEvent? event;
}

class _StoryJourneyDeckLayoutItem {
  const _StoryJourneyDeckLayoutItem({
    required this.index,
    required this.slot,
    required this.entry,
  });

  final int index;
  final int slot;
  final _StoryJourneyDeckEntry entry;
}

class _ProfileStoryJourneyDeck extends StatefulWidget {
  const _ProfileStoryJourneyDeck({
    required this.entries,
    required this.initialSelectedEventId,
    required this.eras,
    required this.charactersByCode,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.todayStoryActionCompleted,
    required this.onExploreStoriesFromHome,
    required this.onOpenStory,
  });

  final List<_StoryJourneyDeckEntry> entries;
  final String? initialSelectedEventId;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final bool todayStoryActionCompleted;
  final VoidCallback? onExploreStoriesFromHome;
  final ValueChanged<StoryEvent> onOpenStory;

  @override
  State<_ProfileStoryJourneyDeck> createState() =>
      _ProfileStoryJourneyDeckState();
}

class _ProfileStoryJourneyDeckState extends State<_ProfileStoryJourneyDeck> {
  String? _mainEventId;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _mainEventId = _resolvedInitialMainEventId();
  }

  @override
  void didUpdateWidget(covariant _ProfileStoryJourneyDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasSelected = widget.entries.any(
      (entry) => entry.event?.id == _mainEventId,
    );
    if (!hasSelected ||
        oldWidget.initialSelectedEventId != widget.initialSelectedEventId) {
      _mainEventId = _resolvedInitialMainEventId();
    }
  }

  int _recentIndex() {
    final recentId = widget.initialSelectedEventId;
    if (recentId == null) return -1;
    return widget.entries.indexWhere((entry) => entry.event?.id == recentId);
  }

  int _initialMainIndex() {
    final recentIndex = _recentIndex();
    if (recentIndex < 0) return widget.entries.isEmpty ? -1 : 0;
    final nextIndex = recentIndex + 1;
    if (nextIndex < widget.entries.length) {
      return nextIndex;
    }
    return recentIndex;
  }

  String? _resolvedInitialMainEventId() {
    final index = _initialMainIndex();
    if (index < 0 || index >= widget.entries.length) return null;
    return widget.entries[index].event?.id;
  }

  int _mainIndex() {
    final index = widget.entries.indexWhere(
      (entry) => entry.event?.id == _mainEventId,
    );
    if (index >= 0) return index;
    return _initialMainIndex().clamp(0, widget.entries.length - 1).toInt();
  }

  void _resetToInitialDeck() {
    setState(() => _mainEventId = _resolvedInitialMainEventId());
  }

  void _moveMainBy(int delta) {
    if (widget.entries.isEmpty) return;
    final nextIndex = (_mainIndex() + delta).clamp(
      0,
      widget.entries.length - 1,
    );
    final nextEventId = widget.entries[nextIndex].event?.id;
    if (nextEventId == null || nextEventId == _mainEventId) {
      return;
    }
    setState(() => _mainEventId = nextEventId);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _dragDistance = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _dragDistance += details.primaryDelta ?? 0;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDistance;
    _dragDistance = 0;
    if (velocity.abs() < 180 && distance.abs() < 42) {
      return;
    }
    if (velocity < -180 || distance < -42) {
      _moveMainBy(1);
    } else if (velocity > 180 || distance > 42) {
      _moveMainBy(-1);
    }
  }

  void _handleHorizontalDragCancel() {
    _dragDistance = 0;
  }

  List<_StoryJourneyDeckLayoutItem> _visibleDeckItems(int mainIndex) {
    final count = widget.entries.length;
    if (count == 0 || mainIndex < 0) return const [];

    final targetCount = math.min(3, count);
    final slotsByIndex = <int, int>{};

    void add(int index, int slot) {
      if (index < 0 || index >= count) return;
      slotsByIndex.putIfAbsent(index, () => slot);
    }

    add(mainIndex - 1, -1);
    add(mainIndex, 0);
    add(mainIndex + 1, 1);

    var nextRight = mainIndex + 2;
    while (slotsByIndex.length < targetCount && nextRight < count) {
      add(nextRight, nextRight - mainIndex);
      nextRight += 1;
    }

    var nextLeft = mainIndex - 2;
    while (slotsByIndex.length < targetCount && nextLeft >= 0) {
      add(nextLeft, nextLeft - mainIndex);
      nextLeft -= 1;
    }

    final items = [
      for (final entry in slotsByIndex.entries)
        _StoryJourneyDeckLayoutItem(
          index: entry.key,
          slot: entry.value,
          entry: widget.entries[entry.key],
        ),
    ]..sort((a, b) => a.slot.compareTo(b.slot));
    return items;
  }

  String _labelForIndex(int index) {
    final recentIndex = _recentIndex();
    if (recentIndex < 0 && index == 0) {
      return '다음 이야기';
    }
    if (index == recentIndex) {
      return '최근 탐험 이야기';
    }
    if (recentIndex >= 0 && index == recentIndex + 1) {
      return '다음 이야기';
    }
    return '';
  }

  void _handleEntryTap(_StoryJourneyDeckEntry entry) {
    final event = entry.event;
    if (event == null) {
      return;
    }
    if (_mainEventId == event.id) {
      widget.onOpenStory(event);
      return;
    }
    setState(() => _mainEventId = event.id);
  }

  @override
  Widget build(BuildContext context) {
    const sideScale = 0.82;
    const farSideScale = 0.72;
    const sidePeekTop = 9.0;
    const farSidePeekTop = 14.0;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final largeHeight =
        198.0 + ((textScale - 1) * 140).clamp(0.0, 72.0).toDouble();
    final entries = widget.entries;
    final mainIndex = entries.isEmpty ? -1 : _mainIndex();
    final initialMainEventId = _resolvedInitialMainEventId();
    final canReset =
        initialMainEventId != null && _mainEventId != initialMainEventId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileDashboardTitle(
          icon: Icons.explore_rounded,
          label: '이야기 탐험',
          color: AppPaletteTheme.of(context).regionAccent,
          trailing: AnimatedOpacity(
            opacity: canReset ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !canReset,
              child: TextButton.icon(
                onPressed: _resetToInitialDeck,
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text('되돌아가기'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        if (entries.isEmpty)
          _EmptyStoryJourneyCtaCard(onTap: widget.onExploreStoriesFromHome)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final deckWidth = (maxWidth * 0.95).clamp(260.0, maxWidth);
              final deckLeft = (maxWidth - deckWidth) / 2;
              final deckRight = deckLeft + deckWidth;
              final largeWidth = (deckWidth * 0.50).clamp(162.0, 250.0);
              final sideWidth = (deckWidth * 0.35).clamp(116.0, 194.0);
              final farSideWidth = (deckWidth * 0.30).clamp(96.0, 170.0);
              final sideHeight = largeHeight * sideScale;
              final farSideHeight = largeHeight * farSideScale;
              final deckHeight = largeHeight;
              final largeLeft = (deckLeft + deckWidth * 0.50 - largeWidth / 2)
                  .clamp(deckLeft, deckRight - largeWidth);
              final deckItems = _visibleDeckItems(mainIndex);
              final paintItems = [...deckItems]
                ..sort((a, b) {
                  final aMain = a.slot == 0;
                  final bMain = b.slot == 0;
                  if (aMain != bMain) {
                    return aMain ? 1 : -1;
                  }
                  final aDistance = a.slot.abs();
                  final bDistance = b.slot.abs();
                  return bDistance.compareTo(aDistance);
                });

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _handleHorizontalDragStart,
                onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                onHorizontalDragEnd: _handleHorizontalDragEnd,
                onHorizontalDragCancel: _handleHorizontalDragCancel,
                child: SizedBox(
                  height: deckHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final item in paintItems)
                        Builder(
                          builder: (context) {
                            final entry = item.entry;
                            final isMain = item.slot == 0;
                            final isFarSide = item.slot.abs() > 1;
                            final width = isMain
                                ? largeWidth
                                : (isFarSide ? farSideWidth : sideWidth);
                            final height = isMain
                                ? largeHeight
                                : (isFarSide ? farSideHeight : sideHeight);
                            final contentScale = isMain
                                ? 1.0
                                : (isFarSide ? farSideScale : sideScale);
                            final label = _labelForIndex(item.index);
                            final top = isMain
                                ? 0.0
                                : (isFarSide ? farSidePeekTop : sidePeekTop);
                            final left = switch (item.slot) {
                              <= -2 => deckLeft,
                              -1 => (largeLeft - sideWidth * 0.72).clamp(
                                deckLeft,
                                deckRight - width,
                              ),
                              0 => largeLeft,
                              1 =>
                                (largeLeft + largeWidth - sideWidth * 0.28)
                                    .clamp(deckLeft, deckRight - width),
                              _ => deckRight - width,
                            };
                            final card = _StoryJourneyCard(
                              label: label,
                              event: entry.event,
                              eras: widget.eras,
                              charactersByCode: widget.charactersByCode,
                              eventEmotionMarks: widget.eventEmotionMarks,
                              quizAttemptSummaries: widget.quizAttemptSummaries,
                              onTap: () => _handleEntryTap(entry),
                              muted: !isMain,
                              emptyMessage: isMain
                                  ? '아직 탐험한 이야기가 없어요.'
                                  : '기록 없음',
                              contentScale: contentScale,
                              highlight:
                                  label == '다음 이야기' &&
                                  !widget.todayStoryActionCompleted,
                            );
                            return AnimatedPositioned(
                              key: ValueKey(
                                'profile-story-journey-${entry.event?.id}',
                              ),
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              top: top,
                              left: left,
                              width: width,
                              height: height,
                              child: card,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _StoryJourneyCard extends StatelessWidget {
  const _StoryJourneyCard({
    required this.label,
    required this.event,
    required this.eras,
    required this.charactersByCode,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.onTap,
    required this.muted,
    required this.emptyMessage,
    required this.contentScale,
    required this.highlight,
  });

  final String label;
  final StoryEvent? event;
  final List<Era> eras;
  final Map<String, Character> charactersByCode;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final VoidCallback? onTap;
  final bool muted;
  final String emptyMessage;
  final double contentScale;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final event = this.event;
    final rawCard = event == null
        ? _EmptyStoryJourneyCard(
            message: emptyMessage,
            onTap: onTap,
            muted: muted,
          )
        : StoryEventThumbCard(
            event: event,
            era: {for (final era in eras) era.id: era}[event.eraId],
            charactersByCode: charactersByCode,
            selected: false,
            completed: eventEmotionMarks.containsKey(event.id),
            emotionKey: eventEmotionMarks[event.id]?.emotionKey,
            attemptSummary: quizAttemptSummaries[event.id],
            orderNumber: event.storyIndex,
            showSummary: !muted,
            showCharacterPills: !muted,
            forceOpaqueSurface: !muted,
            expandSurface: true,
            surfaceColorOverride: muted
                ? null
                : _profileOpaqueStoryCardSurface(palette),
            loader: SceneAssetLoader(),
            onTap: onTap ?? () {},
          );
    final currentTextScale = MediaQuery.textScalerOf(context).scale(1);
    final cappedTextScale = math.min(currentTextScale, muted ? 1.12 : 1.4);
    final card = MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(cappedTextScale)),
      child: rawCard,
    );

    final glowingCard = highlight ? _StoryJourneyNextGlow(child: card) : card;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Opacity(opacity: muted ? 0.74 : 1, child: glowingCard),
        ),
        if (label.isNotEmpty)
          Positioned(
            top: 8,
            left: 9,
            child: _StoryJourneyLabel(
              label: label,
              color: muted ? palette.regionAccent : palette.currentAccentDeep,
              filled: !muted,
            ),
          ),
      ],
    );
    final scaledContent = contentScale == 1
        ? content
        : LayoutBuilder(
            builder: (context, constraints) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Transform.scale(
                  scale: contentScale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: constraints.maxWidth / contentScale,
                    height: constraints.maxHeight / contentScale,
                    child: content,
                  ),
                ),
              );
            },
          );
    return scaledContent;
  }
}

class _StoryJourneyNextGlow extends StatefulWidget {
  const _StoryJourneyNextGlow({required this.child});

  final Widget child;

  @override
  State<_StoryJourneyNextGlow> createState() => _StoryJourneyNextGlowState();
}

class _StoryJourneyNextGlowState extends State<_StoryJourneyNextGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final t = (1 - math.cos(progress * math.pi * 2)) / 2;
        final edgeAlpha = 0.30 + 0.42 * t;
        final centerAlpha = 0.035 + 0.075 * t;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.goldLight.withValues(alpha: 0.30 + 0.40 * t),
                blurRadius: 20 + 22 * t,
                spreadRadius: 3.0 + 5.5 * t,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (child != null) child,
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.92,
                        colors: [
                          AppColors.goldHi.withValues(alpha: centerAlpha),
                          AppColors.goldHi.withValues(alpha: centerAlpha),
                          AppColors.gold.withValues(alpha: edgeAlpha),
                        ],
                        stops: const [0.0, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.goldHi.withValues(
                          alpha: 0.42 + 0.42 * t,
                        ),
                        width: 1.7 + 0.7 * t,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _EmptyStoryJourneyCtaCard extends StatelessWidget {
  const _EmptyStoryJourneyCtaCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 178,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: palette.cardSurface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: palette.regionAccent.withValues(alpha: 0.24),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '홈 화면에서 이야기를 탐험해보세요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14.2,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 16),
              ProfileGlowingAddButton(
                tooltip: '이야기 탐험 시작',
                onTap: onTap,
                size: 42,
                iconSize: 27,
                backgroundColor: palette.regionAccent.withValues(alpha: 0.16),
                foregroundColor: palette.regionAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryJourneyLabel extends StatelessWidget {
  const _StoryJourneyLabel({
    required this.label,
    required this.color,
    required this.filled,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : palette.cardSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: filled ? 0.16 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: filled ? AppColors.fgOnDark : color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _EmptyStoryJourneyCard extends StatelessWidget {
  const _EmptyStoryJourneyCard({
    required this.message,
    required this.onTap,
    required this.muted,
  });

  final String message;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: muted ? palette.softSurface : palette.cardSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.fromLTRB(12, 34, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.subtleBorder, width: 1.2),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12.2,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileQuizStatsColumn extends StatelessWidget {
  const _ProfileQuizStatsColumn({
    required this.stats,
    required this.selectedFilter,
    required this.onTapWrong,
    required this.onTapConfused,
  });

  final ProfileQuizStats stats;
  final _ProfileInlineReviewFilter? selectedFilter;
  final VoidCallback onTapWrong;
  final VoidCallback onTapConfused;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final items = [
      _ProfileQuizStatItem(
        emoji: '✅',
        label: '정답',
        storyCount: stats.correctEventCount,
        quizCount: stats.correct,
        color: palette.successBottom,
        selected: false,
        onTap: null,
      ),
      _ProfileQuizStatItem(
        emoji: '❌',
        label: '오답',
        storyCount: stats.wrongEventCount,
        quizCount: stats.wrong,
        color: AppColors.dangerBot,
        selected: selectedFilter == _ProfileInlineReviewFilter.wrong,
        onTap: onTapWrong,
      ),
      _ProfileQuizStatItem(
        emoji: '❔',
        label: '헷갈려요',
        storyCount: stats.confusedEventCount,
        quizCount: stats.confused,
        color: palette.currentAccentDeep,
        selected: selectedFilter == _ProfileInlineReviewFilter.confused,
        onTap: onTapConfused,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: items[i]),
          if (i != items.length - 1) SizedBox(width: largeText ? 5 : 6),
        ],
      ],
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
    final palette = AppPaletteTheme.of(context);
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: palette.subtleBorder),
    );
  }
}

class _BibleChapterVerticalDivider extends StatelessWidget {
  const _BibleChapterVerticalDivider();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: palette.subtleBorder,
      ),
    );
  }
}

class _ProfileQuizStatItem extends StatelessWidget {
  const _ProfileQuizStatItem({
    required this.emoji,
    required this.label,
    required this.storyCount,
    required this.quizCount,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final int storyCount;
  final int quizCount;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = _profileUsesLargeTextLayout(context);
    final enabled = onTap != null;
    final labelColor = color;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: EdgeInsets.fromLTRB(7, largeText ? 7 : 8, 7, largeText ? 7 : 8),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(
                color.withValues(alpha: 0.22),
                palette.cardSurface,
              )
            : enabled
            ? Color.alphaBlend(
                color.withValues(alpha: 0.07),
                palette.cardSurface,
              )
            : Color.alphaBlend(
                color.withValues(alpha: 0.06),
                palette.cardSurface,
              ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withValues(
            alpha: selected
                ? 0.72
                : enabled
                ? 0.36
                : 0.20,
          ),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji,
                maxLines: 1,
                style: TextStyle(fontSize: largeText ? 14.4 : 16.2, height: 1),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: largeText ? 2 : 1,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: largeText ? 10.4 : 11.4,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$storyCount 이야기',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: largeText ? 9.1 : 9.8,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: ' $quizCount 문항',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: largeText ? 8.5 : 9.2,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
    if (!enabled) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
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
