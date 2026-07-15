import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('내정보 헤더는 사진·닉네임 수정과 공지·알림·설정 진입점을 제공한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final helperSource = File(
      'lib/widgets/profile/profile_helpers.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("Text(\n            '내정보'")));
    expect(source, contains("tooltip: '공지사항과 사용법'"));
    expect(source, contains('Icons.campaign_rounded'));
    expect(source, contains('onTap: widget.onOpenAppPublications'));
    expect(source, contains('NotificationBellButton('));
    expect(
      source.indexOf("tooltip: '공지사항과 사용법'"),
      lessThan(source.indexOf('NotificationBellButton(')),
    );
    expect(source, isNot(contains('Icons.edit_rounded')));
    expect(source, contains('_buildProfileBodyShell'));
    expect(source, contains('_profileBodyShellSurface'));
    expect(source, contains('color: _profileBodyShellSurface(palette)'));
    expect(
      source,
      contains('AppColorPalette.blackMap => const Color(0xFF05070B)'),
    );
    expect(source, contains("ValueKey('profile-header-identity')"));
    expect(source, contains('_buildCurrentUserAvatar('));
    expect(source, contains('profile.nickname'));
    expect(source, isNot(contains('_buildProfileIdentityCard(')));
    expect(source, isNot(contains("'샬롬! 🙌 '")));
    expect(
      source,
      isNot(contains("'오늘도 이야기 탐험, 신앙 다이어리 작성, 통독으로 하나님과 함께 해보아요!'")),
    );
    expect(source, isNot(contains('_buildProfileJourneyButton')));
    expect(source, isNot(contains("'말씀 여정 보기'")));
    expect(source, isNot(contains('_buildTodayProfileActionChecklist')));
    expect(
      source,
      isNot(contains("ValueKey('profile-today-action-checklist-info')")),
    );
    expect(source, isNot(contains('_openTodayActionChecklistInfo')));
    expect(source, isNot(contains("'오늘 할 일:'")));
    expect(source, contains('size: 34'));
    expect(source, contains("message: '프로필 수정'"));
    expect(
      helperSource,
      contains('child: Icon(icon, size: 17, color: palette.text)'),
    );
    expect(homeSource, isNot(contains("tooltip: '공지사항과 사용법'")));
    expect(homeSource, isNot(contains('NotificationBellButton(')));
  });

  test('프로필 수정 팝업은 사진과 닉네임 섹션 외곽선을 숨긴다', () {
    final source = File(
      'lib/widgets/profile_editor_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('_editorCardDecoration'));
    expect(source, contains('decoration: _editorCardDecoration('));
    expect(source, contains('modalSurfaceDecoration(palette: palette)'));
    expect(source, isNot(contains('decoration: floatingPanelDecoration(')));
  });

  test('프로필 다크 모드 보조 팝업과 당겨 새로고침은 팔레트를 따른다', () {
    final profileSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();
    final leftPanelSource = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final bibleProgressSource = File(
      'lib/screens/bible_progress_screen.dart',
    ).readAsStringSync();
    final mapDialogSource = File(
      'lib/widgets/map/map_attribution_dialog.dart',
    ).readAsStringSync();
    final legalSource = File(
      'lib/screens/legal_documents_screen.dart',
    ).readAsStringSync();

    expect(profileSource, contains('Future<void> _refreshProfilePage()'));
    expect(profileSource, contains('RefreshIndicator('));
    expect(profileSource, contains('onRefresh: _refreshProfilePage'));
    expect(profileSource, contains('AlwaysScrollableScrollPhysics'));
    expect(profileSource, contains('sigmaX: 1.5'));
    expect(profileSource, contains('sigmaY: 1.5'));
    expect(profileSource, contains('opacity: 0.96'));
    expect(
      profileSource,
      contains("ValueKey('profile-locked-content-blocker')"),
    );
    expect(profileSource, contains('final VoidCallback? onBackToHome;'));
    expect(profileSource, contains('onBack: widget.onBackToHome'));
    expect(leftPanelSource, contains('BibleProgressScreen('));
    expect(leftPanelSource, isNot(contains('showGeneralDialog(')));
    expect(
      bibleProgressSource,
      contains('final palette = AppPaletteTheme.of(context);'),
    );
    expect(bibleProgressSource, contains('ParchmentListPageScaffold('));
    expect(bibleProgressSource, contains('palette.cardSurface'));
    expect(leftPanelSource, contains('color: palette.text'));
    expect(
      mapDialogSource,
      contains('final palette = AppPaletteTheme.of(context);'),
    );
    expect(mapDialogSource, contains('color: palette.text'));
    expect(mapDialogSource, contains('color: palette.primaryDeep'));
    expect(legalSource, contains('backgroundColor: palette.pageBottom'));
    expect(legalSource, contains('colors: palette.pageGradient'));
    expect(
      legalSource,
      contains('BoxDecoration _panelDecoration(AppColorPalette palette)'),
    );
    expect(
      legalSource,
      contains('BoxDecoration _cardDecoration(AppColorPalette palette)'),
    );
  });

  test('내정보 루트의 뒤로가기는 오늘 탭으로 전환한다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(
      homeSource,
      contains('onBackToHome: () => _selectRootTab(StoryRootTab.today)'),
    );
    expect(homeSource, contains('StoryRootTab _rootTab = StoryRootTab.today'));
    expect(homeSource, contains('embedded: true'));
  });

  test('프로필 활동 탭은 밝은 레일과 선택색 본문 표면을 연결한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_profileTabRailDecoration'));
    expect(source, contains('_profileLinkedTabGroupDecoration'));
    expect(source, contains('_profileLinkedTabBodyDecoration'));
    expect(source, contains('_profileSelectedTabSurface'));
    expect(source, contains('_profileSelectedTabButtonSurface'));
    expect(source, contains('_ProfileIconTabButton'));
    expect(source, contains('AppColors.fgOnDark'));
    expect(source, contains('palette.cardUnselectedTop'));
    expect(source, contains('palette.cardUnselectedBottom'));
    expect(source, contains('Icons.self_improvement_rounded'));
    expect(source, isNot(contains('_ProfileContentTab.records')));
    expect(source, contains('_profileIconTabHeight = 44'));
    expect(source, contains('height: _profileIconTabHeight'));
    expect(source, contains('child: Row('));
    expect(source, contains('Flexible('));
    expect(source, contains('child: Icon(icon, color: accent, size: 16.5)'));
    expect(source, contains('alignment: Alignment.center'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.center'));
    expect(source, contains('_profileLeftCardChromeHeight = 90'));
    expect(source, isNot(contains('return 258;')));
    expect(source, isNot(contains('labelBelow')));
    expect(source, isNot(contains('fgOnDark.withValues(alpha: 0.92)')));
    expect(source, isNot(contains('floatingPanelDecoration')));
    expect(source, isNot(contains('_ProfileTabContentConnector')));
    expect(source, isNot(contains('math.min(constraints.maxWidth, 336.0)')));
  });

  test('프로필 이야기 탐험 영역은 요약과 탐험 달력 흔적을 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final progressSource = File(
      'lib/widgets/profile/profile_progress_section.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(source, contains('_ProfileStoryExplorationDashboard'));
    expect(source, contains('_profileStoryExplorationSurface'));
    expect(source, contains('color: _profileStoryExplorationSurface(palette)'));
    expect(source, contains('_ProfileDashboardTitle'));
    expect(source, contains("'이야기 탐험'"));
    expect(source, contains('Icons.explore_rounded'));
    expect(source, contains('LinearGradient'));
    expect(source, contains('_ProfileStoryJourneyDeck'));
    expect(source, contains('_StoryJourneyDeckEntry'));
    expect(source, contains('_StoryJourneyDeckLayoutItem'));
    expect(source, contains('AnimatedPositioned'));
    expect(source, contains('198.0 + ((textScale - 1) * 140)'));
    expect(source, contains('sideScale = 0.82'));
    expect(source, contains('farSideScale = 0.72'));
    expect(source, contains('maxWidth * 0.95'));
    expect(source, contains('math.min(3, count)'));
    expect(source, contains('_visibleDeckItems'));
    expect(source, contains('_resetToInitialDeck'));
    expect(source, contains('_handleHorizontalDragEnd'));
    expect(source, contains('_handleHorizontalDragUpdate'));
    expect(source, contains('_dragDistance'));
    expect(source, contains('onHorizontalDragEnd'));
    expect(source, contains('onHorizontalDragUpdate'));
    expect(source, contains("'되돌아가기'"));
    expect(source, contains("recentIndex < 0 && index == 0"));
    expect(source, contains('ProfileGlowingAddButton'));
    expect(source, contains('onExploreStoriesFromHome'));
    expect(source, contains('_ProfileExplorationTraceSection'));
    expect(source, contains('traceSection: _ProfileExplorationTraceSection'));
    expect(source, contains('companionDiaryEntries:'));
    expect(source, isNot(contains('Expanded(flex: 8, child: exploration)')));
    expect(source, isNot(contains('Expanded(flex: 9, child: stats)')));
    expect(source, isNot(contains('final useVertical')));
    expect(progressSource, contains('_buildProfileStoryExplorationDashboard'));
    expect(progressSource, isNot(contains('_buildProfileStoryStatsDashboard')));
    expect(source, contains('_ProfileCompletedRatioText'));
    expect(source, contains('_StoryExplorationSummarySection'));
    expect(source, contains('_StoryExplorationSummaryCard'));
    expect(source, contains('_ProfileStoryProgressPage'));
    expect(source, contains('_ProfileExplorationLogPage'));
    expect(source, contains("'이야기 탐험 요약'"));
    expect(source, contains("label: '완료'"));
    expect(source, contains("label: '복습'"));
    expect(source, contains("label: '저장'"));
    expect(source, contains("label: '말씀'"));
    expect(source, contains("text: '개'"));
    expect(source, contains("math.max(storyProgress.total, 301)"));
    expect(source, contains("ValueKey('profile-story-summary-explored')"));
    expect(
      source,
      contains("ValueKey('profile-story-summary-exploration-log')"),
    );
    expect(source, contains("ValueKey('profile-story-summary-saved-stories')"));
    expect(source, contains("ValueKey('profile-story-summary-saved-verses')"));
    expect(source, contains('_StoryJourneyCard'));
    expect(source, contains('StoryEventThumbCard'));
    expect(source, contains('SceneAssetLoader()'));
    expect(source, contains('_ProfileQuizStatsColumn'));
    expect(source, contains("label: '다이어리'"));
    expect(source, isNot(contains("'내가 새긴 감정들과 코멘트'")));
    expect(source, contains("'최근 탐험 이야기'"));
    expect(source, contains("'다음 이야기'"));
    expect(source, contains('_StoryJourneyNextGlow'));
    expect(source, contains("label == '다음 이야기'"));
    expect(source, contains('!widget.todayStoryActionCompleted'));
    expect(source, contains('ClipRRect'));
    expect(source, contains(')..repeat();'));
    expect(source, contains('math.cos(progress * math.pi * 2)'));
    expect(source, contains('final edgeAlpha = 0.30 + 0.42 * t'));
    expect(source, contains('final centerAlpha = 0.035 + 0.075 * t'));
    expect(source, contains('AppColors.goldHi'));
    expect(source, contains('AppColors.goldLight'));
    expect(source, contains('AppColors.gold.withValues(alpha: edgeAlpha)'));
    expect(source, contains('RadialGradient'));
    expect(source, isNot(contains('AppColors.profileNextStoryGlow')));
    expect(source, isNot(contains('AppColors.profileNextStoryGlowEdge')));
    expect(source, isNot(contains('foregroundDecoration')));
    expect(source, isNot(contains('_StoryJourneySparkleDot')));
    expect(source, isNot(contains('Transform.translate')));
    expect(source, isNot(contains('_StoryJourneyGuideNote')));
    expect(source, isNot(contains('카드를 눌러 탐험하세요! (완료조건: 감정 새기기)')));
    expect(
      source,
      isNot(
        contains('color: palette.currentAccentDeep.withValues(alpha: 0.22)'),
      ),
    );
    expect(source, isNot(contains('isCanonicalNextStory')));
    expect(source, isNot(contains('nextJourneyEventId')));
    expect(source, isNot(contains('ProfileEventOpenSource.targetOnly')));
    expect(source, contains('ProfileEventOpenSource.detailOnly'));
    expect(homeSource, contains('source != ProfileEventOpenSource.targetOnly'));
    expect(homeSource, contains('notifier.setDisplayedEvents({homeEvent.id})'));
    expect(homeSource, contains('_mapPanelController.focusSelectedEvent'));
    expect(homeSource, contains('duration: const Duration(seconds: 1)'));
    expect(homeSource, contains('returnToProfileOnRoot: true'));
    expect(homeSource, contains('_StoryDetailBackContext'));
    expect(homeSource, contains('_handleEventDetailBack'));
    expect(
      homeSource,
      contains('final previousEvent = backContext.previousEvent'),
    );
    expect(source, contains('label.isNotEmpty'));
    expect(source, contains('showCharacterPills: !muted'));
    expect(source, isNot(contains("'이전이전 이야기'")));
    expect(source, isNot(contains("'이전 이야기'")));
    expect(source, isNot(contains("'다다음 이야기'")));
    expect(
      source,
      contains('completed: eventEmotionMarks.containsKey(event.id)'),
    );
    expect(source, contains('showSummary: !muted'));
    expect(source, contains('forceOpaqueSurface: !muted'));
    expect(source, contains('_profileOpaqueStoryCardSurface(palette)'));
    expect(source, contains('AppColorPalette.blackMap => palette.cardSurface'));
    expect(source, contains('_profileProgressPageSurface'));
    expect(pageSource, contains('_profileStoryEraCodeOrder'));
    expect(pageSource, contains("'era_primeval': 0"));
    expect(pageSource, contains("'era_nt_post_apostolic': 9"));
    expect(pageSource, contains('isHiddenEraCode(era.code)'));
    expect(pageSource, contains('_sortEventsByEraThenIndex('));
    expect(source, contains("const _ProfileProgressPageSectionTitle("));
    expect(source, contains("title: '완료'"));
    expect(source, contains("title: '복습'"));
    expect(source, contains("'복습 항목'"));
    expect(source, contains("label: '다이어리'"));
    expect(source, isNot(contains("label: '내가 새긴 감정들과 코멘트'")));
    expect(source, contains('오답이나 헷갈려요를 누르면 이야기 카드가 나타납니다.'));
    expect(source, contains("ValueKey('exploration-log-review-events')"));
    expect(source, contains('scrollable: false'));
    expect(source, isNot(contains('_ProfileProgressPageDivider')));
    expect(source, contains('ProfileEmotionMarksList'));
    expect(source, contains('countsByKey: countsByKey'));
    expect(source, contains('_EmotionCategoryRow'));
    expect(source, contains('EventEmotionOption.options.length'));
    expect(source, contains("ValueKey('emotion-category-\${option.key}')"));
    expect(
      source,
      contains("ValueKey('emotion-category-count-\${option.key}')"),
    );
    expect(source, contains('selectedDate: _selectedDate'));
    expect(source, contains('onSelectedDateChanged'));

    final reviewPageStart = source.indexOf('class _ProfileExplorationLogPage');
    final traceSectionStart = source.indexOf(
      'class _ProfileExplorationTraceSection',
    );
    final reviewPageSource = source.substring(
      reviewPageStart,
      traceSectionStart,
    );
    expect(
      reviewPageSource,
      isNot(contains('_ProfileExplorationTraceSection(')),
    );
    expect(reviewPageSource, isNot(contains('_ProfileProgressPageDivider')));
    expect(source, contains('_ExplorationTracePanel'));
    expect(source, contains('_SelectedDateEmotionSummary'));
    expect(source, contains('_SelectedDateDiarySummary'));
    expect(source, contains("ValueKey('selected-date-emotion-comments')"));
    expect(source, contains("ValueKey('selected-date-companion-diary')"));
    expect(source, contains('_ProfileLogNavigationHint'));
    expect(source, contains('Icons.home_rounded'));
    expect(source, contains('Icons.menu_book_rounded'));
    expect(source, contains('Icons.map_rounded'));
    expect(source, isNot(contains("ValueKey('emotion-filter-all')")));
    expect(source, isNot(contains('selectedKeys.isEmpty')));
    expect(source, isNot(contains('_EmotionFilterChips')));
    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, contains('storyCount: stats.wrongEventCount'));
    expect(source, contains('quizCount: stats.wrong'));
    expect(source, contains('storyCount: stats.confusedEventCount'));
    expect(source, contains('quizCount: stats.confused'));
    expect(
      source,
      contains('constraints: const BoxConstraints(minHeight: 62)'),
    );
    expect(source, contains('emoji: \'✅\''));
    expect(source, contains('emoji: \'❌\''));
    expect(source, contains('emoji: \'❔\''));
    expect(source, contains('fontSize: largeText ? 14.4 : 16.2'));
    expect(source, contains('fontSize: largeText ? 10.4 : 11.4'));
    expect(source, contains("text: '\$storyCount 이야기'"));
    expect(source, contains("text: ' \$quizCount 문항'"));
    expect(source, contains('fontSize: largeText ? 9.1 : 9.8'));
    expect(source, contains('textAlign: TextAlign.center'));
    expect(source, contains('fontSize: largeText ? 8.5 : 9.2'));
    expect(
      source,
      contains('constraints: const BoxConstraints(minHeight: 64)'),
    );
    expect(source, isNot(contains('progressFraction')));
    expect(source, isNot(contains('color.withValues(alpha: 0.14)')));
    expect(source, isNot(contains('Color(0x0A000000)')));
    expect(source, isNot(contains('Icons.north_east_rounded')));
    expect(source, contains('onTap: null'));
    expect(source, contains('_selectedReviewFilter == filter ? null : filter'));
    expect(
      source,
      contains("openAllKeyPrefix: 'exploration-log-review-open-all'"),
    );
    expect(source, contains("gridKeyPrefix: 'exploration-log-emotion-grid'"));
    expect(source, contains('_buildInlineEventCards('));
    expect(source, isNot(contains('_openEmotionCategoryPopup')));
    expect(source, contains("ValueKey('exploration-log-review-all-grid')"));
    expect(source, contains('events: previewEvents'));
    expect(source, contains("label: '정답'"));
    expect(source, contains("label: '오답'"));
    expect(source, contains("label: '헷갈려요'"));
    expect(source, contains('color: palette.successBottom'));
    expect(source, isNot(contains("label: '통독 진행률'")));
    expect(source, isNot(contains('_ProfileRecordsStatsPanel')));
    expect(source, isNot(contains('profileQuizCountLabel(')));
    expect(source, isNot(contains('textScale >= 1.3')));
  });

  test('프로필 이야기 탐험 요약은 숫자와 테마 역할색을 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_StoryExplorationSummaryCard'));
    expect(source, contains("text: '/\$totalLabel'"));
    expect(source, contains("text: '개'"));
    expect(
      source,
      contains('if (trailing != null) trailing,\n            countUnitSpan(),'),
    );
    expect(source, contains('fontSize: 11.4'));
    expect(source, contains('fontSize: 12.2'));
    expect(source, contains('fontSize: largeText ? 14.8 : 16.2'));
    expect(
      source,
      contains('constraints: const BoxConstraints(minHeight: 64)'),
    );
    expect(source, contains('color: palette.primary'));
    expect(source, contains('color: palette.currentAccentDeep'));
    expect(source, contains('color: palette.successBottom'));
    expect(source, contains('color: palette.primaryDeep'));
    expect(source, isNot(contains('progressFraction: storyProgress.fraction')));
    expect(source, isNot(contains('_StoryProgressMiniCard')));
    expect(source, isNot(contains('_ProfileProgressDonut')));
    expect(source, isNot(contains("replaceFirst('/', ' / ')")));
    expect(source, isNot(contains("valueSuffix: '장'")));
    expect(source, isNot(contains("'퀴즈를 풀면 기록이 쌓여요.'")));
    expect(source, contains('boxShadow: AppShadows.sm'));
  });

  test('다크 테마에서 주요 프로필과 탐험 표면은 팔레트를 사용한다', () {
    final profileSource = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final companionSource = File(
      'lib/widgets/profile/profile_companion_diary.dart',
    ).readAsStringSync();
    final emotionSource = File(
      'lib/widgets/profile/profile_emotion_diary.dart',
    ).readAsStringSync();
    final characterSource = File(
      'lib/widgets/character_panel.dart',
    ).readAsStringSync();
    final eventCardSource = File(
      'lib/widgets/v2/region_event_list.dart',
    ).readAsStringSync();
    final eraRowsSource = File(
      'lib/widgets/v2/era_pick_rows.dart',
    ).readAsStringSync();
    final selectionPanelSource = File(
      'lib/widgets/story_selection_panel.dart',
    ).readAsStringSync();
    final bottomPanelStyleSource = File(
      'lib/widgets/story_bottom_panel_style.dart',
    ).readAsStringSync();
    final dailyMissionSource = File(
      'lib/widgets/quiz/daily_exploration_section.dart',
    ).readAsStringSync();
    final eventDetailSource = File(
      'lib/widgets/event_detail_page.dart',
    ).readAsStringSync();
    final stylesSource = File(
      'lib/widgets/story_home_styles.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final homeWidgetsSource = File(
      'lib/screens/story_home_screen_widgets.dart',
    ).readAsStringSync();
    final quizDialogSource = File(
      'lib/widgets/event_quiz_dialog.dart',
    ).readAsStringSync();
    final profileEditorSource = File(
      'lib/widgets/profile_editor_dialog.dart',
    ).readAsStringSync();
    final bibleProgressSource = File(
      'lib/screens/bible_progress_screen.dart',
    ).readAsStringSync();
    final fontScaleSource = File(
      'lib/widgets/font_scale_bottom_sheet.dart',
    ).readAsStringSync();
    final weeklySource = File(
      'lib/widgets/weekly_tab_page.dart',
    ).readAsStringSync();
    final settingsSource = File(
      'lib/widgets/profile/profile_settings_sheet.dart',
    ).readAsStringSync();
    final publicationsSource = File(
      'lib/screens/app_publications_screen.dart',
    ).readAsStringSync();

    expect(
      profileSource,
      isNot(contains('color: Colors.white.withValues(alpha: 0.96)')),
    );
    expect(profileSource, contains('palette.cardSurface'));
    expect(
      companionSource,
      isNot(contains('backgroundColor: AppColors.goldDeep')),
    );
    expect(companionSource, contains('backgroundColor: palette.successBottom'));
    expect(
      emotionSource,
      isNot(contains('Colors.white.withValues(alpha: 0.98)')),
    );
    expect(characterSource, isNot(contains("import 'game_ui_skin.dart'")));
    expect(characterSource, isNot(contains('panelFrameDecoration')));
    expect(characterSource, isNot(contains('tabItemDecoration')));
    expect(characterSource, contains('palette.panelSurface'));
    expect(eventCardSource, isNot(contains('? Colors.white')));
    expect(eventCardSource, contains('palette.cardSurface'));
    expect(profileSource, contains('_profileBodyShellSurface'));
    expect(profileSource, contains('_profileOpaqueStoryCardSurface'));
    expect(selectionPanelSource, contains('storyBottomPanelDecoration'));
    expect(bottomPanelStyleSource, contains('palette.softSurface'));
    expect(bottomPanelStyleSource, contains('palette.panelSurface'));
    expect(bottomPanelStyleSource, contains('palette.mutedSurface'));
    expect(dailyMissionSource, contains('_dailyMissionSurface'));
    expect(dailyMissionSource, contains('_dailyMissionCardSurface'));
    expect(
      eventDetailSource,
      contains('borderlessModalSurfaceDecoration(palette: palette)'),
    );
    expect(
      stylesSource,
      contains('modalSurfaceDecoration({AppColorPalette? palette})'),
    );
    expect(stylesSource, contains('bool includeShadow = true'));
    expect(
      homeSource,
      contains('_selectionSheetPanelDecoration(BuildContext context)'),
    );
    expect(homeSource, contains('storyBottomPanelDecoration'));
    expect(homeWidgetsSource, contains('palette.cardSurface'));
    expect(homeWidgetsSource, contains('palette.mutedSurface'));
    expect(homeWidgetsSource, contains('palette.subtleBorder'));
    expect(homeSource, isNot(contains('_parchmentPanelDecoration()')));
    expect(weeklySource, contains('floatingPanelDecoration(palette: palette)'));
    expect(weeklySource, contains('headerChipDecoration(palette: palette)'));
    expect(
      settingsSource,
      contains('modalSurfaceDecoration(palette: palette)'),
    );
    expect(settingsSource, contains('color: palette.cardSurface'));
    expect(profileSource, contains('BibleProgressScreen('));
    expect(bibleProgressSource, contains('palette.cardSurface'));
    expect(bibleProgressSource, contains('palette.softSurface'));
    expect(
      profileEditorSource,
      contains('modalSurfaceDecoration(palette: palette)'),
    );
    expect(publicationsSource, contains('color: palette.cardSurface'));
    expect(eraRowsSource, contains('includeShadow: false'));
    expect(eraRowsSource, isNot(contains('boxShadow: [')));
    expect(quizDialogSource, contains('palette.cardSurface'));
    expect(quizDialogSource, contains('palette.currentAccentDeep'));
    expect(stylesSource, contains('palette.mutedSurface'));
    expect(fontScaleSource, contains('surfacePalette.cardSurface'));
    expect(fontScaleSource, contains('palette.cardSurface'));
  });

  test('탐험한 이야기 페이지는 전체/완료/미완료 필터를 제공한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(pageSource, contains('enum _StoryProgressFilter'));
    expect(source, contains('ParchmentListPageScaffold'));
    expect(source, contains('_StoryProgressFilterTabs'));
    expect(source, contains("label: '전체'"));
    expect(source, contains("label: '완료'"));
    expect(source, contains("label: '미완료'"));
    expect(source, contains('filteredEvents'));
  });

  test('저장한 이야기 전체보기는 공용 3열 복습 그리드를 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains("ValueKey('saved-stories-review-grid')"));
    expect(source, contains('ProfileEventReviewGrid('));
    expect(source, isNot(contains('_buildEventGroupsByEra(')));
  });

  test('시대 선택 칩은 공용으로 다이어리 역할색을 사용한다', () {
    final source = File('lib/widgets/v2/era_pick_rows.dart').readAsStringSync();

    expect(source, contains('palette.currentAccentDeep'));
    expect(source, isNot(contains('palette.cardSelectedTop')));
    expect(source, isNot(contains('selectedAccent')));
  });

  test('프로필 진행률 섹션은 이야기 탐험 뒤에 다이어리 카드를 보여준다', () {
    final source = File(
      'lib/widgets/profile/profile_progress_section.dart',
    ).readAsStringSync();
    final leftPanelSource = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();
    final companionSource = File(
      'lib/widgets/profile/profile_companion_diary.dart',
    ).readAsStringSync();
    final emotionSource = File(
      'lib/widgets/profile/profile_emotion_diary.dart',
    ).readAsStringSync();

    expect(source, contains('_buildProfileStoryExplorationDashboard'));
    expect(source, isNot(contains('_buildProfileStoryStatsDashboard')));
    expect(source, contains('ProfileDiaryFeatureCards'));
    expect(source, isNot(contains('ProfileEmotionDiary')));
    expect(source, isNot(contains('showFeatureCards: false')));
    expect(leftPanelSource, contains("label: '다이어리'"));
    expect(leftPanelSource, contains('ProfileEmotionDiary('));
    expect(leftPanelSource, contains('showFeatureCards: false'));
    expect(source, contains('SingleChildScrollView'));
    expect(source, isNot(contains('_profileLinkedTabGroupDecoration')));
    expect(source, isNot(contains('_profileLinkedTabBodyDecoration')));
    expect(source, isNot(contains('selectedAccent')));
    expect(source, isNot(contains('featureCardsFirst: true')));
    expect(source, isNot(contains('_profileProgressTabAccent(palette)')));
    expect(source, isNot(contains('Icons.directions_walk_rounded')));
    expect(source, isNot(contains('Icons.place_rounded')));
    expect(source, isNot(contains('_ProfileIconTabButton')));
    expect(source, isNot(contains('_profileProgressTabBar')));
    expect(source, isNot(contains('floatingPanelDecoration')));
    expect(pageSource, contains('_profileSectionsFrame'));
    expect(pageSource, contains('floatingPanelDecoration'));
    expect(pageSource, contains('scrollBody: false'));
    expect(source, isNot(contains('_ProfileTabContentConnector')));
    expect(source, isNot(contains('_profileProgressTabIndex()')));
    expect(emotionSource, contains('LayoutBuilder'));
    expect(
      emotionSource,
      contains('final cardWidth = (constraints.maxWidth - 10) / 2'),
    );
    expect(
      emotionSource,
      contains(
        'final expandTextForNarrowLargeText = largeText && cardWidth < 176',
      ),
    );
    expect(
      emotionSource,
      contains(
        'final featureCardMinHeight = profileSummaryMode ? 118.0 : 158.0',
      ),
    );
    expect(emotionSource, contains('minHeight: featureCardMinHeight'));
    expect(companionSource, contains('maxLines: expandReadableText ? 2 : 1'));
    expect(companionSource, contains('maxLines: expandReadableText ? 4 : 2'));
    expect(companionSource, contains('TextOverflow.visible'));
    expect(
      companionSource,
      contains('color: darkSurface ? AppColors.goldLight : AppColors.goldHi'),
    );
    expect(companionSource, isNot(contains('final pulseColor')));
    expect(companionSource, isNot(contains('auraColor')));
    expect(companionSource, isNot(contains('ringColor')));
  });

  test('기도 empty 상태의 추가 버튼은 동행 일지와 같은 초록 원형 톤을 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_intercessory_prayer.dart',
    ).readAsStringSync();
    final glowSource = File(
      'lib/widgets/profile/glowing_add_button.dart',
    ).readAsStringSync();
    final emptyStateSource = source
        .split('Widget _intercessoryPrayerFab')
        .first;

    expect(emptyStateSource, contains('_profilePrayerEmptyAddButton'));
    expect(emptyStateSource, contains('ProfileGlowingAddButton'));
    expect(glowSource, contains('AnimationController'));
    expect(glowSource, contains('pulseCount = 2'));
    expect(glowSource, contains('repeat(reverse: true);'));
    expect(
      glowSource,
      contains('repeat(reverse: true, count: widget.pulseCount)'),
    );
    expect(glowSource, contains("ValueKey('profile-add-button-pulse-ring')"));
    expect(glowSource, contains('Colors.white.withValues(alpha: 0.88)'));
    expect(glowSource, contains('AppColors.greenTint2'));
    expect(glowSource, contains('AppColors.greenBot'));
    expect(
      emptyStateSource,
      isNot(contains("colors: [Color(0xFFD99F4A), Color(0xFFB26B28)]")),
    );
  });
}
