// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Project imports:
import '../models/era.dart';
import '../models/quiz_question.dart';
import '../models/story_event.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../utils/scene_asset_loader.dart';
import '../widgets/bible_reader_page.dart';
import '../widgets/event_detail_page.dart';
import '../widgets/font_scale_bottom_sheet.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/parchment_texture_layer.dart';
import '../widgets/person_panel.dart';
import '../widgets/profile_tab_page.dart';
import '../widgets/search_bottom_sheet.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/story_map_panel.dart';
import '../widgets/story_selection_panel.dart';
import '../widgets/weekly_tab_page.dart';

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
  PersonSortMode _personSortMode = PersonSortMode.eraOrder;
  int _selectionStep = 1;
  StorySelectionPanelStage _selectionPanelStage =
      StorySelectionPanelStage.expanded;
  double _selectionSheetExtent = _selectionSheetExpandedSize;
  Set<String> _draftSelectedPersonIds = <String>{};

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

  Set<String> _sanitizeDraftSelectedPersonIds(StoryState state) {
    return _draftSelectedPersonIds
        .where((id) => state.persons.any((person) => person.id == id))
        .toSet();
  }

  Map<String, Color> _draftPersonColors(StoryState state) {
    final selectedIds = _sanitizeDraftSelectedPersonIds(state).toList();
    final next = <String, Color>{};
    for (var i = 0; i < selectedIds.length; i++) {
      next[selectedIds[i]] =
          _draftSelectionPalette[i % _draftSelectionPalette.length];
    }
    return next;
  }

  Color _colorForDraftPerson(String personId, StoryState state) {
    return _draftPersonColors(state)[personId] ?? const Color(0xFF8E7B61);
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

  bool _hasPendingPersonSelectionChanges(StoryState state) {
    final sanitizedDraft = _sanitizeDraftSelectedPersonIds(state);
    return !_sameStringSet(sanitizedDraft, state.selectedPersonIds);
  }

  List<StoryEvent> _timelineForSelectedPersons(
    StoryState state,
    Set<String> selectedPersonIds,
  ) {
    final filtered = state.events.where((event) {
      return event.personIds.any(selectedPersonIds.contains);
    }).toList();

    filtered.sort((a, b) {
      final cmp = a.timeSortKey.compareTo(b.timeSortKey);
      if (cmp != 0) {
        return cmp;
      }
      return a.id.compareTo(b.id);
    });
    return filtered;
  }

  bool _canOpenSelectionStep(int step, StoryState state) {
    if (step <= 1) {
      return true;
    }
    if (step == 2) {
      return state.selectedEraId != null;
    }
    return state.selectedPersonIds.isNotEmpty &&
        !_hasPendingPersonSelectionChanges(state);
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
      _draftSelectedPersonIds = nextState.selectedPersonIds.toSet();
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
      _draftSelectedPersonIds = nextState.selectedPersonIds.toSet();
    });
  }

  void _toggleDraftPerson(String personId) {
    setState(() {
      final next = {..._draftSelectedPersonIds};
      if (next.contains(personId)) {
        next.remove(personId);
      } else {
        next.add(personId);
      }
      _draftSelectedPersonIds = next;
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
        final sanitizedDraft = _sanitizeDraftSelectedPersonIds(state);
        _draftSelectedPersonIds = _selectionStep == 3
            ? state.selectedPersonIds.toSet()
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
      _draftSelectedPersonIds = state.selectedPersonIds.toSet();
      _selectionStep = 2;
    });
  }

  void _proceedFromPersonStep() {
    final state = ref.read(storyControllerProvider);
    final sanitizedDraft = _sanitizeDraftSelectedPersonIds(state);
    if (sanitizedDraft.isEmpty) {
      return;
    }
    ref
        .read(storyControllerProvider.notifier)
        .setSelectedPersons(sanitizedDraft);
    final viewportSize = MediaQuery.sizeOf(context);
    final collapsedExtent = _sheetSizeForStage(
      viewportSize,
      StorySelectionPanelStage.collapsed,
    );
    setState(() {
      _draftSelectedPersonIds = sanitizedDraft;
      _selectionStep = 3;
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
          _draftSelectedPersonIds = nextState.selectedPersonIds.toSet();
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
    setState(() {
      _selectionStep = 3;
      _draftSelectedPersonIds = state.selectedPersonIds.toSet();
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

  void _handleSelectionPanelEventSelect(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }

    final viewportSize = MediaQuery.sizeOf(context);
    final targetSheetExtent = _sheetFocusSizeForSelectedEvent(viewportSize);

    setState(() {
      _selectionStep = 3;
      _draftSelectedPersonIds = state.selectedPersonIds.toSet();
      _selectionPanelStage = StorySelectionPanelStage.collapsed;
      _selectionSheetExtent = targetSheetExtent;
    });
    controller.selectEvent(event.id);

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
      _draftSelectedPersonIds = state.selectedPersonIds.toSet();
    });
    _openEventDetailPage(event);
  }

  void _closeSelectedEventPopup() {
    ref.read(storyControllerProvider.notifier).selectEvent(null);
  }

  Future<void> _openEventDetailPage(StoryEvent event) async {
    final sceneAssetsFuture = _sceneAssetLoader.loadForEvent(event);
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
        .markEventCompleted(eventId: eventId, score: score, isCompleted: true);
    await _profileTabKey.currentState?.refreshProgressAfterQuizCompletion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final timeline = _timelineForSelectedPersons(
      state,
      state.selectedPersonIds,
    );
    final testamentEras =
        state.eras
            .where((era) => _eraTestament(era) == state.selectedTestament)
            .toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final selectedEra = state.eras
        .where((era) => era.id == state.selectedEraId)
        .firstOrNull;
    final avatarByPersonId = <String, String>{
      for (final person in state.persons) person.id: person.avatarAssetPath,
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
              events: timeline,
              selectedEventId: state.selectedEventId,
              onSelectEvent: _handleEventSelect,
              onCloseSelectedCallout: _closeSelectedEventPopup,
              onOpenDetail: _openEventDetail,
              colorForPerson: controller.colorForPerson,
              avatarAssetForPerson: (personId) =>
                  avatarByPersonId[personId] ?? '',
              selectedPersonIds: state.selectedPersonIds,
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
                        persons: state.persons,
                        personSortMode: _personSortMode,
                        onPersonSortModeChanged: (mode) {
                          setState(() {
                            _personSortMode = mode;
                          });
                        },
                        draftSelectedPersonIds: _sanitizeDraftSelectedPersonIds(
                          state,
                        ),
                        onToggleDraftPerson: _toggleDraftPerson,
                        committedSelectedPersonIds: state.selectedPersonIds,
                        hasPendingPersonChanges:
                            _hasPendingPersonSelectionChanges(state),
                        colorForDraftPerson: (personId) =>
                            _colorForDraftPerson(personId, state),
                        colorForCommittedPerson: controller.colorForPerson,
                        events: timeline,
                        selectedEventId: state.selectedEventId,
                        completedEventIds: state.completedEventIds,
                        onSelectEvent: _handleSelectionPanelEventSelect,
                        onNextFromEra: _proceedFromEraStep,
                        onNextFromPersons: _proceedFromPersonStep,
                        onStartQuiz: () {
                          final eventId = state.selectedEventId;
                          if (eventId == null) {
                            return;
                          }
                          _startQuiz(eventId);
                        },
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
                        topFontScaleButton(
                          onTap: () => showFontScaleSheet(context),
                        ),
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
