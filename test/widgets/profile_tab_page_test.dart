import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/app_user_profile.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/intercessory_prayer_item.dart';
import 'package:story_bible/models/paged_result.dart';
import 'package:story_bible/models/saved_bible_verse.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/profile_editor_dialog.dart';
import 'package:story_bible/widgets/profile_tab_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

StoryEvent _profileEvent({
  required String id,
  required String title,
  int storyIndex = 1,
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'landmark-$id',
    eraId: 'era-1',
    title: title,
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    rankInEra: storyIndex,
    globalRank: storyIndex,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: const <String>[],
    bibleRefs: const [],
  );
}

EventEmotionMark _profileEmotionMark(
  String eventId, {
  String emotionKey = 'joy',
  String emotionLabel = '기쁨',
  String emotionEmoji = '🌟',
  String note = '',
  DateTime? updatedAt,
}) {
  return EventEmotionMark(
    eventId: eventId,
    emotionKey: emotionKey,
    emotionLabel: emotionLabel,
    emotionEmoji: emotionEmoji,
    note: note,
    updatedAt: updatedAt ?? DateTime.utc(2026, 5, 26),
  );
}

void main() {
  late _MockStoryRepository storyRepository;
  late _MockUserRepository userRepository;
  late _MockSupabaseClient supabaseClient;
  late _MockGoTrueClient auth;

  const user = User(
    id: 'user-1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-05-26T00:00:00Z',
  );

  final now = DateTime.parse('2026-05-26T00:00:00Z');
  late AppUserProfile profile;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    storyRepository = _MockStoryRepository();
    userRepository = _MockUserRepository();
    supabaseClient = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    profile = AppUserProfile(
      userId: user.id,
      shareId: 'ABC1234',
      nickname: '기도친구',
      photoUrl: null,
      prayerRequest: '오늘 함께 기도해주세요.',
      createdAt: now,
      updatedAt: now,
    );

    when(() => supabaseClient.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);
    when(() => storyRepository.fetchEras()).thenAnswer(
      (_) async => [
        const Era(
          id: 'era-1',
          code: 'era_test',
          testament: 'old',
          name: '테스트 시대',
          displayOrder: 1,
          startYear: null,
          endYear: null,
          mapCenterLat: null,
          mapCenterLng: null,
          mapZoom: null,
        ),
      ],
    );
    when(() => storyRepository.fetchLandmarks()).thenAnswer((_) async => []);
    when(() => storyRepository.fetchCharactersByEra('era-1')).thenAnswer(
      (_) async => [
        const Character(
          id: 'person-1',
          code: 'moses',
          name: '모세',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 1,
        ),
      ],
    );
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    when(
      () => storyRepository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);
    when(
      () => userRepository.fetchCompanionDiaryEntries(userId: user.id),
    ).thenAnswer((_) async => const <UserCompanionDiaryEntry>[]);

    when(
      () => userRepository.ensureSignedInUser(user),
    ).thenAnswer((_) async => profile);
    when(
      () => userRepository.fetchIntercessoryPrayerPage(
        pageIndex: 0,
        pageSize: 12,
      ),
    ).thenAnswer(
      (_) async => const PagedResult<IntercessoryPrayerItem>(
        items: [],
        pageIndex: 0,
        pageSize: 12,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 5,
      ),
    ).thenAnswer(
      (_) async => const PagedResult<SavedBibleVerse>(
        items: [],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      ),
    );
  });

  testWidgets('프로필 헤더의 이름을 누르면 수정 다이얼로그를 연다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final profileGreeting = find.textContaining('기도친구');
    expect(profileGreeting, findsOneWidget);
    expect(tester.getTopLeft(profileGreeting).dx, greaterThan(100));

    await tester.tap(profileGreeting);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditorDialog), findsOneWidget);
    expect(find.text('프로필 수정'), findsOneWidget);
    expect(find.text('사진'), findsOneWidget);
    expect(find.text('닉네임'), findsOneWidget);
    expect(find.text('기도제목'), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('기도 탭의 내 기도 텍스트를 누르면 수정 다이얼로그를 연다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(find.text('기도'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('오늘 함께 기도해주세요.'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditorDialog), findsOneWidget);
    expect(find.text('프로필 수정'), findsOneWidget);
  });

  testWidgets('설정 시트에서 지도 설명을 열 수 있다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('지도 설명'), findsOneWidget);

    await tester.tap(find.text('지도 설명'));
    await tester.pumpAndSettle();

    expect(find.text('지도 출처'), findsOneWidget);
    expect(find.textContaining('현재 배경:'), findsOneWidget);
  });

  testWidgets('계정 삭제는 확인 아이디를 입력해야 활성화된다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('계정 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('ABC1234'), findsWidgets);
    final disabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '계정 삭제'),
    );
    expect(disabledButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'ABC1234');
    await tester.pump();

    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '계정 삭제'),
    );
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('계정 삭제 취소는 다이얼로그만 닫고 프로필 화면을 유지한다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('계정 삭제'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('기도친구'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsNothing);
  });

  testWidgets('프로필 진행 섹션은 다이어리만 보여준다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(find.byIcon(Icons.directions_walk_rounded), findsNothing);
    expect(find.byIcon(Icons.place_rounded), findsNothing);
  });

  testWidgets('좁은 프로필 화면은 활동과 진행 섹션을 하나의 패널에 담고 overflow 없이 보여준다', (
    tester,
  ) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(430, 932),
      textScale: 1.4,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('기록'), findsOneWidget);
    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('기록')).dy,
      lessThan(tester.getTopLeft(find.text('신앙 다이어리').first).dy),
    );

    final faithPrompt = find.text('오늘 하나님과 함께한 순간을 기록해 보세요!');
    await tester.ensureVisible(faithPrompt);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(faithPrompt).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
  });

  testWidgets('저장 탭을 누르면 저장한 이야기 미리보기를 다시 불러온다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );
    clearInteractions(storyRepository);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    verify(() => storyRepository.fetchEventsByIds(any())).called(1);
  });

  testWidgets('말씀 탭을 누르면 저장한 말씀 미리보기를 최신으로 다시 불러온다', (tester) async {
    var fetchCount = 0;
    final savedVerse = SavedBibleVerse(
      id: 'saved-1',
      userId: user.id,
      translation: '개역개정',
      bookNo: 1,
      bookName: '창세기',
      chapterNo: 1,
      verseNo: 1,
      verseText: '태초에 하나님이 천지를 창조하시니라',
      comment: '처음 저장한 말씀',
      createdAt: now,
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 5,
      ),
    ).thenAnswer((_) async {
      fetchCount += 1;
      return PagedResult<SavedBibleVerse>(
        items: fetchCount == 1 ? const [] : [savedVerse],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      );
    });

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.text('태초에 하나님이 천지를 창조하시니라'), findsNothing);

    await tester.tap(find.text('말씀'));
    await tester.pumpAndSettle();

    expect(fetchCount, greaterThanOrEqualTo(2));
    expect(find.text('저장한 말씀'), findsNothing);
    expect(find.text('태초에 하나님이 천지를 창조하시니라'), findsOneWidget);
    expect(find.text('처음 저장한 말씀'), findsOneWidget);
  });

  testWidgets('통독 진행률 팝업에서 장을 누르면 해당 장 성경 리더를 연다', (tester) async {
    int? openedBookNo;
    int? openedChapterNo;
    int? openedVerseNo;

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      onOpenBibleReader:
          ({initialBookNo, initialChapterNo, initialVerseNo}) async {
            openedBookNo = initialBookNo;
            openedChapterNo = initialChapterNo;
            openedVerseNo = initialVerseNo;
          },
    );

    await tester.tap(find.text('통독 진행률'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bible-progress-chapter-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('bible-progress-chapter-2')));
    await tester.pumpAndSettle();

    expect(openedBookNo, 1);
    expect(openedChapterNo, 2);
    expect(openedVerseNo, isNull);
    expect(
      find.byKey(const ValueKey('bible-progress-chapter-2')),
      findsNothing,
    );
  });

  testWidgets('이야기 진행률 팝업은 전체/완료/미완료 필터로 카드를 거른다', (tester) async {
    final completedEvent = _profileEvent(
      id: 'event-done',
      title: '완료한 이야기',
      storyIndex: 1,
    );
    final incompleteEvent = _profileEvent(
      id: 'event-todo',
      title: '미완료 이야기',
      storyIndex: 2,
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [completedEvent, incompleteEvent]);
    when(() => storyRepository.fetchEventProgress(user.id)).thenAnswer(
      (_) async => const {
        'event-done': (bibleRead: true, quizCompleted: true, completed: true),
      },
    );
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {'event-done': _profileEmotionMark('event-done')},
    );
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => const <String>{});

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final storyProgressCard = find.byKey(
      const ValueKey('profile-story-progress-card'),
    );
    await tester.ensureVisible(storyProgressCard);
    await tester.pumpAndSettle();
    await tester.tap(storyProgressCard);
    await tester.pumpAndSettle();

    expect(find.text('완료한 이야기'), findsWidgets);
    expect(find.text('미완료 이야기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-progress-filter-완료')));
    await tester.pumpAndSettle();

    expect(find.text('완료한 이야기'), findsWidgets);
    expect(find.text('미완료 이야기'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-progress-filter-미완료')));
    await tester.pumpAndSettle();

    expect(find.text('미완료 이야기'), findsOneWidget);
  });

  testWidgets('내가 새긴 감정들 팝업은 복수 감정 필터를 적용한다', (tester) async {
    final joyEvent = _profileEvent(
      id: 'event-joy',
      title: '기쁨으로 새긴 이야기',
      storyIndex: 1,
    );
    final gratitudeEvent = _profileEvent(
      id: 'event-gratitude',
      title: '감사로 새긴 이야기',
      storyIndex: 2,
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [joyEvent, gratitudeEvent]);
    when(() => storyRepository.fetchEventProgress(user.id)).thenAnswer(
      (_) async =>
          const <
            String,
            ({bool bibleRead, bool quizCompleted, bool completed})
          >{},
    );
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {
        'event-joy': _profileEmotionMark(
          'event-joy',
          note: '기쁨 메모',
          updatedAt: DateTime.utc(2026, 5, 25),
        ),
        'event-gratitude': _profileEmotionMark(
          'event-gratitude',
          emotionKey: 'gratitude',
          emotionLabel: '감사',
          emotionEmoji: '💛',
          note: '감사 메모',
          updatedAt: DateTime.utc(2026, 5, 26),
        ),
      },
    );
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => const <String>{});

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final emotionGrid = find.byKey(
      const ValueKey('profile-emotion-stats-grid'),
    );
    await tester.ensureVisible(emotionGrid);
    await tester.pumpAndSettle();
    await tester.tap(emotionGrid);
    await tester.pumpAndSettle();

    expect(find.text('기쁨으로 새긴 이야기'), findsOneWidget);
    expect(find.text('감사로 새긴 이야기'), findsWidgets);
    expect(find.textContaining('5월 26일'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('emotion-filter-gratitude')));
    await tester.pumpAndSettle();

    expect(find.text('기쁨으로 새긴 이야기'), findsNothing);
    expect(find.text('감사로 새긴 이야기'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('emotion-filter-joy')));
    await tester.pumpAndSettle();

    expect(find.text('기쁨으로 새긴 이야기'), findsOneWidget);
    expect(find.text('감사로 새긴 이야기'), findsWidgets);
  });
}

Future<void> _pumpProfileTab(
  WidgetTester tester, {
  required User user,
  required StoryRepository storyRepository,
  required UserRepository userRepository,
  required SupabaseClient supabaseClient,
  Future<void> Function({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  })?
  onOpenBibleReader,
  Size viewSize = const Size(900, 700),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(user),
        storyRepositoryProvider.overrideWithValue(storyRepository),
        userRepositoryProvider.overrideWithValue(userRepository),
        supabaseClientProvider.overrideWithValue(supabaseClient),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ProfileTabPage(
            onStartQuiz: (_) {},
            onOpenEventDetail: (_, {source}) {},
            onOpenBibleReader:
                onOpenBibleReader ??
                ({initialBookNo, initialChapterNo, initialVerseNo}) {
                  return Future<void>.value();
                },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
