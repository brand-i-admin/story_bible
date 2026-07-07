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
import 'package:story_bible/widgets/parchment_page_scaffold.dart';
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
          code: 'era_patriarch',
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
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 10,
      ),
    ).thenAnswer(
      (_) async => const PagedResult<SavedBibleVerse>(
        items: [],
        pageIndex: 0,
        pageSize: 10,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.countSavedVerses(userId: user.id),
    ).thenAnswer((_) async => 0);
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
    expect(find.text('기도제목'), findsNothing);
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('기도 기능은 pending 상태로 코드만 보존하고 화면에는 표시하지 않는다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.text('기도'), findsNothing);
    expect(find.text('내 기도'), findsNothing);
    expect(find.text('중보 기도'), findsNothing);
    expect(find.text('오늘 함께 기도해주세요.'), findsNothing);
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

  testWidgets('프로필 진행 섹션은 이야기 탐험과 다이어리 카드를 보여준다', (tester) async {
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

  testWidgets('탐험 기록이 없으면 홈 탐험 CTA를 보여주고 콜백을 호출한다', (tester) async {
    final firstEvent = _profileEvent(id: 'event-first', title: '첫 이야기');

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [firstEvent]);
    when(() => storyRepository.fetchEventProgress(user.id)).thenAnswer(
      (_) async =>
          const <
            String,
            ({bool bibleRead, bool quizCompleted, bool completed})
          >{},
    );
    when(
      () => storyRepository.fetchEventEmotionMarks(user.id),
    ).thenAnswer((_) async => const <String, EventEmotionMark>{});
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => const <String>{});

    var tapped = false;
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      onExploreStoriesFromHome: () => tapped = true,
    );

    expect(find.text('홈 화면에서 이야기를 탐험해보세요!'), findsOneWidget);

    await tester.tap(find.byTooltip('이야기 탐험 시작'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('좁은 프로필 화면은 기도 없이 독립 진행 카드를 overflow 없이 보여준다', (tester) async {
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
    expect(find.text('기록'), findsNothing);
    expect(find.text('기도'), findsNothing);
    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(find.text('이야기 탐험'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('이야기 탐험')).dy,
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

  testWidgets('아주크게에서 이야기 탐험 메인 카드 제목도 커진다', (tester) async {
    final recentEvent = _profileEvent(
      id: 'event-recent',
      title: '최근 탐험한 이야기',
      storyIndex: 1,
    );
    final nextEvent = _profileEvent(
      id: 'event-next',
      title: '고라의 반역: 권위에 맞서다',
      storyIndex: 2,
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [recentEvent, nextEvent]);
    when(() => storyRepository.fetchEventProgress(user.id)).thenAnswer(
      (_) async =>
          const <
            String,
            ({bool bibleRead, bool quizCompleted, bool completed})
          >{},
    );
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {
        recentEvent.id: _profileEmotionMark(
          recentEvent.id,
          emotionKey: 'gratitude',
          emotionLabel: '감사',
          emotionEmoji: '💛',
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
      viewSize: const Size(430, 932),
      textScale: 1.4,
    );

    final titleFinder = find.text('고라의 반역: 권위에 맞서다');
    expect(titleFinder, findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(titleFinder)).scale(1),
      greaterThanOrEqualTo(1.3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('하단 저장/말씀 탭 대신 이야기 탐험 요약 카드를 보여준다', (tester) async {
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
    final savedEvent = _profileEvent(id: 'saved-event', title: '저장한 이야기');

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => {'saved-event'});
    when(
      () => storyRepository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => [savedEvent]);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchEventEmotionMarks(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 5,
      ),
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 10,
      ),
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 10,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.countSavedVerses(userId: user.id),
    ).thenAnswer((_) async => 1);

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.text('저장'), findsNothing);
    expect(find.text('말씀'), findsNothing);
    expect(find.text('이야기 탐험 요약'), findsOneWidget);
    expect(find.text('탐험한 이야기'), findsOneWidget);
    expect(find.text('저장 이야기 개수'), findsOneWidget);
    expect(find.text('저장한 말씀'), findsOneWidget);
    expect(find.text('1개'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('profile-story-summary-saved-stories')),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 이야기'), findsWidgets);
    expect(find.byType(ParchmentListPageScaffold), findsOneWidget);
  });

  testWidgets('저장한 말씀 요약 카드는 저장 말씀 페이지로 이동한다', (tester) async {
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
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 10,
      ),
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 10,
        hasNextPage: false,
      ),
    );
    when(
      () => userRepository.countSavedVerses(userId: user.id),
    ).thenAnswer((_) async => 1);

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(
      find.byKey(const ValueKey('profile-story-summary-saved-verses')),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 성경 구절'), findsOneWidget);
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

    final bibleProgressCard = find.byKey(
      const ValueKey('bible-progress-feature-card'),
    );
    await tester.ensureVisible(bibleProgressCard);
    await tester.pumpAndSettle();
    await tester.tap(bibleProgressCard);
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

  testWidgets('통독 진행률 팝업은 마지막 묵상 권으로 열린다', (tester) async {
    final savedVerse = SavedBibleVerse(
      id: 'saved-john',
      userId: user.id,
      translation: '개역개정',
      bookNo: 43,
      bookName: '요한복음',
      chapterNo: 3,
      verseNo: 16,
      verseText: '하나님이 세상을 이처럼 사랑하사',
      createdAt: now,
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 5,
      ),
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      ),
    );

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final bibleProgressCard = find.byKey(
      const ValueKey('bible-progress-feature-card'),
    );
    await tester.ensureVisible(bibleProgressCard);
    await tester.pumpAndSettle();
    await tester.tap(bibleProgressCard);
    await tester.pumpAndSettle();

    expect(find.text('신약'), findsOneWidget);
    expect(find.text('요한복음'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bible-progress-chapter-21')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bible-progress-chapter-22')),
      findsNothing,
    );
  });

  testWidgets('통독 이어 읽기는 마지막 묵상 다음 장을 연다', (tester) async {
    int? openedBookNo;
    int? openedChapterNo;
    int? openedVerseNo;
    final savedVerse = SavedBibleVerse(
      id: 'saved-john',
      userId: user.id,
      translation: '개역개정',
      bookNo: 43,
      bookName: '요한복음',
      chapterNo: 3,
      verseNo: 16,
      verseText: '하나님이 세상을 이처럼 사랑하사',
      createdAt: now,
    );
    when(
      () => userRepository.fetchSavedVersesPage(
        userId: user.id,
        pageIndex: 0,
        pageSize: 5,
      ),
    ).thenAnswer(
      (_) async => PagedResult<SavedBibleVerse>(
        items: [savedVerse],
        pageIndex: 0,
        pageSize: 5,
        hasNextPage: false,
      ),
    );

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

    final continueButton = find.byKey(
      const ValueKey('bible-progress-continue-button'),
    );
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(openedBookNo, 43);
    expect(openedChapterNo, 4);
    expect(openedVerseNo, isNull);
  });

  testWidgets('이야기 진행률 페이지는 전체/완료/미완료 필터로 카드를 거른다', (tester) async {
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
      const ValueKey('profile-story-summary-explored'),
    );
    await tester.ensureVisible(storyProgressCard);
    await tester.pumpAndSettle();
    await tester.tap(storyProgressCard);
    await tester.pumpAndSettle();

    final progressGrid = find.byKey(
      const ValueKey('story-progress-review-grid'),
    );
    Finder progressGridTitle(String title) {
      return find.descendant(of: progressGrid, matching: find.text(title));
    }

    expect(find.text('완료한 이야기'), findsWidgets);
    expect(progressGridTitle('미완료 이야기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-progress-filter-완료')));
    await tester.pumpAndSettle();

    expect(progressGridTitle('완료한 이야기'), findsOneWidget);
    expect(progressGridTitle('미완료 이야기'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-progress-filter-미완료')));
    await tester.pumpAndSettle();

    expect(progressGridTitle('미완료 이야기'), findsOneWidget);
  });

  testWidgets('이야기 진행률 페이지는 복수 감정 필터를 적용한다', (tester) async {
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
    final comfortEvent = _profileEvent(
      id: 'event-comfort',
      title: '위로로 새긴 이야기',
      storyIndex: 3,
    );
    final fearEvent = _profileEvent(
      id: 'event-fear',
      title: '두려움으로 새긴 이야기',
      storyIndex: 4,
    );
    StoryEvent? openedEmotionEvent;
    ProfileEventOpenSource? openedEmotionSource;

    when(() => auth.currentUser).thenReturn(user);
    when(() => storyRepository.fetchEventsByEra('era-1')).thenAnswer(
      (_) async => [joyEvent, gratitudeEvent, comfortEvent, fearEvent],
    );
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
        'event-comfort': _profileEmotionMark(
          'event-comfort',
          emotionKey: 'comfort',
          emotionLabel: '위로',
          emotionEmoji: '🌿',
          note: '위로 메모',
          updatedAt: DateTime.utc(2026, 5, 24),
        ),
        'event-fear': _profileEmotionMark(
          'event-fear',
          emotionKey: 'fear',
          emotionLabel: '두려움',
          emotionEmoji: '⚡',
          note: '두려움 메모',
          updatedAt: DateTime.utc(2026, 5, 23),
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
      onOpenEventDetail: (event, {source}) {
        openedEmotionEvent = event;
        openedEmotionSource = source;
      },
    );

    final storyProgressCard = find.byKey(
      const ValueKey('profile-story-summary-explored'),
    );
    await tester.ensureVisible(storyProgressCard);
    await tester.pumpAndSettle();
    await tester.tap(storyProgressCard);
    await tester.pumpAndSettle();

    final emotionList = find.byKey(const ValueKey('emotion-marks-review-list'));
    Finder emotionListTitle(String title) {
      return find.descendant(of: emotionList, matching: find.text(title));
    }

    expect(emotionListTitle('기쁨으로 새긴 이야기'), findsOneWidget);
    expect(emotionListTitle('감사로 새긴 이야기'), findsOneWidget);
    expect(emotionListTitle('위로로 새긴 이야기'), findsOneWidget);
    expect(emotionListTitle('두려움으로 새긴 이야기'), findsNothing);
    expect(
      find.descendant(of: emotionList, matching: find.textContaining('5월 26일')),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey('emotion-marks-open-all')),
      findsOneWidget,
    );

    await tester.tap(emotionListTitle('감사로 새긴 이야기'));
    await tester.pumpAndSettle();

    expect(openedEmotionEvent?.title, '감사로 새긴 이야기');
    expect(openedEmotionSource, ProfileEventOpenSource.detailOnly);
    expect(
      find.byKey(const ValueKey('emotion-marks-review-list')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-marks-open-all')));
    await tester.pumpAndSettle();

    final allEmotionList = find.byKey(const ValueKey('emotion-marks-all-list'));
    expect(
      find.descendant(of: allEmotionList, matching: find.text('두려움으로 새긴 이야기')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('emotion-filter-gratitude')));
    await tester.pumpAndSettle();

    expect(emotionListTitle('기쁨으로 새긴 이야기'), findsNothing);
    expect(emotionListTitle('감사로 새긴 이야기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emotion-filter-joy')));
    await tester.pumpAndSettle();

    expect(emotionListTitle('기쁨으로 새긴 이야기'), findsOneWidget);
    expect(emotionListTitle('감사로 새긴 이야기'), findsOneWidget);
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
  VoidCallback? onExploreStoriesFromHome,
  ProfileEventDetailCallback? onOpenEventDetail,
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
            onOpenEventDetail: onOpenEventDetail ?? (_, {source}) {},
            onOpenBibleReader:
                onOpenBibleReader ??
                ({initialBookNo, initialChapterNo, initialVerseNo}) {
                  return Future<void>.value();
                },
            onExploreStoriesFromHome: onExploreStoriesFromHome,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
