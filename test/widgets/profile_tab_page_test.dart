import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/app_user_profile.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/character_study_progress.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/intercessory_prayer_item.dart';
import 'package:story_bible/models/paged_result.dart';
import 'package:story_bible/models/saved_bible_verse.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/profile_editor_dialog.dart';
import 'package:story_bible/widgets/profile_tab_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

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
      () => storyRepository.fetchCharacterTimelineOrder(),
    ).thenAnswer((_) async => const <String, int>{});
    when(
      () => storyRepository.fetchEventsByIds(any()),
    ).thenAnswer((_) async => const <StoryEvent>[]);

    when(
      () => userRepository.ensureSignedInUser(user),
    ).thenAnswer((_) async => profile);
    when(
      () => userRepository.fetchCharacterStudyProgress(
        userId: user.id,
        people: any(named: 'people'),
      ),
    ).thenAnswer((_) async => const <CharacterStudyProgress>[]);
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

    final nickname = find.text('기도친구');
    expect(nickname, findsOneWidget);
    expect(tester.getTopLeft(nickname).dx, greaterThan(100));

    await tester.tap(nickname);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditorDialog), findsOneWidget);
    expect(find.text('프로필 수정'), findsOneWidget);
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
    expect(find.text('기도친구'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsNothing);
  });

  testWidgets('프로필 진행 탭은 다이어리 다음에 인물과 걷기를 먼저 보여준다', (tester) async {
    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    final diaryX = tester.getCenter(find.text('나의 다이어리')).dx;
    final walkX = tester.getCenter(find.text('인물과 걷기')).dx;
    final placeX = tester.getCenter(find.text('장소로 시작')).dx;

    expect(diaryX, lessThan(walkX));
    expect(walkX, lessThan(placeX));
  });

  testWidgets('인물과 걷기 탭은 각 인물의 첫 이야기 순으로 나열한다', (tester) async {
    when(() => storyRepository.fetchCharactersByEra('era-1')).thenAnswer(
      (_) async => const [
        Character(
          id: 'person-saul',
          code: 'saul',
          name: '사울',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 1,
        ),
        Character(
          id: 'person-abraham',
          code: 'abraham',
          name: '아브라함',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 2,
        ),
        Character(
          id: 'person-adam',
          code: 'adam',
          name: '아담',
          tagline: null,
          description: null,
          avatarUrl: null,
          displayOrder: 3,
        ),
      ],
    );
    when(
      () => storyRepository.fetchCharacterTimelineOrder(),
    ).thenAnswer((_) async => const {'adam': 1, 'abraham': 20, 'saul': 60});

    await _pumpProfileTab(
      tester,
      user: user,
      storyRepository: storyRepository,
      userRepository: userRepository,
      supabaseClient: supabaseClient,
    );

    await tester.tap(find.text('인물과 걷기'));
    await tester.pumpAndSettle();

    final adamX = tester.getCenter(find.text('아담')).dx;
    final abrahamX = tester.getCenter(find.text('아브라함')).dx;
    final saulX = tester.getCenter(find.text('사울')).dx;

    expect(adamX, lessThan(abrahamX));
    expect(abrahamX, lessThan(saulX));
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
    expect(find.text('태초에 하나님이 천지를 창조하시니라'), findsOneWidget);
    expect(find.text('처음 저장한 말씀'), findsOneWidget);
  });
}

Future<void> _pumpProfileTab(
  WidgetTester tester, {
  required User user,
  required StoryRepository storyRepository,
  required UserRepository userRepository,
  required SupabaseClient supabaseClient,
}) async {
  tester.view.physicalSize = const Size(900, 700);
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
        home: ProfileTabPage(
          onStartQuiz: (_) {},
          onOpenEventDetail: (_, {source, sourceId}) {},
          onOpenBibleReader:
              ({initialBookNo, initialChapterNo, initialVerseNo}) {
                return Future<void>.value();
              },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
