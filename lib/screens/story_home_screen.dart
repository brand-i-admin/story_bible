import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/era.dart';
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

  /// Step 3 에서 사용자가 체크박스로 고르고 있는 이벤트 id — 아직 커밋 전.
  /// "다음" 을 눌러야 `controller.setDisplayedEvents` 로 커밋되어 지도 핀/화살표
  /// 애니메이션이 실제로 시작된다.
  Set<String> _draftDisplayedEventIds = <String>{};

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
    setState(() {
      final next = {..._draftSelectedCharacterCodes};
      if (next.contains(characterId)) {
        next.remove(characterId);
      } else {
        next.add(characterId);
      }
      _draftSelectedCharacterCodes = next;
    });
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
    setState(() {
      final next = {..._draftDisplayedEventIds};
      if (next.contains(eventId)) {
        next.remove(eventId);
      } else {
        next.add(eventId);
      }
      _draftDisplayedEventIds = next;
    });
  }

  void _selectAllDraftDisplayedEvents(List<StoryEvent> availableEvents) {
    setState(() {
      _draftDisplayedEventIds = availableEvents.map((e) => e.id).toSet();
    });
  }

  void _deselectAllDraftDisplayedEvents() {
    setState(() {
      _draftDisplayedEventIds = <String>{};
    });
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
    bool didPass = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final question = questions[currentIndex];
            final isLast = currentIndex == questions.length - 1;
            final canMoveNext = selectedAnswers[currentIndex] != null;

            return Dialog(
              backgroundColor: const Color(0xFFF6EAD8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.title} - 퀴즈',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${currentIndex + 1} / ${questions.length}'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question.question,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...question.choices.asMap().entries.map((entry) {
                                final index = entry.key;
                                final choice = entry.value;
                                return RadioListTile<int>(
                                  dense: true,
                                  value: index,
                                  groupValue: selectedAnswers[currentIndex],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(() {
                                      selectedAnswers[currentIndex] = value;
                                    });
                                  },
                                  title: Text(
                                    choice,
                                    style: const TextStyle(
                                      color: Color(0xFF332A1D),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (currentIndex > 0)
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  currentIndex -= 1;
                                });
                              },
                              child: const Text('이전'),
                            ),
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
                                    didPass = score == questions.length;

                                    await showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => ParchmentDialog(
                                        title: '제출 결과',
                                        subtitle: didPass
                                            ? '총 ${questions.length}문제 중 $score문제를 맞췄습니다.\n모든 문제 정답입니다.'
                                            : '총 ${questions.length}문제 중 $score문제를 맞췄습니다.',
                                        actions: [
                                          ParchmentDialogActionButton(
                                            label: '확인',
                                            style: ParchmentDialogActionStyle
                                                .secondary,
                                            onTap: () => Navigator.of(
                                              dialogContext,
                                            ).pop(),
                                          ),
                                        ],
                                        child: const SizedBox.shrink(),
                                      ),
                                    );

                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.of(context).pop();
                                  },
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
              avatarAssetForCharacter: (characterCode) =>
                  avatarByCharacterCode[characterCode] ?? '',
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
            ),
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
              const selectionButtonForeground = Color(0xFFF8EED9);
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
