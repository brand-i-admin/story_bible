part of 'story_home_screen.dart';

class _StoryHomeScreenState extends ConsumerState<StoryHomeScreen> {
  static const double _selectionSheetCollapsedSize = 0.16;
  static const double _selectionSheetExpandedSize = 0.60;

  /// 인트로 패널(시대/모드 선택 단계) 의 기본 콘텐츠 높이.
  /// 실제 시트 높이는 화면 높이 대비 비율로 변환하되, 컨텐츠가 짧은 화면에서는
  /// 내부 스크롤이 맡는다.
  static const double _selectionSheetIntroHeight = 560;

  /// 사건 핀 reveal 모드(region 선택 후 또는 character step 3) 의 panel 크기.
  /// 카드 280px (썸네일+제목+위치+요약+인물) + 핸들 + padding.
  static const double _selectionSheetCardOnlyHeight = 390;
  static const Duration _emotionMapPreStampDelay = Duration(milliseconds: 500);
  static const Duration _emotionMapPostStampDelay = Duration(seconds: 1);
  static const Duration _emotionMapStampFallbackSlack = Duration(
    milliseconds: 650,
  );
  final StoryMapPanelController _mapPanelController = StoryMapPanelController();
  final ScrollController _selectionPanelScrollController = ScrollController();
  final GlobalKey<ProfileTabPageState> _profileTabKey =
      GlobalKey<ProfileTabPageState>();
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  ProviderSubscription<User?>? _authUserSubscription;
  CharacterSortMode _characterSortMode = CharacterSortMode.eraOrder;
  String? _mapCelebrationEventId;
  String? _mapCelebrationStampLabel;
  int _mapCelebrationNonce = 0;
  Completer<void>? _mapCelebrationCompleter;
  bool _mapAnimationInputLocked = false;
  OverlayEntry? _mapAnimationInputBlockerEntry;
  late int _selectionStep = widget.initialStep.clamp(1, 3);

  /// 시대 선택 후 사용자가 고른 탐색 모드. null = intro 패널(시대+모드 카드).
  _SelectionMode? _mode;
  StorySelectionPanelStage _selectionPanelStage =
      StorySelectionPanelStage.expanded;
  double _selectionSheetExtent = _selectionSheetExpandedSize;
  Set<String> _draftSelectedCharacterCodes = <String>{};

  /// step 3 진입 시 panel 을 collapsed 로 내리고 핀 reveal 이 끝나길 기다리는
  /// 중인지. true 면 reveal 완료 콜백이 panel 을 자동 expand 한다. 사용자가
  /// 수동으로 ^ 클릭해서 expand 하면 [_revealInstantly] 가 true 가 되어 핀이
  /// 즉시 모두 노출되며 동시에 panel 도 expand.
  bool _awaitingRevealComplete = false;
  bool _revealInstantly = false;

  /// Step 3 에서 사용자가 체크박스로 고르고 있는 이벤트 id.
  /// 토글 즉시 `controller.setDisplayedEvents` 로 반영되어 지도에 핀이 박힌다
  /// (step 2 인물 토글과 같은 패턴). "다음" 버튼은 단순히 선택 패널을 접는
  /// 역할만 한다.
  Set<String> _draftDisplayedEventIds = <String>{};

  /// 지도 위 안내 오버레이([MapHintOverlay])를 사용자가 한 번이라도 dismiss
  /// 했는지. 새 단계 진입 (`_handlePickMode` / `_handleStepperTap`) 시 false 로
  /// reset 되어 안내가 다시 보이고, 사용자가 지도를 만지거나 region/인물을
  /// 선택하면 true 가 되어 사라진다. step·mode 자체가 "안내가 필요 없는" 상태
  /// (예: region 선택 완료, character step 3) 면 _currentMapHint() 가 null 을
  /// 반환해 이 플래그와 무관하게 hint 가 안 뜬다.
  bool _mapHintDismissed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _authUserSubscription = ref.listenManual<User?>(signedInUserProvider, (
      previous,
      next,
    ) {
      final previousId = previous?.id;
      final nextId = next?.id;
      if (previousId == nextId) {
        return;
      }
      _handleAuthUserChanged(next);
    });
    Future.microtask(() {
      ref.read(storyControllerProvider.notifier).initialize();
    });
    // 앱 시작 시 이미 Supabase 세션이 복원된 상태라면 listenManual 은
    // "값 변화"를 감지하지 못해 fire 되지 않는다. 이 경우 FCM 토큰 등록 +
    // ensureSignedInUser 가 건너뛰어지므로, initState 에서 한 번 명시 호출.
    Future.microtask(() {
      final initialUser = Supabase.instance.client.auth.currentUser;
      if (initialUser != null) {
        _handleAuthUserChanged(initialUser);
      }
    });
  }

  @override
  void dispose() {
    _completeMapCelebration();
    _removeMapAnimationInputBlocker();
    _authUserSubscription?.close();
    _selectionPanelScrollController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _completeMapCelebration([int? nonce]) {
    if (nonce != null && nonce != _mapCelebrationNonce) {
      return;
    }
    final completer = _mapCelebrationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  VoidCallback _mapCelebrationCompleteCallback() {
    final nonce = _mapCelebrationNonce;
    return () => _completeMapCelebration(nonce);
  }

  void _setMapAnimationInputLocked(bool locked) {
    if (!mounted) {
      return;
    }
    if (locked) {
      _insertMapAnimationInputBlocker();
    } else {
      _removeMapAnimationInputBlocker();
    }
    if (_mapAnimationInputLocked != locked) {
      setState(() {
        _mapAnimationInputLocked = locked;
      });
    }
  }

  void _insertMapAnimationInputBlocker() {
    if (_mapAnimationInputBlockerEntry != null) {
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: ModalBarrier(color: Colors.transparent, dismissible: false),
      ),
    );
    _mapAnimationInputBlockerEntry = entry;
    overlay.insert(entry);
  }

  void _removeMapAnimationInputBlocker() {
    _mapAnimationInputBlockerEntry?.remove();
    _mapAnimationInputBlockerEntry = null;
  }

  Future<void> _handleAuthUserChanged(User? user) async {
    if (!mounted) {
      return;
    }
    if (user == null) {
      await ref
          .read(storyControllerProvider.notifier)
          .refreshCompletedEventIds();
      return;
    }

    try {
      await ref.read(userRepositoryProvider).ensureSignedInUser(user);
      if (!mounted) {
        return;
      }
      await ref
          .read(storyControllerProvider.notifier)
          .refreshCompletedEventIds();
      // FCM 토큰 upsert — Firebase 미설정/권한 거부면 내부적으로 no-op.
      try {
        await PushService.instance.registerCurrentTokenIfAuthenticated();
      } catch (_) {
        // 푸시 등록 실패는 앱 동작에 영향 없음
      }
    } catch (_) {
      // 인증 상태 변경 처리 실패는 무시 (재시도 기회 존재)
    }
  }

  static const List<Color> _draftSelectionPalette = <Color>[
    Color(0xFF3B6C94),
    Color(0xFFB6673C),
    Color(0xFF557C3E),
    Color(0xFF8A4E5D),
    Color(0xFF616161),
    Color(0xFF9E7C24),
    Color(0xFF7B5D43),
    Color(0xFF5C6B9F),
  ];

  Set<String> _sanitizeDraftSelectedCharacterCodes(StoryState state) {
    return _draftSelectedCharacterCodes
        .where(
          (code) => state.characters.any((character) => character.code == code),
        )
        .toSet();
  }

  Map<String, Color> _draftCharacterColors(StoryState state) {
    final selectedCodes = _sanitizeDraftSelectedCharacterCodes(state).toList();
    final next = <String, Color>{};
    for (var i = 0; i < selectedCodes.length; i++) {
      next[selectedCodes[i]] =
          _draftSelectionPalette[i % _draftSelectionPalette.length];
    }
    return next;
  }

  Color _colorForDraftCharacter(String characterCode, StoryState state) {
    return _draftCharacterColors(state)[characterCode] ??
        const Color(0xFF8E7B61);
  }

  bool _sameStringSet(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final item in a) {
      if (!b.contains(item)) {
        return false;
      }
    }
    return true;
  }

  bool _hasPendingCharacterSelectionChanges(StoryState state) {
    final sanitizedDraft = _sanitizeDraftSelectedCharacterCodes(state);
    return !_sameStringSet(sanitizedDraft, state.selectedCharacterCodes);
  }

  /// 인물 기반 기본 타임라인 — 선택된 인물 중 하나라도 등장하는 모든 사건을
  /// globalRank 오름차순으로 정렬해 반환. 정렬 로직의 single source of truth.
  List<StoryEvent> _timelineForSelectedCharacters(
    StoryState state,
    Set<String> selectedCharacterCodes,
  ) {
    final filtered = state.events.where((event) {
      return event.characterCodes.any(selectedCharacterCodes.contains);
    }).toList();

    filtered.sort((a, b) {
      final cmp = a.globalRank.compareTo(b.globalRank);
      if (cmp != 0) {
        return cmp;
      }
      return a.id.compareTo(b.id);
    });
    return filtered;
  }

  /// 지도에 넘길 타임라인: 커밋된 `state.displayedEventIds` 에 속한 사건만.
  /// 비어 있으면 빈 리스트 → 지도 핀/화살표가 완전히 사라진다.
  List<StoryEvent> _timelineForMap(
    StoryState state,
    List<StoryEvent> baseCharacterTimeline,
  ) {
    if (state.displayedEventIds.isEmpty) {
      return const <StoryEvent>[];
    }
    // v3 — region 모드에서는 인물 timeline 이 비어 있을 수 있어 base 를
    // state.events 전체로 둔다. character 모드는 timeline 이 채워져 있어 동일.
    return state.events
        .where((e) => state.displayedEventIds.contains(e.id))
        .toList(growable: false);
  }

  /// draft 집합에서 현재 사용 가능한 이벤트만 남긴다. 인물이 바뀌어 더 이상
  /// 후보에 없는 id 는 자동으로 빠진다.
  Set<String> _sanitizeDraftDisplayedEventIds(
    List<StoryEvent> availableEvents,
  ) {
    final valid = availableEvents.map((e) => e.id).toSet();
    return _draftDisplayedEventIds.intersection(valid);
  }

  bool _canOpenSelectionStep(int step, StoryState state) {
    if (step <= 1) {
      return true;
    }
    if (step == 2) {
      return state.selectedEraId != null;
    }
    return state.selectedCharacterCodes.isNotEmpty &&
        !_hasPendingCharacterSelectionChanges(state);
  }

  bool _isPhoneSheetLayoutForSize(Size size) => size.width < 720;

  double _sheetFractionForHeight(
    Size size,
    double height, {
    double min = 0.20,
    double max = _selectionSheetExpandedSize,
  }) {
    if (size.height <= 0) {
      return min;
    }
    return (height / size.height).clamp(min, max);
  }

  double _sheetMaxSizeFor(Size size) {
    final state = ref.read(storyControllerProvider);
    if (_isInRevealMode(state)) {
      return _sheetFractionForHeight(
        size,
        _selectionSheetCardOnlyHeight,
        min: 0.24,
        max: 0.38,
      );
    }
    // 인트로 패널 (시대 미선택 또는 모드 미선택) — 화면 비율이 아니라
    // 콘텐츠 예상 높이를 기준으로 잡아, 내용 아래에 큰 빈 양피지 영역이
    // 남지 않게 한다.
    if (_mode == null) {
      return _sheetFractionForHeight(
        size,
        _selectionSheetIntroHeight,
        min: 0.30,
        max: 0.44,
      );
    }
    if (_mode == _SelectionMode.region) {
      final selectedLandmarkId = state.selectedLandmarkId;
      if (selectedLandmarkId != null) {
        return _sheetFractionForHeight(
          size,
          _selectionSheetCardOnlyHeight,
          min: 0.24,
          max: 0.38,
        );
      }
      final eraCodes = state.eras
          .where((e) => state.selectedEraIds.contains(e.id))
          .map((e) => e.code)
          .toSet();
      final eventCounts = _regionEventCounts(state);
      final regionCount = state.landmarks
          .where(
            (lm) =>
                lm.isRegion &&
                (eventCounts[lm.id] ?? 0) > 0 &&
                (lm.eraCodes.isEmpty || lm.eraCodes.any(eraCodes.contains)),
          )
          .length;
      final rows = math.max(1, (regionCount / 2).ceil());
      final visibleRows = rows <= 3 ? rows.toDouble() : 3.2;
      final px = 132.0 + visibleRows * 122.0;
      return _sheetFractionForHeight(size, px, min: 0.26, max: 0.46);
    }
    // 인물 모드 step 2 — 인물 카드 줄 수에 맞춰 sheet 높이 동적 계산.
    // 카드 mainAxisExtent 108 + spacing 8 = 행당 ~116px. 1행/2행/2.2행.
    if (_mode == _SelectionMode.character && _selectionStep == 2) {
      final charCount = state.characters.length;
      final rowCount = (charCount / 4).ceil(); // 4 cols
      const rowPx = 116.0; // 카드 108 + spacing 8
      const chromePx = 110.0; // 핸들 + 헤더 + grid padding 등
      final visibleRows = rowCount <= 1
          ? 1.0
          : rowCount == 2
          ? 2.0
          : 2.2;
      final px = chromePx + visibleRows * rowPx;
      // viewport 높이 대비 비율 — 안전한 범위로 clamp.
      return _sheetFractionForHeight(size, px, min: 0.28, max: 0.48);
    }
    return _sheetFractionForHeight(
      size,
      _selectionSheetCardOnlyHeight,
      min: 0.24,
      max: 0.42,
    );
  }

  double _sheetCollapsedPeekSizeFor(Size size) => _selectionSheetCollapsedSize;

  double _sheetSizeForStage(Size size, StorySelectionPanelStage stage) {
    return switch (stage) {
      StorySelectionPanelStage.collapsed => _sheetCollapsedPeekSizeFor(size),
      StorySelectionPanelStage.half => _sheetMaxSizeFor(size),
      StorySelectionPanelStage.expanded => _sheetMaxSizeFor(size),
    };
  }

  Future<void> _handleStepEraSelect(String eraId) async {
    final controller = ref.read(storyControllerProvider.notifier);
    await controller.selectEra(eraId);
    if (!mounted) {
      return;
    }
    final nextState = ref.read(storyControllerProvider);
    setState(() {
      _selectionStep = 1;
      _draftSelectedCharacterCodes = nextState.selectedCharacterCodes.toSet();
    });
  }

  Future<void> _handleStepTestamentSelect(String testament) async {
    final controller = ref.read(storyControllerProvider.notifier);
    await controller.selectTestament(testament);
    if (!mounted) {
      return;
    }
    final nextState = ref.read(storyControllerProvider);
    setState(() {
      _selectionStep = 1;
      _draftSelectedCharacterCodes = nextState.selectedCharacterCodes.toSet();
    });
  }

  void _toggleDraftCharacter(String characterId) {
    final next = {..._draftSelectedCharacterCodes};
    if (next.contains(characterId)) {
      next.remove(characterId);
    } else {
      next.add(characterId);
    }
    setState(() {
      _draftSelectedCharacterCodes = next;
    });
    // controller state 도 같이 업데이트해 step 2 에서도 인물별 path 미리보기가
    // 즉시 반영되게 한다. step 3 진입은 '다음' 버튼 (_proceedFromCharacterStep).
    ref.read(storyControllerProvider.notifier).setSelectedCharacters(next);
  }

  /// 현재 단계/모드에 어울리는 지도 안내 문구. null 이면 hint 미표시.
  /// 사용자가 dismiss (지도 제스처/region 선택 등) 했으면 null.
  ({String message, IconData icon})? _currentMapHint() {
    if (_mapHintDismissed) return null;
    if (_mode == _SelectionMode.region) {
      final state = ref.read(storyControllerProvider);
      if (state.selectedLandmarkId == null) {
        return (
          message: '노란 지역을 눌러 그곳의 사건을 보세요.\n손가락 동작으로 지도를 확대·축소할 수 있어요.',
          icon: Icons.touch_app_rounded,
        );
      }
      return null;
    }
    if (_mode == _SelectionMode.character && _selectionStep == 2) {
      return (
        message: '아래 패널에서 인물을 한 명 이상 고른 뒤\n좌측 상단의 「다음」 버튼을 눌러주세요.',
        icon: Icons.people_alt_rounded,
      );
    }
    return null;
  }

  /// 사용자가 지도를 만지면(드래그/줌/탭 등) hint dismiss. _mapHintDismissed=true
  /// 로 다음 단계 진입 전까지 hint 가 다시 안 뜬다.
  void _handleMapInteraction() {
    if (_mapHintDismissed) return;
    setState(() {
      _mapHintDismissed = true;
    });
  }

  /// 새 단계로 들어갔거나 mode 가 바뀌었을 때 hint 를 다시 보여 줄 수 있도록
  /// dismiss flag 를 reset. setState 안에서 호출해야 build 에 반영된다.
  void _resetMapHint() {
    _mapHintDismissed = false;
  }

  void _animateSelectionPanelToStage(StorySelectionPanelStage stage) {
    final viewportSize = MediaQuery.sizeOf(context);
    final maxExtent = _sheetMaxSizeFor(viewportSize);
    final targetExtent = stage == StorySelectionPanelStage.collapsed
        ? _selectionSheetCollapsedSize
        : maxExtent;
    setState(() {
      _selectionPanelStage = stage;
      _selectionSheetExtent = targetExtent;
      // 사용자가 핀 reveal 도중 수동으로 expand 했다면 stagger 를 건너뛰고
      // 즉시 모든 핀을 보여 준다. (StoryMapPanel.revealInstantly).
      if (_awaitingRevealComplete &&
          stage != StorySelectionPanelStage.collapsed) {
        _revealInstantly = true;
        _awaitingRevealComplete = false;
      }
    });
  }

  /// MapPanel 이 마지막 핀을 노출 완료했을 때 1회 호출. await 중이었다면
  /// panel 을 다시 expand 시켜 사건 카드 리스트를 노출. (수동 expand 로
  /// 이미 _awaitingRevealComplete=false 면 noop.)
  void _handleRevealComplete() {
    if (!_awaitingRevealComplete) return;
    final expandExtent = _sheetMaxSizeFor(MediaQuery.sizeOf(context));
    setState(() {
      _awaitingRevealComplete = false;
      _selectionPanelStage = StorySelectionPanelStage.expanded;
      _selectionSheetExtent = expandExtent;
    });
  }

  void _collapseSelectionPanel() {
    _animateSelectionPanelToStage(StorySelectionPanelStage.collapsed);
  }

  void _expandSelectionPanelFully() {
    _animateSelectionPanelToStage(StorySelectionPanelStage.expanded);
  }

  void _stepSelectionPanelUp() {
    switch (_selectionPanelStage) {
      case StorySelectionPanelStage.collapsed:
      case StorySelectionPanelStage.half:
        _expandSelectionPanelFully();
        return;
      case StorySelectionPanelStage.expanded:
        return;
    }
  }

  void _stepSelectionPanelDown() {
    switch (_selectionPanelStage) {
      case StorySelectionPanelStage.expanded:
      case StorySelectionPanelStage.half:
        _collapseSelectionPanel();
        return;
      case StorySelectionPanelStage.collapsed:
        return;
    }
  }

  void _goToSelectionStep(int step) {
    final state = ref.read(storyControllerProvider);
    if (!_canOpenSelectionStep(step, state)) {
      return;
    }
    setState(() {
      if (step == 2) {
        final sanitizedDraft = _sanitizeDraftSelectedCharacterCodes(state);
        _draftSelectedCharacterCodes = _selectionStep == 3
            ? state.selectedCharacterCodes.toSet()
            : sanitizedDraft;
      }
      // step 1 (시대 선택) 으로 돌아가면 시대+모드 카드 통합 인트로 화면이
      // 다시 떠야 한다. _mode 도 null 로 reset.
      if (step == 1) {
        _mode = null;
        ref.read(storyControllerProvider.notifier).clearSelectionMode();
      }
      // step 3 을 떠나는 시점에 reveal 관련 플래그 정리 — 다음번 step 3
      // 진입 시 처음부터 stagger reveal 이 되도록. step 3 직후 panel 이
      // collapsed 였다면 step 2 로 돌아갈 때 다시 펼쳐 인물 선택을 보여 줌.
      if (step != 3) {
        _awaitingRevealComplete = false;
        _revealInstantly = false;
        if (_selectionStep == 3 &&
            _selectionPanelStage == StorySelectionPanelStage.collapsed) {
          _selectionPanelStage = StorySelectionPanelStage.expanded;
          _selectionSheetExtent = _selectionSheetExpandedSize;
        }
      }
      _selectionStep = step;
    });
  }

  void _proceedFromEraStep() {
    final state = ref.read(storyControllerProvider);
    if (state.selectedEraId == null) {
      return;
    }
    setState(() {
      _draftSelectedCharacterCodes = state.selectedCharacterCodes.toSet();
      _selectionStep = 2;
    });
  }

  /// SelectionStepper 의 동그라미를 누른 처리.
  /// - 미래 step (current 보다 큼): 무시 (눌리지 않음).
  /// - 현재 step: 그 단계 진행 내역 초기화.
  /// - 이전 step: 그 단계로 돌아가며 그 단계 이후 모든 선택 초기화.
  void _handleStepperTap(int step) {
    final ctl = ref.read(storyControllerProvider.notifier);
    final current = _currentStepperIndex();
    if (step > current) return; // 미래 단계 비활성

    if (step == 1) {
      // 시대 + 모드 + 모든 하위 선택 초기화 → 인트로 화면 복귀.
      ctl.setSelectedEra(null);
      ctl.clearSelectionMode();
      ctl.selectLandmark(null);
      ctl.setDisplayedEvents(const <String>{});
      setState(() {
        _mode = null;
        _selectionStep = 1;
        _draftSelectedCharacterCodes = const <String>{};
        // intro 화면은 자체 안내가 충분하므로 hint overlay 는 dismiss.
        _mapHintDismissed = true;
      });
      _animateSelectionPanelToStage(StorySelectionPanelStage.expanded);
      return;
    }

    if (step == 2) {
      // 장소/인물 선택 + 사건 선택 초기화. 시대 + 모드는 유지.
      ctl.selectLandmark(null);
      ctl.setSelectedCharacters(const <String>{});
      ctl.setDisplayedEvents(const <String>{});
      setState(() {
        _selectionStep = 2;
        _draftSelectedCharacterCodes = const <String>{};
        // 새 단계 시작 — hint overlay 다시 보여줌.
        _resetMapHint();
      });
      // region 모드는 사용자가 지도에서 폴리곤/핀을 직접 누르는 단계 — 패널은
      // 최소화해 지도가 보이게. character 모드는 인물 카드를 골라야 하니 expand.
      _animateSelectionPanelToStage(
        _mode == _SelectionMode.region
            ? StorySelectionPanelStage.collapsed
            : StorySelectionPanelStage.expanded,
      );
      // region 모드면 그 시대 모든 region 한눈에 보이게 카메라 fit.
      if (_mode == _SelectionMode.region) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusOnEraRegions(ref.read(storyControllerProvider));
        });
      }
      return;
    }

    if (step == 3) {
      // 사건 선택 초기화 (현재 단계 진행 내역 reset).
      ctl.setDisplayedEvents(const <String>{});
      setState(() {
        _selectionStep = 3;
      });
      return;
    }
  }

  /// stepper 의 현재 step 결정.
  /// - 시대 미선택/모드 미선택 → 1
  /// - region 모드 + region 미선택 → 2
  /// - region 모드 + region 선택 → 3
  /// - character 모드: 명시적으로 사용자가 "다음" 을 눌러 [_selectionStep] 이
  ///   3 으로 올라가야 step 3. 단순히 인물을 골랐다고 자동 step 3 X.
  int _currentStepperIndex() {
    final state = ref.read(storyControllerProvider);
    if (state.selectedEraId == null || _mode == null) return 1;
    if (_mode == _SelectionMode.region) {
      return state.selectedLandmarkId == null ? 2 : 3;
    }
    // character 모드 — _selectionStep 이 3 일 때만 3, 그 외(2,1) 는 2.
    return _selectionStep >= 3 ? 3 : 2;
  }

  /// 핀 reveal 모드 판정. region 모드에서 landmark 가 선택됐거나, character
  /// 모드에서 step 3 진입 후 displayedEventIds 가 set 된 상태.
  bool _isInRevealMode(StoryState state) {
    if (_mode == _SelectionMode.region && state.selectedLandmarkId != null) {
      return true;
    }
    if (_mode == _SelectionMode.character &&
        _selectionStep == 3 &&
        state.displayedEventIds.isNotEmpty) {
      return true;
    }
    return false;
  }

  /// 장소 모드에서 region 선택 (지도 폴리곤·핀 클릭 OR RegionPickPanel 카드 클릭)
  /// 시 호출. 인물 모드의 _proceedFromCharacterStep 과 같은 패턴 — panel 을
  /// collapsed 로 내리고, MapPanel 이 핀을 0.3s 간격 reveal, 마지막 핀 노출 시
  /// onRevealComplete 가 panel 을 다시 expand.
  ///
  /// 사용자가 reveal 도중 ^ 클릭으로 수동 expand 하면 _animateSelectionPanelToStage
  /// 안에서 _revealInstantly=true 로 바뀌어 즉시 모든 핀 노출.
  void _selectRegionLandmark(Landmark lm) {
    final ctl = ref.read(storyControllerProvider.notifier);
    ctl.selectLandmark(lm.id);
    final state = ref.read(storyControllerProvider);
    final regionEvents = _eventsAtLandmark(state, lm)
      ..sort((a, b) => a.globalRank.compareTo(b.globalRank));
    ctl.setDisplayedEvents(regionEvents.map((e) => e.id).toSet());
    setState(() {
      _selectionPanelStage = StorySelectionPanelStage.collapsed;
      _selectionSheetExtent = _selectionSheetCollapsedSize;
      _awaitingRevealComplete = true;
      _revealInstantly = false;
      // region 선택 완료 — hint overlay 사라짐.
      _mapHintDismissed = true;
    });
    // 사건들이 분포한 영역에 fit + 줌인. region 폴리곤 fit 보다 사건 자체에
    // 포커스가 맞아 자세히 보임.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapPanelController.focusEvents(zoomBoost: 1.0);
    });
  }

  void _proceedFromCharacterStep() {
    final state = ref.read(storyControllerProvider);
    final sanitizedDraft = _sanitizeDraftSelectedCharacterCodes(state);
    if (sanitizedDraft.isEmpty) {
      return;
    }
    final ctl = ref.read(storyControllerProvider.notifier);
    ctl.setSelectedCharacters(sanitizedDraft);
    // step 3 진입 — 선택 인물들의 모든 사건을 시간순으로 displayedEventIds 에
    // set. 지도 핀이 0.3초 간격 reveal (StoryMapPanel 의 _eventRevealTimer).
    final timeline = _timelineForSelectedCharacters(state, sanitizedDraft);
    ctl.setDisplayedEvents(timeline.map((e) => e.id).toSet());
    setState(() {
      _draftSelectedCharacterCodes = sanitizedDraft;
      _draftDisplayedEventIds = timeline.map((e) => e.id).toSet();
      _selectionStep = 3;
      // panel 을 collapsed 로 내려 사용자가 핀이 박히는 걸 한눈에 보게 한다.
      // 마지막 핀 reveal 완료 시 onRevealComplete 가 panel 을 다시 expand.
      _selectionPanelStage = StorySelectionPanelStage.collapsed;
      _selectionSheetExtent = _selectionSheetCollapsedSize;
      _awaitingRevealComplete = true;
      _revealInstantly = false;
      // character step 3 진입 — 인물 선택 안내 hint 사라짐.
      _mapHintDismissed = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapPanelController.focusEvents(zoomBoost: 1.0);
    });
  }

  void _toggleDraftDisplayedEvent(String eventId) {
    final next = {..._draftDisplayedEventIds};
    if (next.contains(eventId)) {
      next.remove(eventId);
    } else {
      next.add(eventId);
    }
    setState(() {
      _draftDisplayedEventIds = next;
    });
    // step 3 사건 토글 시 "다음" 누르기 전이라도 즉시 지도에 핀이 박히도록
    // controller state 도 같이 업데이트. step 2 인물 토글과 같은 패턴.
    ref.read(storyControllerProvider.notifier).setDisplayedEvents(next);
  }

  void _selectAllDraftDisplayedEvents(List<StoryEvent> availableEvents) {
    final next = availableEvents.map((e) => e.id).toSet();
    setState(() {
      _draftDisplayedEventIds = next;
    });
    ref.read(storyControllerProvider.notifier).setDisplayedEvents(next);
  }

  void _deselectAllDraftDisplayedEvents() {
    setState(() {
      _draftDisplayedEventIds = <String>{};
    });
    ref
        .read(storyControllerProvider.notifier)
        .setDisplayedEvents(const <String>{});
  }

  /// Step 3 "다음" 버튼 핸들러 — draft 를 커밋해 지도 핀 reveal 애니메이션 트리거.
  /// 커밋 후 선택 패널을 최소화하여 지도를 드러낸다.
  void _proceedFromStoryStep() {
    final state = ref.read(storyControllerProvider);
    final characterTimeline = _timelineForSelectedCharacters(
      state,
      state.selectedCharacterCodes,
    );
    final sanitized = _sanitizeDraftDisplayedEventIds(characterTimeline);
    if (sanitized.isEmpty) {
      return;
    }
    ref.read(storyControllerProvider.notifier).setDisplayedEvents(sanitized);
    final viewportSize = MediaQuery.sizeOf(context);
    final collapsedExtent = _sheetSizeForStage(
      viewportSize,
      StorySelectionPanelStage.collapsed,
    );
    setState(() {
      _draftDisplayedEventIds = sanitized;
      _selectionPanelStage = StorySelectionPanelStage.collapsed;
      _selectionSheetExtent = collapsedExtent;
    });
    // step 3 toggle 단계에서는 핀이 즉시 노출돼 있다. "다음" 을 누르면 사용자가
    // 명시적으로 마무리한 시점이므로, 핀들이 시간 순서대로 하나씩 pop-in 되는
    // reveal 애니메이션을 한 번 더 재생해 시간 흐름을 강조한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapPanelController.replayReveal();
    });
  }

  Future<void> _openWeeklyTab() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizTabPage(
          onStartQuiz: _startQuiz,
          onOpenEventDetail: _openEventDetailPage,
        ),
      ),
    );
  }

  /// 웹 한정 "이야기 등록" 탭 핸들러.
  /// - 비로그인: 안내 스낵바 → 프로필 탭으로 이동 (그쪽에 로그인 UI 있음)
  /// - 로그인 + is_pastor=false: PastorGateDialog (메일 안내)
  /// - 로그인 + is_pastor=true OR admin: ProposalBoardScreen 진입
  Future<void> _openProposalBoardOrGate() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 로그인해주세요 (프로필 탭에서 로그인)')));
      await _openProfileTab();
      return;
    }
    final isAdmin = ref.read(isAdminProvider);
    final isPastor = await ref.read(isPastorProvider.future);
    if (!mounted) return;
    if (!isPastor && !isAdmin) {
      await PastorGateDialog.show(context);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProposalBoardScreen()),
    );
  }

  Future<void> _openProfileTab() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileTabPage(
          key: _profileTabKey,
          onStartQuiz: _startQuiz,
          onOpenEventDetail: _openEventDetailPage,
          onOpenBibleReader:
              ({
                int? initialBookNo,
                int? initialChapterNo,
                int? initialVerseNo,
              }) => _openBibleReaderPopup(
                initialBookNo: initialBookNo,
                initialChapterNo: initialChapterNo,
                initialVerseNo: initialVerseNo,
              ),
        ),
      ),
    );
  }

  void _handleEventSelect(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    controller.selectEvent(event.id);
    // 지도에 이 사건이 아직 커밋 표시되지 않았다면 displayedEventIds + draft
    // 모두에 추가해 지도에 핀이 뜨도록.
    if (!state.displayedEventIds.contains(event.id)) {
      final nextCommitted = {...state.displayedEventIds, event.id};
      controller.setDisplayedEvents(nextCommitted);
      _draftDisplayedEventIds = {..._draftDisplayedEventIds, event.id};
    }
    setState(() {
      _selectionStep = 3;
      _draftSelectedCharacterCodes = state.selectedCharacterCodes.toSet();
    });
    // 핀 클릭 시 panel 을 카드 사이즈로 올려 선택된 이야기가 보이도록.
    // _animateSelectionPanelToStage 가 _isInRevealMode 분기로 카드/expanded 자동 결정.
    _animateSelectionPanelToStage(StorySelectionPanelStage.expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _mapPanelController.focusSelectedEvent(force: true);
    });
  }

  void _openEventDetail(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    controller.selectEvent(event.id);
    setState(() {
      _selectionStep = 3;
      _draftSelectedCharacterCodes = state.selectedCharacterCodes.toSet();
    });
    _openEventDetailPage(event);
  }

  void _closeSelectedEventPopup() {
    ref.read(storyControllerProvider.notifier).selectEvent(null);
  }

  /// 거리 측정 결과를 한국 거리 비교와 함께 SnackBar 로 보여 준다.
  void _showMeasureResult(MeasureResult result) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF3D2A14),
        duration: const Duration(seconds: 5),
        content: Text(
          '${result.fromName} → ${result.toName}\n'
          '직선 거리 약 ${result.kilometers.toStringAsFixed(1)}km '
          '(${result.koreanComparison})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  /// 랜드마크 마커가 탭됐을 때 간단한 정보 다이얼로그를 띄운다.
  /// 이모지 + 이름 + 설명 + 카테고리/시대 칩.
  void _showLandmarkPopup(Landmark landmark) {
    // 지도 포커스를 그 랜드마크로 이동 (설명 팝업과 함께).
    _mapPanelController.focusLandmark(landmark.latLng);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (ctx) => _LandmarkScrollDialog(
        landmark: landmark,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// 지도 출처/라이선스 dialog — Stamen Watercolor (CC BY 4.0) + OpenStreetMap
  /// (ODbL) + Cooper Hewitt(Smithsonian) archive + Natural Earth. CC BY 4.0
  /// 과 ODbL 모두 attribution 의무이므로 사용자 view 에 노출되어야 한다.
  void _showMapAttributionDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '지도 출처',
        subtitle: '본 지도는 다음 오픈 데이터/타일을 사용합니다.',
        showCloseButton: true,
        onClose: () => Navigator.of(dialogContext).pop(),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AttributionLine(
              source: 'Stamen Watercolor 타일',
              license: 'CC BY 4.0',
            ),
            SizedBox(height: 8),
            _AttributionLine(source: 'OpenStreetMap 데이터', license: 'ODbL'),
            SizedBox(height: 8),
            _AttributionLine(
              source: '아카이브 호스팅: Cooper Hewitt, Smithsonian Design Museum',
            ),
            SizedBox(height: 8),
            _AttributionLine(
              source: '국경/수계 보조: Natural Earth',
              license: 'Public Domain',
            ),
          ],
        ),
      ),
    );
  }

  /// region(영역) 마커 옆에 표시할 사건 개수 — 그 region + 자식 마커들의
  /// landmark_id 를 가진 events 합산. region kind 만 key 로 둔다.
  Map<String, int> _regionEventCounts(StoryState state) {
    final counts = <String, int>{};
    for (final region in state.landmarks) {
      if (!region.isRegion) continue;
      final ids = <String>{region.id};
      for (final child in state.landmarks) {
        if (child.parentLandmarkId == region.id) ids.add(child.id);
      }
      var n = 0;
      for (final e in state.events) {
        if (ids.contains(e.landmarkId)) n++;
      }
      if (n > 0) counts[region.id] = n;
    }
    return counts;
  }

  List<Landmark> _activeLandmarksForEra(StoryState state) {
    // 멀티 시대 지원 — selectedEraIds 의 모든 시대에 매칭되는 landmark 합집합.
    if (state.selectedEraIds.isEmpty) {
      return const [];
    }
    final eraCodes = state.eras
        .where((era) => state.selectedEraIds.contains(era.id))
        .map((era) => era.code)
        .toSet();
    if (eraCodes.isEmpty) {
      return const [];
    }
    // 시대만 선택한 상태(mode 미정) 에서는 landmark 마커를 모두 숨기고 시대
    // 폴리곤(region union)만 표시 — 사용자가 [장소에서 시작하기] 를 고르면
    // landmark 가 등장.
    if (_mode == null) {
      return const [];
    }
    final categories = state.selectedLandmarkCategories;
    // 카테고리 필터 — non-region 에 적용. region 은 항상 통과 (폴리곤 라벨용).
    bool passesCategory(Landmark l) {
      if (categories.isEmpty || l.isRegion) return true;
      final cat = (l.category != null && l.category!.isNotEmpty)
          ? l.category!
          : l.kind;
      return categories.contains(cat);
    }

    // 지역 모드 + region 미선택: 그 시대 region 핀 + 그 region 들의 모든 자식
    // landmark 까지 한꺼번에 표시. 사용자가 폴리곤을 누르면 그 region 으로
    // zoom 되며 다른 region 마커들은 가려진다.
    if (_mode == _SelectionMode.region && state.selectedLandmarkId == null) {
      return state.landmarks
          .where((l) => l.eraCodes.any(eraCodes.contains) && passesCategory(l))
          .toList(growable: false);
    }
    // 특정 region 을 누른 뒤(step 3): 선택한 region + 그 region 의 자식 +
    // 시대 전체의 다른 non-region 랜드마크도 함께 노출 (카테고리 필터 적용).
    // 선택 region 이외의 region 마커는 가린다 (선택 region 만 강조).
    if (_mode == _SelectionMode.region && state.selectedLandmarkId != null) {
      final id = state.selectedLandmarkId!;
      return state.landmarks
          .where((l) {
            if (!l.eraCodes.any(eraCodes.contains)) return false;
            // 선택 region 본인 + 그 자식: 무조건 노출 (카테고리만 통과시키면 됨).
            if (l.id == id || l.parentLandmarkId == id) {
              return passesCategory(l);
            }
            // 그 외 region 마커는 숨김 (선택 region 만 큰 핀으로 강조).
            if (l.isRegion) return false;
            // 시대 전체의 다른 non-region 랜드마크: 카테고리 필터 적용.
            return passesCategory(l);
          })
          .toList(growable: false);
    }
    // 인물 모드: 그 시대의 모든 non-region landmark.
    return state.landmarks
        .where((l) {
          if (l.isRegion) return false;
          if (!l.eraCodes.any(eraCodes.contains)) return false;
          if (categories.isEmpty) return true;
          // v3 — category 컬럼은 옛 v1 잔존. 새 데이터는 kind 가 카테고리.
          final cat = (l.category != null && l.category!.isNotEmpty)
              ? l.category!
              : l.kind;
          return categories.contains(cat);
        })
        .toList(growable: false);
  }

  /// 시대 영역 폴리곤(=region polygon union) 입력. 선택된 시대(단일)의
  /// region 종류 landmark 를 반환 — 인물 모드에서도 시대 영역은 그대로 유지.
  List<Landmark> _eraRegionLandmarks(StoryState state) {
    if (state.selectedEraId == null) return const [];
    final selectedEra = state.eras
        .where((e) => e.id == state.selectedEraId)
        .firstOrNull;
    if (selectedEra == null) return const [];
    final eraCode = selectedEra.code;
    return state.landmarks
        .where(
          (l) =>
              l.isRegion &&
              l.polygon.isNotEmpty &&
              l.eraCodes.contains(eraCode),
        )
        .toList(growable: false);
  }

  Future<void> _openEventDetailPage(
    StoryEvent event, {
    String? quizWeekKey,
  }) async {
    // 하이브리드 로딩: 로컬 assets 가 있으면 그걸로, 없으면
    // events.scene_image_paths 를 Supabase Storage public URL 로 변환해 반환.
    final client = ref.read(supabaseClientProvider);
    final sceneAssetsFuture = _sceneAssetLoader.loadForEvent(
      event,
      publicUrlFor: (storagePath) {
        final slash = storagePath.indexOf('/');
        if (slash < 0) return storagePath;
        final bucket = storagePath.substring(0, slash);
        final path = storagePath.substring(slash + 1);
        return client.storage.from(bucket).getPublicUrl(path);
      },
    );
    if (!mounted) {
      return;
    }
    // prev/next 결정 — 현재 region/character 모드의 사건 시퀀스에서.
    final state = ref.read(storyControllerProvider);
    final sequence = _eventSequenceForDetail(state);
    final currentIndex = sequence.indexWhere((e) => e.id == event.id);
    final prev = (currentIndex > 0) ? sequence[currentIndex - 1] : null;
    final next = (currentIndex >= 0 && currentIndex < sequence.length - 1)
        ? sequence[currentIndex + 1]
        : null;

    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailPage(
          event: event,
          quizWeekKey: quizWeekKey,
          sceneAssetsFuture: sceneAssetsFuture,
          onOpenBibleReader: (target) async {
            if (!mounted) {
              return;
            }
            await _openBibleReaderPopup(
              initialBookNo: target.bookNo,
              initialChapterNo: target.chapterNo,
              initialVerseNo: target.verseNo,
              highlightTarget: target,
            );
            // 사용자가 본문을 보고 돌아왔으면 '읽기' 완료 처리. 퀴즈 모드면
            // 별도 weekly_quiz_progress 에 저장 (프로필 진행도 영향 X).
            if (!mounted) return;
            final notifier = ref.read(storyControllerProvider.notifier);
            if (quizWeekKey != null) {
              await notifier.setWeeklyQuizBibleRead(
                weekKey: quizWeekKey,
                eventId: event.id,
                isRead: true,
              );
            } else {
              await notifier.setBibleRead(eventId: event.id, isRead: true);
            }
          },
          onStartQuiz: (eventId) =>
              _startQuiz(eventId, quizWeekKey: quizWeekKey, event: event),
          onEmotionEngraved: (event, option) => _showEmotionCelebrationOnMap(
            event: event,
            option: option,
            quizWeekKey: quizWeekKey,
          ),
          prevEvent: prev,
          nextEvent: next,
          onNavigateToEvent: (target) {
            unawaited(
              _navigateDetailThroughMap(
                from: event,
                target: target,
                quizWeekKey: quizWeekKey,
              ),
            );
          },
        ),
      ),
    );
  }

  /// prev/next 시퀀스 — 현재 활성 모드(인물/지역) 의 사건 카드 순서를 그대로 따름.
  /// region 모드 + region 선택: 그 region 의 사건 globalRank 순.
  /// character 모드: 인물 timeline 순.
  /// 그 외(혹은 빈 상태): state.events 전체 globalRank 순.
  List<StoryEvent> _eventSequenceForDetail(StoryState state) {
    if (_mode == _SelectionMode.region && state.selectedLandmarkId != null) {
      final lm = state.landmarkById(state.selectedLandmarkId!);
      if (lm != null) {
        final list = _eventsAtLandmark(state, lm);
        list.sort((a, b) => a.globalRank.compareTo(b.globalRank));
        return list;
      }
    }
    if (_mode == _SelectionMode.character &&
        state.selectedCharacterCodes.isNotEmpty) {
      return _timelineForSelectedCharacters(
        state,
        state.selectedCharacterCodes,
      );
    }
    final all = [...state.events]
      ..sort((a, b) => a.globalRank.compareTo(b.globalRank));
    return all;
  }

  /// pushReplacement 시 동일 detail page 빌드 — 새 prev/next 도 다시 계산.
  /// quizWeekKey 가 있으면 prev/next 이동 후에도 퀴즈 모드 유지.
  Widget _buildDetailPageForEvent(StoryEvent event, {String? quizWeekKey}) {
    final client = ref.read(supabaseClientProvider);
    final sceneAssetsFuture = _sceneAssetLoader.loadForEvent(
      event,
      publicUrlFor: (storagePath) {
        final slash = storagePath.indexOf('/');
        if (slash < 0) return storagePath;
        final bucket = storagePath.substring(0, slash);
        final path = storagePath.substring(slash + 1);
        return client.storage.from(bucket).getPublicUrl(path);
      },
    );
    final state = ref.read(storyControllerProvider);
    final sequence = _eventSequenceForDetail(state);
    final currentIndex = sequence.indexWhere((e) => e.id == event.id);
    final prev = (currentIndex > 0) ? sequence[currentIndex - 1] : null;
    final next = (currentIndex >= 0 && currentIndex < sequence.length - 1)
        ? sequence[currentIndex + 1]
        : null;
    return EventDetailPage(
      event: event,
      quizWeekKey: quizWeekKey,
      sceneAssetsFuture: sceneAssetsFuture,
      onOpenBibleReader: (target) async {
        if (!mounted) return;
        await _openBibleReaderPopup(
          initialBookNo: target.bookNo,
          initialChapterNo: target.chapterNo,
          initialVerseNo: target.verseNo,
          highlightTarget: target,
        );
        if (!mounted) return;
        // 본문 읽기 완료 처리 — quiz 모드면 weekly 진행도, 아니면 일반.
        final notifier = ref.read(storyControllerProvider.notifier);
        if (quizWeekKey != null) {
          await notifier.setWeeklyQuizBibleRead(
            weekKey: quizWeekKey,
            eventId: event.id,
            isRead: true,
          );
        } else {
          await notifier.setBibleRead(eventId: event.id, isRead: true);
        }
      },
      onStartQuiz: (eventId) =>
          _startQuiz(eventId, quizWeekKey: quizWeekKey, event: event),
      onEmotionEngraved: (event, option) => _showEmotionCelebrationOnMap(
        event: event,
        option: option,
        quizWeekKey: quizWeekKey,
      ),
      prevEvent: prev,
      nextEvent: next,
      onNavigateToEvent: (target) {
        unawaited(
          _navigateDetailThroughMap(
            from: event,
            target: target,
            quizWeekKey: quizWeekKey,
          ),
        );
      },
    );
  }

  Future<void> _showEmotionCelebrationOnMap({
    required StoryEvent event,
    required EventEmotionOption option,
    String? quizWeekKey,
  }) async {
    if (!mounted || _mapAnimationInputLocked) return;
    _setMapAnimationInputLocked(true);
    try {
      _completeMapCelebration();
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
      if (!mounted) return;

      final notifier = ref.read(storyControllerProvider.notifier);
      final state = ref.read(storyControllerProvider);
      notifier.selectEvent(event.id);
      if (!state.displayedEventIds.contains(event.id)) {
        notifier.setDisplayedEvents({...state.displayedEventIds, event.id});
      }

      setState(() {
        _draftDisplayedEventIds = {..._draftDisplayedEventIds, event.id};
        _selectionStep = 3;
        _selectionPanelStage = StorySelectionPanelStage.expanded;
        _selectionSheetExtent = _sheetMaxSizeFor(MediaQuery.sizeOf(context));
        _mapHintDismissed = true;
        _mapCelebrationEventId = null;
        _mapCelebrationStampLabel = null;
      });

      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(_emotionMapPreStampDelay);
      if (!mounted) return;

      final celebrationCompleter = Completer<void>();
      _mapCelebrationCompleter = celebrationCompleter;
      setState(() {
        _mapCelebrationEventId = event.id;
        _mapCelebrationStampLabel = option.emoji;
        _mapCelebrationNonce += 1;
      });

      await WidgetsBinding.instance.endOfFrame;
      await Future.any<void>([
        celebrationCompleter.future,
        Future<void>.delayed(
          CompletionCelebration.stampDuration + _emotionMapStampFallbackSlack,
        ),
      ]);
      if (_mapCelebrationCompleter == celebrationCompleter) {
        _mapCelebrationCompleter = null;
      }
      if (!mounted) return;

      await Future<void>.delayed(_emotionMapPostStampDelay);
      if (!mounted) return;

      _setMapAnimationInputLocked(false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _buildDetailPageForEvent(event, quizWeekKey: quizWeekKey),
        ),
      );
    } finally {
      _setMapAnimationInputLocked(false);
    }
  }

  Future<void> _navigateDetailThroughMap({
    required StoryEvent from,
    required StoryEvent target,
    String? quizWeekKey,
  }) async {
    if (!mounted || _mapAnimationInputLocked) return;
    _setMapAnimationInputLocked(true);
    try {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (!mounted) return;

      final notifier = ref.read(storyControllerProvider.notifier);
      final state = ref.read(storyControllerProvider);
      final nextDisplayed = {...state.displayedEventIds, from.id, target.id};
      notifier.setDisplayedEvents(nextDisplayed);
      if (state.selectedEventId != from.id) {
        notifier.selectEvent(from.id);
      }
      setState(() {
        _draftDisplayedEventIds = {
          ..._draftDisplayedEventIds,
          from.id,
          target.id,
        };
        _selectionPanelStage = StorySelectionPanelStage.collapsed;
        _selectionSheetExtent = _sheetSizeForStage(
          MediaQuery.sizeOf(context),
          StorySelectionPanelStage.collapsed,
        );
        _mapHintDismissed = true;
      });

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      await _mapPanelController.playEventTransition(from: from, to: target);
      if (!mounted) return;

      notifier.selectEvent(target.id);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      _setMapAnimationInputLocked(false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _buildDetailPageForEvent(target, quizWeekKey: quizWeekKey),
        ),
      );
    } finally {
      _setMapAnimationInputLocked(false);
    }
  }

  Future<void> _openBibleReaderPopup({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
    BibleNavigationTarget? highlightTarget,
  }) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleReaderPage(
          initialBookNo: initialBookNo,
          initialChapterNo: initialChapterNo,
          initialVerseNo: initialVerseNo,
          highlightTarget: highlightTarget,
        ),
      ),
    );
  }

  /// 알림 탭 처리 — 읽음 처리 + 딥링크 라우팅.
  /// 제안 관련 알림인데 모바일/태블릿이면 "컴퓨터로 확인하세요" 다이얼로그 후
  /// 화면 전환은 하지 않는다(편집이 웹 전용).
  Future<void> _handleNotificationTap(AppNotification notification) async {
    // 1) 읽음 처리 + 상태 무효화.
    final repo = ref.read(notificationRepositoryProvider);
    try {
      await repo.markRead(notification);
    } catch (_) {
      // 읽음 실패는 무시 (다음 refresh 에 반영됨)
    }
    ref.invalidate(unreadNotificationsProvider);
    ref.invalidate(notificationHistoryProvider);

    if (!mounted) return;

    // 2) 모바일/태블릿 + 제안 알림 → 다이얼로그만 띄우고 종료.
    final proceed = await shouldProceedWithNavigation(context, notification);
    if (!proceed || !mounted) return;

    // 3) deep_link 파싱 후 화면 전환.
    final link = NotificationDeepLink.parse(notification.deepLink);
    switch (link.target) {
      case NotificationTarget.proposal:
        if (link.id != null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProposalDetailScreen(proposalId: link.id!),
            ),
          );
        }
        break;
      case NotificationTarget.event:
        if (link.id != null) {
          _openEventDetail(link.id!);
        }
        break;
      case NotificationTarget.weekly:
        await _openWeeklyTab();
        break;
      case NotificationTarget.unknown:
        break;
    }
  }

  Future<void> _openNotificationHistory() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NotificationHistoryScreen(onNavigate: _handleNotificationTap),
      ),
    );
  }

  String _eraTestament(Era era) {
    final raw = era.testament.trim().toLowerCase();
    if (raw == 'new' || raw == 'nt' || raw == 'new_testament') {
      return 'new';
    }
    if (era.code.startsWith('era_nt_')) {
      return 'new';
    }
    return 'old';
  }

  Future<void> _startQuiz(
    String eventId, {
    String? quizWeekKey,
    StoryEvent? event,
  }) async {
    final state = ref.read(storyControllerProvider);
    final repo = ref.read(storyRepositoryProvider);
    final isAuthenticated = ref.read(signedInUserProvider) != null;
    // 호출자가 event 를 직접 넘겼으면 그걸 사용 (주간 퀴즈처럼 state.events
    // 에 없는 이벤트도 처리). 아니면 state.events 에서 lookup.
    final resolvedEvent =
        event ?? state.events.where((e) => e.id == eventId).firstOrNull;
    if (resolvedEvent == null) {
      return;
    }

    List<QuizQuestion> questions;
    try {
      questions = await repo.fetchQuizQuestions(eventId);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ParchmentDialog(
          title: resolvedEvent.title,
          subtitle: '퀴즈를 불러오지 못했습니다. 다시 시도해 주세요.',
          actions: [
            ParchmentDialogActionButton(
              label: '닫기',
              style: ParchmentDialogActionStyle.secondary,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: Text(
            '$error',
            style: const TextStyle(
              color: Color(0xFF5A4326),
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }

    if (questions.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ParchmentDialog(
          title: resolvedEvent.title,
          subtitle: '해당 사건의 퀴즈가 아직 준비되지 않았습니다. 퀴즈 단계를 완료 처리합니다.',
          actions: [
            ParchmentDialogActionButton(
              label: '확인',
              style: ParchmentDialogActionStyle.secondary,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );
      // 퀴즈가 없는 사건도 본문 읽기와 함께 진행률에 들어가도록 자동 완료.
      // 점수는 0/0 로 기록 (실제 풀어야 할 문제가 없으므로).
      if (mounted) {
        final notifier = ref.read(storyControllerProvider.notifier);
        if (quizWeekKey != null) {
          await notifier.setWeeklyQuizCompleted(
            weekKey: quizWeekKey,
            eventId: eventId,
            isCompleted: true,
            correct: 0,
            total: 0,
          );
        } else {
          await notifier.setQuizCompleted(
            eventId: eventId,
            isCompleted: true,
            correct: 0,
            total: 0,
          );
          await _profileTabKey.currentState
              ?.refreshProgressAfterQuizCompletion();
        }
      }
      return;
    }

    final selectedAnswers = List<int?>.filled(questions.length, null);
    int currentIndex = 0;
    int score = 0;
    int confusedCount = 0;
    bool quizFinished = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final question = questions[currentIndex];
            final isLast = currentIndex == questions.length - 1;
            final canMoveNext = selectedAnswers[currentIndex] != null;
            final progress = (currentIndex + 1) / questions.length;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6EAD8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFB58A47),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              resolvedEvent.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF5A4326),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5D2A8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${currentIndex + 1} / ${questions.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5A4326),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xFFEBD9B2),
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(999),
                              child: const SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFF6A4A25),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5D2A8),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFB58A47),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF1DD),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFD9C18B),
                                  ),
                                ),
                                child: Text(
                                  question.question,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF332A1D),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (var i = 0; i < question.choices.length; i++)
                                _QuizChoiceCard(
                                  index: i,
                                  text: question.choices[i],
                                  selected: selectedAnswers[currentIndex] == i,
                                  onTap: () {
                                    setDialogState(() {
                                      selectedAnswers[currentIndex] = i;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: currentIndex > 0
                                ? () => setDialogState(() {
                                    currentIndex -= 1;
                                  })
                                : null,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7A6748),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            child: const Text(
                              '이전',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: !canMoveNext
                                ? null
                                : () async {
                                    if (!isLast) {
                                      setDialogState(() {
                                        currentIndex += 1;
                                      });
                                      return;
                                    }

                                    score = 0;
                                    confusedCount = 0;
                                    for (var i = 0; i < questions.length; i++) {
                                      final selected = selectedAnswers[i];
                                      if (questions[i].isConfusedChoiceIndex(
                                        selected,
                                      )) {
                                        confusedCount += 1;
                                      } else if (selected ==
                                          questions[i].answerIndex) {
                                        score += 1;
                                      }
                                    }

                                    await showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) =>
                                          _QuizResultDialog(
                                            event: resolvedEvent,
                                            questions: questions,
                                            selectedAnswers: selectedAnswers,
                                            score: score,
                                            confusedCount: confusedCount,
                                          ),
                                    );

                                    // 결과/해설 다이얼로그까지 본 경우만 완료 처리.
                                    quizFinished = true;

                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.of(context).pop();
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB58A47),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            child: Text(isLast ? '제출' : '다음'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // 사용자가 퀴즈를 끝까지 풀고 해설 다이얼로그까지 봐야만 완료 처리.
    // 중간에 빠져나오면 (Android back / 외부 dismiss) quizFinished 가 false.
    if (!quizFinished) {
      return;
    }

    if (!isAuthenticated) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비로그인 상태라 퀴즈 진행 상황은 저장되지 않아요.')),
      );
      return;
    }

    // 퀴즈 완료 + 점수 저장. quizWeekKey 가 있으면 주간 퀴즈 진행도(별도
    // 테이블)에, 없으면 일반 진행도에 저장. 일반은 controller 가 자동으로
    // markEventCompleted 까지 동기화 (_syncOverallCompletion).
    final notifier = ref.read(storyControllerProvider.notifier);
    if (quizWeekKey != null) {
      await notifier.setWeeklyQuizCompleted(
        weekKey: quizWeekKey,
        eventId: eventId,
        isCompleted: true,
        correct: score,
        total: questions.length,
        confusedCount: confusedCount,
        selectedAnswers: selectedAnswers,
      );
    } else {
      await notifier.setQuizCompleted(
        eventId: eventId,
        isCompleted: true,
        correct: score,
        total: questions.length,
        confusedCount: confusedCount,
        selectedAnswers: selectedAnswers,
      );
    }
    // 인앱 알림 row 삽입 — 실패해도 퀴즈 완료 UX 를 막지 않도록 try-catch.
    try {
      await ref
          .read(notificationRepositoryProvider)
          .notifyQuizCompleted(eventId);
      ref.invalidate(unreadNotificationsProvider);
    } catch (_) {
      // 알림 실패는 조용히 무시
    }
    await _profileTabKey.currentState?.refreshProgressAfterQuizCompletion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    // 인물 기반 전체 후보: Step 3 선택지 + 정렬 기준.
    final characterTimeline = _timelineForSelectedCharacters(
      state,
      state.selectedCharacterCodes,
    );
    // 지도에 실제로 렌더할 사건: 커밋된 displayedEventIds 로 필터.
    final mapTimeline = _timelineForMap(state, characterTimeline);
    // 현재 draft 가 후보 밖을 가리키면 자동 정리된 뷰.
    final sanitizedDraftDisplayed = _sanitizeDraftDisplayedEventIds(
      characterTimeline,
    );
    final quizReviewEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.needsReview)
        .map((attempt) => attempt.eventId)
        .toSet();
    final quizConfusedEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.confusedCount > 0)
        .map((attempt) => attempt.eventId)
        .toSet();
    final testamentEras =
        state.eras
            .where((era) => _eraTestament(era) == state.selectedTestament)
            .toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final selectedEra = state.eras
        .where((era) => era.id == state.selectedEraId)
        .firstOrNull;
    final avatarByCharacterCode = <String, String>{
      for (final character in state.characters)
        character.code: character.avatarAssetPath,
    };

    // 첫 화면 (시대 미선택) 은 줌 6 (저배율) 로 가나안~광야~메소포타미아 일대가
    // 한눈에 들어오도록 중심 잡음. 하단 시트 0.46 으로 visible 영역의 중앙이
    // 가나안이 되도록 lat 을 약간 남쪽으로 offset.
    final mapCenter = state.selectedEraIds.isEmpty
        ? const LatLng(28.5, 35.20)
        : (selectedEra?.mapCenterLat != null &&
                  selectedEra?.mapCenterLng != null
              ? LatLng(selectedEra!.mapCenterLat!, selectedEra.mapCenterLng!)
              : null);

    final mapZoom = state.selectedEraIds.isEmpty ? 6.0 : selectedEra?.mapZoom;
    final topInset = MediaQuery.of(context).padding.top;
    // Android 3-button nav bar / iOS home indicator 등 system gesture bar 가
    // 차지하는 픽셀. gesture-only / 풀스크린 모드면 0. 이 값만큼 시트를 위로
    // 띄워야 패널 하단이 nav bar 에 가려지지 않는다 (사용자 보고).
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const outerMargin = 20.0;
    // Toolbar (38) + 8 gap + chip bar (28) + 6 gap = 80. 약간 여유 두어 88.
    final mapCalloutTopObscuredPixels = topInset + 88;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: StoryMapPanel(
              events: mapTimeline,
              selectedEventId: state.selectedEventId,
              onSelectEvent: _handleEventSelect,
              onCloseSelectedCallout: _closeSelectedEventPopup,
              onOpenDetail: _openEventDetail,
              colorForCharacter: controller.colorForCharacter,
              avatarAssetForCharacter: (characterCode) {
                // 1) 현재 era 의 character 에 있으면 그 경로 사용 (정확한 경로
                //    포함 — 향후 storage path 확장 가능).
                final cached = avatarByCharacterCode[characterCode];
                if (cached != null && cached.isNotEmpty) {
                  return cached;
                }
                // 2) state.characters 에 없는 인물 코드는 컨벤션 경로
                //    `assets/avatars_thumbs/{code}.png` 로 폴백 — 번들에 실제
                //    파일이 없으면 _AvatarImage 의 errorBuilder 가
                //    Icons.person 으로 처리.
                if (characterCode.isEmpty) {
                  return '';
                }
                return 'assets/avatars_thumbs/$characterCode.png';
              },
              selectedCharacterCodes: state.selectedCharacterCodes,
              eventEmotionMarks: state.eventEmotionMarks,
              controller: _mapPanelController,
              initialCenter: mapCenter,
              initialZoom: mapZoom,
              topObscuredPixels: mapCalloutTopObscuredPixels,
              // 시트 비율 + nav bar 비율 합산. nav bar 영역까지 obscured 로 처리해
              // 콜아웃이 그 위에 그려지지 않게 한다 (panel 을 nav bar 위로 띄운
              // 만큼 panel + nav bar 가 같이 가린다).
              bottomObscuredFraction:
                  (_selectionSheetExtent > 0
                      ? _selectionSheetExtent
                      : _sheetSizeForStage(
                          MediaQuery.sizeOf(context),
                          _selectionPanelStage,
                        )) +
                  (bottomInset / MediaQuery.sizeOf(context).height),
              decorate: false,
              activeLandmarks: _activeLandmarksForEra(state),
              activeEraBoundaries: state.selectedEraIds.isEmpty
                  ? const []
                  : state.eraBoundaries
                        .where((b) => state.selectedEraIds.contains(b.eraId))
                        .toList(growable: false),
              // 주: region 모드라도 activeEraBoundaries 는 그대로 넘긴다.
              // StoryMapPanel 은 이 데이터를 era 폴리곤 그리기에 쓰지 않고
              // (1) era 변경 카메라 fit 트리거, (2) `_eraColorForRegion` 의
              // 시대 색 lookup 에만 사용한다. 비우면 여러 시대에 속하는
              // region 의 색이 lm.eraCodes.first 로 폴백되어 사용자가 선택한
              // 시대와 다른 색으로 보임.
              selectedLandmarkId: state.selectedLandmarkId,
              // reveal trigger: region 모드면 landmark id, character 모드 step3
              // 면 인물 코드 정렬한 키. 키가 변경되면 사건 핀 0.3초 순차 reveal.
              revealEventsKey:
                  _mode == _SelectionMode.character &&
                      _selectionStep >= 3 &&
                      state.selectedCharacterCodes.isNotEmpty
                  ? 'characters:${(state.selectedCharacterCodes.toList()..sort()).join('+')}'
                  : (state.selectedLandmarkId != null
                        ? 'region:${state.selectedLandmarkId}'
                        : null),
              // 사용자가 reveal 도중 panel 을 ^ 로 펼치면 stagger 를 건너뛰고
              // 즉시 모든 핀 노출. _animateSelectionPanelToStage 에서 토글.
              revealInstantly: _revealInstantly,
              // 마지막 핀까지 reveal 완료 시 panel 자동 expand. (이미 수동으로
              // expand 한 경우 _awaitingRevealComplete 가 false 라 noop.)
              onRevealComplete: _handleRevealComplete,
              onLandmarkTap: (lm) {
                // 지역 모드 + region 클릭 → collapse → reveal → expand 자동
                // 흐름 (인물 모드 _proceedFromCharacterStep 과 동일 패턴).
                if (_mode == _SelectionMode.region && lm.isRegion) {
                  _selectRegionLandmark(lm);
                  return;
                }
                // 그 외(인물 모드 + 어떤 마커든, 지역 모드 + non-region 마커) →
                // 단순 정보 팝업.
                _showLandmarkPopup(lm);
              },
              onMeasureResult: _showMeasureResult,
              eraCodeForId: (eraId) {
                for (final e in state.eras) {
                  if (e.id == eraId) return e.code;
                }
                return null;
              },
              // region 마커에 표시할 사건 개수 — region 본인 + 자식 anchor/minor
              // + alias_group 멤버들의 landmark_id 를 가진 events 수.
              eventCountByLandmarkId: _regionEventCounts(state),
              // step 2 (장소 선택) — region 미선택 상태 = 폴리곤을 큰 단위로
              // 직접 탭하는 UI. 핀/나라 라벨 숨기고 폴리곤 중앙 라벨만 노출.
              regionPickerMode:
                  _mode == _SelectionMode.region &&
                  state.selectedLandmarkId == null,
              // 그 시대의 모든 사건을 인물별 path 로 항상 보여 준다 (선택 인물
              // 진하게, 미선택 흐리게). 사용자가 step 3 에서 사건을 골라도 인물
              // 이동 경로 자체는 사라지면 안 되므로 displayedEventIds 와 무관하게
              // 미리보기를 켜둔다. 선택된 사건은 그 path 위에 핀으로 표시된다
              // (`_buildMarkers`).
              eraPreviewEvents: state.events,
              // 시대 폴리곤(hull) 입력은 path preview 와 분리. 인물 모드 +
              // 인물 선택 시 그 인물 사건만 사용해 폴리곤이 인물 활동 영역에
              // 정확히 맞도록. 그 외에는 빈 리스트 → preview 전체로 폴백.
              hullEvents:
                  _mode == _SelectionMode.character &&
                      state.selectedCharacterCodes.isNotEmpty
                  ? state.events
                        .where(
                          (e) => e.characterCodes.any(
                            state.selectedCharacterCodes.contains,
                          ),
                        )
                        .toList(growable: false)
                  : const <StoryEvent>[],
              // 시대 영역 폴리곤 = 그 시대 region 들의 polygon 합집합. 시대만
              // 선택된 시점부터 region 모드 진입 직후까지 일관되게 표시된다.
              // 인물 모드에서는 region 폴리곤 표시 정책에 따라 빈 리스트로.
              eraRegionLandmarks: _eraRegionLandmarks(state),
              // legend 표시용 인물 이름 lookup.
              nameForCharacter: (code) {
                for (final ch in state.characters) {
                  if (ch.code == code) return ch.name;
                }
                return code;
              },
              // 사용자가 지도와 상호작용하면(드래그/줌/탭 등) hint overlay 를
              // dismiss. region/character 단계 진입 시 _resetMapHint() 가
              // 다시 보여줌.
              onMapInteraction: _handleMapInteraction,
              // 인물 모드에서는 region 검정 캡슐 라벨(가나안·시내 광야·애굽 등)
              // 이 인물 path 점선을 가리는 문제가 있어 라벨을 숨긴다.
              suppressRegionLabels: _mode == _SelectionMode.character,
            ),
          ),
          // 카테고리 필터 칩 — 시대가 선택돼야 의미가 있으므로 그때만 표시.
          // 칩 클릭 시 inline dropdown 으로 그 카테고리의 실제 랜드마크 리스트가
          // 칩 바로 아래에 펼쳐진다 (Dropbox 스타일). 닫기 버튼 또는 다시 칩
          // 클릭으로 닫음. 비활성화 토글 (이미 active 였던 칩 클릭) 시에는
          // dropdown 안 열고 필터만 끔.
          if (state.selectedEraId != null)
            Positioned(
              // 세로 모드: toolbar 바로 아래. 좌우 끝까지 가득 채우고
              // 추가 칩은 horizontal scroll 로 노출.
              top: topInset + 50,
              left: 0,
              right: 0,
              child: _LandmarkCategoryChipsBar(
                state: state,
                onToggle: (cat) => ref
                    .read(storyControllerProvider.notifier)
                    .toggleLandmarkCategory(cat),
                onClear: () => ref
                    .read(storyControllerProvider.notifier)
                    .clearLandmarkCategories(),
                onLandmarkTap: _showLandmarkPopup,
              ),
            ),
          // v3 — 좌측 "랜드마크 25" 토글 + 사이드 패널 제거. 사용자가 카테고리
          // 칩 바로 멀티 필터를 사용한다.
          LayoutBuilder(
            builder: (context, constraints) {
              final sideTop = topInset + 8;
              final viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final isPhone = _isPhoneSheetLayoutForSize(viewportSize);
              final sheetHorizontalMargin = isPhone ? 10.0 : 18.0;
              final sheetHeight =
                  constraints.maxHeight *
                  _sheetSizeForStage(viewportSize, _selectionPanelStage);
              // 모드별 지도 안내 문구. null 이면 hint overlay 미표시.
              final mapHint = _currentMapHint();

              return Stack(
                children: [
                  // 양피지 grain 은 StoryMapPanel 내부에서 ParchmentMultiplyLayer
                  // (BlendMode.multiply CustomPainter) 로 처리. 단순 Opacity
                  // overlay 는 화면을 뿌옇게 만들어서 폐기.
                  Positioned(
                    left: sheetHorizontalMargin,
                    right: sheetHorizontalMargin,
                    // 시트는 화면 맨 아래까지 차지하고 height 를 sheetHeight +
                    // bottomInset 으로 키운다 — panel 자체의 양피지 deco 가 그
                    // height 에 맞게 늘어나 nav bar 영역까지 자연스럽게 양피지가
                    // 이어진다. 각 panel 은 자체적으로 bottomInset 만큼 마지막
                    // spacer 를 두어 컨텐츠를 nav bar 위로 띄운다.
                    // (gesture-only 단말은 bottomInset=0 이라 기존과 동일한 동작.)
                    bottom: 0,
                    child: AnimatedContainer(
                      key: const ValueKey<String>('selection-sheet'),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: sheetHeight + bottomInset,
                      child: _mode == _SelectionMode.region
                          ? _buildRegionPanel(state, bottomInset)
                          : (_mode == null && _selectionStep == 1)
                          ? _buildHomeIntroPanel(state, bottomInset)
                          : StorySelectionPanel(
                              scrollController: _selectionPanelScrollController,
                              step: _selectionStep,
                              panelStage: _selectionPanelStage,
                              // 장소 모드와 동일한 핸들·stepper 헤더를 인물 모드에도 노출.
                              headerOverride: _panelStageHandle(),
                              // step 2 인물 카드의 "사건 N개" 카운트 source.
                              eraEvents: state.events,
                              onStepUp: _stepSelectionPanelUp,
                              onStepDown: _stepSelectionPanelDown,
                              canOpenStep: (step) =>
                                  _canOpenSelectionStep(step, state),
                              onSelectStep: (step) => _goToSelectionStep(step),
                              eras: testamentEras,
                              selectedEraId: state.selectedEraId,
                              selectedTestament: state.selectedTestament,
                              onSelectEra: (eraId) {
                                _handleStepEraSelect(eraId);
                              },
                              onSelectTestament: (testament) {
                                _handleStepTestamentSelect(testament);
                              },
                              characters: state.characters,
                              characterSortMode: _characterSortMode,
                              onCharacterSortModeChanged: (mode) {
                                setState(() {
                                  _characterSortMode = mode;
                                });
                              },
                              draftSelectedCharacterCodes:
                                  _sanitizeDraftSelectedCharacterCodes(state),
                              onToggleDraftCharacter: _toggleDraftCharacter,
                              committedSelectedCharacterCodes:
                                  state.selectedCharacterCodes,
                              hasPendingCharacterChanges:
                                  _hasPendingCharacterSelectionChanges(state),
                              colorForDraftCharacter: (characterId) =>
                                  _colorForDraftCharacter(characterId, state),
                              colorForCommittedCharacter:
                                  controller.colorForCharacter,
                              events: characterTimeline,
                              completedEventIds: state.completedEventIds,
                              eventEmotionMarks: state.eventEmotionMarks,
                              quizAttemptSummaries: state.quizAttemptSummaries,
                              celebrationEventId: _mapCelebrationEventId,
                              celebrationStampLabel: _mapCelebrationStampLabel,
                              celebrationNonce: _mapCelebrationNonce,
                              onCelebrationComplete:
                                  _mapCelebrationCompleteCallback(),
                              quizReviewEventIds: quizReviewEventIds,
                              quizConfusedEventIds: quizConfusedEventIds,
                              draftDisplayedEventIds: sanitizedDraftDisplayed,
                              committedDisplayedEventIds:
                                  state.displayedEventIds,
                              onToggleDisplayedEvent:
                                  _toggleDraftDisplayedEvent,
                              onSelectAllDisplayedEvents: () =>
                                  _selectAllDraftDisplayedEvents(
                                    characterTimeline,
                                  ),
                              onDeselectAllDisplayedEvents:
                                  _deselectAllDraftDisplayedEvents,
                              onCommitDisplayedEvents: _proceedFromStoryStep,
                              onNextFromEra: _proceedFromEraStep,
                              onNextFromCharacters: _proceedFromCharacterStep,
                              onOpenEventDetail: (event) {
                                ref
                                    .read(storyControllerProvider.notifier)
                                    .selectEvent(event.id);
                                _openEventDetailPage(event);
                              },
                              // 지도 핀 클릭 등으로 controller 가 가진 현재
                              // 강조 이벤트. EventTimelineRow 가 자동 스크롤.
                              currentSelectedEventId: state.selectedEventId,
                            ),
                    ),
                  ),
                  // 우측 사이드: 줌 +/- 만 (stepper 는 시트 헤더로 이동).
                  // toolbar(38) + 8 + chip bar(28) + 8 ≈ topInset + 90 부터 노출.
                  Positioned(
                    right: outerMargin,
                    top: topInset + 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        mapControlButton(
                          icon: Icons.add,
                          tooltip: '확대',
                          onTap: _mapPanelController.zoomIn,
                        ),
                        const SizedBox(height: 6),
                        mapControlButton(
                          icon: Icons.remove,
                          tooltip: '축소',
                          onTap: _mapPanelController.zoomOut,
                        ),
                        const SizedBox(height: 6),
                        // 지도 출처/라이선스 — CC BY 4.0(Stamen Watercolor) +
                        // ODbL(OpenStreetMap) attribution 의무 충족.
                        mapControlButton(
                          icon: Icons.info_outline,
                          tooltip: '지도 출처',
                          onTap: _showMapAttributionDialog,
                        ),
                      ],
                    ),
                  ),
                  // 세로 모드: 4개 핵심 버튼 + 알림/Aa/이야기등록을
                  // 좌우 끝까지 가득 펼치고 horizontal scroll 로 추가 노출.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: sideTop,
                    child: SizedBox(
                      height: 38,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            // "사건선택" 버튼 제거 (2026-05-08) — 하단 스크롤 패널이
                            // 항상 일부 보이므로 별도 토글 불필요.
                            // "Aa" (글자크기) 버튼 제거 — 프로필 설정 시트로 이전.
                            topUtilityButton(
                              label: '성경',
                              onTap: _openBibleReaderPopup,
                            ),
                            const SizedBox(width: 4),
                            topUtilityButton(
                              label: '퀴즈',
                              onTap: _openWeeklyTab,
                            ),
                            const SizedBox(width: 4),
                            topUtilityButton(
                              label: '프로필',
                              onTap: _openProfileTab,
                            ),
                            const SizedBox(width: 4),
                            NotificationBellButton(
                              onNavigate: _handleNotificationTap,
                              onOpenHistory: _openNotificationHistory,
                            ),
                            if (kIsWeb) ...[
                              const SizedBox(width: 4),
                              topUtilityButton(
                                label: '이야기 등록',
                                onTap: _openProposalBoardOrGate,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 지도 위 모드별 안내 오버레이. 사용자가 무엇을 해야 할지
                  // 모를 때 가운데 흐리게 떠 있다가, 지도 제스처/region 선택/
                  // 인물 「다음」 등 한 번의 행동으로 dismiss. IgnorePointer 로
                  // 감싸 hint 가 떠 있어도 폴리곤·핀 클릭은 그대로 가능.
                  if (mapHint != null)
                    Positioned(
                      top: topInset + 96,
                      left: 0,
                      right: 0,
                      bottom: bottomInset + sheetHeight + 16,
                      child: IgnorePointer(
                        child: MapHintOverlay(
                          message: mapHint.message,
                          icon: mapHint.icon,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (state.error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 86,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xAA000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          if (_mapAnimationInputLocked)
            const Positioned.fill(
              child: ModalBarrier(
                color: Colors.transparent,
                dismissible: false,
              ),
            ),
          if (state.loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 통합 흐름 — 시대+모드 카드 (intro) / 인물 모드 (StorySelectionPanel) /
  // 지역 모드 (RegionPickPanel + RegionEventList) 한 화면에서 swap.
  // ===========================================================================

  /// V1 StorySelectionPanel 과 동일한 양피지 양식 (그라데이션 + 갈색 외곽선).
  /// HomeIntroPanel / RegionPickPanel / RegionEventList 모두 같은 wrapper 안.
  BoxDecoration _parchmentPanelDecoration() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFBF5E9), Color(0xFFF6EAD5), Color(0xFFEEDCBE)],
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      border: Border(
        top: BorderSide(color: Color(0xFF8C6743), width: 1.15),
        left: BorderSide(color: Color(0xFF8C6743), width: 1.15),
        right: BorderSide(color: Color(0xFF8C6743), width: 1.15),
      ),
      boxShadow: [
        BoxShadow(
          color: Color(0x38000000),
          blurRadius: 16,
          offset: Offset(0, -2),
        ),
      ],
    );
  }

  /// 시트 헤더 — 가운데 핸들(인디케이터 + 단일 toggle 화살표) + 우측
  /// stepper(홈·1·2·?). 좌측은 stepper 와 균형을 맞춘 빈 공간 (또는
  /// 인물 모드 step 1 의 "N명 다음" 핀).
  ///
  /// 옛 ▲▼ 두 IconButton 은 stepper 와 시각적으로 충돌해 사용자가 ▲ 를
  /// 인지하지 못하는 문제가 있었다 (panel half stage 도 실질적으로 expanded 와
  /// 동일 사이즈라 두 버튼이 redundant). 핸들 영역 전체가 하나의 InkWell —
  /// 탭하면 collapsed ↔ expanded 토글.
  Widget _panelStageHandle() {
    final stage = _selectionPanelStage;
    final state = ref.read(storyControllerProvider);
    // 인물 모드 step 2 + 1명 이상 선택 → 좌측에 "N명 다음" 핀.
    final draftCharacters = _sanitizeDraftSelectedCharacterCodes(state);
    final showCharacterNext =
        _mode == _SelectionMode.character &&
        _selectionStep == 2 &&
        draftCharacters.isNotEmpty;
    // stepper 의 estimated width (3 dots × 20 + 2 separators × 10 + helpButton
    // 20 + paddings 12 + 6 ≈ 128). 좌측 SizedBox 도 같은 width 로 맞춰
    // 가운데 핸들 영역이 정확히 화면 중앙에 오게 한다.
    const headerSideSlot = 128.0;
    final isExpanded = stage == StorySelectionPanelStage.expanded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          SizedBox(
            width: headerSideSlot,
            child: showCharacterNext
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _CharacterNextPill(
                      count: draftCharacters.length,
                      onPressed: _proceedFromCharacterStep,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _animateSelectionPanelToStage(
                    isExpanded
                        ? StorySelectionPanelStage.collapsed
                        : StorySelectionPanelStage.expanded,
                  ),
                  child: Tooltip(
                    message: isExpanded ? '아래로 접기' : '위로 펼치기',
                    child: Container(
                      width: 48,
                      height: 30,
                      decoration: BoxDecoration(
                        // stepper 의 활성 초록(_activeColor 0xFF2E8B57) 의 옅은
                        // tint 로 panel toggle 임을 색으로 시그널링.
                        color: const Color(0xFF2E8B57).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(
                            0xFF2E8B57,
                          ).withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        size: 22,
                        color: const Color(0xFF2E8B57),
                        semanticLabel: isExpanded ? '아래로 접기' : '위로 펼치기',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: headerSideSlot,
            child: Align(
              alignment: Alignment.centerRight,
              child: _SelectionStepper(
                currentStep: _currentStepperIndex(),
                mode: _mode,
                onStepTap: _handleStepperTap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeIntroPanel(StoryState state, double bottomInset) {
    return Container(
      decoration: _parchmentPanelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _panelStageHandle(),
          Expanded(child: _buildHomeIntroBody(state)),
          // nav bar 영역에는 panel 양피지만 노출 — 컨텐츠는 그 위로 띄움.
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildHomeIntroBody(StoryState state) {
    return Container(
      color: Colors.transparent,
      child: HomeIntroPanel(
        eras: state.eras,
        selectedEraId: state.selectedEraId,
        onSelectEra: (eraId) async {
          // 같은 시대 다시 누르면 해제, 아니면 새 시대로 교체 (단일 선택).
          final next = state.selectedEraId == eraId ? null : eraId;
          await ref.read(storyControllerProvider.notifier).setSelectedEra(next);
          // 새 시대 선택 시 그 시대 region 폴리곤이 모두 화면에 들어오도록
          // 카메라 fit. 다음 frame 에 _eraRegionLandmarks 가 build 되어야 하므로
          // post-frame.
          if (!mounted || next == null) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _focusOnEraRegions(ref.read(storyControllerProvider));
          });
        },
        onPickMode: (mode) => _handlePickMode(mode, state),
      ),
    );
  }

  Future<void> _handlePickMode(SelectionMode mode, StoryState state) async {
    final ctl = ref.read(storyControllerProvider.notifier);
    if (mode == SelectionMode.region) {
      ctl.setSelectionMode(SelectionMode.region);
      setState(() {
        _mode = _SelectionMode.region;
        _resetMapHint();
      });
      // 슬라이딩 패널을 collapsed 로 내려서 사용자가 지도에서 region 마커를
      // 직접 클릭해 선택할 수 있게 한다.
      _animateSelectionPanelToStage(StorySelectionPanelStage.collapsed);
      // 그 시대의 모든 region 폴리곤이 한눈에 들어오도록 카메라 fit.
      // 다음 frame 에 _eraRegionLandmarks 가 build 되어 있어야 하므로 post-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusOnEraRegions(state);
      });
      return;
    }
    // 인물 모드 — 선택된 시대 중 첫 시대로 selectEra 를 명시 호출해 characters
    // 가 확실히 채워지게 하고, step 2 (인물) 부터 시작.
    final orderedEras = [...state.eras]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final firstSelected = orderedEras
        .where((e) => state.selectedEraIds.contains(e.id))
        .firstOrNull;
    if (firstSelected != null) {
      await ctl.selectEra(firstSelected.id);
    }
    if (!mounted) return;
    setState(() {
      _mode = _SelectionMode.character;
      _selectionStep = 2;
      _resetMapHint();
    });
  }

  /// 현재 시대의 region 폴리곤이 한눈에 들어오도록 카메라 fit.
  /// 실제로 화면에 그려지는 폴리곤(사건 ≥ 1) 만 fit 대상에 포함 — 비활성 region
  /// 까지 포함하면 카메라가 불필요하게 줌아웃된다.
  /// 시대 선택, "장소에서 시작" 클릭, stepper 2 로 돌아갈 때 호출.
  void _focusOnEraRegions(StoryState state) {
    final counts = _regionEventCounts(state);
    final regions = _eraRegionLandmarks(
      state,
    ).where((r) => (counts[r.id] ?? 0) > 0);
    final allPoints = <LatLng>[];
    for (final r in regions) {
      for (final p in r.polygon) {
        allPoints.add(p);
      }
    }
    // fallback — 사건이 어디에도 없으면 전체 region 으로 폴백.
    if (allPoints.isEmpty) {
      for (final r in _eraRegionLandmarks(state)) {
        for (final p in r.polygon) {
          allPoints.add(p);
        }
      }
    }
    if (allPoints.length < 2) return;
    _mapPanelController.focusRegion(allPoints);
  }

  Widget _buildRegionPanel(StoryState state, double bottomInset) {
    final quizReviewEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.needsReview)
        .map((attempt) => attempt.eventId)
        .toSet();
    final quizConfusedEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.confusedCount > 0)
        .map((attempt) => attempt.eventId)
        .toSet();
    final eraCodes = state.eras
        .where((e) => state.selectedEraIds.contains(e.id))
        .map((e) => e.code)
        .toSet();
    final eraFiltered = state.landmarks
        .where(
          (lm) => lm.eraCodes.isEmpty || lm.eraCodes.any(eraCodes.contains),
        )
        .toList();
    // 사건이 있는 region 만 카드로 노출 — 지도 위 폴리곤(사건 ≥ 1) 과 1:1 매칭.
    final eventCounts = _regionEventCounts(state);
    final regionsOnly = eraFiltered
        .where((lm) => lm.isRegion && (eventCounts[lm.id] ?? 0) > 0)
        .toList();
    final regions = regionsOnly.isNotEmpty ? regionsOnly : eraFiltered;
    final selected = state.landmarkById(state.selectedLandmarkId);

    return Container(
      decoration: _parchmentPanelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _panelStageHandle(),
          // v3 — region 선택 전후 모두 panel 자체 헤더 제거. 인물 모드 흐름과
          // 동일하게, 단계 이동은 우측 상단 _SelectionStepper 1·2·3 으로 처리.
          // region 카드/사건 카드 영역에 바로 진입.
          Expanded(
            child: selected == null
                ? RegionPickPanel(
                    regions: regions,
                    allEras: state.eras,
                    selectedEraIds: state.selectedEraIds,
                    selectedLandmarkId: state.selectedLandmarkId,
                    onSelect: _selectRegionLandmark,
                  )
                : RegionEventList(
                    landmark: selected,
                    events: _eventsAtLandmark(state, selected),
                    allEras: state.eras,
                    allCharacters: state.characters,
                    selectedEventId: state.selectedEventId,
                    completedEventIds: state.completedEventIds,
                    eventEmotionMarks: state.eventEmotionMarks,
                    quizAttemptSummaries: state.quizAttemptSummaries,
                    celebrationEventId: _mapCelebrationEventId,
                    celebrationStampLabel: _mapCelebrationStampLabel,
                    celebrationNonce: _mapCelebrationNonce,
                    onCelebrationComplete: _mapCelebrationCompleteCallback(),
                    quizReviewEventIds: quizReviewEventIds,
                    quizConfusedEventIds: quizConfusedEventIds,
                    onSelectEvent: (event) {
                      ref
                          .read(storyControllerProvider.notifier)
                          .selectEvent(event.id);
                      // v3 — 미리보기 팝업 단계 생략. 카드 클릭 시 바로 상세
                      // 페이지로 이동. 빠져나오면 selectedEventId 가 유지되어
                      // 패널·지도 핀에 '현재 이야기' 강조 표시.
                      _openEventDetailPage(event);
                    },
                    onClose: () {
                      ref
                          .read(storyControllerProvider.notifier)
                          .selectLandmark(null);
                      setState(() {});
                    },
                  ),
          ),
          // nav bar 영역에는 panel 양피지만 노출 — 컨텐츠는 그 위로 띄움.
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  List<StoryEvent> _eventsAtLandmark(StoryState state, dynamic lm) {
    final ids = <String>{lm.id as String};
    if (lm.isRegion as bool) {
      for (final child in state.landmarks) {
        if (child.parentLandmarkId == lm.id) ids.add(child.id);
      }
    }
    return state.events.where((e) => ids.contains(e.landmarkId)).toList();
  }

  // v3 — _showEventPreviewDialog 제거됨. 카드 클릭 시 바로 _openEventDetailPage.
}
