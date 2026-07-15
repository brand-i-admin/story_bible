import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/home/story_root_navigation_bar.dart';

void main() {
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

    expect(surface.margin, isNull);
    expect(decoration.borderRadius, isNull);
    expect(decoration.boxShadow, isNull);
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
      68,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('root-navigation-surface')))
          .height,
      102,
    );
  });

  test('오늘 헤더는 찾기·큰글자·테마 순서와 흰색 단색 아이콘을 사용한다', () {
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
    expect(source, contains('color: Colors.white'));
  });

  test('오늘 헤더 유틸리티 버튼은 48px 터치 영역과 작은 아이콘을 사용한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();
    final actionSource = source.substring(
      source.indexOf('class _TodayHeaderAction extends StatelessWidget'),
    );

    expect(actionSource, contains('static const double extent = 48;'));
    expect(actionSource, contains('static const double iconSize = 20;'));
    expect(actionSource, contains('width: extent'));
    expect(actionSource, contains('height: extent'));
    expect(source, contains('size: _TodayHeaderAction.iconSize'));
  });

  test('오늘과 지도 탭은 같은 3D 지도와 컨트롤러를 재사용하며 지도 제스처를 켠다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(homeSource, contains('final GlobalKey _sharedMapKey'));
    expect(homeSource, contains('mapKey: _sharedMapKey'));
    expect(homeSource, contains('mapController: _mapPanelController'));
    expect(homeSource, contains('key: _sharedMapKey'));
    expect(todaySource, contains('mapGesturesEnabled: true'));
    expect(todaySource, isNot(contains('mapGesturesEnabled: false')));
    expect(todaySource, contains('suspendMapGestures'));
    expect(todaySource, contains('clearMapGestureSuspension'));
  });

  test('오늘 화면은 첫 터치에 사라지는 환영 가이드와 최소화 패널을 제공한다', () {
    final source = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('MapHintOverlay('));
    expect(source, contains('환영합니다! 매일 3가지로 주님과 동행해요!'));
    expect(source, contains('① 이야기 탐험'));
    expect(source, contains('(최근 감정을 새긴 다음 이야기가 추천되요)'));
    expect(source, contains('② 신앙 다이어리'));
    expect(source, contains('③ 통독'));
    expect(source, contains("(기록은 '내정보'에 쌓여요)"));
    expect(source, contains('_showWelcomeGuide'));
    expect(source, contains('onPointerDown: (_) => _dismissWelcomeGuide()'));
    expect(source, contains('IgnorePointer('));
    expect(source, contains('AnimatedContainer('));
    expect(source, contains('_todayPanelCollapsedHeight'));
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
  });

  test('오늘 패널은 지도 패널과 공유하는 표면과 모바일 배치를 쓴다', () {
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();
    final mapSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final overlaySource = File(
      'lib/widgets/home/home_journey_overlay.dart',
    ).readAsStringSync();

    expect(todaySource, contains('storyBottomPanelHorizontalMargin'));
    expect(mapSource, contains('storyBottomPanelHorizontalMargin'));
    expect(todaySource, contains('bottom: 0'));
    expect(overlaySource, contains('storyBottomPanelDecoration(context)'));
  });

  test('선택된 오늘 탭을 다시 누르면 환영 가이드를 다시 보여 준다', () {
    final homeSource = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final todaySource = File(
      'lib/widgets/home/today_home_page.dart',
    ).readAsStringSync();

    expect(homeSource, contains('TodayHomePageController'));
    expect(homeSource, contains('showWelcomeGuide()'));
    expect(todaySource, contains('class TodayHomePageController'));
    expect(todaySource, contains('void showWelcomeGuide()'));
  });

  test('지도 탭을 벗어나면 지도 탐색 선택을 첫 단계로 초기화한다', () {
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
      contains('if (leavingMap) {\n      _resetMapTabExploration();'),
    );
    expect(resetSource, contains('controller.clearMapExplorationSelection();'));
    expect(resetSource, contains('_selectionStep = 1;'));
    expect(resetSource, contains('_mode = null;'));
    expect(
      resetSource,
      contains('_selectionPanelStage = StorySelectionPanelStage.expanded;'),
    );
  });
}
