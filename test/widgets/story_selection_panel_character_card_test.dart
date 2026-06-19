import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/widgets/character_panel.dart';
import 'package:story_bible/widgets/story_selection_panel.dart';

void main() {
  testWidgets('인물 카드에 정체성 설명과 +사건수 배지를 표시한다', (tester) async {
    const character = Character(
      id: 'c-zedekiah',
      code: 'zedekiah',
      name: '시드기야',
      tagline: '남유다 20대 마지막 왕',
      description: '시드기야는 남유다의 마지막 왕이다.',
      avatarUrl: null,
      displayOrder: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 360,
              child: StorySelectionPanel(
                scrollController: ScrollController(),
                step: 2,
                panelStage: StorySelectionPanelStage.expanded,
                onStepUp: () {},
                onStepDown: () {},
                canOpenStep: (_) => true,
                onSelectStep: (_) {},
                eras: const [],
                selectedEraId: 'era_divided_kingdom',
                selectedTestament: 'old',
                onSelectEra: (_) {},
                onSelectTestament: (_) {},
                characters: const [character],
                characterSortMode: CharacterSortMode.eraOrder,
                onCharacterSortModeChanged: (_) {},
                draftSelectedCharacterCodes: const {},
                onToggleDraftCharacter: (_) {},
                committedSelectedCharacterCodes: const {},
                hasPendingCharacterChanges: false,
                colorForDraftCharacter: (_) => Colors.teal,
                colorForCommittedCharacter: (_) => Colors.teal,
                events: const [],
                eraEvents: [_event('e1'), _event('e2'), _event('e3')],
                completedEventIds: const {},
                draftDisplayedEventIds: const {},
                committedDisplayedEventIds: const {},
                onToggleDisplayedEvent: (_) {},
                onSelectAllDisplayedEvents: () {},
                onDeselectAllDisplayedEvents: () {},
                onCommitDisplayedEvents: () {},
                onNextFromEra: () {},
                onNextFromCharacters: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('시드기야'), findsOneWidget);
    expect(find.text('남유다 20대\n마지막 왕'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('사건 3개'), findsNothing);

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisExtent, kStorySelectionCharacterCardExtent);
    expect(delegate.mainAxisExtent, lessThan(120));

    final identityText = tester.widget<Text>(find.text('남유다 20대\n마지막 왕'));
    expect(identityText.maxLines, 3);
  });
}

StoryEvent _event(String id) {
  return StoryEvent(
    id: id,
    eraId: 'era_divided_kingdom',
    title: '이야기 $id',
    summary: '요약',
    storyScenes: const [],
    sceneCharacters: const [],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: 1,
    rankInEra: 1,
    globalRank: 1,
    landmarkId: 'lm',
    placeName: '사마리아',
    lat: 0,
    lng: 0,
    characterCodes: const ['zedekiah'],
    bibleRefs: const <BibleRef>[],
  );
}
