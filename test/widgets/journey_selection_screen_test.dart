import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/journey_selection.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/screens/journey_selection/book_journey_screen.dart';
import 'package:story_bible/screens/journey_selection/partial_journey_screen.dart';
import 'package:story_bible/screens/journey_selection/person_journey_screen.dart';
import 'package:story_bible/screens/journey_selection_screen.dart';
import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/state/journey_selection_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';

const _era = Era(
  id: 'era-primeval',
  code: 'era_primeval',
  testament: 'old',
  name: '원역사',
  displayOrder: 1,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _adam = Character(
  id: 'character-adam',
  code: 'adam',
  name: '아담',
  tagline: null,
  description: null,
  avatarUrl: null,
  displayOrder: 1,
  eraCodes: ['era_primeval'],
);

const _apostolicEra = Era(
  id: 'era-apostolic',
  code: 'era_nt_apostolic',
  testament: 'new',
  name: '사도',
  displayOrder: 2,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _publicMinistryEra = Era(
  id: 'era-public-ministry',
  code: 'era_nt_public_ministry',
  testament: 'new',
  name: '예수님의 공생애',
  displayOrder: 1,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _exileEra = Era(
  id: 'era-exile-return',
  code: 'era_exile_return',
  testament: 'old',
  name: '포로 및 포로 후기',
  displayOrder: 7,
  startYear: null,
  endYear: null,
  mapCenterLat: null,
  mapCenterLng: null,
  mapZoom: null,
);

const _paul = Character(
  id: 'character-paul',
  code: 'paul',
  name: '바울',
  tagline: null,
  description: null,
  avatarUrl: null,
  displayOrder: 2,
  eraCodes: ['era_nt_apostolic'],
);

class _JourneyStoryController extends StoryController {
  @override
  StoryState build() => const StoryState(loading: false, eras: [_era]);
}

void main() {
  testWidgets('전체 310개가 기본이고 일부 구간 적용 뒤 선택 상태와 진행률을 유지한다', (tester) async {
    final catalog = _catalog(eventCount: 310);
    final container = await _pumpWithCatalog(
      tester,
      catalog: catalog,
      child: const JourneySelectionScreen(),
    );

    _expectPlainJourneyHeader(tester, title: '여정 선택');
    expect(find.text('아래 4가지 버튼에서 여정 방식을 선택해주세요'), findsOneWidget);
    expect(find.text('시간 순으로 차근차근'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(
      (tester.getCenter(find.text('시간 순으로 차근차근')).dy -
              tester.getCenter(find.text('추천')).dy)
          .abs(),
      lessThan(2),
    );
    final chronologicalTitle = tester.widget<Text>(find.text('시간 순으로 차근차근'));
    final targetedTitle = tester.widget<Text>(find.text('특정 방식으로 시작하기'));
    expect(chronologicalTitle.style?.fontSize, targetedTitle.style?.fontSize);
    expect(chronologicalTitle.style?.fontWeight, FontWeight.w700);
    expect(targetedTitle.style?.fontWeight, FontWeight.w700);

    final recommendation = tester.widget<Container>(
      find.byKey(const ValueKey('journey-recommendation-badge')),
    );
    final recommendationDecoration =
        recommendation.decoration! as BoxDecoration;
    expect(
      recommendationDecoration.color,
      AppColorPalette.colorfulMap.currentFill,
    );
    final recommendationText = tester.widget<Text>(find.text('추천'));
    expect(recommendationText.style?.color, AppColorPalette.colorfulMap.text);
    expect(find.text('1. 전체 순서'), findsOneWidget);
    expect(find.text('2. 일부 구간 선택'), findsOneWidget);
    expect(find.text('3. 성경책으로 찾기'), findsOneWidget);
    expect(find.text('4. 인물로 찾기'), findsOneWidget);
    expect(find.text('성경 전체 이야기를 시간 순으로 걸어요'), findsOneWidget);
    final allDescription = tester.widget<Text>(
      find.text('성경 전체 이야기를 시간 순으로 걸어요'),
    );
    expect(allDescription.overflow, isNot(TextOverflow.ellipsis));
    final allChoice = find.byKey(const ValueKey('journey-choice-all'));
    expect(
      (tester
                  .getCenter(
                    find.descendant(
                      of: allChoice,
                      matching: find.byIcon(Icons.route_rounded),
                    ),
                  )
                  .dy -
              tester
                  .getCenter(
                    find.descendant(
                      of: allChoice,
                      matching: find.text('1. 전체 순서'),
                    ),
                  )
                  .dy)
          .abs(),
      lessThan(2),
    );
    expect(
      find.descendant(of: allChoice, matching: find.textContaining('/310')),
      findsNothing,
    );
    expect(find.text('선택된 이야기 정보'), findsOneWidget);
    expect(find.text('310개 이야기 중 0개 해결'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('journey-choice-all'))).height,
      lessThan(150),
    );
    final allChoiceSurface = tester.widget<Material>(
      find.descendant(of: allChoice, matching: find.byType(Material)).first,
    );
    expect(allChoiceSurface.color, Colors.white);
    expect(container.read(journeySelectionProvider).source, JourneySource.all);
    await tester.tap(find.text('2. 일부 구간 선택'));
    await tester.pumpAndSettle();
    _expectPlainJourneyHeader(tester, title: '일부 구간 선택');
    expect(find.text('걷고 싶은 시대와 구간을 골라주세요'), findsNothing);
    expect(find.text('시대 전체를 체크하거나 펼친 뒤 소분류를 여러 개 선택할 수 있어요.'), findsNothing);
    expect(find.text('0개 구간 선택'), findsNothing);
    expect(find.textContaining('해결'), findsNothing);
    expect(find.text('세상의 시작과 첫 사람들'), findsOneWidget);
    expect(find.text('창세기'), findsOneWidget);
    expect(find.text('원역사'), findsOneWidget);
    expect(find.text('창조와 사람의 사명'), findsNothing);
    expect(find.byKey(const ValueKey('partial-journey-apply')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('journey-partial-testament-old')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('journey-partial-testament-new')),
      findsOneWidget,
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    final apply = find.text('선택한 310개 이야기로 시작');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(
      container.read(journeySelectionProvider).source,
      JourneySource.segments,
    );
    expect(find.text('창조와 사람의 사명'), findsOneWidget);
    expect(find.text('선택 구간 · 창조와 사람의 사명'), findsOneWidget);
    expect(find.text('310개 이야기 중 0개 해결'), findsOneWidget);
    final selectedInfo = find.byKey(const ValueKey('selected-journey-info'));
    expect(
      find.descendant(
        of: selectedInfo,
        matching: find.byKey(const ValueKey('selected-journey-info-accent')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: selectedInfo,
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
      findsNothing,
    );
    final selectedInfoDecoration =
        tester.widget<Container>(selectedInfo).decoration! as BoxDecoration;
    expect(selectedInfoDecoration.border, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('journey-choice-segments')),
        matching: find.textContaining('/310'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('1. 전체 순서'));
    await tester.pumpAndSettle();
    expect(find.text('전체 순서로 설정하시겠습니까?'), findsOneWidget);
    expect(
      container.read(journeySelectionProvider).source,
      JourneySource.segments,
    );
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(container.read(journeySelectionProvider).source, JourneySource.all);
  });

  testWidgets('크게 글자에서도 네 여정 버튼 정보는 말줄임표 없이 모두 표시한다', (tester) async {
    await _pumpWithCatalog(
      tester,
      catalog: _catalog(eventCount: 4),
      textScale: 1.4,
      child: const JourneySelectionScreen(),
    );

    for (final source in ['all', 'segments', 'book', 'person']) {
      final choice = find.byKey(ValueKey('journey-choice-$source'));
      final texts = tester.widgetList<Text>(
        find.descendant(of: choice, matching: find.byType(Text)),
      );
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('추천 라벨은 다크 테마에서도 팔레트 대비색을 사용한다', (tester) async {
    await _pumpWithCatalog(
      tester,
      catalog: _catalog(eventCount: 1),
      palette: AppColorPalette.blackMap,
      child: const JourneySelectionScreen(),
    );

    final recommendation = tester.widget<Container>(
      find.byKey(const ValueKey('journey-recommendation-badge')),
    );
    final decoration = recommendation.decoration! as BoxDecoration;
    expect(decoration.color, AppColorPalette.blackMap.currentFill);
    expect(
      tester.widget<Text>(find.text('추천')).style?.color,
      AppColorPalette.blackMap.text,
    );
    final allChoice = find.byKey(const ValueKey('journey-choice-all'));
    final allChoiceSurface = tester.widget<Material>(
      find.descendant(of: allChoice, matching: find.byType(Material)).first,
    );
    expect(allChoiceSurface.color, Colors.black);
  });

  testWidgets('일부 구간은 처음 닫히고 일부 선택된 시대만 다시 펼쳐진다', (tester) async {
    final catalog = _multiUnitCatalog();
    await _pumpWithCatalog(
      tester,
      catalog: catalog,
      child: const JourneySelectionScreen(),
    );

    await tester.tap(find.text('2. 일부 구간 선택'));
    await tester.pumpAndSettle();
    expect(find.text('창조와 사람의 사명'), findsNothing);
    expect(find.text('에덴 밖 세상'), findsNothing);
    expect(find.text('창세기 · 출애굽기'), findsOneWidget);
    final eraTitleScroll = find.byKey(
      const ValueKey('journey-era-title-scroll-era_primeval'),
    );
    expect(eraTitleScroll, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(eraTitleScroll).scrollDirection,
      Axis.horizontal,
    );
    expect(
      find.byKey(const ValueKey('journey-era-label-era_primeval')),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: eraTitleScroll, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );

    await tester.tap(find.text('세상의 시작과 첫 사람들'));
    await tester.pump();
    expect(find.text('창조와 사람의 사명'), findsOneWidget);
    expect(find.text('에덴 밖 세상'), findsOneWidget);
    final creationRow = find.byKey(
      const ValueKey('journey-unit-era-primeval::creation'),
    );
    final creationCheckbox = find.descendant(
      of: creationRow,
      matching: find.byType(Checkbox),
    );
    final creationTitle = find.descendant(
      of: creationRow,
      matching: find.text('창조와 사람의 사명'),
    );
    expect(
      (tester.getCenter(creationCheckbox).dy -
              tester.getCenter(creationTitle).dy)
          .abs(),
      lessThan(2),
    );
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(
              const ValueKey(
                'journey-unit-title-scroll-era-primeval::creation',
              ),
            ),
          )
          .scrollDirection,
      Axis.horizontal,
    );

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(find.text('선택한 1개 이야기로 시작'), findsOneWidget);
    await tester.tap(find.text('선택한 1개 이야기로 시작'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2. 일부 구간 선택'));
    await tester.pumpAndSettle();
    expect(find.text('창조와 사람의 사명'), findsOneWidget);
    expect(find.text('에덴 밖 세상'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('창조와 사람의 사명'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
  });

  testWidgets('일부 구간은 구약·신약을 필터링하고 선택은 필터 전환 뒤에도 유지한다', (tester) async {
    final catalog = _testamentJourneyCatalog();
    await _pumpWithCatalog(
      tester,
      catalog: catalog,
      child: PartialJourneyScreen(catalog: catalog),
    );

    expect(find.text('세상의 시작과 첫 사람들'), findsOneWidget);
    expect(find.text('예수님의 삶과 가르침'), findsNothing);
    await tester.tap(find.text('세상의 시작과 첫 사람들'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('journey-unit-era-primeval::creation')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(find.text('선택한 1개 이야기로 시작'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('journey-partial-testament-new')),
    );
    await tester.pump();
    expect(find.text('세상의 시작과 첫 사람들'), findsNothing);
    expect(find.text('예수님의 삶과 가르침'), findsOneWidget);
    expect(find.text('선택한 1개 이야기로 시작'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('journey-partial-testament-old')),
    );
    await tester.pump();
    expect(find.text('창조와 사람의 사명'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.byKey(
                const ValueKey('journey-unit-era-primeval::creation'),
              ),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('양쪽 성약에 일부 선택이 저장되면 처음 보이는 시대를 각각 펼친다', (tester) async {
    final catalog = _crossTestamentPartialCatalog();
    await _pumpWithCatalog(
      tester,
      catalog: catalog,
      initialSelection: const JourneySelection(
        source: JourneySource.segments,
        scope: JourneyScope.units,
        unitKeys: {
          'era-primeval::creation',
          'era-public-ministry::public_ministry',
        },
      ),
      child: PartialJourneyScreen(catalog: catalog),
    );

    expect(find.text('창조와 사람의 사명'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('journey-partial-testament-new')),
    );
    await tester.pump();
    expect(find.text('산상수훈과 하나님 나라'), findsOneWidget);
    expect(find.text('비유로 배우는 하나님 나라'), findsOneWidget);
  });

  testWidgets('긴 시대 제목과 시대 라벨은 한 줄 가로 스크롤과 우측 페이드를 사용한다', (tester) async {
    final catalog = _longEraJourneyCatalog();
    await _pumpWithCatalog(
      tester,
      catalog: catalog,
      textScale: 1.4,
      child: PartialJourneyScreen(catalog: catalog),
    );

    final scroll = find.byKey(
      const ValueKey('journey-era-title-scroll-era_exile_return'),
    );
    expect(scroll, findsOneWidget);
    expect(find.text('포로 및 포로 후기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('journey-era-label-era_exile_return')),
      findsOneWidget,
    );
    final scrollView = tester.widget<SingleChildScrollView>(scroll);
    expect(scrollView.controller?.position.maxScrollExtent, greaterThan(0));
    expect(
      find.ancestor(of: scroll, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('성경책은 실제 연결 수로 활성화하고 이야기가 없는 권은 비활성화한다', (tester) async {
    final catalog = _catalog(eventCount: 2);
    final container = await _pumpWithCatalog(
      tester,
      catalog: catalog,
      child: BookJourneyScreen(catalog: catalog, engravedEventIds: const {}),
    );

    _expectPlainJourneyHeader(tester, title: '성경책으로 찾기');
    expect(find.text('어떤 성경책이 궁금한가요?'), findsNothing);
    expect(find.text('연결된 이야기가 없는 권은 비활성화되어 있어요.'), findsNothing);

    final genesisInk = find.ancestor(
      of: find.text('창세기'),
      matching: find.byType(InkWell),
    );
    final psalmsInk = find.ancestor(
      of: find.text('시편'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(genesisInk.first).onTap, isNotNull);
    expect(tester.widget<InkWell>(psalmsInk.first).onTap, isNull);
    final oldTestament = find.byKey(
      const ValueKey('journey-book-testament-old'),
    );
    expect(
      tester.widget<Material>(oldTestament).color,
      AppColorPalette.colorfulMap.utilitySelectedBackground,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: oldTestament, matching: find.text('구약')),
          )
          .style
          ?.color,
      AppColorPalette.colorfulMap.activeTextOnAccent,
    );
    final disabledPsalms = find.byKey(const ValueKey('journey-book-시편'));
    expect(
      tester.widget<Material>(disabledPsalms).color,
      AppColorPalette.colorfulMap.disabledSurface,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: disabledPsalms, matching: find.text('시편')),
          )
          .style
          ?.color,
      AppColorPalette.colorfulMap.disabledText,
    );

    await container
        .read(journeySelectionProvider.notifier)
        .setSelection(
          const JourneySelection(
            source: JourneySource.book,
            scope: JourneyScope.targetOnly,
            bookName: '창세기',
          ),
        );
    await tester.pump();
    final selectedGenesis = find.byKey(const ValueKey('journey-book-창세기'));
    expect(
      tester.widget<Material>(selectedGenesis).color,
      AppColorPalette.colorfulMap.utilitySelectedBackground,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: selectedGenesis, matching: find.text('창세기')),
          )
          .style
          ?.color,
      AppColorPalette.colorfulMap.activeTextOnAccent,
    );

    await tester.tap(find.text('창세기'));
    await tester.pumpAndSettle();
    _expectPlainJourneyHeader(tester, title: '읽을 범위 선택');
    expect(find.byKey(const ValueKey('journey-target-info')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('journey-target-info')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.text('창세기가 선택되었어요'), findsOneWidget);
    expect(find.text('포함된 시대 · 원역사'), findsOneWidget);
    expect(find.text('읽을 범위를 하나 선택해주세요'), findsOneWidget);
    expect(find.text('창세기가 속한 시대 선택'), findsOneWidget);
    expect(find.text('창세기 이야기만'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('journey-scope-target-only')))
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('journey-scope-units'))).dy,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('journey-scope-target-only')),
        matching: find.byType(Checkbox),
      ),
      findsOneWidget,
    );
    expect(find.text('창조와 사람의 사명'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('journey-scope-units-checkbox')),
    );
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('journey-scope-units-checkbox')),
          )
          .value,
      isTrue,
    );
    expect(find.text('창조와 사람의 사명'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('journey-scope-target-only')));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.byKey(const ValueKey('journey-scope-target-only')),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('journey-scope-units-checkbox')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Opacity>(find.byKey(const ValueKey('journey-scope-apply')))
          .opacity,
      1,
    );
  });

  testWidgets('인물은 구약·신약과 정렬 방식을 바꾸고 실제 연결 시대 범위를 보여준다', (tester) async {
    final catalog = _personCatalog();
    await _pumpWithCatalog(
      tester,
      catalog: catalog,
      child: PersonJourneyScreen(catalog: catalog, engravedEventIds: const {}),
    );

    _expectPlainJourneyHeader(tester, title: '인물로 찾기');
    expect(find.text('누구의 이야기가 궁금한가요?'), findsNothing);
    expect(find.text('구약·신약을 고르고 시간순 또는 가나다순으로 찾아보세요.'), findsNothing);

    expect(find.text('구약'), findsOneWidget);
    expect(find.text('신약'), findsOneWidget);
    expect(find.text('시간순'), findsOneWidget);
    expect(find.text('가나다순'), findsNothing);
    expect(find.text('아담'), findsOneWidget);
    expect(find.text('바울'), findsNothing);
    final controlCenterY = tester.getCenter(find.text('구약')).dy;
    for (final label in ['신약', '시간순']) {
      expect(
        (tester.getCenter(find.text(label)).dy - controlCenterY).abs(),
        lessThan(2),
      );
    }
    final oldTestament = find.byKey(
      const ValueKey('journey-person-testament-old'),
    );
    expect(
      tester.widget<Material>(oldTestament).color,
      AppColorPalette.colorfulMap.utilitySelectedBackground,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: oldTestament, matching: find.text('구약')),
          )
          .style
          ?.color,
      AppColorPalette.colorfulMap.activeTextOnAccent,
    );
    expect(
      find.byKey(const ValueKey('journey-person-sort-dropdown')),
      findsOneWidget,
    );
    final grid = tester.widget<GridView>(find.byType(GridView));
    final gridDelegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(gridDelegate.crossAxisCount, 5);

    await tester.tap(find.text('신약'));
    await tester.pumpAndSettle();
    expect(find.text('아담'), findsNothing);
    expect(find.text('바울'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('journey-person-sort-dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('가나다순').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('바울'));
    await tester.pumpAndSettle();
    _expectPlainJourneyHeader(tester, title: '읽을 범위 선택');
    expect(find.text('바울이 선택되었어요'), findsOneWidget);
    expect(find.text('포함된 시대 · 사도'), findsOneWidget);
    expect(find.text('바울이 속한 시대 선택'), findsOneWidget);
    expect(find.text('바울 이야기만'), findsOneWidget);
    expect(find.text('바울의 선교 여행'), findsNothing);
  });
}

void _expectPlainJourneyHeader(WidgetTester tester, {required String title}) {
  final header = find.byKey(const ValueKey('sub-page-plain-header'));
  expect(header, findsOneWidget);
  expect(find.byTooltip('이전'), findsOneWidget);
  expect(find.text('이전'), findsNothing);
  final titleText = tester.widget<Text>(
    find.descendant(of: header, matching: find.text(title)),
  );
  expect(titleText.style?.fontWeight, FontWeight.w700);
}

Future<ProviderContainer> _pumpWithCatalog(
  WidgetTester tester, {
  required JourneyCatalogData catalog,
  required Widget child,
  AppColorPalette palette = AppColorPalette.colorfulMap,
  double textScale = 1,
  JourneySelection? initialSelection,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      storyControllerProvider.overrideWith(_JourneyStoryController.new),
      journeyCatalogProvider.overrideWith((ref) async => catalog),
    ],
  );
  addTearDown(container.dispose);
  if (initialSelection != null) {
    await container
        .read(journeySelectionProvider.notifier)
        .setSelection(initialSelection);
  }
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(palette: palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

JourneyCatalogData _multiUnitCatalog() {
  return JourneyCatalogData(
    eras: const [_era],
    characters: const [_adam],
    events: [
      _event(
        id: 'creation',
        era: _era,
        characterCode: 'adam',
        book: '창',
        unitCode: 'creation',
        unitTitle: '창조와 사람의 사명',
        globalRank: 1,
      ),
      _event(
        id: 'outside-eden',
        era: _era,
        characterCode: 'adam',
        book: '출',
        unitCode: 'outside',
        unitTitle: '에덴 밖 세상',
        globalRank: 2,
      ),
    ],
  );
}

JourneyCatalogData _testamentJourneyCatalog() {
  return JourneyCatalogData(
    eras: const [_era, _publicMinistryEra],
    characters: const [_adam],
    events: [
      _event(
        id: 'creation',
        era: _era,
        characterCode: 'adam',
        book: '창',
        unitCode: 'creation',
        unitTitle: '창조와 사람의 사명',
        globalRank: 1,
      ),
      _event(
        id: 'public-ministry',
        era: _publicMinistryEra,
        characterCode: 'adam',
        book: '마',
        unitCode: 'public_ministry',
        unitTitle: '산상수훈과 하나님 나라',
        globalRank: 2,
      ),
    ],
  );
}

JourneyCatalogData _crossTestamentPartialCatalog() {
  return JourneyCatalogData(
    eras: const [_era, _publicMinistryEra],
    characters: const [_adam],
    events: [
      _event(
        id: 'creation',
        era: _era,
        characterCode: 'adam',
        book: '창',
        unitCode: 'creation',
        unitTitle: '창조와 사람의 사명',
        globalRank: 1,
      ),
      _event(
        id: 'outside-eden',
        era: _era,
        characterCode: 'adam',
        book: '창',
        unitCode: 'outside',
        unitTitle: '에덴 밖 세상',
        globalRank: 2,
      ),
      _event(
        id: 'public-ministry',
        era: _publicMinistryEra,
        characterCode: 'adam',
        book: '마',
        unitCode: 'public_ministry',
        unitTitle: '산상수훈과 하나님 나라',
        globalRank: 3,
      ),
      _event(
        id: 'public-ministry-parables',
        era: _publicMinistryEra,
        characterCode: 'adam',
        book: '누',
        unitCode: 'public_ministry_parables',
        unitTitle: '비유로 배우는 하나님 나라',
        globalRank: 4,
      ),
    ],
  );
}

JourneyCatalogData _longEraJourneyCatalog() {
  return JourneyCatalogData(
    eras: const [_exileEra],
    characters: const [_adam],
    events: [
      _event(
        id: 'return-from-exile',
        era: _exileEra,
        characterCode: 'adam',
        book: '스',
        unitCode: 'return_from_exile',
        unitTitle: '포로에서 돌아와 성전을 다시 세우는 긴 이야기',
        globalRank: 1,
      ),
    ],
  );
}

JourneyCatalogData _catalog({required int eventCount}) {
  return JourneyCatalogData(
    eras: const [_era],
    characters: const [_adam],
    events: [
      for (var index = 0; index < eventCount; index += 1)
        StoryEvent(
          id: 'event-$index',
          eraId: _era.id,
          title: '이야기 $index',
          summary: null,
          storyScenes: const [],
          sceneCharacters: const [],
          startYear: null,
          endYear: null,
          timePrecision: 'approx',
          storyIndex: index + 1,
          unitCode: 'creation',
          unitTitle: '창조와 사람의 사명',
          unitOrder: 1,
          rankInEra: index + 1,
          globalRank: index + 1,
          landmarkId: 'landmark',
          placeName: null,
          lat: null,
          lng: null,
          characterCodes: const ['adam'],
          bibleRefs: const [BibleRef(book: '창', from: '1:1', to: '1:2')],
        ),
    ],
  );
}

JourneyCatalogData _personCatalog() {
  return JourneyCatalogData(
    eras: const [_era, _apostolicEra],
    characters: const [_adam, _paul],
    events: [
      _event(
        id: 'adam-event',
        era: _era,
        characterCode: 'adam',
        book: '창',
        unitCode: 'creation',
        unitTitle: '창조와 사람의 사명',
        globalRank: 1,
      ),
      _event(
        id: 'paul-event',
        era: _apostolicEra,
        characterCode: 'paul',
        book: '행',
        unitCode: 'paul_mission',
        unitTitle: '바울의 선교 여행',
        globalRank: 2,
      ),
    ],
  );
}

StoryEvent _event({
  required String id,
  required Era era,
  required String characterCode,
  required String book,
  required String unitCode,
  required String unitTitle,
  required int globalRank,
}) {
  return StoryEvent(
    id: id,
    eraId: era.id,
    title: '$unitTitle 이야기',
    summary: null,
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 1,
    unitCode: unitCode,
    unitTitle: unitTitle,
    unitOrder: 1,
    rankInEra: 1,
    globalRank: globalRank,
    landmarkId: 'landmark',
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: [characterCode],
    bibleRefs: [BibleRef(book: book, from: '1:1', to: '1:2')],
  );
}
