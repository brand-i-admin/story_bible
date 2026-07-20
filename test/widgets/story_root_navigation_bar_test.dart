import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/home/story_root_navigation_bar.dart';

class _RetainedTabProbe extends StatefulWidget {
  const _RetainedTabProbe({required this.label, required this.onDispose});

  final String label;
  final VoidCallback onDispose;

  @override
  State<_RetainedTabProbe> createState() => _RetainedTabProbeState();
}

class _RetainedTabProbeState extends State<_RetainedTabProbe> {
  var count = 0;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => count += 1),
      child: Text('${widget.label}:$count'),
    );
  }
}

void main() {
  testWidgets('루트 탭 레이어는 숨긴 화면을 Offstage로 유지해 재진입 로딩을 막는다', (tester) async {
    var bibleDisposed = false;
    var selectedTab = StoryRootTab.bible;

    Widget buildRetentionStack() {
      return MaterialApp(
        home: StoryRootTabRetentionStack(
          selectedTab: selectedTab,
          mapChild: const Text('지도'),
          bibleChild: _RetainedTabProbe(
            label: '성경',
            onDispose: () => bibleDisposed = true,
          ),
          profileChild: const Text('내정보'),
        ),
      );
    }

    await tester.pumpWidget(buildRetentionStack());
    await tester.tap(find.text('성경:0'));
    await tester.pump();
    expect(find.text('성경:1'), findsOneWidget);

    selectedTab = StoryRootTab.profile;
    await tester.pumpWidget(buildRetentionStack());
    expect(bibleDisposed, isFalse);
    expect(find.text('성경:1', skipOffstage: false), findsOneWidget);
    expect(find.text('성경:1'), findsNothing);

    selectedTab = StoryRootTab.bible;
    await tester.pumpWidget(buildRetentionStack());
    expect(find.text('성경:1'), findsOneWidget);
    expect(bibleDisposed, isFalse);
  });

  testWidgets('오늘 성경 지도 내정보 순서로 네비게이션 항목을 표시한다', (tester) async {
    StoryRootTab? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StoryRootNavigationBar(
            selectedTab: StoryRootTab.today,
            onSelect: (tab) => selected = tab,
          ),
        ),
      ),
    );

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('성경'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('내정보'), findsOneWidget);

    final labels = <String>['오늘', '성경', '지도', '내정보'];
    final positions = labels
        .map((label) => tester.getCenter(find.text(label)).dx)
        .toList();
    expect(positions, orderedEquals([...positions]..sort()));

    await tester.tap(find.text('지도'));
    await tester.pump();
    expect(selected, StoryRootTab.map);
  });

  testWidgets('이미 선택된 오늘 항목을 다시 눌러도 콜백을 호출한다', (tester) async {
    StoryRootTab? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StoryRootNavigationBar(
            selectedTab: StoryRootTab.today,
            onSelect: (tab) => selected = tab,
          ),
        ),
      ),
    );

    await tester.tap(find.text('오늘'));
    await tester.pump();

    expect(selected, StoryRootTab.today);
  });

  testWidgets('선택된 탭만 강조 상태를 가진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StoryRootNavigationBar(
            selectedTab: StoryRootTab.profile,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('root-navigation-profile-selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('root-navigation-today-selected')),
      findsNothing,
    );
  });

  testWidgets('하단 네비게이션은 화면 폭을 채우는 단순한 바 표면을 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StoryRootNavigationBar(
            selectedTab: StoryRootTab.today,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('root-navigation-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final content = tester.widget<Container>(
      find.byKey(const ValueKey('root-navigation-content')),
    );
    final contentDecoration = content.decoration! as BoxDecoration;

    expect(surface.margin, isNull);
    expect(decoration.borderRadius, isNull);
    expect(decoration.boxShadow, isNull);
    expect(contentDecoration.border, isNull);
  });

  testWidgets('하단 시스템 안전영역까지 네비게이션 표면색이 이어진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Scaffold(
            bottomNavigationBar: StoryRootNavigationBar(
              selectedTab: StoryRootTab.today,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('root-navigation-content')))
          .height,
      60,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('root-navigation-surface')))
          .height,
      94,
    );
  });

  test('오늘 헤더는 찾기·큰글자·테마 순서와 팔레트 기반 아이콘을 사용한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    final searchIndex = source.indexOf("label: '찾기'");
    final fontIndex = source.indexOf("label: '큰글자'");
    final themeIndex = source.indexOf("label: '테마'");
    expect(searchIndex, greaterThanOrEqualTo(0));
    expect(searchIndex, lessThan(fontIndex));
    expect(fontIndex, lessThan(themeIndex));
    expect(source, contains('Icons.search_rounded'));
    expect(source, contains("Text('Aa'"));
    expect(source, contains('Icons.palette_outlined'));
    expect(source, contains('final palette = AppPaletteTheme.of(context);'));
    expect(source, contains('color: foreground'));
    expect(source, isNot(contains('color: AppColors.ink800')));
  });

  test('오늘 헤더 유틸리티 버튼은 40px 영역과 더 작은 아이콘을 사용한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();
    final actionSource = source.substring(
      source.indexOf('class _TodayHeaderAction extends StatelessWidget'),
    );

    expect(actionSource, contains('static const double extent = 40;'));
    expect(actionSource, contains('static const double iconSize = 17;'));
    expect(actionSource, contains('fontSize: 9.2'));
    expect(actionSource, contains('width: extent'));
    expect(actionSource, contains('height: extent'));
    expect(actionSource, contains('palette.primary.withValues(alpha: 0.20)'));
    expect(source, contains('size: _TodayHeaderAction.iconSize'));
  });

  test('오늘과 지도 탭은 같은 3D 지도를 재사용하고 숨겨진 탭에서는 제스처를 끈다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();
    final retentionSource = File(
      'lib/widgets/home/story_root_navigation_bar.dart',
    ).readAsStringSync();

    expect(homeSource, contains('final GlobalKey _sharedMapKey'));
    expect(homeSource, contains('mapKey: _sharedMapKey'));
    expect(homeSource, contains('mapController: _mapPanelController'));
    expect(homeSource, contains('key: _sharedMapKey'));
    expect(homeSource, contains('StoryRootTab _retainedMapRootTab'));
    expect(homeSource, contains('_buildRetainedMapBody'));
    expect(retentionSource, contains('IgnorePointer('));
    expect(retentionSource, contains('TickerMode('));
    expect(retentionSource, contains('Offstage('));
    expect(homeSource, contains('StoryRootTabRetentionStack('));
    expect(homeSource, contains('_hasBuiltBibleTab'));
    expect(homeSource, contains('_hasBuiltProfileTab'));
    expect(todaySource, contains('final bool mapGesturesEnabled;'));
    expect(
      todaySource,
      contains('mapGesturesEnabled: widget.mapGesturesEnabled'),
    );
    expect(
      homeSource,
      contains('mapGesturesEnabled: _rootTab == StoryRootTab.today'),
    );
    expect(
      homeSource,
      contains('mapGesturesEnabled: _rootTab == StoryRootTab.map'),
    );
    expect(todaySource, contains('suspendMapGestures'));
    expect(todaySource, contains('clearMapGestureSuspension'));
    expect(
      todaySource,
      contains("key: const ValueKey('today-header-map-input-blocker')"),
    );
    expect(todaySource, contains('onStreakDialogVisibilityChanged:'));
    expect(todaySource, contains('Duration(hours: 1)'));
    expect(
      homeSource,
      contains(
        'user == null\n        ? TodayActivitySummary.empty\n        : summarizeTodayActivity(',
      ),
    );
  });

  test('홈/내정보 로딩 경로는 전체 이야기와 활성 인물을 각각 한 번만 조회한다', () {
    final catalogSource = File(
      'lib/state/daily_mission_provider.dart',
    ).readAsStringSync();
    final profileSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(catalogSource, contains('repo.fetchAllEvents()'));
    expect(
      catalogSource,
      isNot(contains('eras.map((era) => repo.fetchEventsByEra')),
    );
    expect(profileSource, contains('repo.fetchAllActiveCharacters()'));
    expect(profileSource, isNot(contains('repo.fetchCharactersByEra')));
  });

  test('로그아웃과 계정 전환은 루트와 내정보에서 사용자 전용 캐시를 즉시 비운다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final profileSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(
      homeSource,
      contains(
        'ref.read(storyControllerProvider.notifier).clearUserScopedData();',
      ),
    );
    expect(
      profileSource,
      contains('ref.listenManual<User?>(signedInUserProvider'),
    );
    expect(profileSource, contains('_handleProfileAuthUserChanged(next);'));
    expect(profileSource, contains('_profileSavedVersesCount = 0;'));
    expect(
      profileSource,
      contains('_profileCompanionDiaryEntries = const [];'),
    );
  });

  test('오늘 화면은 일일 활동 헤더, 가이드, 지도 위 플로팅 카드 덱을 제공한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('TodayActivityHeader('));
    expect(source, contains('MapHintOverlay('));
    expect(source, contains('_todayGuideDismissed'));
    expect(source, contains('_dismissTodayGuide'));
    expect(
      source,
      contains('!oldWidget.mapGesturesEnabled && widget.mapGesturesEnabled'),
    );
    expect(source, contains('_todayGuideDismissed = false;'));
    expect(source, contains('이야기, 다이어리, 통독을 해보세요!'));
    expect(source, contains('(이야기 순서는 감정을 새길 때마다 재정렬 됩니다)'));
    expect(source, contains('onPointerDown: (_) => _dismissTodayGuide()'));
    expect(source, contains('textScale >= 1.3 ? 60.0 : 0.0'));
    expect(source, contains('Transform.translate('));
    expect(source, contains('offset: Offset(0, todayGuideVerticalOffset)'));
    expect(source, isNot(contains('todayGuideTopInset')));
    expect(source, isNot(contains('AnimatedContainer(')));
    expect(source, isNot(contains('_todayPanelCollapsedHeight')));
    expect(source, isNot(contains('constraints.maxHeight * 0.43')));
    expect(source, contains('HomeJourneyOverlay('));
    expect(source, contains('bottom: 8'));
  });

  test('오늘 지도는 역할 핀 경로와 촘촘한 세 사건 전용 확대 상한을 사용한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('showEventPath: true'));
    expect(source, contains('fitTightClusterMaxZoom: 9.0'));
    expect(source, contains('fitAllZoomAdjust: 0.0'));
  });

  test('루트 화면은 시스템 네비게이션 영역도 탭 표면색으로 맞춘다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(source, contains('AnnotatedRegion<SystemUiOverlayStyle>'));
    expect(
      source,
      contains('systemNavigationBarColor: navigationSurfaceColor'),
    );
    expect(source, contains('systemNavigationBarContrastEnforced: false'));
    expect(source, contains('showRootHeaderSurface'));
    expect(source, contains('StoryRootTab.profile'));
    expect(source, contains('statusBarColor: showRootHeaderSurface'));
    expect(source, contains('? navigationSurfaceColor'));
    expect(source, contains('statusBarIconBrightness: showRootHeaderSurface'));
    expect(source, contains('? navigationIconBrightness'));
    expect(source, contains('statusBarBrightness: showRootHeaderSurface'));
    expect(source, contains('? navigationSurfaceBrightness'));
    expect(source, isNot(contains('AppColors.parchmentLight')));
  });

  test('오늘 카드 덱은 지도 하단 패널 표면에서 분리되어 공중에 뜬다', () {
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();
    final mapSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final overlaySource = File(
      'lib/widgets/home/home_journey_overlay.dart',
    ).readAsStringSync();

    expect(todaySource, isNot(contains('storyBottomPanelHorizontalMargin')));
    expect(mapSource, contains('storyBottomPanelHorizontalMargin'));
    expect(todaySource, contains('bottom: 8'));
    expect(
      overlaySource,
      isNot(contains('storyBottomPanelDecoration(context)')),
    );
    expect(overlaySource, isNot(contains('home-journey-panel-toggle')));
  });

  test('선택된 오늘 탭을 다시 눌러도 별도 컨트롤러로 가이드를 다시 만들지 않는다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(homeSource, isNot(contains('TodayHomePageController')));
    expect(homeSource, isNot(contains('showWelcomeGuide()')));
    expect(todaySource, isNot(contains('class TodayHomePageController')));
    expect(todaySource, isNot(contains('void showWelcomeGuide()')));
  });

  test('지도 탭에 들어가거나 벗어날 때 지도 탐색 선택을 첫 단계로 초기화한다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final resetSource = source.substring(
      source.indexOf('void _resetMapTabExploration()'),
      source.indexOf('void _selectRootTab(StoryRootTab tab)'),
    );
    final selectTabSource = source.substring(
      source.indexOf('void _selectRootTab(StoryRootTab tab)'),
      source.indexOf('void _continueBibleReading('),
    );

    expect(
      selectTabSource,
      contains(
        'final leavingMap = _rootTab == StoryRootTab.map && '
        'tab != StoryRootTab.map;',
      ),
    );
    expect(
      selectTabSource,
      contains(
        'final enteringMap = _rootTab != StoryRootTab.map && '
        'tab == StoryRootTab.map;',
      ),
    );
    expect(
      selectTabSource,
      contains(
        'if (leavingMap || enteringMap) {\n'
        '      _resetMapTabExploration();',
      ),
    );
    expect(resetSource, contains('controller.clearMapExplorationSelection();'));
    expect(resetSource, contains('_selectionStep = 1;'));
    expect(resetSource, contains('_mode = null;'));
    expect(
      resetSource,
      contains('_selectionPanelStage = StorySelectionPanelStage.expanded;'),
    );
  });

  test('앱 시작 후 지도 탭에 처음 들어갈 때도 가이드 dismiss 유예를 시작한다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final selectTabSource = source.substring(
      source.indexOf('void _selectRootTab(StoryRootTab tab)'),
      source.indexOf('void _continueBibleReading('),
    );

    expect(
      selectTabSource,
      contains(
        'if (leavingMap || enteringMap) {\n'
        '      _resetMapTabExploration();',
      ),
    );
  });
}
