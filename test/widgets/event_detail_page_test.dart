import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/models/bible_ref.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/character_avatar.dart';
import 'package:story_bible/widgets/event_detail_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

void main() {
  late _MockStoryRepository storyRepository;

  setUp(() {
    storyRepository = _MockStoryRepository();
    when(() => storyRepository.fetchCharactersByEra('era-exodus')).thenAnswer(
      (_) async => const [
        Character(
          id: 'c-moses',
          code: 'moses',
          name: '모세',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 1,
        ),
        Character(
          id: 'c-aaron',
          code: 'aaron',
          name: '아론',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 2,
        ),
      ],
    );
  });

  testWidgets('감정 새기기는 한 팝업에서 필수 감정과 선택 코멘트를 받는다', (tester) async {
    EventEmotionOption? savedOption;
    String? savedNote;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<EventEmotionOption>(
                  context: context,
                  builder: (_) => EmotionEngravingDialog(
                    eventTitle: '홍해를 건너다',
                    initialMark: null,
                    onSave: (option, note) async {
                      savedOption = option;
                      savedNote = note;
                    },
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('감정 선택'), findsOneWidget);
    expect(find.text('필수'), findsOneWidget);
    expect(find.text('코멘트'), findsOneWidget);
    expect(find.text('선택사항'), findsOneWidget);
    _expectLabelImmediatelyAfterTitle(tester, title: '감정 선택', label: '필수');
    _expectLabelImmediatelyAfterTitle(tester, title: '코멘트', label: '선택사항');
    expect(find.text('다음'), findsNothing);
    expect(find.text('이전'), findsNothing);
    expect(find.byKey(const ValueKey('emotion-note-input')), findsOneWidget);

    await tester.tap(find.text('새기기'));
    await tester.pump();
    expect(savedOption, isNull);

    await tester.tap(find.text('기쁨'));
    await tester.pump();
    await tester.tap(find.text('새기기'));
    await tester.pumpAndSettle();

    expect(savedOption?.key, 'joy');
    expect(savedNote, '');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('키보드가 열린 상태에서도 코멘트와 함께 새기기를 저장한다', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    EventEmotionOption? savedOption;
    String? savedNote;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<EventEmotionOption>(
                  context: context,
                  builder: (_) => EmotionEngravingDialog(
                    eventTitle: '요나단의 신호: 다윗을 떠나보내다',
                    initialMark: null,
                    onSave: (option, note) async {
                      savedOption = option;
                      savedNote = note;
                    },
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('두려움'));
    await tester.enterText(
      find.byKey(const ValueKey('emotion-note-input')),
      '친구를 보내는 마음이 남았다',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    final saveButtonRect = tester.getRect(find.text('새기기'));
    expect(saveButtonRect.bottom, lessThanOrEqualTo(dialogRect.bottom));

    await tester.tap(find.text('새기기'));
    await tester.pumpAndSettle();

    expect(savedOption?.key, 'fear');
    expect(savedNote, '친구를 보내는 마음이 남았다');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('배경 지식 제목 옆에 등장인물 아바타와 인라인 요약을 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(),
            sceneAssetsFuture: Future.value(const []),
            onOpenBibleReader: (_) async => false,
            onStartQuiz: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('시내산 도착'), findsOneWidget);
    expect(find.text('B.C. 1446년경 · 시내산(전승)'), findsOneWidget);
    expect(find.text('배경 지식'), findsOneWidget);
    expect(find.text('출애굽 여정의 배경을 먼저 떠올립니다.'), findsOneWidget);
    expect(find.text('요약 이야기'), findsNothing);
    expect(_summaryFinder(), findsOneWidget);
    expect(find.byType(CharacterAvatar), findsNWidgets(2));
    expect(find.text('모세'), findsOneWidget);
    expect(find.text('아론'), findsOneWidget);
    expect(tester.getSize(find.byType(CharacterAvatar).first).width, 31);
    expect(_avatarNames(tester), ['모세', '아론']);
    final storySurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('event-detail-outer-surface')),
    );
    final storyDecoration = storySurface.decoration as BoxDecoration;
    expect(storyDecoration.border, isNull);
    expect(storyDecoration.boxShadow, isNotEmpty);
    _expectAvatarsBesideBackgroundTitle(tester);
    _expectAvatarsDoNotOverlap(tester);
    verify(() => storyRepository.fetchCharactersByEra('era-exodus')).called(1);
  });

  testWidgets('DB 목록에 없는 등장인물 코드도 한글 fallback으로 모두 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(characterCodes: const ['god', 'moses', 'cain']),
            sceneAssetsFuture: Future.value(const []),
            onOpenBibleReader: (_) async => false,
            onStartQuiz: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CharacterAvatar), findsNWidgets(3));
    expect(find.text('하나님'), findsOneWidget);
    expect(find.text('모세'), findsOneWidget);
    expect(find.text('가인'), findsOneWidget);
    expect(find.text('god'), findsNothing);
    expect(find.text('cain'), findsNothing);
    expect(_avatarNames(tester), ['하나님', '가인', '모세']);
    _expectAvatarsBesideBackgroundTitle(tester);
    _expectAvatarsDoNotOverlap(tester);
  });

  testWidgets('비로그인 사건 읽기와 퀴즈는 리더나 퀴즈 대신 로그인 팝업을 요청한다', (tester) async {
    final loginMessages = <String>[];
    var readerOpened = false;
    var quizOpened = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(
              bibleRefs: const [BibleRef(book: '출', from: '19:1', to: '19:1')],
            ),
            sceneAssetsFuture: Future.value(const []),
            onLoginRequired: loginMessages.add,
            onOpenBibleReader: (_) async {
              readerOpened = true;
              return false;
            },
            onStartQuiz: (_) => quizOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('출 19:1 · 읽기'));
    await tester.tap(find.text('출 19:1 · 읽기'));
    await tester.pump();

    expect(loginMessages, ['본문을 읽으려면 로그인이 필요해요.']);
    expect(readerOpened, isFalse);

    await tester.ensureVisible(find.text('퀴즈 시작'));
    await tester.tap(find.text('퀴즈 시작'));
    await tester.pump();

    expect(loginMessages, ['본문을 읽으려면 로그인이 필요해요.', '퀴즈를 풀려면 로그인이 필요해요.']);
    expect(quizOpened, isFalse);
  });

  testWidgets('이전·다음 이야기 제목은 한 줄로 반복 자동 스크롤한다', (tester) async {
    const longTitle =
        '아주 긴 이전과 다음 이야기 제목이 카드 너비를 넘어 끝까지 천천히 이동합니다 '
        '아주 긴 이전과 다음 이야기 제목이 카드 너비를 넘어 끝까지 천천히 이동합니다';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(storyRepository),
          signedInUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: EventDetailPage(
            event: _event(),
            prevEvent: _event(id: 'previous', title: longTitle),
            nextEvent: _event(id: 'next', title: longTitle),
            sceneAssetsFuture: Future.value(const []),
            onOpenBibleReader: (_) async => false,
            onStartQuiz: (_) {},
            onNavigateToEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final suffix in ['prev', 'next']) {
      final title = tester.widget<Text>(
        find.byKey(ValueKey('event-detail-nav-title-$suffix')),
      );
      expect(title.maxLines, 1);
      expect(title.softWrap, isFalse);
      expect(
        find.byKey(ValueKey('event-detail-nav-title-scroll-$suffix')),
        findsOneWidget,
      );
    }

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('event-detail-nav-title-scroll-prev')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final scrollDuration = Duration(
      milliseconds: (position.maxScrollExtent * 34).round().clamp(2400, 9000),
    );

    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(scrollDuration);
    await tester.pump();
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
    var restarted = false;
    for (var i = 0; i < 30 && !restarted; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      restarted = position.pixels < position.maxScrollExtent / 2;
    }
    expect(restarted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _expectLabelImmediatelyAfterTitle(
  WidgetTester tester, {
  required String title,
  required String label,
}) {
  final titleRect = tester.getRect(find.text(title));
  final labelRect = tester.getRect(
    find.byKey(ValueKey('emotion-requirement-$label')),
  );

  expect(labelRect.left - titleRect.right, inInclusiveRange(0, 8));
  expect(labelRect.center.dy, closeTo(titleRect.center.dy, 2));
}

List<String> _avatarNames(WidgetTester tester) {
  return tester
      .widgetList<CharacterAvatar>(find.byType(CharacterAvatar))
      .map((avatar) => avatar.character.name)
      .toList(growable: false);
}

void _expectAvatarsDoNotOverlap(WidgetTester tester) {
  final rects = find
      .byType(CharacterAvatar)
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)))
      .toList(growable: false);

  for (var index = 1; index < rects.length; index++) {
    expect(rects[index].left, greaterThanOrEqualTo(rects[index - 1].right));
  }
}

void _expectAvatarsBesideBackgroundTitle(WidgetTester tester) {
  final titleRect = tester.getRect(find.text('배경 지식'));
  final avatarRect = tester.getRect(find.byType(CharacterAvatar).first);
  final summaryRect = tester.getRect(_summaryFinder());

  expect(avatarRect.center.dy, closeTo(titleRect.center.dy, 12));
  expect(avatarRect.top, lessThan(summaryRect.top));
}

Finder _summaryFinder() {
  return find.text('요약: 하나님은 백성에게 살아갈 길을 선포하신다.', findRichText: true);
}

StoryEvent _event({
  String id = 'event-1',
  String title = '시내산 도착',
  List<String> characterCodes = const ['aaron', 'moses'],
  List<BibleRef> bibleRefs = const [],
}) {
  return StoryEvent(
    id: id,
    eraId: 'era-exodus',
    title: title,
    summary: '하나님은 백성에게 살아갈 길을 선포하신다.',
    backgroundContext: '출애굽 여정의 배경을 먼저 떠올립니다.',
    storyScenes: [],
    sceneCharacters: [],
    startYear: -1446,
    endYear: -1446,
    timePrecision: 'approx',
    storyIndex: 1,
    rankInEra: 1,
    globalRank: 1,
    landmarkId: 'lm-sinai',
    placeName: '시내산(전승)',
    lat: 28.5392,
    lng: 33.9756,
    characterCodes: characterCodes,
    bibleRefs: bibleRefs,
  );
}
