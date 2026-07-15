part of 'story_controller_test.dart';

void main() {
  late _MockStoryRepository mockRepo;
  late _MockUserRepository mockUserRepo;
  late _MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;

  setUpAll(() {
    registerFallbackValue(_fallbackEmotionMark);
    registerFallbackValue(_fallbackQuizAttemptSummary);
  });

  setUp(() {
    mockRepo = _MockStoryRepository();
    mockUserRepo = _MockUserRepository();
    mockClient = _MockSupabaseClient();
    mockAuth = _MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(null);
  });

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        storyRepositoryProvider.overrideWithValue(mockRepo),
        userRepositoryProvider.overrideWithValue(mockUserRepo),
        supabaseClientProvider.overrideWithValue(mockClient),
      ],
    );
  }

  group('StoryController.initialize', () {
    test('eras 로드 성공 시 첫 구약 시대를 기본 testament로 설정', () async {
      final eras = [
        _era(id: 'era1', code: 'era_primeval', testament: 'old'),
        _era(
          id: 'era2',
          code: 'era_nt_gospels',
          testament: 'new',
          displayOrder: 1,
        ),
      ];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.eras, hasLength(2));
      expect(state.selectedTestament, 'old');
      expect(state.error, isNull);
    });

    test('eras가 비어있으면 에러 메시지 설정', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, '시대 데이터가 없습니다.');
    });

    test('fetchEras 실패 시 에러 메시지 포함한 상태로 전환', () async {
      when(() => mockRepo.fetchEras()).thenThrow(Exception('network down'));

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, contains('초기 데이터를 불러오지 못했습니다'));
    });

    test('구약이 없고 신약만 있으면 신약을 기본 testament로 선택', () async {
      final eras = [_era(id: 'era1', code: 'era_nt_test', testament: 'new')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
    });

    test('사용자 진행률 조회가 실패해도 기본 이야기 데이터는 표시한다', () async {
      final user = _user(id: 'u1');
      final eras = [_era(id: 'era1', code: 'era_primeval')];
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchEventProgress(user.id),
      ).thenThrow(Exception('Failed host lookup'));
      when(
        () => mockRepo.fetchEventEmotionMarks(user.id),
      ).thenThrow(Exception('Failed host lookup'));
      when(
        () => mockRepo.fetchSavedEventIds(user.id),
      ).thenThrow(Exception('Failed host lookup'));
      when(
        () => mockRepo.fetchCompletedBibleChapterReadAts(user.id),
      ).thenThrow(Exception('Failed host lookup'));
      when(
        () => mockRepo.fetchCompletedBibleChapterKeys(user.id),
      ).thenThrow(Exception('Failed host lookup'));
      when(
        () => mockRepo.fetchQuizAttemptSummaries(user.id),
      ).thenThrow(Exception('Failed host lookup'));

      final container = buildContainer();
      await container.read(storyControllerProvider.notifier).initialize();

      final state = container.read(storyControllerProvider);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(state.eras, eras);
      expect(state.completedEventIds, isEmpty);
      expect(state.quizAttemptSummaries, isEmpty);
    });
  });

  group('StoryController.clearUserScopedData', () {
    test('로그아웃 시 공개 이야기 데이터는 유지하고 모든 사용자 기록을 비운다', () async {
      final user = _user(id: 'u1');
      final eras = [_era(id: 'era1', code: 'era_primeval')];
      when(() => mockAuth.currentUser).thenReturn(user);
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(() => mockRepo.fetchLandmarks()).thenAnswer((_) async => const []);
      when(() => mockRepo.fetchEventProgress(user.id)).thenAnswer(
        (_) async => {
          'e1': (bibleRead: true, quizCompleted: true, completed: true),
        },
      );
      when(() => mockRepo.fetchEventEmotionMarks(user.id)).thenAnswer(
        (_) async => const {
          'e1': EventEmotionMark(
            eventId: 'e1',
            emotionKey: 'joy',
            emotionLabel: '기쁨',
            emotionEmoji: '🌟',
            note: '',
            updatedAt: null,
          ),
        },
      );
      when(
        () => mockRepo.fetchSavedEventIds(user.id),
      ).thenAnswer((_) async => const {'e1'});
      when(
        () => mockRepo.fetchCompletedBibleChapterReadAts(user.id),
      ).thenAnswer((_) async => {'1:1': DateTime.utc(2026, 7, 15, 14)});
      when(() => mockRepo.fetchQuizAttemptSummaries(user.id)).thenAnswer(
        (_) async => const {
          'e1': QuizAttemptSummary(
            eventId: 'e1',
            correctCount: 1,
            totalCount: 3,
            wrongCount: 1,
            confusedCount: 1,
            selectedAnswers: [0, 1, 3],
            updatedAt: null,
          ),
        },
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      final signedInState = container.read(storyControllerProvider);
      expect(signedInState.completedEventIds, {'e1'});
      expect(signedInState.bibleReadEventIds, {'e1'});
      expect(signedInState.quizCompletedEventIds, {'e1'});
      expect(signedInState.lastQuizScores, contains('e1'));
      expect(signedInState.quizAttemptSummaries, contains('e1'));
      expect(signedInState.eventEmotionMarks, contains('e1'));
      expect(signedInState.savedEventIds, {'e1'});
      expect(signedInState.completedBibleChapterKeys, {'1:1'});
      expect(signedInState.completedBibleChapterReadAts, contains('1:1'));

      controller.clearUserScopedData();

      final signedOutState = container.read(storyControllerProvider);
      expect(signedOutState.eras, eras);
      expect(signedOutState.completedEventIds, isEmpty);
      expect(signedOutState.bibleReadEventIds, isEmpty);
      expect(signedOutState.quizCompletedEventIds, isEmpty);
      expect(signedOutState.lastQuizScores, isEmpty);
      expect(signedOutState.quizAttemptSummaries, isEmpty);
      expect(signedOutState.eventEmotionMarks, isEmpty);
      expect(signedOutState.savedEventIds, isEmpty);
      expect(signedOutState.completedBibleChapterKeys, isEmpty);
      expect(signedOutState.completedBibleChapterReadAts, isEmpty);
    });

    test('로그아웃 전에 시작한 사용자 조회가 늦게 끝나도 기록을 되살리지 않는다', () async {
      final user = _user(id: 'u1');
      final pendingSavedEvents = Completer<Set<String>>();
      when(() => mockAuth.currentUser).thenReturn(user);
      when(
        () => mockRepo.fetchSavedEventIds(user.id),
      ).thenAnswer((_) => pendingSavedEvents.future);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      final refresh = controller.refreshSavedEventIds();
      await untilCalled(() => mockRepo.fetchSavedEventIds(user.id));

      controller.clearUserScopedData();
      pendingSavedEvents.complete({'old-user-event'});
      await refresh;

      expect(container.read(storyControllerProvider).savedEventIds, isEmpty);
    });
  });

  group('StoryController.selectEra', () {
    setUp(() {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'era1', code: 'era_primeval')]);
    });

    test('characters와 events를 로드하고 selectedEraId를 설정', () async {
      when(
        () => mockRepo.fetchCharactersByEra('era1'),
      ).thenAnswer((_) async => [_person(id: 'p1', name: '아담')]);
      when(() => mockRepo.fetchEventsByEra('era1')).thenAnswer(
        (_) async => [
          _event(id: 'e1', eraId: 'era1', characterCodes: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');

      final state = container.read(storyControllerProvider);
      expect(state.selectedEraId, 'era1');
      expect(state.characters, hasLength(1));
      expect(state.events, hasLength(1));
      expect(state.loading, isFalse);
    });

    test('실패 시 error 메시지 설정', () async {
      when(
        () => mockRepo.fetchCharactersByEra('era1'),
      ).thenThrow(Exception('boom'));

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');

      final state = container.read(storyControllerProvider);
      expect(state.error, contains('시대 변경 중'));
    });
  });

  group('StoryController.toggleCharacter', () {
    test('비어있는 set에 id 추가', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.toggleCharacter('p1');

      expect(
        container.read(storyControllerProvider).selectedCharacterCodes,
        containsAll(['p1']),
      );
    });

    test('이미 있는 id는 제거', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.toggleCharacter('p1');
      controller.toggleCharacter('p1');

      expect(
        container.read(storyControllerProvider).selectedCharacterCodes,
        isEmpty,
      );
    });

    test('색상 팔레트가 선택 순서대로 할당', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.toggleCharacter('p1');
      controller.toggleCharacter('p2');

      final colors = container
          .read(storyControllerProvider)
          .selectedCharacterColors;
      expect(colors['p1'], isNotNull);
      expect(colors['p2'], isNotNull);
      expect(colors['p1'], isNot(equals(colors['p2'])));
    });
  });

  group('StoryController.selectEvent', () {
    test('null 전달 시 selectedEventId 클리어', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.selectEvent('e1');
      expect(container.read(storyControllerProvider).selectedEventId, 'e1');

      controller.selectEvent(null);
      expect(container.read(storyControllerProvider).selectedEventId, isNull);
    });
  });

  group('StoryController.colorForCharacter', () {
    test('미선택 인물도 hash 기반 안정 색상을 반환한다 (시대 미리보기 path 색)', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      // 같은 코드는 항상 같은 색 — 화면 새로고침/시대 전환에도 일관됨.
      final c1 = controller.colorForCharacter('unknown_a');
      final c2 = controller.colorForCharacter('unknown_a');
      expect(c1, c2);
      // 다른 코드는 다른 팔레트 슬롯에 매핑되므로 보통 다른 색 (충돌 가능하지만
      // 같은 코드끼리의 stability 만 검증).
      expect(c1, isNot(equals(const Color(0x00000000))));
    });

    test('빈 코드면 characterFallback 토큰을 반환', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      expect(controller.colorForCharacter(''), AppColors.characterFallback);
    });
  });

  group('StoryController.mergedTimeline', () {
    test('선택된 인물의 이벤트만 time_sort_key 오름차순으로 반환', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'era1', code: 'era_primeval')]);
      when(() => mockRepo.fetchCharactersByEra('era1')).thenAnswer(
        (_) async => [
          _person(id: 'p1', name: '아담'),
          _person(id: 'p2', name: '이브', displayOrder: 1),
        ],
      );
      when(() => mockRepo.fetchEventsByEra('era1')).thenAnswer(
        (_) async => [
          _event(
            id: 'e1',
            eraId: 'era1',
            characterCodes: ['p1'],
            globalRank: 20,
          ),
          _event(
            id: 'e2',
            eraId: 'era1',
            characterCodes: ['p2'],
            globalRank: 10,
          ),
          _event(
            id: 'e3',
            eraId: 'era1',
            characterCodes: ['p1'],
            globalRank: 5,
          ),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('era1');
      controller.setSelectedCharacters({'p1'});

      final timeline = controller.mergedTimeline();
      expect(timeline.map((e) => e.id), orderedEquals(['e3', 'e1']));
    });
  });

  group('StoryController.selectTestament', () {
    test('구약 → 신약 전환 시 해당 testament의 첫 시대를 선택', () async {
      final eras = [
        _era(id: 'e1', code: 'old1', testament: 'old'),
        _era(id: 'e2', code: 'new1', testament: 'new', displayOrder: 0),
        _era(id: 'e3', code: 'new2', testament: 'new', displayOrder: 1),
      ];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      await controller.selectTestament('new');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
      // 첫 번째 신약 시대 선택
      expect(state.selectedEraId, 'e2');
    });

    test('이미 같은 testament이고 시대도 일치하면 아무 동작 없음', () async {
      final eras = [_era(id: 'e1', code: 'old1', testament: 'old')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      // 같은 testament 다시 호출 — selectEra가 추가 호출되지 않아야 함
      await controller.selectTestament('old');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'old');
      expect(state.selectedEraId, 'e1');
    });

    test('해당 testament에 시대가 없으면 선택 초기화', () async {
      final eras = [_era(id: 'e1', code: 'old1', testament: 'old')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      await controller.selectTestament('new');
      final state = container.read(storyControllerProvider);
      expect(state.selectedTestament, 'new');
      expect(state.selectedEraId, isNull);
      expect(state.characters, isEmpty);
      expect(state.events, isEmpty);
    });
  });

  group('StoryController.toggleEra', () {
    test('선택된 시대를 다시 토글하면 선택 해제', () async {
      final eras = [_era(id: 'e1', code: 'old1')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      expect(container.read(storyControllerProvider).selectedEraId, 'e1');

      await controller.toggleEra('e1');
      expect(container.read(storyControllerProvider).selectedEraId, isNull);
    });

    test('다른 시대를 토글하면 해당 시대를 선택', () async {
      final eras = [_era(id: 'e1', code: 'old1'), _era(id: 'e2', code: 'old2')];
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => eras);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      await controller.toggleEra('e2');
      expect(container.read(storyControllerProvider).selectedEraId, 'e2');
    });
  });

  group('StoryController.clearEraSelection', () {
    test('모든 선택 상태를 초기화', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(() => mockRepo.fetchLandmarks()).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      controller.toggleCharacter('p1');
      controller.selectEvent('ev1');

      controller.clearEraSelection();
      final state = container.read(storyControllerProvider);
      expect(state.selectedEraId, isNull);
      expect(state.selectedEventId, isNull);
      expect(state.selectedCharacterCodes, isEmpty);
      expect(state.characters, isEmpty);
      expect(state.events, isEmpty);
      expect(state.searchQuery, '');
    });
  });

  group('StoryController.clearMapExplorationSelection', () {
    test('지도 선택은 비우고 사용자 완료 기록은 유지', () async {
      final user = _user(id: 'u1');
      when(() => mockAuth.currentUser).thenReturn(user);
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(() => mockRepo.fetchLandmarks()).thenAnswer((_) async => const []);
      when(
        () => mockRepo.fetchCharactersByEra('e1'),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra('e1')).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
        ],
      );
      when(() => mockRepo.fetchEventProgress(user.id)).thenAnswer(
        (_) async => {
          'ev1': (bibleRead: true, quizCompleted: true, completed: true),
        },
      );
      when(() => mockRepo.fetchEventEmotionMarks(user.id)).thenAnswer(
        (_) async => const {
          'ev1': EventEmotionMark(
            eventId: 'ev1',
            emotionKey: 'joy',
            emotionLabel: '기쁨',
            emotionEmoji: '🌟',
            note: '',
            updatedAt: null,
          ),
        },
      );
      when(
        () => mockRepo.fetchSavedEventIds(user.id),
      ).thenAnswer((_) async => const {});
      when(
        () => mockRepo.fetchCompletedBibleChapterReadAts(user.id),
      ).thenAnswer((_) async => const {});
      when(
        () => mockRepo.fetchQuizAttemptSummaries(user.id),
      ).thenAnswer((_) async => const {});

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      controller.setSelectionMode(SelectionMode.character);
      controller.toggleCharacter('p1');
      controller.selectEvent('ev1');

      controller.clearMapExplorationSelection();
      final state = container.read(storyControllerProvider);
      expect(state.selectedEraId, isNull);
      expect(state.selectionMode, isNull);
      expect(state.selectedEventId, isNull);
      expect(state.selectedCharacterCodes, isEmpty);
      expect(state.characters, isEmpty);
      expect(state.events, isEmpty);
      expect(state.completedEventIds, contains('ev1'));
      expect(state.bibleReadEventIds, contains('ev1'));
      expect(state.quizCompletedEventIds, contains('ev1'));
    });
  });

  group('StoryController.setSelectedCharacters', () {
    test('characters에 없는 id는 필터링된다', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(() => mockRepo.fetchCharactersByEra(any())).thenAnswer(
        (_) async => [
          _person(id: 'p1', name: 'A'),
          _person(id: 'p2', name: 'B'),
        ],
      );
      when(
        () => mockRepo.fetchEventsByEra(any()),
      ).thenAnswer((_) async => const []);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      controller.setSelectedCharacters({'p1', 'p999'});
      final state = container.read(storyControllerProvider);
      expect(state.selectedCharacterCodes, {'p1'});
      expect(state.selectedCharacterColors.containsKey('p1'), true);
      expect(state.selectedCharacterColors.containsKey('p999'), false);
    });
  });

  group('StoryController.setSearchQuery', () {
    test('빈 쿼리면 검색 결과 초기화', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('모세');
      controller.setSearchQuery('');
      final state = container.read(storyControllerProvider);
      expect(state.searchQuery, '');
      expect(state.isSearching, false);
      expect(state.searchResults, isEmpty);
    });

    test('공백만 있는 쿼리도 빈 쿼리 처리', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('   ');
      final state = container.read(storyControllerProvider);
      expect(state.isSearching, false);
    });

    test('유효한 쿼리면 isSearching을 true로 설정', () async {
      when(() => mockRepo.fetchEras()).thenAnswer((_) async => const []);
      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();

      controller.setSearchQuery('모세');
      final state = container.read(storyControllerProvider);
      expect(state.searchQuery, '모세');
      expect(state.isSearching, true);
    });
  });

  group('StoryController.setDisplayedEvents', () {
    test('전달된 id 중 state.events 에 있는 것만 displayedEventIds 에 저장', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
          _event(id: 'ev2', eraId: 'e1', characterCodes: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      controller.setDisplayedEvents({'ev1', 'evX', 'ev2'});
      final state = container.read(storyControllerProvider);
      expect(state.displayedEventIds, {'ev1', 'ev2'});
    });

    test('빈 Set 을 전달하면 displayedEventIds 가 비워진다', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');

      controller.setDisplayedEvents({'ev1'});
      expect(container.read(storyControllerProvider).displayedEventIds, {
        'ev1',
      });

      controller.setDisplayedEvents(const <String>{});
      expect(
        container.read(storyControllerProvider).displayedEventIds,
        isEmpty,
      );
    });
  });

  group('displayedEventIds 리셋 조건', () {
    test('setSelectedCharacters 호출 시 displayedEventIds 가 초기화된다', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(() => mockRepo.fetchCharactersByEra(any())).thenAnswer(
        (_) async => [
          _person(id: 'p1', name: 'A'),
          _person(id: 'p2', name: 'B'),
        ],
      );
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
          _event(id: 'ev2', eraId: 'e1', characterCodes: ['p2']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      controller.setSelectedCharacters({'p1', 'p2'});
      controller.setDisplayedEvents({'ev1', 'ev2'});
      expect(container.read(storyControllerProvider).displayedEventIds, {
        'ev1',
        'ev2',
      });

      // 인물을 다시 설정하면 지도 표시 집합도 비어야 한다
      controller.setSelectedCharacters({'p1'});
      expect(
        container.read(storyControllerProvider).displayedEventIds,
        isEmpty,
      );
    });

    test(
      'setSelectedCharacters 에 동일 집합을 넘기면 displayedEventIds 는 유지된다',
      () async {
        when(
          () => mockRepo.fetchEras(),
        ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
        when(() => mockRepo.fetchCharactersByEra(any())).thenAnswer(
          (_) async => [
            _person(id: 'p1', name: 'A'),
            _person(id: 'p2', name: 'B'),
          ],
        );
        when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
          (_) async => [
            _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
            _event(id: 'ev2', eraId: 'e1', characterCodes: ['p2']),
          ],
        );

        final container = buildContainer();
        final controller = container.read(storyControllerProvider.notifier);
        await controller.initialize();
        await controller.selectEra('e1');
        controller.setSelectedCharacters({'p1', 'p2'});
        controller.setDisplayedEvents({'ev1', 'ev2'});

        // 같은 집합을 다시 커밋 — 지도 표시는 그대로여야 한다
        controller.setSelectedCharacters({'p1', 'p2'});
        expect(container.read(storyControllerProvider).displayedEventIds, {
          'ev1',
          'ev2',
        });
      },
    );

    test('toggleCharacter 호출 시 displayedEventIds 가 초기화된다', () async {
      when(
        () => mockRepo.fetchEras(),
      ).thenAnswer((_) async => [_era(id: 'e1', code: 'old1')]);
      when(
        () => mockRepo.fetchCharactersByEra(any()),
      ).thenAnswer((_) async => [_person(id: 'p1', name: 'A')]);
      when(() => mockRepo.fetchEventsByEra(any())).thenAnswer(
        (_) async => [
          _event(id: 'ev1', eraId: 'e1', characterCodes: ['p1']),
        ],
      );

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.initialize();
      await controller.selectEra('e1');
      controller.setSelectedCharacters({'p1'});
      controller.setDisplayedEvents({'ev1'});
      expect(container.read(storyControllerProvider).displayedEventIds, {
        'ev1',
      });

      controller.toggleCharacter('p1');
      expect(
        container.read(storyControllerProvider).displayedEventIds,
        isEmpty,
      );
    });
  });

  group('StoryController emotion marks', () {
    test('clearEmotionMark는 감정 새김을 삭제하고 state에서 제거한다', () async {
      when(() => mockAuth.currentUser).thenReturn(_user(id: 'u1'));
      when(
        () => mockRepo.upsertEventEmotionMark(
          userId: 'u1',
          mark: any(named: 'mark'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.deleteEventEmotionMark(userId: 'u1', eventId: 'e1'),
      ).thenAnswer((_) async {});

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);

      await controller.setEmotionMark(
        eventId: 'e1',
        option: EventEmotionOption.options.first,
        note: '기쁨이 남았다',
      );
      expect(
        container.read(storyControllerProvider).eventEmotionMarks['e1']?.note,
        '기쁨이 남았다',
      );

      await controller.clearEmotionMark(eventId: 'e1');

      expect(
        container.read(storyControllerProvider).eventEmotionMarks,
        isNot(contains('e1')),
      );
      verify(
        () => mockRepo.deleteEventEmotionMark(userId: 'u1', eventId: 'e1'),
      ).called(1);
    });
  });

  group('StoryController quiz attempts', () {
    test('퀴즈 완료 취소는 저장된 결과와 버튼 표시용 상태를 모두 초기화한다', () async {
      when(() => mockAuth.currentUser).thenReturn(_user(id: 'u1'));
      when(
        () => mockRepo.upsertQuizAttempt(
          userId: 'u1',
          summary: any(named: 'summary'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.deleteQuizAttempt(userId: 'u1', eventId: 'e1'),
      ).thenAnswer((_) async {});
      when(
        () => mockRepo.upsertEventProgress(
          userId: 'u1',
          eventId: 'e1',
          isBibleRead: any(named: 'isBibleRead'),
          isQuizCompleted: any(named: 'isQuizCompleted'),
          isCompleted: any(named: 'isCompleted'),
        ),
      ).thenAnswer((_) async {});

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);

      await controller.setQuizCompleted(
        eventId: 'e1',
        isCompleted: true,
        correct: 1,
        total: 3,
        confusedCount: 1,
        selectedAnswers: const [0, 3, 1],
      );
      expect(
        container.read(storyControllerProvider).quizAttemptSummaries['e1'],
        isNotNull,
      );

      await controller.setQuizCompleted(eventId: 'e1', isCompleted: false);

      final state = container.read(storyControllerProvider);
      expect(state.quizCompletedEventIds, isNot(contains('e1')));
      expect(state.lastQuizScores, isNot(contains('e1')));
      expect(state.quizAttemptSummaries, isNot(contains('e1')));
      verify(
        () => mockRepo.deleteQuizAttempt(userId: 'u1', eventId: 'e1'),
      ).called(1);
    });
  });

  group('StoryController saved events', () {
    test('toggleSavedEvent는 저장 후 state에 eventId를 추가한다', () async {
      when(() => mockAuth.currentUser).thenReturn(_user(id: 'u1'));
      when(
        () => mockRepo.toggleSavedEvent(userId: 'u1', eventId: 'e1'),
      ).thenAnswer((_) async => true);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);

      final saved = await controller.toggleSavedEvent('e1');

      expect(saved, true);
      expect(container.read(storyControllerProvider).savedEventIds, {'e1'});
      verify(
        () => mockRepo.toggleSavedEvent(userId: 'u1', eventId: 'e1'),
      ).called(1);
    });

    test('toggleSavedEvent는 해제 후 state에서 eventId를 제거한다', () async {
      when(() => mockAuth.currentUser).thenReturn(_user(id: 'u1'));
      when(
        () => mockRepo.toggleSavedEvent(userId: 'u1', eventId: 'e1'),
      ).thenAnswer((_) async => true);
      when(
        () => mockRepo.toggleSavedEvent(userId: 'u1', eventId: 'e2'),
      ).thenAnswer((_) async => true);

      final container = buildContainer();
      final controller = container.read(storyControllerProvider.notifier);
      await controller.toggleSavedEvent('e1');
      await controller.toggleSavedEvent('e2');

      when(
        () => mockRepo.toggleSavedEvent(userId: 'u1', eventId: 'e1'),
      ).thenAnswer((_) async => false);

      final saved = await controller.toggleSavedEvent('e1');

      expect(saved, false);
      expect(container.read(storyControllerProvider).savedEventIds, {'e2'});
    });
  });
}
