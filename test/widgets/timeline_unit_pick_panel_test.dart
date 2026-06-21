import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/widgets/v2/timeline_unit_pick_panel.dart';

void main() {
  testWidgets('시간순 구간 선택은 가로 카드 레일만 보여준다', (tester) async {
    String? toggledUnitCode;
    var selectedAll = false;
    var clearedAll = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 240,
            child: TimelineUnitPickPanel(
              events: [
                _event(
                  'primeval_creation_mission',
                  '창조와 사람의 사명',
                  1,
                  title: '창조와 사람의 사명 첫 이야기',
                  globalRank: 1,
                ),
                _event(
                  'primeval_creation_mission',
                  '창조와 사람의 사명',
                  1,
                  title: '창조와 사람의 사명 마지막 이야기',
                  summary: '사람에게 에덴의 사명이 주어진다',
                  globalRank: 2,
                ),
                _event('u2', '족장들의 길', 2, globalRank: 3),
                _event('u3', '출애굽 여정', 3, globalRank: 4),
                _event('u4', '광야 훈련', 4, globalRank: 5),
                _event('u5', '약속의 땅', 5, globalRank: 6),
              ],
              selectedUnitCodes: const {'primeval_creation_mission'},
              onToggleUnit: (code) => toggledUnitCode = code,
              onSelectAll: () => selectedAll = true,
              onClearAll: () => clearedAll = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('보고 싶은 구간'), findsNothing);
    expect(find.text('구간 선택'), findsOneWidget);
    expect(find.text('전체 선택'), findsOneWidget);
    expect(find.text('전체 해제'), findsNothing);
    expect(find.text('1개 구간 다음'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.scrollDirection, Axis.horizontal);
    expect(listView.padding, const EdgeInsets.fromLTRB(16, 8, 16, 12));

    final firstCard = find.byKey(
      const ValueKey('timeline-unit-card-primeval_creation_mission'),
    );
    expect(tester.getSize(firstCard).width, inInclusiveRange(96, 98));
    expect(tester.getSize(firstCard).height, 136);

    final titleRect = tester.getRect(find.text('1. 창조와 사람의 사명'));
    final countRect = tester.getRect(find.text('2개 이야기'));
    expect(countRect.top - titleRect.bottom, lessThanOrEqualTo(5));

    final subtitle = find.text('세상을 창조하시고 사람에게 처음 사명을 맡기십니다.');
    final subtitleRect = tester.getRect(subtitle);
    final cardRect = tester.getRect(firstCard);
    expect(subtitleRect.bottom, lessThanOrEqualTo(cardRect.bottom));
    final subtitleWidget = tester.widget<Text>(subtitle);
    expect(subtitleWidget.maxLines, 4);
    expect(subtitleWidget.overflow, TextOverflow.clip);
    expect(find.textContaining('→'), findsNothing);

    await tester.tap(find.text('1. 창조와 사람의 사명'));

    expect(toggledUnitCode, 'primeval_creation_mission');
    await tester.tap(find.text('전체 선택'));
    expect(selectedAll, isTrue);
    expect(clearedAll, isFalse);
  });

  testWidgets('시간순 구간 카드 설명은 35자 안팎의 짧은 문장으로 렌더링한다', (tester) async {
    const firstSummary = '긴 여정의 시작에서 하나님이 사람에게 맡기신 사명과 선택의 무게를 차분히 보여준다';
    const lastSummary = '무너진 관계 속에서도 하나님이 다시 길을 여시는 장면까지 이어진다';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 270,
            child: TimelineUnitPickPanel(
              events: [
                _event(
                  'u1',
                  '창조와 에덴의 긴 이야기',
                  1,
                  summary: firstSummary,
                  globalRank: 1,
                ),
                _event(
                  'u1',
                  '창조와 에덴의 긴 이야기',
                  1,
                  summary: lastSummary,
                  globalRank: 2,
                ),
                _event('u2', '족장들의 길', 2, globalRank: 3),
              ],
              selectedUnitCodes: const {'u1'},
              onToggleUnit: (_) {},
              onSelectAll: () {},
              onClearAll: () {},
            ),
          ),
        ),
      ),
    );

    final subtitle = find.textContaining('흐름을 이어 봅니다.');
    expect(subtitle, findsOneWidget);
    final subtitleWidget = tester.widget<Text>(subtitle);
    expect(subtitleWidget.data!.runes.length, lessThanOrEqualTo(35));
    expect(subtitleWidget.maxLines, 4);
    expect(subtitleWidget.overflow, TextOverflow.clip);
    expect(find.textContaining('먼저'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('시간순 신약 구간 카드도 짧은 curated 설명을 렌더링한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 240,
            child: TimelineUnitPickPanel(
              events: [
                _event('birth_early_ministry', '탄생과 초기 사역', 1, globalRank: 1),
                _event('birth_early_ministry', '탄생과 초기 사역', 1, globalRank: 2),
              ],
              selectedUnitCodes: const {'birth_early_ministry'},
              onToggleUnit: (_) {},
              onSelectAll: () {},
              onClearAll: () {},
            ),
          ),
        ),
      ),
    );

    const description = '탄생과 세례를 지나 예수님의 사역 길이 열립니다.';
    final subtitle = find.text(description);
    expect(subtitle, findsOneWidget);
    final subtitleWidget = tester.widget<Text>(subtitle);
    expect(subtitleWidget.data!.runes.length, inInclusiveRange(25, 35));
    expect(subtitleWidget.maxLines, 4);
    expect(subtitleWidget.overflow, TextOverflow.clip);
  });

  testWidgets('아주크게 글자 크기에서도 시간순 구간 카드가 overflow 되지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              height: 230,
              child: TimelineUnitPickPanel(
                events: [
                  _event(
                    'divided_two_kingdoms_north_fall',
                    '두 왕국과 북이스라엘의 멸망',
                    1,
                    title: '두 왕국과 북이스라엘의 멸망 첫 이야기',
                    globalRank: 1,
                  ),
                  _event(
                    'divided_two_kingdoms_north_fall',
                    '두 왕국과 북이스라엘의 멸망',
                    1,
                    title: '두 왕국과 북이스라엘의 멸망 마지막 이야기',
                    globalRank: 2,
                  ),
                ],
                selectedUnitCodes: const {'divided_two_kingdoms_north_fall'},
                onToggleUnit: (_) {},
                onSelectAll: () {},
                onClearAll: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final firstCard = find.byKey(
      const ValueKey('timeline-unit-card-divided_two_kingdoms_north_fall'),
    );
    expect(firstCard, findsOneWidget);
    expect(tester.getSize(firstCard).height, greaterThan(0));
    expect(find.text('1. 두 왕국과 북이스라엘의 멸망'), findsOneWidget);
    expect(find.text('두 왕국이 흔들리다 북이스라엘이 끝내 무너집니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('시간순 구간 전체 선택 버튼은 모두 선택되면 전체 해제로 바뀐다', (tester) async {
    var clearedAll = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 240,
            child: TimelineUnitPickPanel(
              events: [
                _event('u1', '창조와 타락', 1, globalRank: 1),
                _event('u2', '족장들의 길', 2, globalRank: 2),
                _event('u3', '출애굽 여정', 3, globalRank: 3),
              ],
              selectedUnitCodes: const {'u1', 'u2', 'u3'},
              onToggleUnit: (_) {},
              onSelectAll: () {},
              onClearAll: () => clearedAll = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('전체 해제'), findsOneWidget);
    expect(find.text('전체 선택'), findsNothing);

    await tester.tap(find.text('전체 해제'));

    expect(clearedAll, isTrue);
  });

  test('시간순 구간 선택 시트는 가로 1줄 높이만 사용한다', () {
    final source = File(
      'lib/screens/story_home_screen_state.dart',
    ).readAsStringSync();
    final timelineBranchStart = source.indexOf(
      'if (_mode == _SelectionMode.timeline && _selectionStep == 2)',
    );
    final timelineBranchEnd = source.indexOf(
      'return _sheetFractionForHeight(\n      size,\n      _selectionSheetCardOnlyHeight',
      timelineBranchStart,
    );
    final timelineBranch = source.substring(
      timelineBranchStart,
      timelineBranchEnd,
    );

    expect(source, contains('timelineUnitPickPanelSheetHeightFor(context)'));
    expect(timelineBranch, contains('timelineUnitPickPanelSheetHeightFor'));
    expect(timelineBranch, contains('max: 0.42'));
    expect(timelineBranch, isNot(contains('rowCount')));
    expect(timelineBranch, isNot(contains('unitCount')));
  });
}

StoryEvent _event(
  String unitCode,
  String unitTitle,
  int order, {
  String? title,
  String? summary,
  int? globalRank,
}) {
  final rank = globalRank ?? order;
  return StoryEvent(
    id: 'event_${unitCode}_$rank',
    eraId: 'era_primeval',
    title: title ?? '$unitTitle 첫 이야기',
    summary: summary ?? '하나님이 세상을 창조하신다',
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: order,
    unitCode: unitCode,
    unitTitle: unitTitle,
    unitOrder: order,
    rankInEra: order,
    globalRank: rank,
    landmarkId: 'landmark',
    placeName: '장소',
    lat: 0,
    lng: 0,
    characterCodes: const [],
    bibleRefs: const [],
  );
}
