import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/widgets/v2/timeline_unit_pick_panel.dart';

void main() {
  testWidgets('시간순 단위 선택은 가로 카드 레일만 보여준다', (tester) async {
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
                _event('u1', '창조와 타락', 1, title: '창조와 타락 첫 이야기', globalRank: 1),
                _event(
                  'u1',
                  '창조와 타락',
                  1,
                  title: '창조와 타락 마지막 이야기',
                  summary: '사람에게 에덴의 사명이 주어진다',
                  globalRank: 2,
                ),
                _event('u2', '족장들의 길', 2, globalRank: 3),
                _event('u3', '출애굽 여정', 3, globalRank: 4),
                _event('u4', '광야 훈련', 4, globalRank: 5),
                _event('u5', '약속의 땅', 5, globalRank: 6),
              ],
              selectedUnitCodes: const {'u1'},
              onToggleUnit: (code) => toggledUnitCode = code,
              onSelectAll: () => selectedAll = true,
              onClearAll: () => clearedAll = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('보고 싶은 단위'), findsNothing);
    expect(find.text('단위 선택'), findsOneWidget);
    expect(find.text('전체 선택'), findsOneWidget);
    expect(find.text('전체 해제'), findsNothing);
    expect(find.text('1개 단위 다음'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.scrollDirection, Axis.horizontal);
    expect(listView.padding, const EdgeInsets.fromLTRB(16, 8, 16, 12));

    final firstCard = find.byKey(const ValueKey('timeline-unit-card-u1'));
    expect(tester.getSize(firstCard).width, inInclusiveRange(96, 98));

    final titleRect = tester.getRect(find.text('1. 창조와 타락'));
    final countRect = tester.getRect(find.text('2개 이야기'));
    expect(countRect.top - titleRect.bottom, lessThanOrEqualTo(5));

    final subtitle = find.text('먼저 하나님이 세상을 창조하신다. 이어 사람에게 에덴의 사명이 주어진다.');
    final subtitleRect = tester.getRect(subtitle);
    final cardRect = tester.getRect(firstCard);
    expect(subtitleRect.bottom, lessThanOrEqualTo(cardRect.bottom));
    final subtitleWidget = tester.widget<Text>(subtitle);
    expect(subtitleWidget.maxLines, 8);
    expect(subtitleWidget.overflow, TextOverflow.clip);
    expect(find.textContaining('→'), findsNothing);

    await tester.tap(find.text('1. 창조와 타락'));

    expect(toggledUnitCode, 'u1');
    await tester.tap(find.text('전체 선택'));
    expect(selectedAll, isTrue);
    expect(clearedAll, isFalse);
  });

  testWidgets('시간순 단위 카드 설명은 길어도 ellipsis 없이 전체 문장을 렌더링한다', (tester) async {
    const firstSummary = '긴 여정의 시작에서 하나님이 사람에게 맡기신 사명과 선택의 무게를 차분히 보여준다';
    const lastSummary = '마지막에는 무너진 관계 속에서도 하나님이 다시 길을 여시는 장면까지 이어진다';

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

    final subtitle = find.textContaining('먼저 긴 여정의 시작에서');
    expect(subtitle, findsOneWidget);
    final subtitleWidget = tester.widget<Text>(subtitle);
    expect(subtitleWidget.data!.runes.length, lessThanOrEqualTo(89));
    expect(subtitleWidget.maxLines, 8);
    expect(subtitleWidget.overflow, TextOverflow.clip);
    expect(tester.takeException(), isNull);
  });

  testWidgets('시간순 단위 전체 선택 버튼은 모두 선택되면 전체 해제로 바뀐다', (tester) async {
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

  test('시간순 단위 선택 시트는 가로 1줄 높이만 사용한다', () {
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

    expect(source, contains('_selectionSheetTimelineUnitHeight'));
    expect(
      source,
      contains('static const double _selectionSheetTimelineUnitHeight = 300'),
    );
    expect(timelineBranch, contains('_selectionSheetTimelineUnitHeight'));
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
