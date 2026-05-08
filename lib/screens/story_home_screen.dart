import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/era.dart';
import '../models/landmark.dart';
import '../models/quiz_question.dart';
import '../models/story_event.dart';
import '../services/push_service.dart';
import '../state/auth_providers.dart';
import '../state/notification_providers.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../utils/scene_asset_loader.dart';
import '../widgets/bible_reader_page.dart';
import '../widgets/character_panel.dart';
import '../widgets/event_detail_page.dart';
import '../widgets/notification/notification_bell_button.dart';
import '../widgets/notification/notification_deep_link.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/profile_tab_page.dart';
import '../widgets/proposal/pastor_gate_dialog.dart';
import '../widgets/quiz/quiz_tab_page.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/story_map_panel.dart';
import '../widgets/story_selection_panel.dart';
import '../widgets/v2/home_intro_panel.dart';
import '../widgets/v2/region_event_list.dart';
import '../widgets/v2/region_pick_panel.dart';
import 'notification_history_screen.dart';
import 'proposal_board_screen.dart';
import 'proposal_detail_screen.dart';

class StoryHomeScreen extends ConsumerStatefulWidget {
  const StoryHomeScreen({super.key, this.initialStep = 1});

  /// 시대 선택 패널의 시작 단계. v2 첫 화면(시대 + 모드 분기)에서 인물 모드를
  /// 고르고 들어오면 `2` 를 넘겨 곧장 인물 선택 단계부터 시작한다.
  final int initialStep;

  @override
  ConsumerState<StoryHomeScreen> createState() => _StoryHomeScreenState();
}

class _StoryHomeScreenState extends ConsumerState<StoryHomeScreen> {
  static const double _selectionSheetCollapsedSize = 0.16;
  static const double _selectionSheetExpandedSize = 0.60;

  /// 인트로 패널(시대/모드 선택 단계) 의 expanded 사이즈 — 컨텐츠가 짧아 0.46
  /// 정도면 충분하다 (그 이상이면 빈 공간이 생김).
  static const double _selectionSheetIntroSize = 0.46;

  /// 사건 핀 reveal 모드(region 선택 후 또는 character step 3) 의 panel 크기.
  /// 카드 280px (썸네일+제목+위치+요약+인물) + 핸들 + padding 으로 ~0.36.
  static const double _selectionSheetCardOnlySize = 0.36;
  final StoryMapPanelController _mapPanelController = StoryMapPanelController();
  final ScrollController _selectionPanelScrollController = ScrollController();
  final GlobalKey<ProfileTabPageState> _profileTabKey =
      GlobalKey<ProfileTabPageState>();
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  ProviderSubscription<User?>? _authUserSubscription;
  CharacterSortMode _characterSortMode = CharacterSortMode.eraOrder;
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
    _authUserSubscription?.close();
    _selectionPanelScrollController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
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

  double _sheetMaxSizeFor(Size size) {
    final state = ref.read(storyControllerProvider);
    if (_isInRevealMode(state)) {
      return _selectionSheetCardOnlySize;
    }
    // 인트로 패널 (시대 미선택 또는 모드 미선택) — 콘텐츠가 짧아 빈 공간이
    // 생기므로 살짝 작은 비율 사용. 컨텐츠가 더 길어지면 SingleChildScrollView
    // 가 알아서 스크롤.
    if (_mode == null) {
      return _selectionSheetIntroSize;
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
      return (px / size.height).clamp(0.28, _selectionSheetExpandedSize);
    }
    return _selectionSheetExpandedSize;
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

  void _animateSelectionPanelToStage(StorySelectionPanelStage stage) {
    final state = ref.read(storyControllerProvider);
    final maxExtent = _isInRevealMode(state)
        ? _selectionSheetCardOnlySize
        : _selectionSheetExpandedSize;
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
    final state = ref.read(storyControllerProvider);
    // reveal 완료 후에도 reveal 모드이므로 카드 사이즈만 사용.
    final expandExtent = _isInRevealMode(state)
        ? _selectionSheetCardOnlySize
        : _selectionSheetExpandedSize;
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

  /// Step 3 "다음" 버튼 핸들러 — draft 를 커밋해 지도 핀/화살표 애니메이션 트리거.
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
    final desc = (landmark.description ?? '').trim();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Text(
                landmark.emoji,
                style: const TextStyle(fontSize: 28, height: 1.0),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  landmark.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            desc.isEmpty ? '이 랜드마크에 대한 설명이 아직 없습니다.' : desc,
            style: const TextStyle(fontSize: 14, height: 1.55),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
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
          onOpenBibleReader: (bookNo, chapterNo, verseNo) async {
            if (!mounted) {
              return;
            }
            await _openBibleReaderPopup(
              initialBookNo: bookNo,
              initialChapterNo: chapterNo,
              initialVerseNo: verseNo,
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
          prevEvent: prev,
          nextEvent: next,
          onNavigateToEvent: (target) {
            // 같은 페이지를 새 사건으로 교체 (push stack 무한 증가 방지).
            // quizWeekKey 가 있으면 prev/next 이동 후에도 퀴즈 모드 유지.
            ref.read(storyControllerProvider.notifier).selectEvent(target.id);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) =>
                    _buildDetailPageForEvent(target, quizWeekKey: quizWeekKey),
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
      onOpenBibleReader: (bookNo, chapterNo, verseNo) async {
        if (!mounted) return;
        await _openBibleReaderPopup(
          initialBookNo: bookNo,
          initialChapterNo: chapterNo,
          initialVerseNo: verseNo,
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
      prevEvent: prev,
      nextEvent: next,
      onNavigateToEvent: (target) {
        ref.read(storyControllerProvider.notifier).selectEvent(target.id);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                _buildDetailPageForEvent(target, quizWeekKey: quizWeekKey),
          ),
        );
      },
    );
  }

  Future<void> _openBibleReaderPopup({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
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
    bool quizFinished = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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
                                    for (var i = 0; i < questions.length; i++) {
                                      if (selectedAnswers[i] ==
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
      );
    } else {
      await notifier.setQuizCompleted(
        eventId: eventId,
        isCompleted: true,
        correct: score,
        total: questions.length,
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
              controller: _mapPanelController,
              initialCenter: mapCenter,
              initialZoom: mapZoom,
              topObscuredPixels: mapCalloutTopObscuredPixels,
              bottomObscuredFraction: _selectionSheetExtent > 0
                  ? _selectionSheetExtent
                  : _sheetSizeForStage(
                      MediaQuery.sizeOf(context),
                      _selectionPanelStage,
                    ),
              decorate: false,
              activeLandmarks: _activeLandmarksForEra(state),
              activeEraBoundaries:
                  state.selectedEraIds.isEmpty || _mode == _SelectionMode.region
                  // 지역 모드 진입 시 시대 영역 폴리곤은 숨기고 region 폴리곤
                  // 만 보이게 한다 (마커가 region kind 만 필터되는 것과 동일).
                  ? const []
                  : state.eraBoundaries
                        .where((b) => state.selectedEraIds.contains(b.eraId))
                        .toList(growable: false),
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

              return Stack(
                children: [
                  // 양피지 grain 은 StoryMapPanel 내부에서 ParchmentMultiplyLayer
                  // (BlendMode.multiply CustomPainter) 로 처리. 단순 Opacity
                  // overlay 는 화면을 뿌옇게 만들어서 폐기.
                  Positioned(
                    left: sheetHorizontalMargin,
                    right: sheetHorizontalMargin,
                    bottom: 0,
                    child: AnimatedContainer(
                      key: const ValueKey<String>('selection-sheet'),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: sheetHeight,
                      child: _mode == _SelectionMode.region
                          ? _buildRegionPanel(state)
                          : (_mode == null && _selectionStep == 1)
                          ? _buildHomeIntroPanel(state)
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

  /// 시트 헤더 — ▲▼ 토글 + 가운데 인디케이터 + 우측 stepper(1-2-3-?).
  /// 우측 상단 stepper Positioned 는 제거하고 여기에 통합해 화면 공간 확보.
  Widget _panelStageHandle() {
    final stage = _selectionPanelStage;
    final state = ref.read(storyControllerProvider);
    // 인물 모드 step 2 + 1명 이상 선택 → 좌측에 "N명 다음" 핀.
    final draftCharacters = _sanitizeDraftSelectedCharacterCodes(state);
    final showCharacterNext =
        _mode == _SelectionMode.character &&
        _selectionStep == 2 &&
        draftCharacters.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          // 좌측 — "N명 다음" 핀 (조건부) 또는 stepper 균형용 빈 공간.
          SizedBox(
            width: 110,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: '아래로',
                  onPressed: stage == StorySelectionPanelStage.collapsed
                      ? null
                      : () => _animateSelectionPanelToStage(
                          stage == StorySelectionPanelStage.expanded
                              ? StorySelectionPanelStage.half
                              : StorySelectionPanelStage.collapsed,
                        ),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                Container(
                  width: 28,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8C6743).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: '위로',
                  onPressed: stage == StorySelectionPanelStage.expanded
                      ? null
                      : () => _animateSelectionPanelToStage(
                          stage == StorySelectionPanelStage.collapsed
                              ? StorySelectionPanelStage.half
                              : StorySelectionPanelStage.expanded,
                        ),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
              ],
            ),
          ),
          // 우측 stepper (1-2-3-?) — 기존 우측 상단에서 이동.
          _SelectionStepper(
            currentStep: _currentStepperIndex(),
            mode: _mode,
            onStepTap: _handleStepperTap,
          ),
        ],
      ),
    );
  }

  Widget _buildHomeIntroPanel(StoryState state) {
    return Container(
      decoration: _parchmentPanelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _panelStageHandle(),
          Expanded(child: _buildHomeIntroBody(state)),
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

  Widget _buildRegionPanel(StoryState state) {
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

enum _SelectionMode { character, region }

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

/// 지도 상단의 랜드마크 카테고리 필터 칩 가로 스크롤 바.
/// 비어 있으면 모든 카테고리 통과(전체 표시), 한 칩 누르면 그 카테고리만.
class _LandmarkCategoryChipsBar extends StatefulWidget {
  const _LandmarkCategoryChipsBar({
    required this.state,
    required this.onToggle,
    required this.onClear,
    required this.onLandmarkTap,
  });

  final StoryState state;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;
  final ValueChanged<Landmark> onLandmarkTap;

  // 키 = DB category, 값 = (이모지, 한국어 라벨).
  static const Map<String, (String, String)> _catMeta = {
    'region': ('🌍', '지역'),
    'city': ('🏛️', '도시'),
    'mountain': ('⛰️', '산'),
    'water': ('🌊', '물·강'),
    'river': ('💧', '강'),
    'sea': ('🌊', '바다'),
    'island': ('🏝️', '섬'),
    'wilderness': ('🏜️', '광야'),
    'campsite': ('⛺', '진영'),
    'palace': ('👑', '궁전'),
    'holy_site': ('🕊️', '거룩한 곳'),
    'temple': ('⛪', '성전'),
    'tomb': ('⚰️', '무덤'),
    'monument': ('🪨', '기념비'),
    'prison': ('⛓️', '감옥'),
    'battle': ('⚔️', '전투'),
    'city_gate': ('🚪', '성문'),
  };

  @override
  State<_LandmarkCategoryChipsBar> createState() =>
      _LandmarkCategoryChipsBarState();
}

class _LandmarkCategoryChipsBarState extends State<_LandmarkCategoryChipsBar> {
  /// 현재 inline 으로 펼쳐진 카테고리. null 이면 dropdown 닫힘. 필터의
  /// selectedLandmarkCategories 와는 별개 — 토글 끄기 시에는 dropdown 안 펼쳐짐.
  String? _expandedCat;

  /// 칩별 LayerLink — dropdown 이 그 칩 아래에 정확히 anchor 되도록.
  final Map<String, LayerLink> _chipLinks = {};

  /// Overlay 에 dropdown 을 렌더해 부모 Positioned hit-test 영역 제약을 우회.
  final OverlayPortalController _portalController = OverlayPortalController();

  /// 현재 build 컨텍스트에서 사용한 dropdown payload 를 overlay child 빌더가
  /// 참조하도록 캐시. expanded 가 바뀔 때마다 setState 로 재할당.
  _DropdownPayload? _dropdownPayload;

  LayerLink _linkFor(String cat) =>
      _chipLinks.putIfAbsent(cat, () => LayerLink());

  void _onChipTap(String cat) {
    final wasActive = widget.state.selectedLandmarkCategories.contains(cat);
    widget.onToggle(cat);
    setState(() {
      // 활성 → 비활성: dropdown 안 열고 닫는다.
      // 비활성 → 활성: 그 카테고리 dropdown 펼친다.
      // 다른 카테고리에서 새 카테고리로 전환: 새 카테고리 dropdown 펼친다.
      _expandedCat = wasActive ? null : cat;
    });
  }

  void _onClearAll() {
    widget.onClear();
    setState(() => _expandedCat = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 그 시대 랜드마크의 카테고리별 카운트.
    final eraCode = state.eras
        .where((e) => e.id == state.selectedEraId)
        .firstOrNull
        ?.code;
    if (eraCode == null) return const SizedBox.shrink();

    final countByCategory = <String, int>{};
    final landmarksByCategory = <String, List<Landmark>>{};
    var totalCount = 0;
    for (final l in state.landmarks) {
      if (l.isRegion) continue; // region 은 폴리곤이라 카테고리 칩에 없음
      if (!l.eraCodes.contains(eraCode)) continue;
      // v3 — landmarks 테이블 'category' 컬럼은 옛 v1 잔존. 새 데이터는 'kind'
      // 가 카테고리 역할 (mountain/city/river/...).
      final cat = (l.category != null && l.category!.isNotEmpty)
          ? l.category!
          : l.kind;
      if (cat.isEmpty) continue;
      countByCategory[cat] = (countByCategory[cat] ?? 0) + 1;
      (landmarksByCategory[cat] ??= <Landmark>[]).add(l);
      totalCount++;
    }
    if (totalCount == 0) return const SizedBox.shrink();
    // _catMeta 순서대로 정렬, 메타에 없는 새 카테고리는 끝에.
    const meta = _LandmarkCategoryChipsBar._catMeta;
    final ordered = [
      ...meta.keys.where(countByCategory.containsKey),
      ...countByCategory.keys.where((c) => !meta.containsKey(c)),
    ];

    final selected = state.selectedLandmarkCategories;
    final expanded = _expandedCat;
    // expanded 가 현재 시대에 더 이상 없는 카테고리가 됐으면 자동 닫기.
    final expandedItems = (expanded != null)
        ? landmarksByCategory[expanded]
        : null;

    final allLink = _linkFor('__all__');

    // dropdown payload 갱신 + portal 노출 토글
    final hasDropdown =
        expanded != null && expandedItems != null && expandedItems.isNotEmpty;
    if (hasDropdown) {
      _dropdownPayload = _DropdownPayload(
        link: _linkFor(expanded),
        emoji: meta[expanded]?.$1 ?? '📍',
        label: meta[expanded]?.$2 ?? expanded,
        items: expandedItems,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_portalController.isShowing) _portalController.show();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_portalController.isShowing) _portalController.hide();
      });
    }

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (_) {
        final payload = _dropdownPayload;
        if (payload == null) return const SizedBox.shrink();
        // Overlay 의 Stack 안에 Positioned 로 배치 (CompositedTransformFollower
        // 가 동작하려면 Stack 내부여야 함). offset 은 follower 가 결정.
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: payload.link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 6),
                child: SizedBox(
                  width: 260,
                  child: _LandmarkCategoryDropdown(
                    categoryEmoji: payload.emoji,
                    categoryLabel: payload.label,
                    items: payload.items,
                    onClose: () => setState(() => _expandedCat = null),
                    onLandmarkTap: (lm) {
                      // dropdown 에서 랜드마크를 누르면 dropdown 을 닫고
                      // 부모 콜백 (포커스 + 설명 팝업) 을 호출.
                      setState(() => _expandedCat = null);
                      widget.onLandmarkTap(lm);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: SizedBox(
        height: 28,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            CompositedTransformTarget(
              link: allLink,
              child: _CategoryChip(
                label: '전체',
                emoji: '✨',
                count: totalCount,
                active: selected.isEmpty,
                onTap: _onClearAll,
              ),
            ),
            for (final cat in ordered) ...[
              const SizedBox(width: 6),
              CompositedTransformTarget(
                link: _linkFor(cat),
                child: _CategoryChip(
                  label: meta[cat]?.$2 ?? cat,
                  emoji: meta[cat]?.$1 ?? '📍',
                  count: countByCategory[cat]!,
                  active: selected.contains(cat),
                  onTap: () => _onChipTap(cat),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// dropdown 의 overlay child 가 참조할 데이터 묶음.
class _DropdownPayload {
  const _DropdownPayload({
    required this.link,
    required this.emoji,
    required this.label,
    required this.items,
  });
  final LayerLink link;
  final String emoji;
  final String label;
  final List<Landmark> items;
}

/// 카테고리 칩 바로 아래에 펼쳐지는 inline dropdown — 그 카테고리에 들어있는
/// 실제 랜드마크들을 한눈에 보여 준다. 칩 아이콘과 마커 emoji 가 다를 수 있어서
/// (예: 일곱 교회 ✉️) "도시 5" 안에 무엇이 있는지 확인용.
class _LandmarkCategoryDropdown extends StatelessWidget {
  const _LandmarkCategoryDropdown({
    required this.categoryEmoji,
    required this.categoryLabel,
    required this.items,
    required this.onClose,
    required this.onLandmarkTap,
  });

  final String categoryEmoji;
  final String categoryLabel;
  final List<Landmark> items;
  final VoidCallback onClose;
  final ValueChanged<Landmark> onLandmarkTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBF5E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF8C6743), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ConstrainedBox(
          // 너무 길어지지 않게 max 높이 제한 — 안에 스크롤.
          constraints: const BoxConstraints(maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더 — 라벨 + 갯수 + 닫기 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
                child: Row(
                  children: [
                    Text(
                      categoryEmoji,
                      style: const TextStyle(fontSize: 18, height: 1.0),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$categoryLabel · ${items.length}곳',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF332A1D),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('닫기', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5A4326),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x22000000)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final lm = items[i];
                    final desc = (lm.description ?? '').trim();
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onLandmarkTap(lm),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                lm.emoji,
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lm.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF332A1D),
                                      ),
                                    ),
                                    if (desc.isNotEmpty)
                                      Text(
                                        desc,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          height: 1.35,
                                          color: Color(0xFF6B5430),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Color(0xFF8C6743),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizChoiceCard extends StatelessWidget {
  const _QuizChoiceCard({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFEFD9A2) : const Color(0xFFFAF1DD);
    final border = selected ? const Color(0xFFB58A47) : const Color(0xFFD9C18B);
    final badgeBg = selected
        ? const Color(0xFFB58A47)
        : const Color(0xFFE5D2A8);
    final badgeFg = selected ? Colors.white : const Color(0xFF5A4326);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: badgeFg,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: const Color(0xFF332A1D),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Color(0xFFB58A47),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizResultDialog extends StatelessWidget {
  const _QuizResultDialog({
    required this.event,
    required this.questions,
    required this.selectedAnswers,
    required this.score,
  });

  final StoryEvent event;
  final List<QuizQuestion> questions;
  final List<int?> selectedAnswers;
  final int score;

  @override
  Widget build(BuildContext context) {
    final total = questions.length;
    final wrong = total - score;
    final didPass = score == total;
    final headerColor = didPass
        ? const Color(0xFF1F7A3A)
        : const Color(0xFFB58A47);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6EAD8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB58A47), width: 1.5),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    didPass ? Icons.emoji_events : Icons.fact_check_outlined,
                    color: headerColor,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      didPass ? '모두 정답!' : '결과 확인',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: headerColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF1DD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD9C18B)),
                ),
                child: Row(
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF5A4326),
                        ),
                        children: [
                          TextSpan(
                            text: '$score',
                            style: TextStyle(fontSize: 28, color: headerColor),
                          ),
                          const TextSpan(
                            text: ' / ',
                            style: TextStyle(fontSize: 18),
                          ),
                          TextSpan(
                            text: '$total',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _ScorePill(
                            label: '정답',
                            count: score,
                            color: const Color(0xFF1F7A3A),
                          ),
                          _ScorePill(
                            label: '오답',
                            count: wrong,
                            color: const Color(0xFFB0392F),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < questions.length; i++)
                        _QuizReviewItem(
                          index: i,
                          question: questions[i],
                          userAnswer: selectedAnswers[i],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB58A47),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _QuizReviewItem extends StatelessWidget {
  const _QuizReviewItem({
    required this.index,
    required this.question,
    required this.userAnswer,
  });

  final int index;
  final QuizQuestion question;
  final int? userAnswer;

  @override
  Widget build(BuildContext context) {
    final isCorrect = userAnswer == question.answerIndex;
    final accent = isCorrect
        ? const Color(0xFF1F7A3A)
        : const Color(0xFFB0392F);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9C18B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Q${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Color(0xFF5A4326),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect ? '정답' : '오답',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question.question,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: Color(0xFF332A1D),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var ci = 0; ci < question.choices.length; ci++)
            _ReviewChoiceRow(
              index: ci,
              text: question.choices[ci],
              isCorrect: ci == question.answerIndex,
              isUserPick: ci == userAnswer,
            ),
          if ((question.explanation ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE0C5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCBB58A).withValues(alpha: 0.6),
                ),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(
                      text: '해설  ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    TextSpan(text: question.explanation!.trim()),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.emoji,
    required this.active,
    required this.onTap,
    this.count,
  });
  final String label;
  final String emoji;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : const Color(0xFF3D2A14);
    final countFg = active ? const Color(0xFFE8D7B0) : const Color(0xFF8C5A2E);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8C5A2E) : const Color(0xF2FFFBEF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? const Color(0xFF8C5A2E) : const Color(0xFFB89A66),
              width: 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 3),
                Text(
                  '+$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: countFg,
                    height: 1.0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewChoiceRow extends StatelessWidget {
  const _ReviewChoiceRow({
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.isUserPick,
  });

  final int index;
  final String text;
  final bool isCorrect;
  final bool isUserPick;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Widget marker;
    FontWeight weight;
    if (isCorrect) {
      textColor = const Color(0xFF1F7A3A);
      marker = const Icon(
        Icons.check_circle,
        size: 16,
        color: Color(0xFF1F7A3A),
      );
      weight = FontWeight.w800;
    } else if (isUserPick) {
      textColor = const Color(0xFFB0392F);
      marker = const Icon(Icons.cancel, size: 16, color: Color(0xFFB0392F));
      weight = FontWeight.w700;
    } else {
      textColor = const Color(0xFF7A6748);
      marker = const Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: Color(0xFFB89F75),
      );
      weight = FontWeight.w500;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: marker),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${index + 1}. $text',
              style: TextStyle(
                color: textColor,
                fontWeight: weight,
                fontSize: 12.6,
                height: 1.4,
              ),
            ),
          ),
          if (isUserPick && !isCorrect)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text(
                '내 답',
                style: TextStyle(
                  color: Color(0xFFB0392F),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 인물 step 2 의 "N명 다음" 작은 핀 — 패널 핸들 좌측에 표시. 인물 1명 이상
/// 선택 시 노출되며, 누르면 step 3 진입 + 사건 reveal 시작.
class _CharacterNextPill extends StatelessWidget {
  const _CharacterNextPill({required this.count, required this.onPressed});
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF8C5A2E),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count명 다음',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택 진행 단계 stepper — 우측 상단 1-2-3 동그라미 + 활성 단계 설명.
/// - 활성(=현재 진행 중): 초록
/// - 완료(=이전 단계, 클릭 시 그 단계로 돌아가며 reset): 노랑
/// - 미진입(=미래 단계, 클릭 비활성): 갈색
/// 같은 step 을 다시 누르면 그 단계 진행 내역만 초기화.
class _SelectionStepper extends StatelessWidget {
  const _SelectionStepper({
    required this.currentStep,
    required this.mode,
    required this.onStepTap,
  });

  final int currentStep;
  final _SelectionMode? mode;
  final ValueChanged<int> onStepTap;

  static const Color _activeColor = Color(0xFF2E8B57); // 초록
  static const Color _doneColor = Color(0xFFE8A33D); // 노랑
  static const Color _futureColor = Color(0xFF8C6743); // 갈색

  Color _colorFor(int step) {
    if (step == currentStep) return _activeColor;
    if (step < currentStep) return _doneColor;
    return _futureColor;
  }

  @override
  Widget build(BuildContext context) {
    // 세로 모드: 3 dots + ? 버튼만 노출. 상세 설명은 ? 버튼 탭으로 팝업에서 본다.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB89A66), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 3; i++) ...[
            _StepDot(
              number: i,
              color: _colorFor(i),
              enabled: i <= currentStep,
              onTap: () => onStepTap(i),
            ),
            if (i < 3)
              Container(
                width: 8,
                height: 1.4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: i < currentStep ? _doneColor : _futureColor,
              ),
          ],
          const SizedBox(width: 6),
          _StepperHelpButton(onTap: () => _showStepperHelp(context)),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final int number;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 1.0 : 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stepper 옆 동그란 ? 버튼 — 클릭 시 단계별 도움말 팝업.
class _StepperHelpButton extends StatelessWidget {
  const _StepperHelpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFF5E9C8),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF8C6743), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            '?',
            style: TextStyle(
              color: Color(0xFF8C6743),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// 양피지 톤의 단계별 도움말 팝업. 사용자가 stepper 의 ? 를 누르면 등장.
void _showStepperHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    builder: (dialogCtx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFB89A66), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8A33D),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '여행 단계 안내',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3D2A14),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF8C6743),
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 1,
                  color: const Color(0xFFD9C9A2),
                  margin: const EdgeInsets.only(bottom: 14),
                ),
                const _HelpStep(
                  number: 1,
                  title: '시대 + 보는 방법 선택',
                  body:
                      '먼저 여행할 시대를 한 가지 고르세요. 그 다음 「장소에서 시작」 또는 '
                      '「인물과 걷기」 두 보는 방법 중 하나를 선택합니다.',
                ),
                const SizedBox(height: 12),
                const _HelpStep(
                  number: 2,
                  title: '장소 또는 인물 선택',
                  body:
                      '「장소에서 시작」을 골랐다면 지도 위 폴리곤이나 핀을 눌러 한 지역을 '
                      '고르세요. 「인물과 걷기」를 골랐다면 등장 인물을 한 명 이상 고른 뒤 '
                      '「다음」 버튼을 누르면 다음 단계로 넘어갑니다.',
                ),
                const SizedBox(height: 12),
                const _HelpStep(
                  number: 3,
                  title: '사건 선택',
                  body:
                      '선택한 지역 또는 인물에 얽힌 사건들이 시간 순서대로 지도에 핀으로 '
                      '박힙니다. 사건 카드를 누르면 자세한 이야기 페이지로 이동합니다.',
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5E9C8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFE8A33D),
                      width: 1,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 단계 동그라미로 자유롭게 이동',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B4A2A),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '동그라미를 눌러 단계를 옮길 수 있어요. 색깔 의미는:',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF3D2A14),
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: 8),
                      _ColorLegendRow(
                        color: Color(0xFF2E8B57),
                        label: '초록 — 지금 진행 중인 단계',
                      ),
                      _ColorLegendRow(
                        color: Color(0xFFE8A33D),
                        label: '노랑 — 이미 끝낸 단계 (눌러서 돌아갈 수 있음)',
                      ),
                      _ColorLegendRow(
                        color: Color(0xFF8C6743),
                        label: '갈색 — 아직 진행하지 않은 단계 (잠금)',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '동그라미를 누르면 그 단계로 돌아가며 이후 선택은 모두 초기화됩니다.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF6B4A2A),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({
    required this.number,
    required this.title,
    required this.body,
  });
  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF8C6743),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3D2A14),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF5C4128),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorLegendRow extends StatelessWidget {
  const _ColorLegendRow({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF3D2A14),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
