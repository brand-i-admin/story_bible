import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/notification_repository.dart';
import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/app_user_profile.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/intercessory_prayer_item.dart';
import 'package:story_bible/models/paged_result.dart';
import 'package:story_bible/models/quiz_attempt_summary.dart';
import 'package:story_bible/models/saved_bible_verse.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/models/user_companion_diary_entry.dart';
import 'package:story_bible/screens/bible_progress_screen.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/notification_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/widgets/home/story_root_navigation_bar.dart';
import 'package:story_bible/widgets/inline_login_prompt_card.dart';
import 'package:story_bible/widgets/parchment_page_scaffold.dart';
import 'package:story_bible/widgets/profile_editor_dialog.dart';
import 'package:story_bible/widgets/profile_tab_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockNotificationRepository extends Mock
    implements NotificationRepository {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _ProfileProgressRefreshStoryController extends StoryController {
  @override
  StoryState build() => const StoryState(
    loading: false,
    eras: [
      Era(
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

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshCompletedEventIds() async {
    state = state.copyWith(completedEventIds: {'event-done'});
  }

  @override
  Future<void> refreshQuizAttemptSummaries() async {}

  @override
  Future<void> refreshSavedEventIds() async {}

  @override
  Future<void> refreshCompletedBibleChapterKeys() async {}
}

StoryEvent _profileEvent({
  required String id,
  required String title,
  int storyIndex = 1,
  String? placeName,
  int? startYear,
  List<String> characterCodes = const <String>[],
  String? summary,
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'landmark-$id',
    eraId: 'era-1',
    title: title,
    summary: summary,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: startYear,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    rankInEra: storyIndex,
    globalRank: storyIndex,
    placeName: placeName,
    lat: null,
    lng: null,
    characterCodes: characterCodes,
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

UserCompanionDiaryEntry _profileDiaryEntry(
  String id, {
  required String userId,
  DateTime? entryDate,
}) {
  final date = entryDate ?? DateTime(2026, 5, 26);
  return UserCompanionDiaryEntry(
    id: id,
    userId: userId,
    entryDate: date,
    title: '오늘의 기록',
    body: '하나님과 함께한 순간',
    createdAt: date,
    updatedAt: date,
  );
}

QuizAttemptSummary _profileQuizAttemptSummary(
  String eventId, {
  int correctCount = 0,
  int wrongCount = 0,
  int confusedCount = 0,
}) {
  final totalCount = correctCount + wrongCount + confusedCount;
  return QuizAttemptSummary(
    eventId: eventId,
    correctCount: correctCount,
    totalCount: totalCount,
    wrongCount: wrongCount,
    confusedCount: confusedCount,
    selectedAnswers: const <int?>[],
    updatedAt: DateTime.utc(2026, 5, 26),
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

  testWidgets('내정보 헤더의 사진·닉네임을 누르면 수정 다이얼로그를 연다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final headerIdentity = find.byKey(
      const ValueKey('profile-header-identity'),
    );
    expect(find.text('내정보'), findsNothing);
    expect(find.text('기도친구'), findsOneWidget);
    expect(headerIdentity, findsOneWidget);
    expect(find.textContaining('샬롬!'), findsNothing);
    expect(find.textContaining('오늘도 이야기 탐험'), findsNothing);
    final nicknameText = tester.widget<Text>(
      find.descendant(of: headerIdentity, matching: find.text('기도친구')),
    );
    expect(nicknameText.overflow, TextOverflow.visible);
    expect(nicknameText.style?.fontSize, 15);

    await tester.tap(headerIdentity);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditorDialog), findsOneWidget);
    expect(find.text('프로필 수정'), findsOneWidget);
    expect(find.text('사진'), findsOneWidget);
    expect(find.text('닉네임'), findsOneWidget);
    expect(find.text('기도제목'), findsNothing);
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsWidgets);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('내정보 상단은 루트 네비게이션과 같은 표면색을 쓴다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final surfaceFinder = find.byKey(const ValueKey('sub-page-top-surface'));
    expect(surfaceFinder, findsOneWidget);
    final surface = tester.widget<ColoredBox>(surfaceFinder);
    final palette = AppPaletteTheme.of(tester.element(surfaceFinder));
    expect(surface.color, storyRootNavigationSurfaceColor(palette));
  });

  testWidgets('내정보 본문 쉘은 헤더와 겹치지 않게 아래에 배치한다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(430, 932),
    );

    final header = find.byKey(const ValueKey('profile-header-identity'));
    final bodyShell = find.byKey(const ValueKey('profile-body-shell'));
    expect(bodyShell, findsOneWidget);
    expect(
      tester.getRect(bodyShell).top - tester.getRect(header).bottom,
      greaterThanOrEqualTo(10),
    );
  });

  testWidgets('로그아웃 미리보기는 배경 정보를 보여주되 입력을 차단한다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      authenticated: false,
      viewSize: const Size(430, 932),
    );

    expect(find.byType(InlineLoginPromptCard), findsOneWidget);
    final blocker = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('profile-locked-content-blocker')),
    );
    expect(blocker.ignoring, isTrue);
  });

  testWidgets('블랙 테마 프로필 수정에서 현재 닉네임은 밝은 글자로 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(palette: AppColorPalette.blackMap),
          home: Scaffold(
            body: ProfileEditorDialog(initialProfile: profile, userId: user.id),
          ),
        ),
      ),
    );

    final nicknameField = tester.widget<TextField>(find.byType(TextField));
    expect(nicknameField.controller?.text, profile.nickname);
    expect(nicknameField.style?.color, AppColorPalette.blackMap.text);
  });

  testWidgets('내정보 헤더는 긴 닉네임도 말줄임표 없이 모두 표시한다', (tester) async {
    profile = AppUserProfile(
      userId: user.id,
      shareId: 'ABC1234',
      nickname: '말씀과 함께 걷는 기도친구',
      photoUrl: null,
      prayerRequest: '오늘 함께 기도해주세요.',
      createdAt: now,
      updatedAt: now,
    );

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(430, 932),
    );

    final identity = find.byKey(const ValueKey('profile-header-identity'));
    final nickname = find.descendant(
      of: identity,
      matching: find.text('말씀과 함께 걷는 기도친구'),
    );
    final nicknameText = tester.widget<Text>(nickname);
    expect(nicknameText.overflow, TextOverflow.visible);
    expect(nicknameText.maxLines, greaterThanOrEqualTo(2));
    expect(
      tester.getRect(nickname).right,
      lessThanOrEqualTo(tester.getRect(identity).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('프로필 정보 카드에는 오늘 할 일 체크리스트를 표시하지 않는다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.text('오늘 할 일:'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-today-action-checklist-info')),
      findsNothing,
    );
  });

  testWidgets('아주크게에서도 프로필 오늘 할 일 체크리스트는 노출하지 않는다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(360, 780),
      textScale: 1.4,
    );

    expect(find.text('오늘 할 일:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 프로필 화면은 아래로 당겨 새로고침할 수 있다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(390, 800),
      tickerEnabled: true,
      settleAfterPump: false,
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);

    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await refresh;
    await tester.pump(const Duration(milliseconds: 100));

    verify(() => storyRepository.fetchCharactersByEra('era-1')).called(2);
    verify(() => storyRepository.fetchEventsByEra('era-1')).called(2);
    verify(() => userRepository.ensureSignedInUser(user)).called(2);
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
    final dialogSurface = tester.widget<Container>(
      find.byKey(const ValueKey('delete-account-dialog-surface')),
    );
    final dialogDecoration = dialogSurface.decoration! as BoxDecoration;
    expect(dialogDecoration.border, isNull);
    expect(dialogDecoration.boxShadow, isNotEmpty);
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

  testWidgets('프로필 진행 섹션은 탐험 흔적과 다이어리 카드를 보여준다', (tester) async {
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

  testWidgets('오늘 액션을 모두 완료해도 프로필 체커는 표시하지 않는다', (tester) async {
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final today = DateTime(nowKst.year, nowKst.month, nowKst.day);
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final event = _profileEvent(
      id: 'today-event',
      title: '오늘 감정을 새긴 이야기',
      storyIndex: 1,
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [event]);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {
        event.id: _profileEmotionMark(event.id, updatedAt: todayUtc),
      },
    );
    when(
      () => userRepository.fetchCompanionDiaryEntries(userId: user.id),
    ).thenAnswer(
      (_) async => [
        _profileDiaryEntry('today-diary', userId: user.id, entryDate: today),
      ],
    );
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchCompletedBibleChapterReadAts(user.id),
    ).thenAnswer((_) async => {'1:1': todayUtc});

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(find.textContaining('샬롬!'), findsNothing);
    expect(find.textContaining('오늘도 이야기 탐험'), findsNothing);
    expect(find.text('오늘 할 일:'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-today-action-story-check')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('profile-today-action-diary-check')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('profile-today-action-bible-check')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('selected-date-emotion-heading-badge')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('selected-date-bible-reading-badge')),
      findsOneWidget,
    );
    final diaryBadge = find.byKey(
      const ValueKey('selected-date-companion-diary-badge'),
    );
    final diaryCard = find.byKey(
      const ValueKey('selected-date-companion-diary'),
    );
    expect(diaryBadge, findsOneWidget);
    expect(diaryCard, findsOneWidget);
    expect(
      tester.getCenter(diaryBadge).dy,
      moreOrLessEquals(tester.getCenter(diaryCard).dy, epsilon: 1.0),
    );

    await tester.ensureVisible(diaryCard);
    await tester.pumpAndSettle();
    await tester.tap(diaryCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('companion-diary-detail-edit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('companion-diary-detail-delete-button')),
      findsOneWidget,
    );
  });

  testWidgets('프로필에서는 이야기 탐험 요약과 다이어리를 독립 레이어로 보여준다', (tester) async {
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

    var homeTapped = false;
    StoryEvent? openedEvent;
    ProfileEventOpenSource? openedSource;
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      onExploreStoriesFromHome: () => homeTapped = true,
      onOpenEventDetail: (event, {source}) {
        openedEvent = event;
        openedSource = source;
      },
    );

    expect(find.text('다이어리'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-story-exploration-summary-layer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-diary-layer')), findsOneWidget);
    final summaryLayer = find.byKey(
      const ValueKey('profile-story-exploration-summary-layer'),
    );
    final featureCards = find.byKey(
      const ValueKey('profile-diary-feature-cards'),
    );
    final diaryLayer = find.byKey(const ValueKey('profile-diary-layer'));
    expect(featureCards, findsOneWidget);
    final diaryLayerContainer = tester.widget<Container>(diaryLayer);
    final diaryLayerDecoration =
        diaryLayerContainer.decoration! as BoxDecoration;
    expect(diaryLayerDecoration.border, isNull);
    expect(diaryLayerDecoration.boxShadow, isNotEmpty);
    final summaryLayerContainer = tester.widget<Container>(summaryLayer);
    final summaryLayerDecoration =
        summaryLayerContainer.decoration! as BoxDecoration;
    expect(summaryLayerDecoration.boxShadow, isNotEmpty);
    expect(
      tester.getTopLeft(summaryLayer).dy,
      lessThan(tester.getTopLeft(featureCards).dy),
    );
    expect(
      tester.getTopLeft(featureCards).dy,
      lessThan(tester.getTopLeft(diaryLayer).dy),
    );
    expect(
      find.byKey(const ValueKey('companion-diary-write-button-pill')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bible-progress-continue-button')),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('profile-diary-layer')),
        matching: find.byKey(
          const ValueKey('profile-story-exploration-summary-layer'),
        ),
      ),
      findsNothing,
    );
    expect(find.text('다음 이야기'), findsNothing);
    expect(find.text('첫 이야기'), findsNothing);
    expect(homeTapped, isFalse);
    expect(openedEvent, isNull);
    expect(openedSource, isNull);
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
    expect(find.text('복습'), findsOneWidget);
    expect(find.text('기도'), findsNothing);
    expect(find.text('신앙 다이어리'), findsWidgets);
    expect(find.text('이야기 탐험 요약'), findsOneWidget);
    final explorationTitle = find.text('이야기 탐험 요약');
    final diaryCardTitle = find.text('신앙 다이어리').last;
    expect(
      tester.getTopLeft(explorationTitle).dy,
      lessThan(tester.getTopLeft(diaryCardTitle).dy),
    );

    final faithPrompt = find.text("오늘 작성한 신앙 다이어리가 없어요.\n'오늘' 탭에서 기록해 보세요.");
    await tester.ensureVisible(faithPrompt);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(faithPrompt).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    final diaryCard = find.byKey(
      const ValueKey('companion-diary-feature-card'),
    );
    final bibleCard = find.byKey(const ValueKey('bible-progress-feature-card'));
    expect(tester.getSize(diaryCard).height, lessThan(138));
    expect(tester.getSize(diaryCard).height, lessThan(204));
    expect(
      tester.getSize(diaryCard).height,
      closeTo(tester.getSize(bibleCard).height, 0.1),
    );
  });

  testWidgets('아주크게 작은 프로필 화면은 다이어리와 통독 카드를 필요한 만큼 확장한다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
      viewSize: const Size(360, 780),
      textScale: 1.4,
    );

    expect(tester.takeException(), isNull);
    final diaryCardTitle = find.text('신앙 다이어리').last;
    final diaryTitleWidget = tester.widget<Text>(diaryCardTitle);
    expect(diaryTitleWidget.maxLines, 2);
    expect(diaryTitleWidget.overflow, TextOverflow.visible);

    final faithPrompt = find.text("오늘 작성한 신앙 다이어리가 없어요.\n'오늘' 탭에서 기록해 보세요.");
    final faithPromptWidget = tester.widget<Text>(faithPrompt);
    expect(faithPromptWidget.maxLines, 4);
    expect(faithPromptWidget.overflow, TextOverflow.visible);

    await tester.ensureVisible(faithPrompt);
    await tester.pumpAndSettle();

    final diaryCard = find.byKey(
      const ValueKey('companion-diary-feature-card'),
    );
    final bibleCard = find.byKey(const ValueKey('bible-progress-feature-card'));
    expect(tester.getSize(diaryCard).height, greaterThanOrEqualTo(118));
    expect(
      tester.getSize(diaryCard).height,
      closeTo(tester.getSize(bibleCard).height, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('아주크게에서도 탐험 달력과 흔적을 overflow 없이 보여준다', (tester) async {
    final recentEvent = _profileEvent(
      id: 'event-recent',
      title: '최근 탐험한 이야기',
      storyIndex: 1,
    );
    final nextEvent = _profileEvent(
      id: 'event-next',
      title: '고라의 반역: 권위에 맞서다',
      storyIndex: 2,
      summary: '하나님이 세우신 권위 앞에서 마음을 돌아보는 이야기입니다.',
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

    final titleFinder = find.text('다이어리');
    expect(titleFinder, findsOneWidget);
    expect(find.text('고라의 반역: 권위에 맞서다'), findsNothing);
    expect(
      MediaQuery.textScalerOf(tester.element(titleFinder)).scale(1),
      greaterThanOrEqualTo(1.3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('다이어리는 감정 카테고리를 중복 표시하지 않는다', (tester) async {
    final recentEvent = _profileEvent(
      id: 'event-recent',
      title: '가나안 정탐: 믿음과 두려움의 갈림길',
      storyIndex: 18,
      placeName: '가데스 바네아',
      startYear: -1445,
      characterCodes: const ['moses', 'god', 'aaron'],
    );
    final nextEvent = _profileEvent(
      id: 'event-next',
      title: '고라의 반역: 권위에 맞서다',
      storyIndex: 19,
      placeName: '가데스 바네아',
      startYear: -1445,
      characterCodes: const ['moses', 'god', 'aaron'],
    );
    final sideEvent = _profileEvent(
      id: 'event-side',
      title: '므리바 물: 바위를 치다',
      storyIndex: 20,
      placeName: '므리바',
      startYear: -1444,
      characterCodes: const ['moses', 'god', 'aaron'],
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [recentEvent, nextEvent, sideEvent]);
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

    expect(find.text('다이어리'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-category-gratitude')),
      findsNothing,
    );
    expect(find.text('고라의 반역: 권위에 맞서다'), findsNothing);
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
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {
        'emotion-event': _profileEmotionMark('emotion-event', note: '감정 코멘트'),
      },
    );
    when(
      () => userRepository.fetchCompanionDiaryEntries(userId: user.id),
    ).thenAnswer((_) async => [_profileDiaryEntry('diary-1', userId: user.id)]);
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

    expect(find.text('이야기 탐험 요약'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('복습'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
    expect(find.text('저장 이야기 개수'), findsNothing);
    expect(find.text('말씀'), findsOneWidget);
    expect(find.text('1개'), findsWidgets);
    expect(find.text('2개'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('profile-story-summary-saved-stories')),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 이야기'), findsWidgets);
    expect(find.byType(ParchmentListPageScaffold), findsOneWidget);
    expect(
      find.byKey(const ValueKey('saved-stories-review-grid')),
      findsOneWidget,
    );
  });

  testWidgets('프로필 첫 진입은 기존 컨트롤러 상태가 비어 있어도 완료 이야기 수를 새로 읽는다', (tester) async {
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
    final notificationRepository = _MockNotificationRepository();

    when(
      () => notificationRepository.watchUnreadCount(),
    ).thenAnswer((_) => Stream<int>.value(0));
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [completedEvent, incompleteEvent]);

    final container = ProviderContainer(
      overrides: [
        signedInUserProvider.overrideWithValue(user),
        storyRepositoryProvider.overrideWithValue(storyRepository),
        storyControllerProvider.overrideWith(
          _ProfileProgressRefreshStoryController.new,
        ),
        userRepositoryProvider.overrideWithValue(userRepository),
        notificationRepositoryProvider.overrideWithValue(
          notificationRepository,
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(storyControllerProvider).completedEventIds, isEmpty);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: TickerMode(
            enabled: false,
            child: ProfileTabPage(
              onStartQuiz: (_) {},
              onOpenEventDetail: (_, {source}) {},
              onOpenBibleReader:
                  ({initialBookNo, initialChapterNo, initialVerseNo}) async {},
              onOpenAppPublications: () {},
              onNavigateNotification: (_) {},
              onOpenNotificationHistory: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(storyControllerProvider).completedEventIds, {
      'event-done',
    });
    final richTexts = tester
        .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
        .map((widget) => widget.text.toPlainText())
        .toList(growable: false);
    expect(richTexts, contains('1/301개'));
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

  testWidgets('통독 진행률 페이지에서 장을 누르면 해당 장 성경 리더를 연다', (tester) async {
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

    expect(find.byType(BibleProgressScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
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

  testWidgets('통독 진행률 페이지는 마지막 통독 완료 권으로 열린다', (tester) async {
    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchEventEmotionMarks(user.id),
    ).thenAnswer((_) async => const <String, EventEmotionMark>{});
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => {'43:3'});

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

    expect(find.byType(BibleProgressScreen), findsOneWidget);
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

  testWidgets('내정보 통독 카드에는 이어 읽기 버튼을 표시하지 않는다', (tester) async {
    int? openedBookNo;
    int? openedChapterNo;
    int? openedVerseNo;
    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchEventEmotionMarks(user.id),
    ).thenAnswer((_) async => const <String, EventEmotionMark>{});
    when(
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchQuizAttemptSummaries(user.id),
    ).thenAnswer((_) async => const {});
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
    when(
      () => storyRepository.fetchCompletedBibleChapterKeys(user.id),
    ).thenAnswer((_) async => {'1:1'});

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

    expect(
      find.byKey(const ValueKey('bible-progress-continue-button')),
      findsNothing,
    );
    expect(openedBookNo, isNull);
    expect(openedChapterNo, isNull);
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

    expect(find.text('탐험한 이야기'), findsNothing);
    expect(find.text('완료'), findsWidgets);
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

  testWidgets('복습 페이지는 복습 항목을 제한된 인라인 카드와 팝업으로 보여준다', (tester) async {
    final wrongEvents = [
      for (var index = 1; index <= 10; index++)
        _profileEvent(
          id: 'event-wrong-$index',
          title: '오답 $index 이야기',
          storyIndex: index,
        ),
    ];
    final confusedEvent = _profileEvent(
      id: 'event-confused',
      title: '헷갈려요로 복습할 이야기',
      storyIndex: 11,
    );
    final correctEvent = _profileEvent(
      id: 'event-correct',
      title: '정답으로 기록된 이야기',
      storyIndex: 12,
    );

    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [...wrongEvents, confusedEvent, correctEvent]);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(
      () => storyRepository.fetchEventEmotionMarks(user.id),
    ).thenAnswer((_) async => const {});
    when(() => storyRepository.fetchQuizAttemptSummaries(user.id)).thenAnswer(
      (_) async => {
        for (final event in wrongEvents)
          event.id: _profileQuizAttemptSummary(event.id, wrongCount: 1),
        'event-confused': _profileQuizAttemptSummary(
          'event-confused',
          confusedCount: 1,
        ),
        'event-correct': _profileQuizAttemptSummary(
          'event-correct',
          correctCount: 3,
        ),
      },
    );
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

    final explorationLogCard = find.byKey(
      const ValueKey('profile-story-summary-exploration-log'),
    );
    await tester.ensureVisible(explorationLogCard);
    await tester.pumpAndSettle();
    await tester.tap(explorationLogCard);
    await tester.pumpAndSettle();

    final reviewPanel = find.byKey(
      const ValueKey('exploration-log-review-events'),
    );
    Finder reviewPanelTitle(String title) {
      return find.descendant(of: reviewPanel, matching: find.text(title));
    }

    expect(reviewPanelTitle('오답이나 헷갈려요를 누르면 이야기 카드가 나타납니다.'), findsOneWidget);

    await tester.tap(find.text('정답'));
    await tester.pumpAndSettle();

    expect(reviewPanelTitle('정답으로 기록된 이야기'), findsNothing);
    expect(reviewPanelTitle('오답이나 헷갈려요를 누르면 이야기 카드가 나타납니다.'), findsOneWidget);

    await tester.tap(find.text('오답'));
    await tester.pumpAndSettle();

    expect(reviewPanelTitle('오답 1 이야기'), findsOneWidget);
    expect(reviewPanelTitle('오답 10 이야기'), findsNothing);
    expect(reviewPanelTitle('헷갈려요로 복습할 이야기'), findsNothing);
    expect(
      find.byKey(const ValueKey('exploration-log-review-open-all-wrong')),
      findsOneWidget,
    );

    await tester.tap(find.text('오답'));
    await tester.pumpAndSettle();

    expect(reviewPanelTitle('오답이나 헷갈려요를 누르면 이야기 카드가 나타납니다.'), findsOneWidget);

    await tester.tap(find.text('오답'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('exploration-log-review-open-all-wrong')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('exploration-log-review-open-all-wrong')),
    );
    await tester.pumpAndSettle();

    expect(find.text('오답 이야기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('exploration-log-review-all-grid')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('exploration-log-review-all-grid')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.text('오답 10 이야기'), findsOneWidget);

    await tester.tap(find.byTooltip('닫기').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('헷갈려요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('헷갈려요'));
    await tester.pumpAndSettle();

    expect(reviewPanelTitle('오답 1 이야기'), findsNothing);
    expect(reviewPanelTitle('헷갈려요로 복습할 이야기'), findsOneWidget);
  });

  testWidgets('복습 페이지에는 다이어리 달력 없이 감정 카테고리만 표시한다', (tester) async {
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final selectedDate = DateTime(nowKst.year, nowKst.month, nowKst.day);
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
          updatedAt: DateTime.utc(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          ),
        ),
        'event-gratitude': _profileEmotionMark(
          'event-gratitude',
          emotionKey: 'gratitude',
          emotionLabel: '감사',
          emotionEmoji: '💛',
          note: '감사 메모',
          updatedAt: DateTime.utc(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            1,
          ),
        ),
        'event-comfort': _profileEmotionMark(
          'event-comfort',
          emotionKey: 'comfort',
          emotionLabel: '위로',
          emotionEmoji: '🌿',
          note: '위로 메모',
          updatedAt: DateTime.utc(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          ).subtract(const Duration(days: 1)),
        ),
        'event-fear': _profileEmotionMark(
          'event-fear',
          emotionKey: 'fear',
          emotionLabel: '두려움',
          emotionEmoji: '⚡',
          note: '두려움 메모',
          updatedAt: DateTime.utc(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          ).subtract(const Duration(days: 2)),
        ),
      },
    );
    when(
      () => userRepository.fetchCompanionDiaryEntries(userId: user.id),
    ).thenAnswer(
      (_) async => [
        _profileDiaryEntry(
          'diary-selected',
          userId: user.id,
          entryDate: selectedDate,
        ),
      ],
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

    final explorationLogCard = find.byKey(
      const ValueKey('profile-story-summary-exploration-log'),
    );
    await tester.ensureVisible(explorationLogCard);
    await tester.pumpAndSettle();
    await tester.tap(explorationLogCard);
    await tester.pumpAndSettle();

    expect(find.text('복습'), findsOneWidget);
    expect(find.text('복습 항목'), findsOneWidget);
    expect(find.text('다이어리'), findsNothing);
    expect(find.byKey(const ValueKey('emotion-category-joy')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('selected-date-companion-diary')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('selected-date-emotion-comments')),
      findsNothing,
    );
  });

  testWidgets('복습 페이지는 감정 카테고리와 복습 항목을 서로 다른 단일 카드로 보여준다', (tester) async {
    final event = _profileEvent(id: 'event-gratitude', title: '감사로 새긴 이야기');
    when(() => auth.currentUser).thenReturn(user);
    when(
      () => storyRepository.fetchEventsByEra('era-1'),
    ).thenAnswer((_) async => [event]);
    when(
      () => storyRepository.fetchEventProgress(user.id),
    ).thenAnswer((_) async => const {});
    when(() => storyRepository.fetchEventEmotionMarks(user.id)).thenAnswer(
      (_) async => {
        event.id: _profileEmotionMark(
          event.id,
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

    final reviewCard = find.byKey(
      const ValueKey('profile-story-summary-exploration-log'),
    );
    await tester.ensureVisible(reviewCard);
    await tester.tap(reviewCard);
    await tester.pumpAndSettle();

    final categoryCard = find.byKey(
      const ValueKey('exploration-log-emotion-categories'),
    );
    final reviewItemsCard = find.byKey(
      const ValueKey('exploration-log-review-events'),
    );
    expect(categoryCard, findsOneWidget);
    expect(reviewItemsCard, findsOneWidget);
    expect(find.text('감정 카테고리'), findsOneWidget);
    expect(find.text('복습 항목'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-category-gratitude')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('emotion-category-gratitude')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('exploration-log-emotion-grid-gratitude')),
      findsOneWidget,
    );
    expect(find.text('감사로 새긴 이야기'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    final categoryDecoration =
        tester.widget<Container>(categoryCard).decoration! as BoxDecoration;
    final reviewDecoration =
        tester.widget<Container>(reviewItemsCard).decoration! as BoxDecoration;
    expect(categoryDecoration.color, isNot(reviewDecoration.color));

    final label = find.byKey(
      const ValueKey('emotion-category-label-gratitude'),
    );
    final count = find.byKey(
      const ValueKey('emotion-category-count-gratitude'),
    );
    expect(
      tester.getTopLeft(count).dy,
      greaterThan(tester.getTopLeft(label).dy),
    );
    expect(
      tester.widget<Text>(count).style?.fontSize,
      greaterThanOrEqualTo(10),
    );
  });

  testWidgets('기록이 없는 날짜에는 다른 탭에서 기록하도록 안내한다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final hint = find.byKey(const ValueKey('profile-log-navigation-hint'));
    expect(hint, findsOneWidget);
    expect(
      find.descendant(
        of: hint,
        matching: find.byKey(const ValueKey('profile-log-nav-today')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hint,
        matching: find.byKey(const ValueKey('profile-log-nav-bible')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hint,
        matching: find.byKey(const ValueKey('profile-log-nav-map')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hint, matching: find.text('오늘')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hint, matching: find.text('성경')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hint, matching: find.text('지도')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hint, matching: find.text('탭으로 이동하여 기록을 남겨보세요')),
      findsOneWidget,
    );
  });

  testWidgets('선택 날짜 통독 기록은 권 장을 가운데점으로 잇고 초과분은 상세에서 보여준다', (tester) async {
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final todayUtc = DateTime.utc(nowKst.year, nowKst.month, nowKst.day, 1);
    when(() => auth.currentUser).thenReturn(user);
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
      () => storyRepository.fetchSavedEventIds(user.id),
    ).thenAnswer((_) async => const <String>{});
    when(
      () => storyRepository.fetchCompletedBibleChapterReadAts(user.id),
    ).thenAnswer(
      (_) async => {
        '1:1': todayUtc,
        '1:3': todayUtc,
        '2:2': todayUtc,
        '43:3': todayUtc,
      },
    );

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    expect(
      find.byKey(const ValueKey('selected-date-bible-reading')),
      findsOneWidget,
    );
    expect(find.text('창세기 1장 · 창세기 3장 · 출애굽기 2장'), findsOneWidget);
    final more = find.byKey(const ValueKey('selected-date-bible-reading-more'));
    expect(more, findsOneWidget);

    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('통독 기록 상세'), findsOneWidget);
    expect(find.text('요한복음 3장'), findsWidgets);
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
  bool tickerEnabled = false,
  bool settleAfterPump = true,
  bool authenticated = true,
  VoidCallback? onExploreStoriesFromHome,
  ProfileEventDetailCallback? onOpenEventDetail,
}) async {
  final notificationRepository = _MockNotificationRepository();
  when(
    () => notificationRepository.watchUnreadCount(),
  ).thenAnswer((_) => Stream<int>.value(0));

  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(authenticated ? user : null),
        storyRepositoryProvider.overrideWithValue(storyRepository),
        userRepositoryProvider.overrideWithValue(userRepository),
        notificationRepositoryProvider.overrideWithValue(
          notificationRepository,
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: TickerMode(
            enabled: tickerEnabled,
            child: ProfileTabPage(
              onStartQuiz: (_) {},
              onOpenEventDetail: onOpenEventDetail ?? (_, {source}) {},
              onOpenBibleReader:
                  onOpenBibleReader ??
                  ({initialBookNo, initialChapterNo, initialVerseNo}) {
                    return Future<void>.value();
                  },
              onExploreStoriesFromHome: onExploreStoriesFromHome,
              onOpenAppPublications: () {},
              onNavigateNotification: (_) {},
              onOpenNotificationHistory: () {},
            ),
          ),
        ),
      ),
    ),
  );
  if (settleAfterPump) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
