import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/widgets/v2/home_intro_panel.dart';

const _eras = [
  Era(
    id: 'era_patriarch',
    code: 'era_patriarch',
    testament: 'old',
    name: '족장 시대',
    displayOrder: 2,
    startYear: -2166,
    endYear: -1805,
    mapCenterLat: 31.5,
    mapCenterLng: 35.2,
    mapZoom: 5.4,
  ),
  Era(
    id: 'era_exodus',
    code: 'era_exodus',
    testament: 'old',
    name: '출애굽 시대',
    displayOrder: 3,
    startYear: -1446,
    endYear: -1406,
    mapCenterLat: 30.0,
    mapCenterLng: 35.0,
    mapZoom: 5.0,
  ),
  Era(
    id: 'era_judges',
    code: 'era_judges',
    testament: 'old',
    name: '사사 시대',
    displayOrder: 4,
    startYear: -1406,
    endYear: -1050,
    mapCenterLat: 31.8,
    mapCenterLng: 35.1,
    mapZoom: 5.4,
  ),
  Era(
    id: 'era_monarchy',
    code: 'era_monarchy',
    testament: 'old',
    name: '왕정 시대',
    displayOrder: 5,
    startYear: -1050,
    endYear: -930,
    mapCenterLat: 31.9,
    mapCenterLng: 35.2,
    mapZoom: 5.3,
  ),
  Era(
    id: 'era_divided_kingdom',
    code: 'era_divided_kingdom',
    testament: 'old',
    name: '분열왕국 시대',
    displayOrder: 6,
    startYear: -930,
    endYear: -586,
    mapCenterLat: 32.2,
    mapCenterLng: 35.25,
    mapZoom: 5.7,
  ),
  Era(
    id: 'era_exile_return',
    code: 'era_exile_return',
    testament: 'old',
    name: '포로 및 포로 후기 시대',
    displayOrder: 7,
    startYear: -586,
    endYear: -430,
    mapCenterLat: 32.2,
    mapCenterLng: 38.3,
    mapZoom: 4.7,
  ),
  Era(
    id: 'era_nt_apostolic',
    code: 'era_nt_apostolic',
    testament: 'new',
    name: '사도의 시대',
    displayOrder: 2,
    startYear: 33,
    endYear: 70,
    mapCenterLat: 37.4,
    mapCenterLng: 26.9,
    mapZoom: 4.9,
  ),
  Era(
    id: 'era_nt_post_apostolic',
    code: 'era_nt_post_apostolic',
    testament: 'new',
    name: '후기 사도의 시대',
    displayOrder: 3,
    startYear: 45,
    endYear: 100,
    mapCenterLat: 37.45,
    mapCenterLng: 27.2,
    mapZoom: 5.2,
  ),
  Era(
    id: 'era_nt_consummation',
    code: 'era_nt_consummation',
    testament: 'new',
    name: '역사의 종결',
    displayOrder: 4,
    startYear: null,
    endYear: null,
    mapCenterLat: 31.78,
    mapCenterLng: 35.22,
    mapZoom: 4.4,
  ),
];

void main() {
  Widget homeIntroHarness({
    required double width,
    required double height,
    required String? selectedEraId,
    required void Function(SelectionMode) onPickMode,
    double textScale = 1,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: selectedEraId,
              onSelectEra: (_) {},
              onPickMode: onPickMode,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('시간 순으로 보기 버튼은 timeline 모드를 선택한다', (tester) async {
    SelectionMode? pickedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: 'era_divided_kingdom',
              onSelectEra: (_) {},
              onPickMode: (mode) => pickedMode = mode,
            ),
          ),
        ),
      ),
    );

    expect(find.text('시간 순'), findsOneWidget);
    expect(find.textContaining('오늘은 성경'), findsNothing);
    expect(find.text('선택한 시대의 사건을\n시간 순으로 봅니다'), findsOneWidget);
    expect(find.text('인물과 걷기'), findsOneWidget);
    expect(find.text('선택한 인물의 사건을\n시간 순으로 봅니다'), findsOneWidget);
    expect(find.text('장소로 시작'), findsOneWidget);
    expect(find.text('한 장소에서 이야기를\n시간 순으로 봅니다'), findsOneWidget);
    expect(
      tester.getCenter(find.text('시간 순')).dx,
      lessThan(tester.getCenter(find.text('인물과 걷기')).dx),
    );
    expect(
      tester.getCenter(find.text('인물과 걷기')).dx,
      lessThan(tester.getCenter(find.text('장소로 시작')).dx),
    );

    await tester.tap(find.text('시간 순'));
    expect(pickedMode, SelectionMode.timeline);
  });

  testWidgets('아주크게 글자 크기에서도 보기 방식 3개 카드를 한 줄로 유지한다', (tester) async {
    await tester.pumpWidget(
      homeIntroHarness(
        width: 390,
        height: 720,
        selectedEraId: 'era_divided_kingdom',
        textScale: 1.4,
        onPickMode: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final timelineCard = find.byKey(const ValueKey('home-mode-timeline'));
    final characterCard = find.byKey(const ValueKey('home-mode-character'));
    final regionCard = find.byKey(const ValueKey('home-mode-region'));
    expect(timelineCard, findsOneWidget);
    expect(characterCard, findsOneWidget);
    expect(regionCard, findsOneWidget);

    expect(
      tester.getTopLeft(timelineCard).dy,
      tester.getTopLeft(characterCard).dy,
    );
    expect(
      tester.getTopLeft(characterCard).dy,
      tester.getTopLeft(regionCard).dy,
    );
    expect(
      tester.getCenter(timelineCard).dx,
      lessThan(tester.getCenter(characterCard).dx),
    );
    expect(
      tester.getCenter(characterCard).dx,
      lessThan(tester.getCenter(regionCard).dx),
    );

    final timelineSubtitle = find.text('선택한 시대의 사건을\n시간 순으로 봅니다');
    final characterSubtitle = find.text('선택한 인물의 사건을\n시간 순으로 봅니다');
    final regionSubtitle = find.text('한 장소에서 이야기를\n시간 순으로 봅니다');
    expect(timelineSubtitle, findsOneWidget);
    expect(characterSubtitle, findsOneWidget);
    expect(regionSubtitle, findsOneWidget);

    expect(
      tester.getRect(timelineSubtitle).bottom,
      lessThanOrEqualTo(tester.getRect(timelineCard).bottom),
    );
    expect(
      tester.getRect(characterSubtitle).bottom,
      lessThanOrEqualTo(tester.getRect(characterCard).bottom),
    );
    expect(
      tester.getRect(regionSubtitle).bottom,
      lessThanOrEqualTo(tester.getRect(regionCard).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈 인트로 패널은 하단 빈 공간을 줄인 패딩을 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: 'era_divided_kingdom',
              onSelectEra: (_) {},
              onPickMode: (_) {},
            ),
          ),
        ),
      ),
    );

    final scrollViews = tester.widgetList<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scrollViews.any(
        (scrollView) =>
            scrollView.padding == const EdgeInsets.fromLTRB(16, 12, 0, 10),
      ),
      isTrue,
    );
  });

  testWidgets('시대 칩 가로 레일은 오른쪽 패널 끝까지 쓰고 마지막 여백을 둔다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 720,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: null,
              onSelectEra: (_) {},
              onPickMode: (_) {},
            ),
          ),
        ),
      ),
    );

    final horizontalScrollViews = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((scrollView) => scrollView.scrollDirection == Axis.horizontal)
        .toList();

    expect(horizontalScrollViews, hasLength(2));
    for (final scrollView in horizontalScrollViews) {
      expect(scrollView.padding, const EdgeInsetsDirectional.only(end: 16));
    }
    expect(find.byType(UnconstrainedBox), findsNothing);
  });

  testWidgets('선택된 시대 단계는 흐려진 뒤 다시 눌러도 시대를 바꾸지 않는다', (tester) async {
    var selectCount = 0;
    SelectionMode? pickedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: 'era_divided_kingdom',
              onSelectEra: (_) => selectCount++,
              onPickMode: (mode) => pickedMode = mode,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('출애굽'), warnIfMissed: false);
    await tester.tap(find.text('분열왕국'), warnIfMissed: false);

    expect(selectCount, 0);

    await tester.tap(find.text('장소로 시작'));
    expect(pickedMode, SelectionMode.region);
  });

  testWidgets('시대 선택 칩은 짧은 라벨을 쓰고 검수 전 시대를 숨긴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 760,
            height: 720,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: null,
              onSelectEra: (_) {},
              onPickMode: (_) {},
            ),
          ),
        ),
      ),
    );

    for (final label in [
      '족장',
      '출애굽',
      '사사',
      '통일 왕국',
      '분열왕국',
      '포로 및 포로 후기',
      '사도',
      '후기 사도',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    for (final label in [
      '족장 시대',
      '출애굽 시대',
      '사사 시대',
      '왕정 시대',
      '분열왕국 시대',
      '포로 및 포로 후기 시대',
      '사도의 시대',
      '후기 사도의 시대',
      '역사의 종결',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });

  test('홈 인트로 시트는 콘텐츠에 맞는 낮은 높이로 열린다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(source, contains('_selectionSheetIntroHeight = 430'));
    expect(source, contains('max: 0.38'));
  });

  test('Android 폰은 시스템 inset 이 0이어도 하단 시트 여백을 보정한다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();

    expect(source, contains('_androidPhoneNavigationFallbackInset'));
    expect(source, contains('double _bottomSheetSafeInsetFor('));
    expect(source, contains('defaultTargetPlatform == TargetPlatform.android'));
    expect(source, contains('rawBottomInset > 0'));
    expect(source, contains('_bottomSheetSafeInsetFor('));
  });
}
