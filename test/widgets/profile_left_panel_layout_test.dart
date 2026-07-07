import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프로필 헤더는 샬롬 인사와 님 호칭을 닉네임 앞뒤에 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('Text.rich'));
    expect(source, contains("text: '샬롬! 🙌 '"));
    expect(source, contains("text: '님'"));
    expect(source, contains("'오늘도 말씀 안에서\\n승리하는 하루 되세요!'"));
    expect(
      source,
      contains('_buildCurrentUserAvatar(profile: profile, size: 56)'),
    );
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
    expect(source, isNot(contains('Icons.edit_note_rounded')));
    expect(source, isNot(contains("label: '기록'")));
    expect(source, isNot(contains("label: '저장'")));
    expect(source, isNot(contains("label: '말씀'")));
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

  test('프로필 이야기 탐험 영역은 전체 너비 카드 덱과 요약 카드를 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final progressSource = File(
      'lib/widgets/profile/profile_progress_section.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(source, contains('_ProfileStoryExplorationDashboard'));
    expect(source, contains('_ProfileDashboardTitle'));
    expect(source, contains("'이야기 탐험'"));
    expect(source, contains('Icons.explore_rounded'));
    expect(source, contains('LinearGradient'));
    expect(source, contains('_ProfileStoryJourneyDeck'));
    expect(source, contains('_StoryJourneyDeckEntry'));
    expect(source, contains('_StoryJourneyDeckLayoutItem'));
    expect(source, contains('AnimatedPositioned'));
    expect(source, contains('largeHeight = 136.0'));
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
    expect(source, contains('_EmptyStoryJourneyCtaCard'));
    expect(source, contains("'홈 화면에서 이야기를 탐험해보세요!'"));
    expect(source, contains('ProfileGlowingAddButton'));
    expect(source, contains('onExploreStoriesFromHome'));
    expect(source, contains('return const [];'));
    expect(source, contains('onOpenStory(event)'));
    expect(source, isNot(contains('Expanded(flex: 8, child: exploration)')));
    expect(source, isNot(contains('Expanded(flex: 9, child: stats)')));
    expect(source, isNot(contains('final useVertical')));
    expect(progressSource, contains('_buildProfileStoryExplorationDashboard'));
    expect(progressSource, isNot(contains('_buildProfileStoryStatsDashboard')));
    expect(source, contains('_ProfileCompletedRatioText'));
    expect(source, contains('_StoryExplorationSummarySection'));
    expect(source, contains('_StoryExplorationSummaryCard'));
    expect(source, contains('_ProfileStoryProgressPage'));
    expect(source, contains("'이야기 탐험 요약'"));
    expect(source, contains("'탐험한 이야기'"));
    expect(source, contains("'저장 이야기 개수'"));
    expect(source, contains("'저장한 말씀'"));
    expect(source, contains("math.max(storyProgress.total, 301)"));
    expect(source, contains("ValueKey('profile-story-summary-explored')"));
    expect(source, contains("ValueKey('profile-story-summary-saved-stories')"));
    expect(source, contains("ValueKey('profile-story-summary-saved-verses')"));
    expect(source, contains('_StoryJourneyCard'));
    expect(source, contains('StoryEventThumbCard'));
    expect(source, contains('SceneAssetLoader()'));
    expect(source, contains('_ProfileQuizStatsColumn'));
    expect(source, contains("'내가 새긴 감정들'"));
    expect(source, contains("'최근 탐험 이야기'"));
    expect(source, contains("'다음 이야기'"));
    expect(source, contains('_StoryJourneyNextGlow'));
    expect(source, contains('highlight: label == \'다음 이야기\''));
    expect(source, contains('clipBehavior: Clip.antiAlias'));
    expect(source, contains('foregroundDecoration'));
    expect(source, isNot(contains('blurRadius: 8 + 12 * t')));
    expect(source, contains('isCanonicalNextStory'));
    expect(source, contains('nextJourneyEventId'));
    expect(source, contains('ProfileEventOpenSource.targetOnly'));
    expect(source, contains('ProfileEventOpenSource.detailOnly'));
    expect(source, contains('label.isNotEmpty'));
    expect(source, isNot(contains("'이전이전 이야기'")));
    expect(source, isNot(contains("'이전 이야기'")));
    expect(source, isNot(contains("'다다음 이야기'")));
    expect(
      source,
      contains('completed: eventEmotionMarks.containsKey(event.id)'),
    );
    expect(source, contains('showSummary: false'));
    expect(source, contains('forceOpaqueSurface: !muted'));
    expect(pageSource, contains('_profileStoryEraCodeOrder'));
    expect(pageSource, contains("'era_primeval': 0"));
    expect(pageSource, contains("'era_nt_post_apostolic': 9"));
    expect(pageSource, contains('isHiddenEraCode(era.code)'));
    expect(pageSource, contains('_sortEventsByEraThenIndex('));
    expect(source, contains("const _ProfileProgressPageSectionTitle("));
    expect(source, contains("title: '탐험한 이야기'"));
    expect(source, contains("'복습 항목'"));
    expect(
      source,
      contains("const _ProfileProgressPageSectionTitle(label: '내가 새긴 감정들')"),
    );
    expect(source, contains('_ProfileProgressPageDivider'));
    expect(source, contains('ProfileEmotionMarksList'));
    expect(source, contains('allCount: marks.length'));
    expect(source, contains('countsByKey: emotionCountsByKey'));
    expect(source, contains('topOptions = EventEmotionOption.options.take(4)'));
    expect(
      source,
      contains('bottomOptions = EventEmotionOption.options.skip(4)'),
    );
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, contains('storyCount: stats.wrongEventCount'));
    expect(source, contains('quizCount: stats.wrong'));
    expect(source, contains('storyCount: stats.confusedEventCount'));
    expect(source, contains('quizCount: stats.confused'));
    expect(source, contains("label: '정답'"));
    expect(source, contains("label: '오답'"));
    expect(source, contains("label: '헷갈려요'"));
    expect(source, isNot(contains("label: '통독 진행률'")));
    expect(source, isNot(contains('_ProfileRecordsStatsPanel')));
    expect(source, isNot(contains('profileQuizCountLabel(')));
    expect(source, isNot(contains('textScale >= 1.3')));
  });

  test('프로필 이야기 탐험 요약의 진행률은 심플한 숫자로 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_StoryExplorationSummaryCard'));
    expect(source, contains("text: '/\$totalLabel'"));
    expect(source, contains('fontSize: 14'));
    expect(source, isNot(contains('_StoryProgressMiniCard')));
    expect(source, isNot(contains('_ProfileProgressDonut')));
    expect(source, isNot(contains("replaceFirst('/', ' / ')")));
    expect(source, isNot(contains("valueSuffix: '장'")));
    expect(source, isNot(contains("'퀴즈를 풀면 기록이 쌓여요.'")));
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

  test('저장한 이야기 미리보기는 썸네일 카드 높이를 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('return 228;'));
    expect(source, contains('EdgeInsets.fromLTRB(2, 8, 20, 8)'));
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
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(source, contains('_buildProfileStoryExplorationDashboard'));
    expect(source, isNot(contains('_buildProfileStoryStatsDashboard')));
    expect(source, contains('ProfileDiaryFeatureCards'));
    expect(source, contains('ProfileEmotionDiary'));
    expect(source, contains('showFeatureCards: false'));
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
    expect(glowSource, contains('repeat(reverse: true, count: 2)'));
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
