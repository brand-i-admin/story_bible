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
import '../theme/tokens.dart';
import '../utils/scene_asset_loader.dart';
import '../widgets/bible_reader_page.dart';
import '../widgets/character_panel.dart';
import '../widgets/event_detail_page.dart';
import '../widgets/font_scale_bottom_sheet.dart';
import '../widgets/notification/notification_bell_button.dart';
import '../widgets/notification/notification_deep_link.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/parchment_texture_layer.dart';
import '../widgets/profile_tab_page.dart';
import '../widgets/proposal/pastor_gate_dialog.dart';
import '../widgets/search_bottom_sheet.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/story_map_panel.dart';
import '../widgets/story_selection_panel.dart';
import '../widgets/weekly_tab_page.dart';
import 'notification_history_screen.dart';
import 'proposal_board_screen.dart';
import 'proposal_detail_screen.dart';

class StoryHomeScreen extends ConsumerStatefulWidget {
  const StoryHomeScreen({super.key});

  @override
  ConsumerState<StoryHomeScreen> createState() => _StoryHomeScreenState();
}

class _StoryHomeScreenState extends ConsumerState<StoryHomeScreen> {
  static const double _selectionSheetCollapsedSize = 0.16;
  static const double _selectionSheetExpandedSize = 0.60;
  final StoryMapPanelController _mapPanelController = StoryMapPanelController();
  final ScrollController _selectionPanelScrollController = ScrollController();
  final GlobalKey<ProfileTabPageState> _profileTabKey =
      GlobalKey<ProfileTabPageState>();
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();
  ProviderSubscription<User?>? _authUserSubscription;
  CharacterSortMode _characterSortMode = CharacterSortMode.eraOrder;
  int _selectionStep = 1;
  StorySelectionPanelStage _selectionPanelStage =
      StorySelectionPanelStage.expanded;
  double _selectionSheetExtent = _selectionSheetExpandedSize;
  Set<String> _draftSelectedCharacterCodes = <String>{};

  /// Step 3 에서 사용자가 체크박스로 고르고 있는 이벤트 id.
  /// 토글 즉시 `controller.setDisplayedEvents` 로 반영되어 지도에 핀이 박힌다
  /// (step 2 인물 토글과 같은 패턴). "다음" 버튼은 단순히 선택 패널을 접는
  /// 역할만 한다.
  Set<String> _draftDisplayedEventIds = <String>{};

  /// 좌측 "랜드마크 목록" 슬라이드인 패널 열림 여부.
  bool _landmarkPanelOpen = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
    return baseCharacterTimeline
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

  double _sheetMaxSizeFor(Size size) => _selectionSheetExpandedSize;

  double _sheetCollapsedPeekSizeFor(Size size) => _selectionSheetCollapsedSize;

  double _sheetSizeForStage(Size size, StorySelectionPanelStage stage) {
    return switch (stage) {
      StorySelectionPanelStage.collapsed => _sheetCollapsedPeekSizeFor(size),
      StorySelectionPanelStage.half => _sheetMaxSizeFor(size),
      StorySelectionPanelStage.expanded => _sheetMaxSizeFor(size),
    };
  }

  double _sheetFocusSizeForSelectedEvent(Size size) {
    return _sheetCollapsedPeekSizeFor(size);
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
    // 지도 미리보기 path 가 step 2 (인물 선택) 에서 "다음" 누르기 전에도 즉시
    // 반응하도록 controller state 도 같이 업데이트한다. setSelectedCharacters
    // 는 charactersChanged 가 true 일 때만 displayedEventIds 를 리셋하므로
    // 같은 set 다시 호출해도 step 3 commit 상태가 유지된다.
    ref.read(storyControllerProvider.notifier).setSelectedCharacters(next);
  }

  void _animateSelectionPanelToStage(StorySelectionPanelStage stage) {
    final targetExtent = stage == StorySelectionPanelStage.collapsed
        ? _selectionSheetCollapsedSize
        : _selectionSheetExpandedSize;
    setState(() {
      _selectionPanelStage = stage;
      _selectionSheetExtent = targetExtent;
    });
  }

  void _collapseSelectionPanel() {
    _animateSelectionPanelToStage(StorySelectionPanelStage.collapsed);
  }

  void _expandSelectionPanelToHalf() {
    _animateSelectionPanelToStage(StorySelectionPanelStage.expanded);
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

  void _toggleSelectionPanelFromTopButton() {
    if (_selectionPanelStage == StorySelectionPanelStage.collapsed) {
      _expandSelectionPanelToHalf();
      return;
    }
    _collapseSelectionPanel();
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

  void _proceedFromCharacterStep() {
    final state = ref.read(storyControllerProvider);
    final sanitizedDraft = _sanitizeDraftSelectedCharacterCodes(state);
    if (sanitizedDraft.isEmpty) {
      return;
    }
    ref
        .read(storyControllerProvider.notifier)
        .setSelectedCharacters(sanitizedDraft);
    // 인물 커밋으로 displayedEventIds 가 컨트롤러에서 리셋된다.
    // Step 3 진입 시 draft 도 깨끗하게 시작.
    setState(() {
      _draftSelectedCharacterCodes = sanitizedDraft;
      _draftDisplayedEventIds = <String>{};
      _selectionStep = 3;
      // 기존 "즉시 collapse" 동작 제거 — 사용자가 Step 3 에서 체크박스로
      // 사건을 골라야 하므로 패널을 열어둔 채로 둔다.
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
        builder: (_) => WeeklyTabPage(
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

  Future<void> _openSearchSheet() async {
    await showEventSearchSheet(
      context: context,
      onResultSelected: (event) {
        if (!mounted) {
          return;
        }
        final nextState = ref.read(storyControllerProvider);
        setState(() {
          _selectionStep = 3;
          _draftSelectedCharacterCodes = nextState.selectedCharacterCodes
              .toSet();
        });
        _handleEventSelect(event.id);
      },
    );
  }

  void _handleEventSelect(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    final viewportSize = MediaQuery.sizeOf(context);
    final collapsedExtent = _sheetFocusSizeForSelectedEvent(viewportSize);
    controller.selectEvent(event.id);
    // 지도에 이 사건이 아직 커밋 표시되지 않았다면(예: 검색 결과에서 진입)
    // displayedEventIds + draft 모두에 추가해 지도에 핀이 뜨도록.
    if (!state.displayedEventIds.contains(event.id)) {
      final nextCommitted = {...state.displayedEventIds, event.id};
      controller.setDisplayedEvents(nextCommitted);
      _draftDisplayedEventIds = {..._draftDisplayedEventIds, event.id};
    }
    setState(() {
      _selectionStep = 3;
      _draftSelectedCharacterCodes = state.selectedCharacterCodes.toSet();
      _selectionPanelStage = StorySelectionPanelStage.collapsed;
      _selectionSheetExtent = collapsedExtent;
    });
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

  /// "현 지도에서 검색" 버튼이 눌리면 지도 패널이 콜백으로 viewport 가운데 80%
  /// 박스를 넘겨 준다. 컨트롤러는 캐시된 사건 풀에서 박스 안 사건들을
  /// 골라 viewportSearchResults 로 채운다 — 패널이 그걸 별도 핀 레이어로 그림.
  Future<void> _handleViewportSearch({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    await ref
        .read(storyControllerProvider.notifier)
        .searchEventsInViewport(
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
        );
    if (!mounted) {
      return;
    }
    final hits = ref.read(storyControllerProvider).viewportSearchResults;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          hits.isEmpty
              ? '이 영역에는 표시할 이야기가 없어요.'
              : '${hits.length}개의 이야기를 찾았어요. 핀을 눌러보세요.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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
    final state = ref.read(storyControllerProvider);
    final eraNamesByCode = <String, String>{
      for (final era in state.eras) era.code: era.name,
    };
    final eraNames = landmark.eraCodes
        .map((code) => eraNamesByCode[code] ?? code)
        .toList(growable: false);

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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((landmark.description ?? '').trim().isNotEmpty)
                Text(
                  landmark.description!,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              if (eraNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in eraNames)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEDFC4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFB89A66),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3D2A14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
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

  /// 현재 선택된 시대(selectedEraId) + 카테고리 필터 기준으로 노출할 랜드마크
  /// 리스트를 반환. 시대 미선택 → 빈 리스트. 카테고리 필터가 비어 있으면 모든
  /// 카테고리 통과.
  List<Landmark> _activeLandmarksForEra(StoryState state) {
    final eraId = state.selectedEraId;
    if (eraId == null) {
      return const [];
    }
    final eraCode = state.eras
        .where((era) => era.id == eraId)
        .firstOrNull
        ?.code;
    if (eraCode == null || eraCode.isEmpty) {
      return const [];
    }
    final categories = state.selectedLandmarkCategories;
    return state.landmarks
        .where((l) {
          if (!l.eraCodes.contains(eraCode)) {
            return false;
          }
          if (categories.isEmpty) {
            return true;
          }
          final cat = l.category;
          return cat != null && categories.contains(cat);
        })
        .toList(growable: false);
  }

  Future<void> _openEventDetailPage(StoryEvent event) async {
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
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailPage(
          event: event,
          sceneAssetsFuture: sceneAssetsFuture,
          onOpenBibleReader: (bookNo, chapterNo, verseNo) {
            if (!mounted) {
              return;
            }
            _openBibleReaderPopup(
              initialBookNo: bookNo,
              initialChapterNo: chapterNo,
              initialVerseNo: verseNo,
            );
          },
          onStartQuiz: _startQuiz,
        ),
      ),
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

  Future<void> _startQuiz(String eventId) async {
    final state = ref.read(storyControllerProvider);
    final repo = ref.read(storyRepositoryProvider);
    final isAuthenticated = ref.read(signedInUserProvider) != null;
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
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
          title: event.title,
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
          title: event.title,
          subtitle: '해당 사건의 퀴즈가 아직 준비되지 않았습니다.',
          actions: [
            ParchmentDialogActionButton(
              label: '닫기',
              style: ParchmentDialogActionStyle.secondary,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );
      return;
    }

    final selectedAnswers = List<int?>.filled(questions.length, null);
    int currentIndex = 0;
    int score = 0;

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
                              event.title,
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
                                            event: event,
                                            questions: questions,
                                            selectedAnswers: selectedAnswers,
                                            score: score,
                                          ),
                                    );

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

    if (!isAuthenticated) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비로그인 상태라 퀴즈 진행 상황은 저장되지 않아요.')),
      );
      return;
    }

    await ref
        .read(storyControllerProvider.notifier)
        .markEventCompleted(eventId: eventId, isCompleted: true);
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

    final mapCenter =
        selectedEra?.mapCenterLat != null && selectedEra?.mapCenterLng != null
        ? LatLng(selectedEra!.mapCenterLat!, selectedEra.mapCenterLng!)
        : null;

    final mapZoom = selectedEra?.mapZoom;
    final topInset = MediaQuery.of(context).padding.top;
    const outerMargin = 20.0;
    final mapCalloutTopObscuredPixels = topInset + 56;

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
                // 2) viewport 검색 결과는 다른 era 인물 코드도 포함될 수 있어
                //    state.characters 에 없는 경우가 흔하다. 이 경우 컨벤션
                //    경로 `assets/avatars_thumbs/{code}.png` 로 폴백 — 번들에
                //    실제 파일이 없으면 _AvatarImage 의 errorBuilder 가
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
              viewportSearchResults: state.viewportSearchResults,
              onSearchInViewport: _handleViewportSearch,
              onClearViewportSearch: () => ref
                  .read(storyControllerProvider.notifier)
                  .clearViewportSearchResults(),
              activeEraBoundaries: state.selectedEraId == null
                  ? const []
                  : state.eraBoundaries
                        .where((b) => b.eraId == state.selectedEraId)
                        .toList(growable: false),
              onLandmarkTap: _showLandmarkPopup,
              onMeasureResult: _showMeasureResult,
              // 그 시대의 모든 사건을 인물별 path 로 항상 보여 준다 (선택 인물
              // 진하게, 미선택 흐리게). 사용자가 step 3 에서 사건을 골라도 인물
              // 이동 경로 자체는 사라지면 안 되므로 displayedEventIds 와 무관하게
              // 미리보기를 켜둔다. 선택된 사건은 그 path 위에 핀으로 표시된다
              // (`_buildMarkers`).
              eraPreviewEvents: state.events,
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
          if (state.selectedEraId != null)
            Positioned(
              top: topInset + 56,
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
              ),
            ),
          // 좌측 "랜드마크 목록" 토글 버튼 + 슬라이드인 패널.
          if (state.selectedEraId != null)
            _LandmarkListSidePanel(
              landmarks: _activeLandmarksForEra(state),
              isOpen: _landmarkPanelOpen,
              onToggle: () =>
                  setState(() => _landmarkPanelOpen = !_landmarkPanelOpen),
              onLandmarkTap: (lm) {
                _mapPanelController.focusLandmark(lm.latLng);
                _showLandmarkPopup(lm);
              },
            ),
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
              final selectionButtonIsOpen =
                  _selectionPanelStage == StorySelectionPanelStage.expanded;
              final selectionButtonBackground = selectionButtonIsOpen
                  ? const Color(0xFF74A856)
                  : const Color(0xFFD2873E);
              final selectionButtonBorder = selectionButtonIsOpen
                  ? const Color(0xFFD4E8BC)
                  : const Color(0xFFF1C98A);
              const selectionButtonForeground = AppColors.fgOnDark;
              final selectionButtonShadow = [
                BoxShadow(
                  color: selectionButtonIsOpen
                      ? const Color(0x3977A85A)
                      : const Color(0x33D2873E),
                  blurRadius: selectionButtonIsOpen ? 9 : 8,
                  offset: const Offset(0, 2),
                ),
              ];

              return Stack(
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ParchmentTextureLayer(
                        opacity: 0.075,
                        tint: Color(0xFFB88A57),
                      ),
                    ),
                  ),
                  Positioned(
                    left: sheetHorizontalMargin,
                    right: sheetHorizontalMargin,
                    bottom: 0,
                    child: AnimatedContainer(
                      key: const ValueKey<String>('selection-sheet'),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: sheetHeight,
                      child: StorySelectionPanel(
                        scrollController: _selectionPanelScrollController,
                        step: _selectionStep,
                        panelStage: _selectionPanelStage,
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
                        committedDisplayedEventIds: state.displayedEventIds,
                        onToggleDisplayedEvent: _toggleDraftDisplayedEvent,
                        onSelectAllDisplayedEvents: () =>
                            _selectAllDraftDisplayedEvents(characterTimeline),
                        onDeselectAllDisplayedEvents:
                            _deselectAllDraftDisplayedEvents,
                        onCommitDisplayedEvents: _proceedFromStoryStep,
                        onNextFromEra: _proceedFromEraStep,
                        onNextFromCharacters: _proceedFromCharacterStep,
                      ),
                    ),
                  ),
                  Positioned(
                    right: outerMargin,
                    top: sideTop,
                    child: Column(
                      children: [
                        mapControlButton(
                          icon: Icons.search,
                          tooltip: '검색',
                          onTap: _openSearchSheet,
                        ),
                        const SizedBox(height: 8),
                        mapControlButton(
                          icon: Icons.add,
                          tooltip: '줌 인',
                          onTap: _mapPanelController.zoomIn,
                        ),
                        const SizedBox(height: 6),
                        mapControlButton(
                          icon: Icons.remove,
                          tooltip: '줌 아웃',
                          onTap: _mapPanelController.zoomOut,
                        ),
                        const SizedBox(height: 6),
                        mapControlButton(
                          icon: Icons.fast_forward,
                          tooltip: 'Skip',
                          onTap: _mapPanelController.skipAnimation,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: outerMargin,
                    top: sideTop,
                    child: Row(
                      children: [
                        topUtilityButton(
                          label: '사건선택',
                          selected: selectionButtonIsOpen,
                          backgroundColor: selectionButtonBackground,
                          borderColor: selectionButtonBorder,
                          foregroundColor: selectionButtonForeground,
                          boxShadow: selectionButtonShadow,
                          onTap: _toggleSelectionPanelFromTopButton,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '금주 인물', onTap: _openWeeklyTab),
                        const SizedBox(width: 8),
                        topUtilityButton(
                          label: '성경',
                          onTap: _openBibleReaderPopup,
                        ),
                        const SizedBox(width: 8),
                        topUtilityButton(label: '프로필', onTap: _openProfileTab),
                        const SizedBox(width: 8),
                        NotificationBellButton(
                          onNavigate: _handleNotificationTap,
                          onOpenHistory: _openNotificationHistory,
                        ),
                        const SizedBox(width: 8),
                        topFontScaleButton(
                          onTap: () => showFontScaleSheet(context),
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(width: 8),
                          topUtilityButton(
                            label: '이야기 등록',
                            onTap: _openProposalBoardOrGate,
                          ),
                        ],
                      ],
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
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

/// 지도 상단의 랜드마크 카테고리 필터 칩 가로 스크롤 바.
/// 비어 있으면 모든 카테고리 통과(전체 표시), 한 칩 누르면 그 카테고리만.
class _LandmarkCategoryChipsBar extends StatelessWidget {
  const _LandmarkCategoryChipsBar({
    required this.state,
    required this.onToggle,
    required this.onClear,
  });

  final StoryState state;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  // 키 = DB category, 값 = (이모지, 한국어 라벨).
  static const Map<String, (String, String)> _catMeta = {
    'city': ('🏛️', '도시'),
    'mountain': ('⛰️', '산'),
    'water': ('🌊', '물·강'),
    'wilderness': ('🏜️', '광야'),
    'battle': ('⚔️', '전투'),
    'temple': ('⛪', '성전'),
    'holy_site': ('🕊️', '거룩한 곳'),
    'tomb': ('⚰️', '무덤'),
    'monument': ('🪨', '기념비'),
    'prison': ('⛓️', '감옥'),
    'city_gate': ('🚪', '성문'),
    'region': ('🌍', '지역'),
    'island': ('🏝️', '섬'),
  };

  @override
  Widget build(BuildContext context) {
    // 시대별 활성 랜드마크에 실제 존재하는 카테고리만 칩으로 노출.
    final activeCategories = <String>{};
    final eraCode = state.eras
        .where((e) => e.id == state.selectedEraId)
        .firstOrNull
        ?.code;
    if (eraCode != null) {
      for (final l in state.landmarks) {
        if (l.eraCodes.contains(eraCode) && l.category != null) {
          activeCategories.add(l.category!);
        }
      }
    }
    if (activeCategories.isEmpty) {
      return const SizedBox.shrink();
    }
    final ordered = _catMeta.keys
        .where(activeCategories.contains)
        .toList(growable: false);

    final selected = state.selectedLandmarkCategories;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _CategoryChip(
            label: '전체',
            emoji: '✨',
            active: selected.isEmpty,
            onTap: onClear,
          ),
          for (final cat in ordered) ...[
            const SizedBox(width: 6),
            _CategoryChip(
              label: _catMeta[cat]!.$2,
              emoji: _catMeta[cat]!.$1,
              active: selected.contains(cat),
              onTap: () => onToggle(cat),
            ),
          ],
        ],
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
  });
  final String label;
  final String emoji;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8C5A2E) : const Color(0xF2FFFBEF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? const Color(0xFF8C5A2E) : const Color(0xFFB89A66),
              width: 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFF3D2A14),
                ),
              ),
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

/// 좌측에 슬라이드인 되는 랜드마크 목록 패널 + 토글 버튼.
class _LandmarkListSidePanel extends StatelessWidget {
  const _LandmarkListSidePanel({
    required this.landmarks,
    required this.isOpen,
    required this.onToggle,
    required this.onLandmarkTap,
  });

  final List<Landmark> landmarks;
  final bool isOpen;
  final VoidCallback onToggle;
  final ValueChanged<Landmark> onLandmarkTap;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        // 좌측 가장자리 토글 버튼 (지도가 살짝 보이도록 좌상단 비켜둠).
        Positioned(
          left: 10,
          top: topInset + 110,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFF8C5A2E)
                      : const Color(0xFFD2873E),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOpen ? Icons.close : Icons.list,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOpen ? '닫기' : '랜드마크 ${landmarks.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 슬라이드인 패널.
        if (isOpen)
          Positioned(
            left: 10,
            top: topInset + 150,
            bottom: 20,
            width: 280,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFFFFFBEF),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: landmarks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            '이 시대에 표시할 랜드마크가 없어요',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF3D2A14),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: landmarks.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: Color(0x22B89A66),
                          indent: 12,
                          endIndent: 12,
                        ),
                        itemBuilder: (context, index) {
                          final lm = landmarks[index];
                          return InkWell(
                            onTap: () => onLandmarkTap(lm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lm.emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lm.name,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF3D2A14),
                                          ),
                                        ),
                                        if ((lm.description ?? '')
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            lm.description!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF6B5239),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
