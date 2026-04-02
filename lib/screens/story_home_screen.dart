import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/era.dart';
import '../models/bible_verse.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/person.dart';
import '../models/person_study_progress.dart';
import '../models/saved_bible_verse.dart';
import '../models/story_event.dart';
import '../models/user_note.dart';
import '../models/quiz_question.dart';
import '../screens/profile_notes_screen.dart';
import '../screens/saved_verses_screen.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../widgets/person_panel.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/story_map_panel.dart';
import '../widgets/story_selection_panel.dart';

class StoryHomeScreen extends ConsumerStatefulWidget {
  const StoryHomeScreen({super.key});

  @override
  ConsumerState<StoryHomeScreen> createState() => _StoryHomeScreenState();
}

enum _ProfileContentTab { notes, verses, prayer }

class _StoryHomeScreenState extends ConsumerState<StoryHomeScreen> {
  static const int _intercessoryPrayerPageSize = 12;
  static const int _profilePreviewPageSize = 5;
  static const double _selectionSheetCollapsedSize = 0.16;
  static const double _selectionSheetExpandedSize = 0.60;
  final StoryMapPanelController _mapPanelController = StoryMapPanelController();
  final ScrollController _selectionPanelScrollController = ScrollController();
  final ScrollController _intercessoryPrayerScrollController =
      ScrollController();
  ProviderSubscription<User?>? _authUserSubscription;
  StateSetter? _profilePageSetState;
  static final RegExp _sceneFilenamePattern = RegExp(
    r'/scene_(\d+)\.(?:png|jpe?g|webp)$',
    caseSensitive: false,
  );
  static final RegExp _sceneCodeDigitsPattern = RegExp(r'(\d+)$');
  static final RegExp _sceneInvalidDirChars = RegExp(r'[\\/:*?"<>|]+');
  static final RegExp _sceneWhitespacePattern = RegExp(r'\s+');
  static final RegExp _sceneLooseNormalizePattern = RegExp(
    r"[\s_\-:·,./\\(){}\[\]']+",
  );
  PersonSortMode _personSortMode = PersonSortMode.eraOrder;
  int _selectionStep = 1;
  StorySelectionPanelStage _selectionPanelStage =
      StorySelectionPanelStage.expanded;
  double _selectionSheetExtent = _selectionSheetExpandedSize;
  Set<String> _draftSelectedPersonIds = <String>{};
  _WeeklyStudyData? _weeklyStudyData;
  String? _weeklySelectedEventId;
  final Set<String> _weeklyCheckedEventIds = <String>{};
  bool _weeklyLoading = false;
  String? _weeklyError;
  bool _weeklyShowShortPopup = true;
  String? _weeklyWeekKey;
  List<Person> _profileAllPeople = const [];
  Map<String, String> _profilePersonTestamentById = const {};
  AppUserProfile? _profileUser;
  Map<String, PersonStudyProgress> _profileStudyProgressByPersonId = const {};
  Map<String, int> _profilePersonTimelineOrderById = const {};
  _ProfileContentTab _profileContentTab = _ProfileContentTab.prayer;
  List<UserNote> _profileNotesPreview = const [];
  List<SavedBibleVerse> _profileSavedVersesPreview = const [];
  bool _profileNotesLoading = false;
  bool _profileSavedVersesLoading = false;
  String? _profileNotesError;
  String? _profileSavedVersesError;
  List<IntercessoryPrayerItem> _intercessoryPrayerItems = const [];
  bool _intercessoryPrayerLoading = false;
  bool _intercessoryPrayerLoadingMore = false;
  bool _intercessoryPrayerHasNextPage = false;
  String? _intercessoryPrayerError;
  int _intercessoryPrayerPageIndex = 0;
  int _profileAttendanceStreak = 0;
  int _profileStudyStreak = 0;
  String _profileSelectedTestament = 'old';
  bool _profileLoading = false;
  String? _profileError;
  bool _subPageLoading = false;
  String _subPageLoadingLabel = '';
  bool _signingOut = false;
  List<String>? _assetManifestCache;
  final Map<String, List<String>> _sceneAssetsCache = <String, List<String>>{};

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
    _intercessoryPrayerScrollController.addListener(
      _handleIntercessoryPrayerScroll,
    );
  }

  @override
  void dispose() {
    _authUserSubscription?.close();
    _selectionPanelScrollController.dispose();
    _intercessoryPrayerScrollController
      ..removeListener(_handleIntercessoryPrayerScroll)
      ..dispose();
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
      setState(() {
        _profileUser = null;
        _profileStudyProgressByPersonId = const {};
        _profileContentTab = _ProfileContentTab.prayer;
        _profileNotesPreview = const [];
        _profileSavedVersesPreview = const [];
        _profileNotesLoading = false;
        _profileSavedVersesLoading = false;
        _profileNotesError = null;
        _profileSavedVersesError = null;
        _intercessoryPrayerItems = const [];
        _intercessoryPrayerLoading = false;
        _intercessoryPrayerLoadingMore = false;
        _intercessoryPrayerHasNextPage = false;
        _intercessoryPrayerError = null;
        _intercessoryPrayerPageIndex = 0;
        _profileAttendanceStreak = 0;
        _profileStudyStreak = 0;
        _profileError = null;
      });
      _profilePageSetState?.call(() {});
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
      await _loadProfilePeople(forceRefresh: true);
      if (!mounted) {
        return;
      }
      await ref
          .read(storyControllerProvider.notifier)
          .refreshCompletedEventIds();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _profilePageSetState?.call(() {});
    }
  }

  Future<void> _refreshProfileProgressAfterQuizCompletion() async {
    if (!mounted) {
      return;
    }
    if (_profileUser == null && _profileAllPeople.isEmpty) {
      return;
    }
    await _loadProfilePeople(forceRefresh: true);
    if (!mounted) {
      return;
    }
    _profilePageSetState?.call(() {});
  }

  void _handleIntercessoryPrayerScroll() {
    if (!_intercessoryPrayerScrollController.hasClients) {
      return;
    }
    if (_intercessoryPrayerLoading ||
        _intercessoryPrayerLoadingMore ||
        !_intercessoryPrayerHasNextPage) {
      return;
    }
    final position = _intercessoryPrayerScrollController.position;
    if (position.extentAfter < 180) {
      unawaited(_loadIntercessoryPrayerPage(loadMore: true));
    }
  }

  Future<void> _loadIntercessoryPrayerPage({bool loadMore = false}) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _intercessoryPrayerItems = const [];
        _intercessoryPrayerLoading = false;
        _intercessoryPrayerLoadingMore = false;
        _intercessoryPrayerHasNextPage = false;
        _intercessoryPrayerError = null;
        _intercessoryPrayerPageIndex = 0;
      });
      _profilePageSetState?.call(() {});
      return;
    }

    if (loadMore) {
      if (_intercessoryPrayerLoading ||
          _intercessoryPrayerLoadingMore ||
          !_intercessoryPrayerHasNextPage) {
        return;
      }
    }

    final nextPageIndex = loadMore ? _intercessoryPrayerPageIndex + 1 : 0;
    if (mounted) {
      setState(() {
        if (loadMore) {
          _intercessoryPrayerLoadingMore = true;
        } else {
          _intercessoryPrayerLoading = true;
          _intercessoryPrayerError = null;
        }
      });
    }

    try {
      final result = await ref
          .read(userRepositoryProvider)
          .fetchIntercessoryPrayerPage(
            pageIndex: nextPageIndex,
            pageSize: _intercessoryPrayerPageSize,
          );
      if (!mounted) {
        return;
      }
      final nextItems = loadMore
          ? <IntercessoryPrayerItem>[
              ..._intercessoryPrayerItems,
              ...result.items.where(
                (item) => _intercessoryPrayerItems.every(
                  (existing) => existing.id != item.id,
                ),
              ),
            ]
          : result.items;
      setState(() {
        _intercessoryPrayerItems = nextItems;
        _intercessoryPrayerHasNextPage = result.hasNextPage;
        _intercessoryPrayerPageIndex = result.pageIndex;
        _intercessoryPrayerLoading = false;
        _intercessoryPrayerLoadingMore = false;
      });
      _profilePageSetState?.call(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _intercessoryPrayerLoading = false;
        _intercessoryPrayerLoadingMore = false;
        _intercessoryPrayerError = '중보할 기도제목을 불러오지 못했습니다.\n$error';
      });
      _profilePageSetState?.call(() {});
    }
  }

  Future<void> _loadProfileNotesPreview({bool showLoading = true}) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileNotesPreview = const [];
        _profileNotesLoading = false;
        _profileNotesError = null;
      });
      _profilePageSetState?.call(() {});
      return;
    }

    if (mounted) {
      setState(() {
        if (showLoading) {
          _profileNotesLoading = true;
        }
        _profileNotesError = null;
      });
    }

    try {
      final result = await ref
          .read(userRepositoryProvider)
          .fetchUserNotesPage(
            userId: user.id,
            pageIndex: 0,
            pageSize: _profilePreviewPageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profileNotesPreview = result.items;
        _profileNotesLoading = false;
      });
      _profilePageSetState?.call(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileNotesLoading = false;
        _profileNotesError = '노트를 불러오지 못했습니다.\n$error';
      });
      _profilePageSetState?.call(() {});
    }
  }

  Future<void> _loadProfileSavedVersesPreview({bool showLoading = true}) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedVersesPreview = const [];
        _profileSavedVersesLoading = false;
        _profileSavedVersesError = null;
      });
      _profilePageSetState?.call(() {});
      return;
    }

    if (mounted) {
      setState(() {
        if (showLoading) {
          _profileSavedVersesLoading = true;
        }
        _profileSavedVersesError = null;
      });
    }

    try {
      final result = await ref
          .read(userRepositoryProvider)
          .fetchSavedVersesPage(
            userId: user.id,
            pageIndex: 0,
            pageSize: _profilePreviewPageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedVersesPreview = result.items;
        _profileSavedVersesLoading = false;
      });
      _profilePageSetState?.call(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedVersesLoading = false;
        _profileSavedVersesError = '저장한 말씀을 불러오지 못했습니다.\n$error';
      });
      _profilePageSetState?.call(() {});
    }
  }

  Future<void> _refreshProfileTabPreviews({bool showLoading = true}) async {
    await Future.wait([
      _loadProfileNotesPreview(showLoading: showLoading),
      _loadProfileSavedVersesPreview(showLoading: showLoading),
    ]);
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

  StoryEvent? get _weeklySelectedEvent {
    final data = _weeklyStudyData;
    if (data == null || _weeklySelectedEventId == null) {
      return null;
    }
    return data.events
        .where((event) => event.id == _weeklySelectedEventId)
        .firstOrNull;
  }

  DateTime _weekStartMonday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _weeklyKeyFor(DateTime monday) {
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  static const Map<String, String> _forcedWeeklyPersonCodeByWeekKey = {
    // Monday, February 23, 2026 week
    '2026-2-23': 'abraham',
  };

  int _seedFromKey(String key) {
    return key.codeUnits.fold<int>(
      0,
      (acc, value) => ((acc * 31) + value) & 0x7fffffff,
    );
  }

  Future<void> _showSubPageLoading(String label) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _subPageLoading = true;
      _subPageLoadingLabel = label;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  void _hideSubPageLoading() {
    if (!mounted || !_subPageLoading) {
      return;
    }
    setState(() {
      _subPageLoading = false;
      _subPageLoadingLabel = '';
    });
  }

  Future<void> _openWeeklyTab() async {
    await _showSubPageLoading('금주 인물 여는 중...');
    try {
      final monday = _weekStartMonday(DateTime.now());
      final weekKey = _weeklyKeyFor(monday);
      if (_weeklyStudyData == null || _weeklyWeekKey != weekKey) {
        setState(() {
          _weeklyLoading = true;
          _weeklyError = null;
        });

        try {
          var state = ref.read(storyControllerProvider);
          if (state.eras.isEmpty) {
            await ref.read(storyControllerProvider.notifier).initialize();
            state = ref.read(storyControllerProvider);
          }

          if (state.eras.isEmpty) {
            throw StateError('시대 데이터를 불러오지 못했습니다.');
          }

          final repo = ref.read(storyRepositoryProvider);
          final eraBundles = await Future.wait(
            state.eras.map((era) async {
              final responses = await Future.wait([
                repo.fetchPersonsByEra(era.id),
                repo.fetchEventsByEra(era.id),
              ]);
              return (
                persons: responses[0] as List<Person>,
                events: responses[1] as List<StoryEvent>,
              );
            }),
          );

          final personById = <String, Person>{};
          final eventsByPersonId = <String, List<StoryEvent>>{};
          for (final bundle in eraBundles) {
            for (final person in bundle.persons) {
              personById.putIfAbsent(person.id, () => person);
            }
            for (final event in bundle.events) {
              for (final personId in event.personIds) {
                eventsByPersonId
                    .putIfAbsent(personId, () => <StoryEvent>[])
                    .add(event);
              }
            }
          }

          final candidates =
              personById.values
                  .where(
                    (person) =>
                        (eventsByPersonId[person.id] ?? const <StoryEvent>[])
                            .isNotEmpty,
                  )
                  .toList()
                ..sort((a, b) {
                  final order = a.displayOrder.compareTo(b.displayOrder);
                  if (order != 0) {
                    return order;
                  }
                  return a.name.compareTo(b.name);
                });
          if (candidates.isEmpty) {
            throw StateError('주간 추천 인물을 찾지 못했습니다.');
          }

          final forcedCode = _forcedWeeklyPersonCodeByWeekKey[weekKey];
          final forcedPerson = forcedCode == null
              ? null
              : candidates
                    .where((person) => person.code == forcedCode)
                    .firstOrNull;
          final weeklyPerson =
              forcedPerson ??
              candidates[_seedFromKey(weekKey) % candidates.length];
          final weeklyEvents =
              [...(eventsByPersonId[weeklyPerson.id] ?? const <StoryEvent>[])]
                ..sort((a, b) {
                  final cmp = a.timeSortKey.compareTo(b.timeSortKey);
                  if (cmp != 0) {
                    return cmp;
                  }
                  return a.id.compareTo(b.id);
                });
          final selectedEventId = weeklyEvents.isNotEmpty
              ? weeklyEvents.first.id
              : null;

          if (!mounted) {
            return;
          }
          setState(() {
            _weeklyStudyData = _WeeklyStudyData(
              person: weeklyPerson,
              events: weeklyEvents,
              weekStartMonday: monday,
            );
            _weeklyWeekKey = weekKey;
            _weeklySelectedEventId = selectedEventId;
            _weeklyCheckedEventIds.clear();
            _weeklyShowShortPopup = false;
            _weeklyLoading = false;
            _weeklyError = weeklyEvents.isEmpty ? '추천 인물의 이야기가 아직 없습니다.' : null;
          });
        } catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _weeklyLoading = false;
            _weeklyError = '주간 탭 데이터를 불러오지 못했습니다: $error';
          });
        }
      }

      final weekly = _weeklyStudyData;
      if (!mounted || weekly == null) {
        return;
      }

      final navigator = Navigator.of(context);
      final pushFuture = navigator.push(
        MaterialPageRoute<void>(
          builder: (pageContext) {
            return StatefulBuilder(
              builder: (pageContext, setPageState) {
                final state = ref.read(storyControllerProvider);
                final controller = ref.read(storyControllerProvider.notifier);
                final isAuthenticated = ref.read(signedInUserProvider) != null;
                final selectedEvent = _weeklySelectedEvent;
                final pageSelectedEvent = selectedEvent;
                return _SubPageScaffold(
                  title: '금주 인물',
                  compactBackOnly: true,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          child: _buildWeeklyBody(
                            state: state,
                            controller: controller,
                            isAuthenticated: isAuthenticated,
                            onSelectEvent: (eventId) {
                              setPageState(() {
                                _weeklySelectedEventId = eventId;
                                _weeklyShowShortPopup = true;
                              });
                            },
                            onToggleChecked: (eventId) {
                              setPageState(() {
                                if (_weeklyCheckedEventIds.contains(eventId)) {
                                  _weeklyCheckedEventIds.remove(eventId);
                                } else {
                                  _weeklyCheckedEventIds.add(eventId);
                                }
                              });
                            },
                            onStartQuiz: _startQuiz,
                          ),
                        ),
                      ),
                      if (pageSelectedEvent != null && _weeklyShowShortPopup)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 320,
                              child: _weeklyShortPopup(
                                event: pageSelectedEvent,
                                maxHeight: 232,
                                onClose: () {
                                  setPageState(() {
                                    _weeklyShowShortPopup = false;
                                  });
                                },
                                onOpenDetail: () {
                                  setPageState(() {
                                    _weeklyShowShortPopup = false;
                                  });
                                  _openEventDetailPage(pageSelectedEvent);
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
      _hideSubPageLoading();
      await pushFuture;
    } finally {
      _hideSubPageLoading();
    }
  }

  Future<void> _openProfileTab() async {
    await _showSubPageLoading('프로필 여는 중...');
    try {
      await _loadProfilePeople(forceRefresh: true);
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context);
      final pushFuture = navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Consumer(
            builder: (context, ref, __) => StatefulBuilder(
              builder: (context, setPageState) {
                _profilePageSetState = setPageState;
                final state = ref.watch(storyControllerProvider);
                final isAuthenticated = ref.watch(signedInUserProvider) != null;
                return _SubPageScaffold(
                  title: '프로필',
                  compactBackOnly: true,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: isAuthenticated
                            ? _buildProfileBody(
                                state: state,
                                isAuthenticated: true,
                              )
                            : ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 4.5,
                                  sigmaY: 4.5,
                                ),
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: 0.9,
                                    child: _buildProfileBody(
                                      state: state,
                                      isAuthenticated: false,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (!isAuthenticated)
                        Positioned.fill(
                          child: _lockedPreviewOverlay(
                            child: _InlineLoginPromptCard(
                              title: '프로필을 보려면 로그인이 필요해요',
                              description:
                                  '프로필, 노트, 저장한 말씀, 공부 기록은 로그인 후 사용할 수 있어요.',
                              onSignedIn: () async {
                                if (!mounted) {
                                  return;
                                }
                                await _loadProfilePeople(forceRefresh: true);
                                _profilePageSetState?.call(() {});
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      _hideSubPageLoading();
      await pushFuture;
      _profilePageSetState = null;
    } finally {
      _hideSubPageLoading();
    }
  }

  Future<void> _loadProfilePeople({bool forceRefresh = false}) async {
    if (!forceRefresh && (_profileAllPeople.isNotEmpty || _profileLoading)) {
      return;
    }
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });

    try {
      var state = ref.read(storyControllerProvider);
      if (state.eras.isEmpty) {
        await ref.read(storyControllerProvider.notifier).initialize();
        state = ref.read(storyControllerProvider);
      }
      if (state.eras.isEmpty) {
        throw StateError('시대 데이터를 불러오지 못했습니다.');
      }

      final user = ref.read(signedInUserProvider);
      final repo = ref.read(storyRepositoryProvider);
      final userRepo = ref.read(userRepositoryProvider);
      final peopleByEra = await Future.wait(
        state.eras.map((era) => repo.fetchPersonsByEra(era.id)),
      );
      final personTimelineOrderById = await repo.fetchPersonTimelineOrder();

      final personById = <String, Person>{};
      final testamentByPersonId = <String, String>{};
      for (var i = 0; i < state.eras.length; i++) {
        final era = state.eras[i];
        final eraPeople = peopleByEra[i];
        final testament = _eraTestament(era);
        for (final person in eraPeople) {
          personById.putIfAbsent(person.id, () => person);
          testamentByPersonId.putIfAbsent(person.id, () => testament);
        }
      }

      final allPeople = personById.values.toList()
        ..sort(
          (a, b) => _compareProfilePeople(
            a,
            b,
            timelineOrderById: personTimelineOrderById,
          ),
        );

      AppUserProfile? profile;
      var attendanceStreak = 0;
      var studyStreak = 0;
      Map<String, PersonStudyProgress> progressByPersonId = const {};

      if (user != null) {
        profile = await userRepo.ensureSignedInUser(user);
        attendanceStreak = await userRepo.fetchAttendanceStreak(user.id);
        studyStreak = await userRepo.fetchStudyStreak(user.id);
        final studyProgress = await userRepo.fetchPersonStudyProgress(
          userId: user.id,
          people: allPeople,
        );
        progressByPersonId = {
          for (final progress in studyProgress) progress.person.id: progress,
        };
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _profileAllPeople = allPeople;
        _profilePersonTestamentById = testamentByPersonId;
        _profileUser = profile;
        _profileStudyProgressByPersonId = progressByPersonId;
        _profilePersonTimelineOrderById = personTimelineOrderById;
        if (user == null) {
          _intercessoryPrayerItems = const [];
          _intercessoryPrayerHasNextPage = false;
          _intercessoryPrayerPageIndex = 0;
          _intercessoryPrayerError = null;
        }
        _profileAttendanceStreak = attendanceStreak;
        _profileStudyStreak = studyStreak;
        _profileLoading = false;
        _profileError = allPeople.isEmpty ? '인물 데이터가 없습니다.' : null;
      });
      if (user != null) {
        await Future.wait([
          _loadIntercessoryPrayerPage(),
          _refreshProfileTabPreviews(),
        ]);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileLoading = false;
        _profileError = '프로필 인물 데이터를 불러오지 못했습니다: $error';
      });
    }
  }

  Future<void> _openSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF5E9D6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final safeHeight =
            mediaQuery.size.height -
            mediaQuery.padding.top -
            mediaQuery.padding.bottom;
        final maxSheetHeight = math.min(
          mediaQuery.orientation == Orientation.landscape ? 520.0 : 560.0,
          safeHeight - 20,
        );
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(storyControllerProvider);
            final controller = ref.read(storyControllerProvider.notifier);
            final results = controller.searchResults();

            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                14,
                12,
                mediaQuery.viewInsets.bottom + 14,
              ),
              child: SizedBox(
                height: maxSheetHeight,
                child: Column(
                  children: [
                    TextFormField(
                      key: ValueKey(state.searchQuery),
                      initialValue: state.searchQuery,
                      autofocus: true,
                      onChanged: controller.setSearchQuery,
                      decoration: InputDecoration(
                        hintText: '단어/문장 검색...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (state.isSearching)
                      const SizedBox(
                        height: 28,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Expanded(
                      child: results.isEmpty
                          ? const Center(child: Text('검색 결과가 없습니다.'))
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final event = results[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(event.title),
                                  subtitle: Text(event.placeName ?? '-'),
                                  onTap: () async {
                                    await controller.selectSearchResult(event);
                                    if (mounted) {
                                      final nextState = ref.read(
                                        storyControllerProvider,
                                      );
                                      setState(() {
                                        _selectionStep = 3;
                                        _draftSelectedPersonIds = nextState
                                            .selectedPersonIds
                                            .toSet();
                                      });
                                    }
                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.of(context).pop();
                                    _handleEventSelect(event.id);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
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
    final shortStoryText = (event.shortStory ?? '').trim();
    final fallbackText = (event.story ?? event.summary ?? '').trim();
    final storyText = shortStoryText.isNotEmpty ? shortStoryText : fallbackText;
    final placeText = (event.placeName ?? '').trim();
    final yearText = event.startYear?.toString() ?? '-';
    final metaText = placeText.isEmpty ? yearText : '$placeText · $yearText';
    final sceneAssetsFuture = _loadSceneAssetsForEvent(event);
    final refs = event.bibleRefs;
    final moveTarget = _parseBibleNavigationTarget(event.bibleRefs.firstOrNull);

    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final currentState = ref.watch(storyControllerProvider);
            final isCompleted = currentState.completedEventIds.contains(
              event.id,
            );
            return _SubPageScaffold(
              title: event.title,
              compactBackOnly: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: DecoratedBox(
                      decoration: _modalSurfaceDecoration(),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Color(0xFF3B2A16),
                            height: 1.55,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        height: 1.22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF3A2B15),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      metaText,
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6A522E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              FutureBuilder<List<String>>(
                                future: sceneAssetsFuture,
                                builder: (context, snapshot) {
                                  final sceneAssets =
                                      snapshot.data ?? const <String>[];
                                  if (sceneAssets.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: _storySceneRow(sceneAssets),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              if (storyText.isNotEmpty)
                                _storySection(
                                  title: '요약 이야기',
                                  content: storyText,
                                )
                              else
                                _storySection(
                                  title: '요약 이야기',
                                  content: '요약 정보가 없습니다.',
                                ),
                              if (refs.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _storySection(
                                  title: '관련 본문',
                                  content: refs
                                      .map((ref) => '• $ref')
                                      .join('\n'),
                                  action: moveTarget == null
                                      ? null
                                      : _bibleMoveButton(
                                          onTap: () {
                                            Future.microtask(() {
                                              if (!mounted) {
                                                return;
                                              }
                                              _openBibleReaderPopup(
                                                initialBookNo:
                                                    moveTarget.bookNo,
                                                initialChapterNo:
                                                    moveTarget.chapterNo,
                                                initialVerseNo:
                                                    moveTarget.verseNo,
                                              );
                                            });
                                          },
                                        ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                width: double.infinity,
                                child: _filledActionButton(
                                  label: '퀴즈 시작',
                                  onTap: () => _startQuiz(event.id),
                                  completed: isCompleted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openBibleReaderPopup({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  }) async {
    await _showSubPageLoading('성경 여는 중...');
    try {
      final repo = ref.read(storyRepositoryProvider);
      final user = ref.read(signedInUserProvider);
      final userRepo = ref.read(userRepositoryProvider);
      var savedVerseKeys = <String>{};
      if (user != null) {
        try {
          savedVerseKeys = await userRepo.fetchSavedVerseKeys(user.id);
        } catch (_) {
          savedVerseKeys = <String>{};
        }
      }
      var selectedBookNo = (initialBookNo ?? 1).clamp(1, _kBibleBooks.length);
      var selectedTestament = selectedBookNo >= 40 ? 'new' : 'old';
      var selectedChapter = initialChapterNo ?? 1;
      var pendingFocusVerse = (initialVerseNo ?? 0) > 0 ? initialVerseNo : null;
      final chapterCache = <String, Future<List<BibleVerse>>>{};

      List<MapEntry<int, _BibleBookMeta>> booksForTestament(String testament) {
        return _kBibleBooks
            .asMap()
            .entries
            .where((entry) {
              final bookNo = entry.key + 1;
              return testament == 'new' ? bookNo >= 40 : bookNo <= 39;
            })
            .toList(growable: false);
      }

      Future<List<BibleVerse>> loadVerses({
        required int bookNo,
        required int chapterNo,
      }) {
        final cacheKey = 'KRV:$bookNo:$chapterNo';
        return chapterCache.putIfAbsent(
          cacheKey,
          () => repo.fetchBibleVersesByChapter(
            translation: 'KRV',
            bookNo: bookNo,
            chapterNo: chapterNo,
          ),
        );
      }

      if (!context.mounted) {
        return;
      }
      // ignore: use_build_context_synchronously
      final navigator = Navigator.of(context);
      final pushFuture = navigator.push(
        MaterialPageRoute<void>(
          builder: (pageContext) {
            return StatefulBuilder(
              builder: (pageContext, setDialogState) {
                final testamentBooks = booksForTestament(selectedTestament);
                final selectedEntry =
                    testamentBooks
                        .where((entry) => (entry.key + 1) == selectedBookNo)
                        .firstOrNull ??
                    testamentBooks.first;
                final selectedBook = selectedEntry.value;
                final selectedBookNoSafe = selectedEntry.key + 1;
                final chapterCount = selectedBook.chapters;
                final chapterItems = List<int>.generate(
                  chapterCount,
                  (i) => i + 1,
                );
                final selectedChapterSafe = selectedChapter.clamp(
                  1,
                  chapterCount,
                );
                final versesFuture = loadVerses(
                  bookNo: selectedBookNoSafe,
                  chapterNo: selectedChapterSafe,
                );

                return _SubPageScaffold(
                  title: '성경',
                  compactBackOnly: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: _floatingPanelDecoration(
                        color: const Color(0xF5F7E9D1),
                        shadowOpacity: 0.10,
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 88,
                                  child: _bibleDropdownFrame<String>(
                                    value: selectedTestament,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'old',
                                        child: Text('구약'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'new',
                                        child: Text('신약'),
                                      ),
                                    ],
                                    onChanged: (testament) {
                                      if (testament == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedTestament = testament;
                                        final nextBooks = booksForTestament(
                                          selectedTestament,
                                        );
                                        if (nextBooks.isEmpty) {
                                          return;
                                        }
                                        final inSameTestament =
                                            selectedTestament == 'new'
                                            ? selectedBookNo >= 40
                                            : selectedBookNo <= 39;
                                        if (!inSameTestament) {
                                          selectedBookNo =
                                              nextBooks.first.key + 1;
                                        }
                                        final maxChapter =
                                            _kBibleBooks[selectedBookNo - 1]
                                                .chapters;
                                        if (selectedChapter > maxChapter) {
                                          selectedChapter = maxChapter;
                                        }
                                        pendingFocusVerse = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 172,
                                  child: _bibleDropdownFrame<int>(
                                    value: selectedBookNoSafe,
                                    items: testamentBooks
                                        .map(
                                          (entry) => DropdownMenuItem<int>(
                                            value: entry.key + 1,
                                            child: Text(
                                              entry.value.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (bookNo) {
                                      if (bookNo == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedBookNo = bookNo;
                                        final maxChapter =
                                            _kBibleBooks[bookNo - 1].chapters;
                                        if (selectedChapter > maxChapter) {
                                          selectedChapter = maxChapter;
                                        }
                                        pendingFocusVerse = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 96,
                                  child: _bibleDropdownFrame<int>(
                                    value: selectedChapterSafe,
                                    items: chapterItems
                                        .map(
                                          (chapter) => DropdownMenuItem<int>(
                                            value: chapter,
                                            child: Text('$chapter장'),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (chapter) {
                                      if (chapter == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedChapter = chapter;
                                        pendingFocusVerse = null;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              decoration: _floatingPanelDecoration(
                                color: const Color(0xF4EFE3CC),
                                shadowOpacity: 0.06,
                              ),
                              padding: const EdgeInsets.all(14),
                              child: FutureBuilder<List<BibleVerse>>(
                                future: versesFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    );
                                  }

                                  if (snapshot.hasError) {
                                    return SingleChildScrollView(
                                      child: Text(
                                        '본문을 불러오지 못했습니다.\n${snapshot.error}',
                                        style: const TextStyle(
                                          color: Color(0xFFA63F2D),
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    );
                                  }

                                  final verses =
                                      snapshot.data ?? const <BibleVerse>[];
                                  final focusVerseNo = pendingFocusVerse;
                                  final focusVerseKey = GlobalKey();
                                  if (verses.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        '선택한 장의 본문 데이터가 없습니다.',
                                        style: TextStyle(
                                          color: Color(0xFF6A5440),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }

                                  if (focusVerseNo != null) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          final targetContext =
                                              focusVerseKey.currentContext;
                                          if (targetContext != null) {
                                            Scrollable.ensureVisible(
                                              targetContext,
                                              duration: const Duration(
                                                milliseconds: 280,
                                              ),
                                              curve: Curves.easeOutCubic,
                                              alignment: 0.12,
                                            );
                                          }
                                          pendingFocusVerse = null;
                                        });
                                  }

                                  return SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${selectedBook.name} $selectedChapterSafe장',
                                          style: const TextStyle(
                                            color: Color(0xFF3B2A17),
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...verses.map((verse) {
                                          final verseKey =
                                              SavedBibleVerse.buildVerseKey(
                                                translation: verse.translation,
                                                bookNo: verse.bookNo,
                                                chapterNo: verse.chapterNo,
                                                verseNo: verse.verseNo,
                                              );
                                          final isSaved = savedVerseKeys
                                              .contains(verseKey);
                                          return Padding(
                                            key:
                                                focusVerseNo != null &&
                                                    verse.verseNo ==
                                                        focusVerseNo
                                                ? focusVerseKey
                                                : null,
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: user == null
                                                    ? null
                                                    : () async {
                                                        try {
                                                          final didSave =
                                                              await userRepo
                                                                  .toggleSavedVerse(
                                                                    userId:
                                                                        user.id,
                                                                    verse:
                                                                        verse,
                                                                  );
                                                          if (!pageContext
                                                              .mounted) {
                                                            return;
                                                          }
                                                          setDialogState(() {
                                                            if (didSave) {
                                                              savedVerseKeys
                                                                  .add(
                                                                    verseKey,
                                                                  );
                                                            } else {
                                                              savedVerseKeys
                                                                  .remove(
                                                                    verseKey,
                                                                  );
                                                            }
                                                          });
                                                          final messenger =
                                                              ScaffoldMessenger.of(
                                                                pageContext,
                                                              );
                                                          messenger
                                                              .hideCurrentSnackBar();
                                                          messenger.showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                didSave
                                                                    ? '저장되었어요'
                                                                    : '저장이 삭제되었어요',
                                                              ),
                                                            ),
                                                          );
                                                        } catch (error) {
                                                          if (!pageContext
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                            pageContext,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                '저장 중 오류가 발생했습니다.\n$error',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 180,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isSaved
                                                        ? const Color(
                                                            0x3DE2BE57,
                                                          )
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: RichText(
                                                    text: TextSpan(
                                                      style: TextStyle(
                                                        color: const Color(
                                                          0xFF3B2A17,
                                                        ),
                                                        fontSize: 15,
                                                        height: 1.25,
                                                      ),
                                                      children: [
                                                        TextSpan(
                                                          text:
                                                              '${verse.verseNo} ',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        TextSpan(
                                                          text: verse.verseText,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
      _hideSubPageLoading();
      await pushFuture;
    } finally {
      _hideSubPageLoading();
    }
  }

  Future<List<String>> _loadAssetManifest() async {
    final cached = _assetManifestCache;
    if (cached != null) {
      return cached;
    }

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetKeys = manifest.listAssets();
      _assetManifestCache = assetKeys;
      return assetKeys;
    } catch (_) {
      // Fall through to JSON manifest for older/alternate environments.
    }

    try {
      final rawManifest = await rootBundle.loadString('AssetManifest.json');
      final decoded = json.decode(rawManifest);
      if (decoded is Map<String, dynamic>) {
        final assetKeys = decoded.keys.toList(growable: false);
        _assetManifestCache = assetKeys;
        return assetKeys;
      }
    } catch (_) {
      // Return empty manifest when assets are unavailable in current build.
    }
    _assetManifestCache = const <String>[];
    return _assetManifestCache!;
  }

  String _sceneDirectoryNameForTitle(String title) {
    final replaced = title.replaceAll(_sceneInvalidDirChars, '_').trim();
    final trimmedDots = replaced.replaceAll(RegExp(r'^\.+|\.+$'), '');
    final collapsed = trimmedDots
        .replaceAll(_sceneWhitespacePattern, ' ')
        .trim();
    return collapsed.isNotEmpty ? collapsed : 'untitled_event';
  }

  String _normalizeSceneLookupKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(_sceneLooseNormalizePattern, '')
        .trim();
  }

  String _stripSceneDirectoryPrefix(String directoryName) {
    return directoryName.replaceFirst(RegExp(r'^\d+\s*'), '').trim();
  }

  String? _scenePrefixForCode(String code) {
    final match = _sceneCodeDigitsPattern.firstMatch(code.trim());
    final digits = match?.group(1);
    if (digits == null || digits.isEmpty) {
      return null;
    }
    final numeric = int.tryParse(digits);
    if (numeric == null) {
      return null;
    }
    return numeric.toString().padLeft(3, '0');
  }

  Future<List<String>> _loadSceneAssetsForEvent(StoryEvent event) async {
    return _loadSceneAssetsForLookup(title: event.title, code: event.code);
  }

  Future<List<String>> _loadSceneAssetsForLookup({
    required String title,
    String? code,
  }) async {
    final dirName = _sceneDirectoryNameForTitle(title);
    final cached = _sceneAssetsCache[dirName];
    if (cached != null) {
      return cached;
    }

    final manifest = await _loadAssetManifest();
    const sceneRoot = 'assets/story_images_thumbs/';
    final allScenePaths = manifest
        .where(
          (path) =>
              path.startsWith(sceneRoot) &&
              _sceneFilenamePattern.hasMatch(path),
        )
        .toList(growable: false);

    final knownDirs = <String>{};
    for (final path in allScenePaths) {
      final relative = path.substring(sceneRoot.length);
      final slashIndex = relative.indexOf('/');
      if (slashIndex <= 0) {
        continue;
      }
      knownDirs.add(relative.substring(0, slashIndex));
    }

    var chosenDir = dirName;
    final directPrefix = '$sceneRoot$chosenDir/';
    final hasDirect = allScenePaths.any(
      (path) => path.startsWith(directPrefix),
    );
    if (!hasDirect) {
      final codePrefix = code == null ? null : _scenePrefixForCode(code);
      if (codePrefix != null) {
        final codeMatchedDir =
            knownDirs
                .where((dir) => dir.startsWith('$codePrefix '))
                .toList(growable: false)
              ..sort((a, b) => a.length.compareTo(b.length));
        if (codeMatchedDir.isNotEmpty) {
          chosenDir = codeMatchedDir.first;
        }
      }
    }

    final chosenPrefixAfterCode = '$sceneRoot$chosenDir/';
    final hasCodeMatched = allScenePaths.any(
      (path) => path.startsWith(chosenPrefixAfterCode),
    );
    if (!hasCodeMatched) {
      final titleKey = _normalizeSceneLookupKey(title);
      final dirNameKey = _normalizeSceneLookupKey(dirName);
      final fallbackCandidates =
          knownDirs
              .map((dir) {
                final rawKey = _normalizeSceneLookupKey(dir);
                final strippedKey = _normalizeSceneLookupKey(
                  _stripSceneDirectoryPrefix(dir),
                );
                var score = -1;
                if (rawKey == titleKey || rawKey == dirNameKey) {
                  score = 0;
                } else if (strippedKey == titleKey ||
                    strippedKey == dirNameKey) {
                  score = 1;
                } else if (strippedKey.endsWith(titleKey) ||
                    strippedKey.endsWith(dirNameKey)) {
                  score = 2;
                } else if (strippedKey.contains(titleKey) ||
                    strippedKey.contains(dirNameKey) ||
                    titleKey.contains(strippedKey) ||
                    dirNameKey.contains(strippedKey)) {
                  score = 3;
                }
                return (dir: dir, score: score);
              })
              .where((candidate) => candidate.score >= 0)
              .toList(growable: false)
            ..sort((a, b) {
              final byScore = a.score.compareTo(b.score);
              if (byScore != 0) {
                return byScore;
              }
              return a.dir.length.compareTo(b.dir.length);
            });
      if (fallbackCandidates.isNotEmpty) {
        chosenDir = fallbackCandidates.first.dir;
      }
    }

    final chosenPrefix = '$sceneRoot$chosenDir/';
    final sceneAssets =
        allScenePaths
            .where((path) => path.startsWith(chosenPrefix))
            .toList(growable: false)
          ..sort((a, b) {
            final aMatch = _sceneFilenamePattern.firstMatch(a);
            final bMatch = _sceneFilenamePattern.firstMatch(b);
            final aIndex = int.tryParse(aMatch?.group(1) ?? '') ?? 0;
            final bIndex = int.tryParse(bMatch?.group(1) ?? '') ?? 0;
            return aIndex.compareTo(bIndex);
          });

    _sceneAssetsCache[dirName] = sceneAssets;
    return sceneAssets;
  }

  Widget _buildWeeklyBody({
    required StoryState state,
    required StoryController controller,
    required bool isAuthenticated,
    required ValueChanged<String> onSelectEvent,
    required ValueChanged<String> onToggleChecked,
    required ValueChanged<String> onStartQuiz,
  }) {
    final weekly = _weeklyStudyData;
    if (_weeklyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_weeklyError != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _weeklyError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFDF8EE)),
          ),
        ),
      );
    }
    if (weekly == null) {
      return const SizedBox.shrink();
    }

    final completedEventIds = state.completedEventIds;
    final totalStories = weekly.events.length;
    final completedStories = weekly.events
        .where((event) => completedEventIds.contains(event.id))
        .length;
    final weeklyProgress = totalStories == 0
        ? 0.0
        : completedStories / totalStories;
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final todayKst = DateTime(nowKst.year, nowKst.month, nowKst.day);
    final weekStartKst = _weekStartMonday(todayKst);
    final weekEndKst = weekStartKst.add(const Duration(days: 6));
    final daysRemainingKst = math.max(
      0,
      weekEndKst.difference(todayKst).inDays,
    );

    final coordinatePoints = weekly.events
        .where((event) => event.hasCoordinate)
        .map((event) => event.latLng)
        .toList(growable: false);
    LatLng? initialMapCenter;
    if (coordinatePoints.isNotEmpty) {
      var minLat = coordinatePoints.first.latitude;
      var maxLat = coordinatePoints.first.latitude;
      var minLng = coordinatePoints.first.longitude;
      var maxLng = coordinatePoints.first.longitude;
      for (final point in coordinatePoints.skip(1)) {
        if (point.latitude < minLat) {
          minLat = point.latitude;
        }
        if (point.latitude > maxLat) {
          maxLat = point.latitude;
        }
        if (point.longitude < minLng) {
          minLng = point.longitude;
        }
        if (point.longitude > maxLng) {
          maxLng = point.longitude;
        }
      }
      initialMapCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final orientation = MediaQuery.orientationOf(context);
        final useSplitLayout = orientation == Orientation.landscape || w >= 900;
        final contentGap = (w * 0.011).clamp(8.0, 14.0).toDouble();
        final progressHeight = (h * 0.084).clamp(44.0, 58.0).toDouble();
        final mapHeightOnNarrow = (h * 0.44).clamp(220.0, 360.0).toDouble();

        String avatarAssetForPerson(String personId) {
          if (personId == weekly.person.id) {
            return weekly.person.avatarAssetPath;
          }
          final person = state.persons
              .where((p) => p.id == personId)
              .firstOrNull;
          return person?.avatarAssetPath ?? weekly.person.avatarAssetPath;
        }

        final mapPanel = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: StoryMapPanel(
            events: weekly.events,
            selectedEventId: _weeklySelectedEventId,
            onSelectEvent: onSelectEvent,
            colorForPerson: controller.colorForPerson,
            avatarAssetForPerson: avatarAssetForPerson,
            selectedPersonIds: {weekly.person.id},
            decorate: false,
            showSelectedCallout: false,
            animateReveal: false,
            centerSelectedOnReady: false,
            fitAllEventsOnReady: true,
            fitAllZoomAdjust: -0.18,
            pinScale: 1.0,
            initialCenter: initialMapCenter,
            initialZoom: 5.4,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: progressHeight,
              child: _weeklyProgressRow(
                daysRemainingKst: daysRemainingKst,
                completedCount: completedStories,
                totalCount: totalStories,
                progress: weeklyProgress,
              ),
            ),
            if (!isAuthenticated) ...[
              SizedBox(height: contentGap * 0.72),
              _weeklyGuestNoticeBanner(),
            ],
            SizedBox(height: contentGap),
            Expanded(
              child: useSplitLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: mapPanel),
                        SizedBox(width: contentGap),
                        Expanded(
                          flex: 9,
                          child: _buildWeeklyListPanel(
                            weekly: weekly,
                            completedEventIds: completedEventIds,
                            colorForPerson: controller.colorForPerson,
                            onSelectEvent: onSelectEvent,
                            onToggleChecked: onToggleChecked,
                            onStartQuiz: onStartQuiz,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: mapHeightOnNarrow, child: mapPanel),
                        SizedBox(height: contentGap),
                        Expanded(
                          child: _buildWeeklyListPanel(
                            weekly: weekly,
                            completedEventIds: completedEventIds,
                            colorForPerson: controller.colorForPerson,
                            onSelectEvent: onSelectEvent,
                            onToggleChecked: onToggleChecked,
                            onStartQuiz: onStartQuiz,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _weeklyGuestNoticeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E5BE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xD7D3A051), width: 1),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8B632E)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '비로그인 상태예요. 금주 인물과 퀴즈는 사용할 수 있지만 진행 상황은 저장되지 않아요.',
              style: TextStyle(
                color: Color(0xFF6A4A23),
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyProgressRow({
    required int daysRemainingKst,
    required int completedCount,
    required int totalCount,
    required double progress,
  }) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentText = '${(clampedProgress * 100).round()}%';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;
        final summaryStyle = TextStyle(
          color: const Color(0xFFFDF8EE),
          fontSize: compact ? 12.6 : 14.2,
          fontWeight: FontWeight.w800,
          height: compact ? 1.25 : 1.1,
          shadows: const [
            Shadow(
              color: Color(0xAA000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        );
        final percentStyle = TextStyle(
          color: const Color(0xFFFFE5A8),
          fontSize: compact ? 12.8 : 14.2,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(
              color: Color(0xAA000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        );
        final progressBar = ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: compact ? 10 : 12,
            value: clampedProgress,
            backgroundColor: const Color(0x664E3A26),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC6922D)),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xAA2A2118),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x99DDB883), width: 1),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 8 : 10,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '이번주 남은 $daysRemainingKst일 · 이야기 $completedCount/$totalCount 달성',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: summaryStyle,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: progressBar),
                          const SizedBox(width: 8),
                          Text(percentText, maxLines: 1, style: percentStyle),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 9,
                        child: Text(
                          '이번주 남은 $daysRemainingKst일 · 이야기 $completedCount/$totalCount 달성',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: summaryStyle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 7, child: progressBar),
                      const SizedBox(width: 8),
                      Text(percentText, maxLines: 1, style: percentStyle),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyListPanel({
    required _WeeklyStudyData weekly,
    required Set<String> completedEventIds,
    required Color Function(String personId) colorForPerson,
    required ValueChanged<String> onSelectEvent,
    required ValueChanged<String> onToggleChecked,
    required ValueChanged<String> onStartQuiz,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: _floatingPanelDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _weeklyPersonTitleBadge(
              text: '금주 인물: ${weekly.person.name}',
              person: weekly.person,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: weekly.events.isEmpty
                  ? const Center(
                      child: Text(
                        '선택된 인물의 사건이 없습니다.',
                        style: TextStyle(
                          color: Color(0xFF5A4327),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: weekly.events.length,
                      itemBuilder: (context, index) {
                        final event = weekly.events[index];
                        final selected = event.id == _weeklySelectedEventId;
                        final isCompleted = completedEventIds.contains(
                          event.id,
                        );
                        final isChecked = _weeklyCheckedEventIds.contains(
                          event.id,
                        );
                        final shortText =
                            (event.shortStory ??
                                    event.story ??
                                    event.summary ??
                                    '')
                                .trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            onTap: () => onSelectEvent(event.id),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              decoration: _interactiveCardDecoration(
                                selected: selected,
                                completed: isCompleted,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isCompactCard =
                                      constraints.maxWidth < 340;
                                  final titleFontSize = isCompactCard
                                      ? 13.2
                                      : 14.8;
                                  final bodyFontSize = isCompactCard
                                      ? 11.2
                                      : 12.2;
                                  final checkboxSize = isCompactCard
                                      ? 26.0
                                      : 29.0;
                                  final checkboxIconSize = isCompactCard
                                      ? 15.0
                                      : 17.0;
                                  return Container(
                                    constraints: BoxConstraints(
                                      minHeight: isCompactCard ? 64 : 74,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompactCard ? 10 : 12,
                                      vertical: isCompactCard ? 9 : 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: isCompactCard ? 11 : 12,
                                          height: isCompactCard ? 11 : 12,
                                          margin: EdgeInsets.only(
                                            right: isCompactCard ? 8 : 10,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: colorForPerson(
                                              weekly.person.id,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${index + 1}. ${event.title}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: titleFontSize,
                                                  fontWeight: FontWeight.w800,
                                                  color: selected
                                                      ? const Color(0xFFFDF8EE)
                                                      : isCompleted
                                                      ? const Color(0xFF2D5A39)
                                                      : const Color(0xFF4A331D),
                                                  height: 1.18,
                                                ),
                                              ),
                                              if (shortText.isNotEmpty) ...[
                                                SizedBox(
                                                  height: isCompactCard ? 3 : 4,
                                                ),
                                                Text(
                                                  shortText,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: bodyFontSize,
                                                    fontWeight: FontWeight.w600,
                                                    color: selected
                                                        ? const Color(
                                                            0xEAFDF8EE,
                                                          )
                                                        : isCompleted
                                                        ? const Color(
                                                            0xCC44624B,
                                                          )
                                                        : const Color(
                                                            0xCC5A4327,
                                                          ),
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: isCompactCard ? 6 : 8),
                                        GestureDetector(
                                          onTap: () =>
                                              onToggleChecked(event.id),
                                          behavior: HitTestBehavior.opaque,
                                          child: Container(
                                            width: checkboxSize,
                                            height: checkboxSize,
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? const Color(0xFF2D7C55)
                                                  : const Color(0xFFF8F1E4),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isChecked
                                                    ? const Color(0xFF2D7C55)
                                                    : const Color(0xFFB58E63),
                                              ),
                                            ),
                                            child: Icon(
                                              isChecked
                                                  ? Icons.check_rounded
                                                  : Icons.circle_outlined,
                                              size: checkboxIconSize,
                                              color: isChecked
                                                  ? const Color(0xFFFDF8EE)
                                                  : const Color(0xFF8E6F48),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _weeklyInlineQuizButton(
                                          completed: isCompleted,
                                          onTap: () => onStartQuiz(event.id),
                                          roomy: !isCompactCard,
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
    );
  }

  Widget _weeklyInlineQuizButton({
    required bool completed,
    required VoidCallback onTap,
    bool roomy = false,
  }) {
    return _filledActionButton(
      label: '퀴즈',
      onTap: onTap,
      completed: completed,
      compact: true,
      minWidth: roomy ? 60 : 52,
      minHeight: roomy ? 40 : 36,
      fontSize: roomy ? 13.8 : 12.8,
      horizontalPadding: roomy ? 14 : 12,
    );
  }

  Widget _weeklyPersonTitleBadge({
    required String text,
    required Person person,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: _headerChipDecoration(),
      child: Row(
        children: [
          _weeklyPersonAvatar(person: person, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.2,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A331D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyPersonAvatar({required Person person, double size = 32}) {
    final avatarPath = person.avatarAssetPath.trim();
    final fallbackText = person.name.trim().isEmpty
        ? '?'
        : person.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF3E7CC), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _weeklyAvatarFallback(fallbackText, fontSize: fallbackFontSize)
            : ColoredBox(
                color: Colors.white,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size,
                    height: size * 2,
                    child: Image.asset(
                      avatarPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => _weeklyAvatarFallback(
                        fallbackText,
                        fontSize: fallbackFontSize,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _weeklyAvatarFallback(String text, {double fontSize = 11}) {
    return Container(
      color: const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Color(0xFFF3EAD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _weeklyShortPopup({
    required StoryEvent event,
    double maxHeight = 232,
    required VoidCallback onClose,
    required VoidCallback onOpenDetail,
  }) {
    final shortText = (event.shortStory ?? event.story ?? event.summary ?? '')
        .trim();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: _floatingPanelDecoration(
          color: const Color(0xFFF9F1E4),
          shadowOpacity: 0.28,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 48, 14),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3D2D18),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (shortText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        shortText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4C3A21),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onOpenDetail,
                        behavior: HitTestBehavior.translucent,
                        child: _filledActionButton(
                          label: '자세히 보기',
                          onTap: onOpenDetail,
                          compact: true,
                          minWidth: 96,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 8,
              child: _modalCloseButton(size: 24, onTap: onClose),
            ),
          ],
        ),
      ),
    );
  }

  List<Person> _profilePeople(StoryState state) {
    final people =
        [...(_profileAllPeople.isNotEmpty ? _profileAllPeople : state.persons)]
          ..retainWhere((person) {
            final testament = _profilePersonTestamentById[person.id] ?? 'old';
            return testament == _profileSelectedTestament;
          })
          ..sort(
            (a, b) => _compareProfilePeople(
              a,
              b,
              timelineOrderById: _profilePersonTimelineOrderById,
            ),
          );
    return people;
  }

  int _compareProfilePeople(
    Person a,
    Person b, {
    required Map<String, int> timelineOrderById,
  }) {
    final aTimeline = timelineOrderById[a.id];
    final bTimeline = timelineOrderById[b.id];
    if (aTimeline != null || bTimeline != null) {
      final timelineOrder = (aTimeline ?? 1 << 30).compareTo(
        bTimeline ?? 1 << 30,
      );
      if (timelineOrder != 0) {
        return timelineOrder;
      }
    }

    final displayOrder = a.displayOrder.compareTo(b.displayOrder);
    if (displayOrder != 0) {
      return displayOrder;
    }
    return a.name.compareTo(b.name);
  }

  AppUserProfile _guestPreviewProfile() {
    final now = DateTime.now();
    return AppUserProfile(
      userId: 'guest',
      shareId: 'ABC1234',
      nickname: '내 프로필',
      photoUrl: null,
      prayerRequest: '로그인하면 기도제목을 저장할 수 있어요.',
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget _buildProfileBody({
    required StoryState state,
    required bool isAuthenticated,
  }) {
    final people = _profilePeople(state);
    final profile = _profileUser ?? _guestPreviewProfile();
    if (_profileLoading && people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profileError != null && isAuthenticated && _profileUser == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _profileError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFDF8EE)),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxWidth * 0.012).clamp(4.0, 10.0).toDouble();
        final leftWidth = (constraints.maxWidth * 0.425)
            .clamp(278.0, 416.0)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: _buildProfileLeftPanel(
                  profile: profile,
                  isAuthenticated: isAuthenticated,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _buildProfileRightPanel(
                  people: people,
                  completedEventIds: state.completedEventIds,
                  selectedTestament: _profileSelectedTestament,
                  onSelectTestament: (testament) {
                    setState(() {
                      _profileSelectedTestament = testament;
                    });
                    _profilePageSetState?.call(() {});
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openProfileEditor() async {
    final profile = _profileUser;
    final user = ref.read(signedInUserProvider);
    if (profile == null || user == null) {
      return;
    }
    final updatedProfile = await showDialog<AppUserProfile>(
      context: context,
      builder: (_) =>
          _ProfileEditorDialog(initialProfile: profile, userId: user.id),
    );
    if (!mounted || updatedProfile == null) {
      return;
    }
    setState(() {
      _profileUser = updatedProfile;
    });
    _profilePageSetState?.call(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프로필이 저장되었어요.')));
  }

  Future<void> _openProfileNotesPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileNotesScreen()));
    if (!mounted) {
      return;
    }
    await _loadProfileNotesPreview(showLoading: false);
  }

  Future<void> _openSavedVersesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedVersesScreen(
          onOpenVerse: (verse) {
            return _openBibleReaderPopup(
              initialBookNo: verse.bookNo,
              initialChapterNo: verse.chapterNo,
              initialVerseNo: verse.verseNo,
            );
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadProfileSavedVersesPreview(showLoading: false);
  }

  Future<void> _copyProfileShareId(String shareId) async {
    final normalized = shareId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('공유 ID가 복사되었어요. ($normalized)')));
  }

  void _openProfilePrayerPreview(String prayerText) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '내 기도',
        showCloseButton: true,
        actions: [
          ParchmentDialogActionButton(
            label: '닫기',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: SingleChildScrollView(
          child: Text(
            prayerText,
            style: const TextStyle(
              color: Color(0xFF3E2B18),
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showShareIdInputDialog() async {
    return showDialog<String>(
      context: context,
      builder: (_) => const _ShareIdInputDialog(),
    );
  }

  Future<void> _promptAddIntercessoryPrayer() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }
    final enteredId = await _showShareIdInputDialog();

    final shareId = enteredId?.trim().toUpperCase() ?? '';
    if (shareId.isEmpty) {
      return;
    }

    try {
      await ref
          .read(userRepositoryProvider)
          .addIntercessoryPrayerByShareId(shareId);
      if (!mounted) {
        return;
      }
      await _loadIntercessoryPrayerPage();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('중보할 기도제목에 추가했어요.')));
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.message.trim().isEmpty
          ? '기도제목을 추가하지 못했습니다.'
          : error.message.trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('기도제목을 추가하지 못했습니다.\n$error')));
    }
  }

  Future<void> _confirmDeleteIntercessoryPrayer(
    IntercessoryPrayerItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '기도제목을 삭제할까요?',
        subtitle: '${item.nickname}님의 기도제목을 목록에서 삭제할까요?',
        actions: [
          ParchmentDialogActionButton(
            label: '취소',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(false),
          ),
          ParchmentDialogActionButton(
            label: '삭제',
            style: ParchmentDialogActionStyle.danger,
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(userRepositoryProvider).deleteIntercessoryPrayer(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _intercessoryPrayerItems = _intercessoryPrayerItems
            .where((entry) => entry.id != item.id)
            .toList(growable: false);
      });
      _profilePageSetState?.call(() {});
      if (_intercessoryPrayerItems.length < 4 &&
          _intercessoryPrayerHasNextPage) {
        await _loadIntercessoryPrayerPage();
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('목록에서 삭제했어요.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다.\n$error')));
    }
  }

  Future<void> _signOut() async {
    if (_signingOut || !mounted) {
      return;
    }

    setState(() {
      _signingOut = true;
    });

    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.popUntil((route) => route.isFirst);

    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        return;
      }
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  Widget _buildProfileLeftPanel({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: _floatingPanelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCurrentUserAvatar(profile: profile, size: 78),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _profileTinyIconButton(
                                tooltip: '프로필 수정',
                                onTap: _openProfileEditor,
                                icon: Icons.edit_rounded,
                              ),
                              const SizedBox(width: 4),
                              _profileTinyIconButton(
                                tooltip: '로그아웃',
                                onTap: _signOut,
                                icon: Icons.logout_rounded,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profile.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF4A331D),
                            fontSize: 20.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildProfileContentTabs(),
            const SizedBox(height: 10),
            Expanded(
              child: _buildProfileContentPanel(
                profile: profile,
                isAuthenticated: isAuthenticated,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContentTabs() {
    final selectedIndex = switch (_profileContentTab) {
      _ProfileContentTab.prayer => 0,
      _ProfileContentTab.notes => 1,
      _ProfileContentTab.verses => 2,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabBarWidth = math.min(constraints.maxWidth, 292.0);
        final segmentWidth = tabBarWidth / 3;
        final indicatorWidth = math.min(62.0, segmentWidth - 18);
        final indicatorLeft =
            segmentWidth * selectedIndex +
            ((segmentWidth - indicatorWidth) / 2);

        return SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: tabBarWidth,
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Color(0x338E6F48),
                      child: SizedBox(height: 2),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    left: indicatorLeft,
                    bottom: 0,
                    child: Container(
                      width: indicatorWidth,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB26B28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: _profileContentTabButton(
                            label: '기도',
                            tab: _ProfileContentTab.prayer,
                          ),
                        ),
                        Expanded(
                          child: _profileContentTabButton(
                            label: '노트',
                            tab: _ProfileContentTab.notes,
                          ),
                        ),
                        Expanded(
                          child: _profileContentTabButton(
                            label: '말씀',
                            tab: _ProfileContentTab.verses,
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

  Widget _profileContentTabButton({
    required String label,
    required _ProfileContentTab tab,
  }) {
    final selected = _profileContentTab == tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _profileContentTab = tab;
          });
          _profilePageSetState?.call(() {});
        },
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? const Color(0xFFB26B28)
                    : const Color(0xFF7E735F),
                fontSize: selected ? 16.4 : 15.4,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContentPanel({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: switch (_profileContentTab) {
        _ProfileContentTab.notes => _buildProfileNotesTabBody(),
        _ProfileContentTab.verses => _buildProfileVersesTabBody(),
        _ProfileContentTab.prayer => _buildProfilePrayerTabBody(
          profile: profile,
          isAuthenticated: isAuthenticated,
        ),
      },
    );
  }

  Widget _buildProfileNotesTabBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileTabSectionHeader(
          title: '내 노트',
          actionLabel: '전체 보기',
          onAction: _openProfileNotesPage,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _profileNotesLoading
              ? const Center(child: CircularProgressIndicator())
              : _profileNotesError != null
              ? _buildProfileTabMessage(
                  _profileNotesError!,
                  textColor: const Color(0xFF7E3426),
                )
              : _profileNotesPreview.isEmpty
              ? _buildProfileTabMessage(
                  '아직 작성한 노트가 없습니다.\n전체 보기에서 노트를 작성해 보세요.',
                )
              : ListView.separated(
                  itemCount: _profileNotesPreview.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final note = _profileNotesPreview[index];
                    return _buildProfileNotePreviewCard(note);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProfileVersesTabBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileTabSectionHeader(
          title: '저장한 말씀',
          actionLabel: '전체 보기',
          onAction: _openSavedVersesPage,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _profileSavedVersesLoading
              ? const Center(child: CircularProgressIndicator())
              : _profileSavedVersesError != null
              ? _buildProfileTabMessage(
                  _profileSavedVersesError!,
                  textColor: const Color(0xFF7E3426),
                )
              : _profileSavedVersesPreview.isEmpty
              ? _buildProfileTabMessage(
                  '아직 저장한 말씀이 없습니다.\n성경 화면에서 구절을 눌러 저장해 보세요.',
                )
              : ListView.separated(
                  itemCount: _profileSavedVersesPreview.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final verse = _profileSavedVersesPreview[index];
                    return _buildProfileSavedVersePreviewCard(verse);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProfilePrayerTabBody({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    final prayerText = (profile.prayerRequest ?? '').trim().isNotEmpty
        ? profile.prayerRequest!.trim()
        : '오늘의 기도제목을 적어 보세요.';
    final hasItems = _intercessoryPrayerItems.isNotEmpty;
    const sectionTitleStyle = TextStyle(
      color: Color(0xFF452F1A),
      fontWeight: FontWeight.w900,
      fontSize: 14.7,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '내 기도',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sectionTitleStyle,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openProfilePrayerPreview(prayerText),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.open_in_full_rounded,
                    size: 16,
                    color: Color(0xFF8A6A46),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0x448E6F48)),
        const SizedBox(height: 7),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openProfilePrayerPreview(prayerText),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.only(right: 2, bottom: 2),
              child: Text(
                prayerText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5A4326),
                  fontWeight: FontWeight.w400,
                  fontSize: 13.4,
                  height: 1.34,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Expanded(
              child: Text(
                '중보 기도',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sectionTitleStyle,
              ),
            ),
            if (isAuthenticated)
              _profileShareIdChip(
                shareId: profile.shareId,
                enabled: true,
                onTap: () => _copyProfileShareId(profile.shareId),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0x448E6F48)),
        const SizedBox(height: 7),
        Expanded(
          child: _intercessoryPrayerLoading && !hasItems
              ? const Center(child: CircularProgressIndicator())
              : _intercessoryPrayerError != null && !hasItems
              ? _buildIntercessoryPrayerErrorCard()
              : !hasItems
              ? _buildIntercessoryPrayerEmptyCard(enabled: isAuthenticated)
              : Stack(
                  children: [
                    ListView.separated(
                      controller: _intercessoryPrayerScrollController,
                      padding: const EdgeInsets.only(bottom: 52),
                      itemCount:
                          _intercessoryPrayerItems.length +
                          (_intercessoryPrayerLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index >= _intercessoryPrayerItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                          );
                        }
                        final item = _intercessoryPrayerItems[index];
                        return _buildIntercessoryPrayerItemCard(item);
                      },
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _intercessoryPrayerFab(enabled: isAuthenticated),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _profileTabSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF452F1A),
              fontWeight: FontWeight.w900,
              fontSize: 15.2,
            ),
          ),
        ),
        _profileInlineTextButton(label: actionLabel, onTap: onAction),
      ],
    );
  }

  Widget _profileInlineTextButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xDDF7E9D2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6C4C28),
              fontSize: 11.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTabMessage(
    String text, {
    Color textColor = const Color(0xFF6D5231),
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 12.4,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileNotePreviewCard(UserNote note) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProfileNotePreview(note),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xC9F1E3CB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF452F1A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatProfilePreviewDate(note.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF8A6A46),
                      fontSize: 10.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                note.previewLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5A4326),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.0,
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSavedVersePreviewCard(SavedBibleVerse verse) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openBibleReaderPopup(
          initialBookNo: verse.bookNo,
          initialChapterNo: verse.chapterNo,
          initialVerseNo: verse.verseNo,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xC9F1E3CB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      verse.referenceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF452F1A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatProfilePreviewDate(verse.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF8A6A46),
                      fontSize: 10.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                verse.verseText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5A4326),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.0,
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfileNotePreview(UserNote note) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: note.title,
        subtitle: _formatProfilePreviewDateTime(note.createdAt),
        showCloseButton: true,
        actions: [
          ParchmentDialogActionButton(
            label: '닫기',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Text(
              note.content,
              style: const TextStyle(
                color: Color(0xFF3E2B18),
                fontSize: 13.2,
                fontWeight: FontWeight.w700,
                height: 1.55,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatProfilePreviewDate(DateTime dateTime) {
    return '${dateTime.month}.${dateTime.day}';
  }

  String _formatProfilePreviewDateTime(DateTime dateTime) {
    return '${dateTime.year}.${dateTime.month}.${dateTime.day}';
  }

  Widget _buildCurrentUserAvatar({
    required AppUserProfile profile,
    required double size,
    Uint8List? previewBytes,
  }) {
    final initials = profile.nickname.trim().isEmpty
        ? '?'
        : profile.nickname.trim().substring(0, 1);
    final ImageProvider? imageProvider = previewBytes != null
        ? MemoryImage(previewBytes)
        : ((profile.photoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(profile.photoUrl!.trim())
              : null);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFD79B), Color(0xFFC88A3D)],
        ),
        border: Border.all(color: const Color(0xFF8C6743), width: 1.4),
      ),
      child: ClipOval(
        child: imageProvider == null
            ? Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: const Color(0xFF4A331D),
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: const Color(0xFF4A331D),
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildProfileRightPanel({
    required List<Person> people,
    required Set<String> completedEventIds,
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader = constraints.maxWidth < 400;
        final headerStats = Row(
          children: [
            Expanded(
              child: _profileTopStatCard(
                title: '연속 출석일',
                value: '$_profileAttendanceStreak일',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _profileTopStatCard(
                title: '연속 인물 공부',
                value: '$_profileStudyStreak일',
              ),
            ),
          ],
        );

        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: _floatingPanelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stackHeader) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _profileTestamentToggle(
                      selectedTestament: selectedTestament,
                      onSelectTestament: onSelectTestament,
                    ),
                  ),
                  const SizedBox(height: 8),
                  headerStats,
                ] else
                  Row(
                    children: [
                      _profileTestamentToggle(
                        selectedTestament: selectedTestament,
                        onSelectTestament: onSelectTestament,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: headerStats),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: people.isEmpty
                      ? Center(
                          child: Text(
                            selectedTestament == 'new'
                                ? '신약 인물 데이터가 없습니다.'
                                : '구약 인물 데이터가 없습니다.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6D5231),
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                              fontSize: 13.2,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: (people.length / 5).ceil(),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, rowIndex) {
                            final start = rowIndex * 5;
                            final end = math.min(start + 5, people.length);
                            final rowPeople = people.sublist(start, end);
                            return _profilePersonProgressRow(
                              rowPeople: rowPeople,
                              completedEventIds: completedEventIds,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profileTestamentToggle({
    required String selectedTestament,
    required ValueChanged<String> onSelectTestament,
  }) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: _floatingPanelDecoration(
        color: const Color(0xFFF7E9D2),
        shadowOpacity: 0.08,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _profileTestamentToggleButton(
            label: '구약',
            selected: selectedTestament != 'new',
            onTap: () => onSelectTestament('old'),
          ),
          const SizedBox(width: 4),
          _profileTestamentToggleButton(
            label: '신약',
            selected: selectedTestament == 'new',
            onTap: () => onSelectTestament('new'),
          ),
        ],
      ),
    );
  }

  Widget _profileMiniActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: _softButtonDecoration(selected: false),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4A331D),
              fontSize: 15.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileShareIdChip({
    required String shareId,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final visibleId = shareId.trim().isEmpty ? '-------' : shareId.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xDDF7E9D2) : const Color(0x9BEEDFC4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                visibleId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF6C4C28)
                      : const Color(0xAA6C4C28),
                  fontSize: 9.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.copy_rounded,
                  size: 10,
                  color: Color(0xFF7A552C),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntercessoryPrayerErrorCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x18A63F2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66A63F2D), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _intercessoryPrayerError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7E3426),
              fontSize: 13.0,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _profileMiniActionButton(
            label: '다시 불러오기',
            onTap: _loadIntercessoryPrayerPage,
          ),
        ],
      ),
    );
  }

  Widget _buildIntercessoryPrayerEmptyCard({required bool enabled}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryCompact = constraints.maxHeight < 150;
        final isCompact = constraints.maxHeight < 180;
        final buttonSize = isVeryCompact ? 32.0 : (isCompact ? 38.0 : 44.0);
        final iconSize = isVeryCompact ? 20.0 : (isCompact ? 24.0 : 26.0);
        final spacing = isVeryCompact ? 4.0 : (isCompact ? 6.0 : 8.0);
        final fontSize = isVeryCompact ? 10.4 : (isCompact ? 11.2 : 12.3);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? _promptAddIntercessoryPrayer : null,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: enabled
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFD99F4A),
                                    Color(0xFFB26B28),
                                  ],
                                )
                              : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFD7CCB9),
                                    Color(0xFFB6A38A),
                                  ],
                                ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 7,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: const Color(0xFFFDF8EE),
                          size: iconSize,
                        ),
                      ),
                      SizedBox(height: spacing),
                      Text(
                        enabled
                            ? '다른 사람의 기도제목을 공유 받아\n함께 기도해요'
                            : '로그인하면 다른 사람의 기도제목을\n함께 볼 수 있어요',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF5A4326),
                          fontSize: fontSize,
                          fontWeight: FontWeight.w800,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntercessoryPrayerItemCard(IntercessoryPrayerItem item) {
    final prayerText = (item.prayerRequest ?? '').trim().isEmpty
        ? '아직 등록된 기도제목이 없어요.'
        : item.prayerRequest!.trim();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xC9F1E3CB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileNetworkAvatar(
            nickname: item.nickname,
            photoUrl: item.photoUrl,
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF452F1A),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.shareId,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF8A6A46),
                        fontSize: 10.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  prayerText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.6,
                    height: 1.34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _profileTinyIconButton(
            tooltip: '삭제',
            onTap: () => _confirmDeleteIntercessoryPrayer(item),
            icon: Icons.delete_outline_rounded,
          ),
        ],
      ),
    );
  }

  Widget _intercessoryPrayerFab({required bool enabled}) {
    return Material(
      color: Colors.transparent,
      elevation: 10,
      shadowColor: const Color(0x33000000),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? _promptAddIntercessoryPrayer : null,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD99F4A), Color(0xFFB26B28)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD7CCB9), Color(0xFFB6A38A)],
                  ),
            border: Border.all(color: const Color(0xFFF2D8A6), width: 1.1),
          ),
          child: const Icon(
            Icons.add_rounded,
            color: Color(0xFFFDF8EE),
            size: 21,
          ),
        ),
      ),
    );
  }

  Widget _profileNetworkAvatar({
    required String nickname,
    required String? photoUrl,
    double size = 42,
  }) {
    final initials = nickname.trim().isEmpty ? '?' : nickname.trim()[0];
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFD79B), Color(0xFFC88A3D)],
        ),
        border: Border.all(color: const Color(0xFF8C6743), width: 1.2),
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl!.trim(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: const Color(0xFF4A331D),
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: const Color(0xFF4A331D),
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _profileTinyIconButton({
    required String tooltip,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xCCF7E9D2),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xAA8E6F48), width: 1),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF7A552C)),
          ),
        ),
      ),
    );
  }

  Widget _profileTestamentToggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: double.infinity,
          alignment: Alignment.center,
          decoration: _softButtonDecoration(selected: selected),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFFDF8EE)
                  : const Color(0xFF4A331D),
              fontSize: 13.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileTopStatCard({required String title, required String value}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: _floatingPanelDecoration(
        color: const Color(0xFFF7E9D2),
        shadowOpacity: 0.08,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6A4C2E),
              fontWeight: FontWeight.w800,
              fontSize: 13.2,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB06B25),
              fontWeight: FontWeight.w900,
              fontSize: 16.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profilePersonProgressRow({
    required List<Person> rowPeople,
    required Set<String> completedEventIds,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x88F5E8CF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xAA8E6F48), width: 1.0),
      ),
      child: Row(
        children: List.generate(rowPeople.length, (index) {
          final person = rowPeople[index];
          final progressData = _profileStudyProgressByPersonId[person.id];
          final progress = progressData?.fraction ?? 0.0;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == rowPeople.length - 1 ? 0 : 6,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openProfilePersonOverview(
                    person: person,
                    completedEventIds: completedEventIds,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final compact = width < 62;
                        final stacked = width < 108;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (compact)
                              Center(
                                child: _weeklyPersonAvatar(
                                  person: person,
                                  size: 24,
                                ),
                              )
                            else if (stacked)
                              Column(
                                children: [
                                  _weeklyPersonAvatar(person: person, size: 26),
                                  const SizedBox(height: 5),
                                  Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF4A331D),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.8,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  _weeklyPersonAvatar(person: person, size: 28),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      person.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF4A331D),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: compact ? 7 : 8,
                                value: progress,
                                backgroundColor: const Color(0x664E3A26),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFC6922D),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _openProfilePersonOverview({
    required Person person,
    required Set<String> completedEventIds,
  }) async {
    final repo = ref.read(storyRepositoryProvider);
    final progressData = _profileStudyProgressByPersonId[person.id];
    final completedCount = progressData?.completedCount ?? 0;
    final totalCount = progressData?.totalCount ?? 0;
    final progress = progressData?.fraction ?? 0.0;
    final eventsFuture = repo.fetchEventsForPerson(person.id);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
              minWidth: 320,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: _modalSurfaceDecoration(),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _weeklyPersonAvatar(person: person, size: 58),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: Text(
                                              person.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF3A2B15),
                                                fontSize: 21,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 5,
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration:
                                                      _headerChipDecoration(),
                                                  child: Text(
                                                    '$completedCount / $totalCount',
                                                    style: const TextStyle(
                                                      color: Color(0xFF6A4C2E),
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    child: LinearProgressIndicator(
                                                      minHeight: 8,
                                                      value: progress,
                                                      backgroundColor:
                                                          const Color(
                                                            0x664E3A26,
                                                          ),
                                                      valueColor:
                                                          const AlwaysStoppedAnimation<
                                                            Color
                                                          >(Color(0xFFC6922D)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        ((person.description ?? '')
                                                    .trim()
                                                    .isNotEmpty
                                                ? person.description
                                                : person.tagline) ??
                                            '아직 등록된 인물 소개가 없습니다.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF4D381F),
                                          fontSize: 13,
                                          height: 1.48,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 28),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '사건 목록',
                              style: TextStyle(
                                color: Color(0xFF4D381F),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: FutureBuilder<List<StoryEvent>>(
                                future: eventsFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    );
                                  }
                                  if (snapshot.hasError) {
                                    return Center(
                                      child: Text(
                                        '사건 목록을 불러오지 못했습니다.\n${snapshot.error}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFA63F2D),
                                          fontWeight: FontWeight.w800,
                                          height: 1.45,
                                        ),
                                      ),
                                    );
                                  }
                                  final events =
                                      snapshot.data ?? const <StoryEvent>[];
                                  if (events.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        '등록된 사건이 없습니다.',
                                        style: TextStyle(
                                          color: Color(0xFF6D5231),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }
                                  return GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          childAspectRatio: 1.48,
                                        ),
                                    itemCount: events.length,
                                    itemBuilder: (context, index) {
                                      final event = events[index];
                                      final isCompleted = completedEventIds
                                          .contains(event.id);
                                      final placeText = (event.placeName ?? '')
                                          .trim();
                                      final yearText =
                                          event.startYear?.toString() ?? '-';
                                      final metaText = placeText.isEmpty
                                          ? yearText
                                          : '$placeText · $yearText';
                                      final summary =
                                          (event.shortStory ??
                                                  event.story ??
                                                  event.summary ??
                                                  '')
                                              .trim();

                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.of(dialogContext).pop();
                                            _openEventDetailPage(event);
                                          },
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              10,
                                              12,
                                              10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isCompleted
                                                  ? const Color(0xFFF3E0BE)
                                                  : const Color(0xEEF7EBD8),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isCompleted
                                                    ? const Color(0xD2C78956)
                                                    : const Color(0xB58E6F48),
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: isCompleted
                                                            ? const Color(
                                                                0xFFC8863B,
                                                              )
                                                            : const Color(
                                                                0xFFF4ECDE,
                                                              ),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: isCompleted
                                                              ? const Color(
                                                                  0xFFF1D39C,
                                                                )
                                                              : const Color(
                                                                  0xBC9A7A4C,
                                                                ),
                                                          width: 1.0,
                                                        ),
                                                      ),
                                                      child: Icon(
                                                        isCompleted
                                                            ? Icons
                                                                  .check_rounded
                                                            : Icons
                                                                  .circle_outlined,
                                                        size: isCompleted
                                                            ? 14
                                                            : 11.5,
                                                        color: isCompleted
                                                            ? const Color(
                                                                0xFFFDF8EE,
                                                              )
                                                            : const Color(
                                                                0xFF8A6A46,
                                                              ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        isCompleted
                                                            ? '완료'
                                                            : '미완료',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        textAlign:
                                                            TextAlign.right,
                                                        style: TextStyle(
                                                          color: isCompleted
                                                              ? const Color(
                                                                  0xFFB26D26,
                                                                )
                                                              : const Color(
                                                                  0xFF8A6A46,
                                                                ),
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  event.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF3D2D18),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                    height: 1.2,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  metaText,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF7A5E38),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                if (summary.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Expanded(
                                                    child: Text(
                                                      summary,
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF5A4326,
                                                        ),
                                                        fontSize: 10.6,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ),
                                                ] else
                                                  const Spacer(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: _modalCloseButton(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _storySection({
    required String title,
    required String content,
    Widget? action,
    Widget? footer,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xF4EFE3CC),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4D381F),
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              content,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF3B2A17),
              ),
            ),
            if (footer != null) footer,
          ],
        ),
      ),
    );
  }

  Widget _storySceneRow(List<String> sceneAssets) {
    final displayedAssets = sceneAssets.take(4).toList(growable: false);
    if (displayedAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    const tileGap = 8.0;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xF4EFE3CC),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - (tileGap * 3)) / 4;
            final viewportHeight = MediaQuery.sizeOf(context).height;
            final maxTileHeight = math.max(180.0, viewportHeight * 0.48);
            final tileHeight = math.min(tileWidth * 1.62, maxTileHeight);
            return Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(displayedAssets.length, (index) {
                  final path = displayedAssets[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == displayedAssets.length - 1 ? 0 : tileGap,
                    ),
                    child: SizedBox(
                      width: tileWidth,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0x9C7C5C39),
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SizedBox(
                            height: tileHeight,
                            child: Image.asset(
                              path,
                              fit: BoxFit.cover,
                              width: tileWidth,
                              height: tileHeight,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bibleMoveButton({required VoidCallback onTap}) {
    return _filledActionButton(
      label: '이동',
      onTap: onTap,
      compact: true,
      minWidth: 78,
    );
  }

  Widget _lockedPreviewOverlay({required Widget child}) {
    return Container(
      color: const Color(0x2EF3E6D0),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: child,
        ),
      ),
    );
  }

  Widget _subPageLoadingOverlay() {
    return AbsorbPointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
          child: Container(
            color: const Color(0x46F5E7D2),
            alignment: Alignment.center,
            child: Container(
              constraints: const BoxConstraints(minWidth: 176, maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: _floatingPanelDecoration(
                color: const Color(0xF5F9EFDF),
                shadowOpacity: 0.12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _subPageLoadingLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5A4020),
                      fontSize: 12.6,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    final event =
        state.events.where((e) => e.id == eventId).firstOrNull ??
        _weeklyStudyData?.events.where((e) => e.id == eventId).firstOrNull;
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
    await _refreshProfileProgressAfterQuizCompletion();
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
              final selectionButtonForeground = const Color(0xFFF8EED9);
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
                      child: _ParchmentTextureLayer(
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
                        _mapControlButton(
                          icon: Icons.search,
                          tooltip: '검색',
                          onTap: _openSearchSheet,
                        ),
                        const SizedBox(height: 8),
                        _mapControlButton(
                          icon: Icons.add,
                          tooltip: '줌 인',
                          onTap: _mapPanelController.zoomIn,
                        ),
                        const SizedBox(height: 6),
                        _mapControlButton(
                          icon: Icons.remove,
                          tooltip: '줌 아웃',
                          onTap: _mapPanelController.zoomOut,
                        ),
                        const SizedBox(height: 6),
                        _mapControlButton(
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
                        _topUtilityButton(
                          label: '사건선택',
                          selected: selectionButtonIsOpen,
                          backgroundColor: selectionButtonBackground,
                          borderColor: selectionButtonBorder,
                          foregroundColor: selectionButtonForeground,
                          boxShadow: selectionButtonShadow,
                          onTap: _toggleSelectionPanelFromTopButton,
                        ),
                        const SizedBox(width: 8),
                        _topUtilityButton(
                          label: '금주 인물',
                          onTap: _openWeeklyTab,
                        ),
                        const SizedBox(width: 8),
                        _topUtilityButton(
                          label: '성경',
                          onTap: _openBibleReaderPopup,
                        ),
                        const SizedBox(width: 8),
                        _topUtilityButton(label: '프로필', onTap: _openProfileTab),
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
          if (_subPageLoading) Positioned.fill(child: _subPageLoadingOverlay()),
        ],
      ),
    );
  }
}

class _WeeklyStudyData {
  const _WeeklyStudyData({
    required this.person,
    required this.events,
    required this.weekStartMonday,
  });

  final Person person;
  final List<StoryEvent> events;
  final DateTime weekStartMonday;
}

class _ProfileEditorDialog extends ConsumerStatefulWidget {
  const _ProfileEditorDialog({
    required this.initialProfile,
    required this.userId,
  });

  final AppUserProfile initialProfile;
  final String userId;

  @override
  ConsumerState<_ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<_ProfileEditorDialog> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _prayerController;
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedBytes;
  String? _selectedExtension;
  bool _saving = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.initialProfile.nickname,
    );
    _prayerController = TextEditingController(
      text: widget.initialProfile.prayerRequest ?? '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _prayerController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 86,
      );
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedBytes = bytes;
        _selectedExtension = picked.path.split('.').last;
        _localError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError = '사진을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() {
        _localError = '닉네임을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _localError = null;
    });

    try {
      String? nextPhotoUrl = widget.initialProfile.photoUrl;
      if (_selectedBytes != null) {
        nextPhotoUrl = await ref
            .read(userRepositoryProvider)
            .uploadProfileImage(
              userId: widget.userId,
              bytes: _selectedBytes!,
              extension: _selectedExtension ?? 'png',
            );
      }

      final updatedProfile = await ref
          .read(userRepositoryProvider)
          .updateUserProfile(
            userId: widget.userId,
            nickname: nickname,
            prayerRequest: _prayerController.text,
            photoUrl: nextPhotoUrl,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updatedProfile);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError = '프로필을 저장하지 못했습니다.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _editorSectionLabel(String title, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF4A331D),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8A6A46),
                fontSize: 10.4,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _editorInputDecoration({
    required String hintText,
    bool multiLine = false,
  }) {
    const borderColor = Color(0xB88E6F48);
    const focusedBorderColor = Color(0xFFB87731);
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF9B805D),
        fontSize: 12.4,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: const Color(0xFFF9F2E7),
      isDense: !multiLine,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: multiLine ? 14 : 12,
      ),
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor, width: 1.1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor, width: 1.1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: focusedBorderColor, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x558E6F48), width: 1.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.initialProfile;
    final initials = profile.nickname.trim().isEmpty
        ? '?'
        : profile.nickname.trim().substring(0, 1);
    final ImageProvider? imageProvider = _selectedBytes != null
        ? MemoryImage(_selectedBytes!)
        : ((profile.photoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(profile.photoUrl!.trim())
              : null);

    final photoCard = Container(
      decoration: _floatingPanelDecoration(
        color: const Color(0xFFF4E6CF),
        shadowOpacity: 0.06,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFD79B), Color(0xFFC88A3D)],
              ),
              border: Border.all(color: const Color(0xFF8C6743), width: 1.8),
            ),
            child: ClipOval(
              child: imageProvider == null
                  ? Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Color(0xFF4A331D),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : Image(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Color(0xFF4A331D),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _pickProfileImage,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('사진 바꾸기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A5523),
                side: const BorderSide(color: Color(0xB88E6F48), width: 1.1),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final formCard = Container(
      decoration: _floatingPanelDecoration(
        color: const Color(0xFFF6EAD4),
        shadowOpacity: 0.05,
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editorSectionLabel('닉네임', subtitle: '다른 사람에게 보이는 이름이에요.'),
          const SizedBox(height: 6),
          TextField(
            controller: _nicknameController,
            enabled: !_saving,
            maxLength: 24,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              color: Color(0xFF402B18),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            onChanged: (_) {
              if (_localError != null) {
                setState(() {
                  _localError = null;
                });
              }
            },
            decoration: _editorInputDecoration(hintText: '예: 기도왕, 다윗러버'),
          ),
          const SizedBox(height: 12),
          _editorSectionLabel('기도제목', subtitle: '함께 기도받고 싶은 내용을 짧게 적어보세요.'),
          const SizedBox(height: 6),
          TextField(
            controller: _prayerController,
            enabled: !_saving,
            maxLength: 120,
            minLines: 3,
            maxLines: 4,
            style: const TextStyle(
              color: Color(0xFF4A331D),
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
            onChanged: (_) {
              if (_localError != null) {
                setState(() {
                  _localError = null;
                });
              }
            },
            decoration: _editorInputDecoration(
              hintText: '예: 이번 주에 마음이 지치지 않도록 함께 기도해주세요.',
              multiLine: true,
            ),
          ),
          if (_localError != null) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x14A63F2D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x55A63F2D), width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                _localError!,
                style: const TextStyle(
                  color: Color(0xFF8E3626),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          decoration: _modalSurfaceDecoration(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 500;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Text(
                            '프로필 수정',
                            style: TextStyle(
                              color: Color(0xFF3F2A17),
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _saving ? null : _saveProfile,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF9B5C1E),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: Text(_saving ? '저장 중' : '저장'),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0x90FFFFFF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xAA8E6F48),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF6E512C),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 156, child: photoCard),
                          const SizedBox(width: 14),
                          Expanded(child: formCard),
                        ],
                      )
                    else ...[
                      photoCard,
                      const SizedBox(height: 14),
                      formCard,
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareIdInputDialog extends StatefulWidget {
  const _ShareIdInputDialog();

  @override
  State<_ShareIdInputDialog> createState() => _ShareIdInputDialogState();
}

class _ShareIdInputDialogState extends State<_ShareIdInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_normalizeText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_normalizeText);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _normalizeText() {
    final normalized = _controller.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (_controller.text == normalized) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }

  void _close([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final shareId = value.text.trim().toUpperCase();
        final canSubmit = shareId.length == 7;

        return ParchmentDialog(
          title: '공유 ID 추가',
          maxWidth: 410,
          showCloseButton: true,
          onClose: _close,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ParchmentDialogTextField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: '예: A1B2C3D',
                maxLength: 7,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                onSubmitted: canSubmit ? (_) => _close(shareId) : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ParchmentDialogActionButton(
                  label: '추가',
                  onTap: canSubmit ? () => _close(shareId) : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubPageScaffold extends StatefulWidget {
  const _SubPageScaffold({
    required this.title,
    required this.child,
    this.compactBackOnly = false,
  });

  final String title;
  final Widget child;
  final bool compactBackOnly;

  @override
  State<_SubPageScaffold> createState() => _SubPageScaffoldState();
}

class _SubPageScaffoldState extends State<_SubPageScaffold> {
  static const double _floatingHomeButtonSize = 44;
  Offset? _floatingHomeOffset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF6EEDC),
                    Color(0xFFF0DFC3),
                    Color(0xFFE7D1AF),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: _ParchmentTextureLayer(
                opacity: 0.11,
                tint: const Color(0xFFB88955),
              ),
            ),
          ),
          SafeArea(
            child: widget.compactBackOnly
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final maxX = math.max(
                        0.0,
                        constraints.maxWidth - _floatingHomeButtonSize,
                      );
                      final maxY = math.max(
                        0.0,
                        constraints.maxHeight - _floatingHomeButtonSize,
                      );
                      final resolvedOffset = Offset(
                        (_floatingHomeOffset?.dx ?? 6).clamp(0.0, maxX),
                        (_floatingHomeOffset?.dy ?? 6).clamp(0.0, maxY),
                      );

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: widget.child,
                            ),
                          ),
                          Positioned(
                            left: resolvedOffset.dx,
                            top: resolvedOffset.dy,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                setState(() {
                                  _floatingHomeOffset = Offset(
                                    (resolvedOffset.dx + details.delta.dx)
                                        .clamp(0.0, maxX),
                                    (resolvedOffset.dy + details.delta.dy)
                                        .clamp(0.0, maxY),
                                  );
                                });
                              },
                              child: _SubPageFloatingHomeButton(
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                        child: Row(
                          children: [
                            _topUtilityButton(
                              label: '이전',
                              onTap: () => Navigator.of(context).pop(),
                              selected: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 40,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: _floatingPanelDecoration(
                                  color: const Color(0xEEF7E9D1),
                                  shadowOpacity: 0.08,
                                ),
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF4A331D),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: widget.child),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InlineLoginPromptCard extends ConsumerStatefulWidget {
  const _InlineLoginPromptCard({
    required this.title,
    required this.description,
    required this.onSignedIn,
  });

  final String title;
  final String description;
  final Future<void> Function() onSignedIn;

  @override
  ConsumerState<_InlineLoginPromptCard> createState() =>
      _InlineLoginPromptCardState();
}

class _InlineLoginPromptCardState
    extends ConsumerState<_InlineLoginPromptCard> {
  bool _submitting = false;
  String? _error;

  Future<void> _handleAppleSignIn() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final nicknameHint = await ref
          .read(authRepositoryProvider)
          .signInWithApple();
      final user = ref.read(signedInUserProvider);
      if (user != null) {
        await ref
            .read(userRepositoryProvider)
            .ensureSignedInUser(user, nicknameHint: nicknameHint);
        await widget.onSignedIn();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '애플 로그인에 실패했습니다.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _handleKakaoSignIn() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithKakao();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '카카오 로그인에 실패했습니다.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _modalSurfaceDecoration(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Opacity(
        opacity: _submitting ? 0.78 : 1,
        child: IgnorePointer(
          ignoring: _submitting,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4A331D),
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6D5231),
                  fontSize: 11.8,
                  height: 1.42,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF2A1B00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: _handleKakaoSignIn,
                  child: const Text('카카오로 로그인'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF161616),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: _handleAppleSignIn,
                  child: const Text('Apple로 로그인'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFA63F2D),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1.38,
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

class _SubPageFloatingHomeButton extends StatelessWidget {
  const _SubPageFloatingHomeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xD06A401E),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF0C36B), width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: Color(0xFFF8EED9),
          ),
        ),
      ),
    );
  }
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _ParchmentTextureLayer extends StatelessWidget {
  const _ParchmentTextureLayer({required this.opacity, required this.tint});

  final double opacity;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(tint, BlendMode.multiply),
        child: Image.asset(
          'assets/elements/parchment_texture.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

BoxDecoration _modalSurfaceDecoration() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8F1E4), Color(0xFFF1E2C6)],
    ),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: const Color(0xC29E7A4C), width: 1.2),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 30,
        offset: Offset(0, 18),
      ),
    ],
  );
}

BoxDecoration _floatingPanelDecoration({
  Color color = const Color(0xF5F7E9D1),
  double shadowOpacity = 0.12,
}) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(const Color(0x14FFFFFF), color), color],
    ),
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xB88E6F48), width: 1.0),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: shadowOpacity),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

BoxDecoration _interactiveCardDecoration({
  required bool selected,
  bool completed = false,
}) {
  if (selected && completed) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF48A86B), Color(0xFF2D7B4D)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD9F0D0), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x24408F5E),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ],
    );
  }
  if (selected) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC8863B), Color(0xFFA85B25)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF1D39C), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26A35B22),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ],
    );
  }
  if (completed) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE3F3DE), Color(0xFFD2EBCB)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF7FB07B), width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x183A7A4B),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
  return BoxDecoration(
    color: const Color(0xEEF7EBD8),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xB58E6F48), width: 1.0),
  );
}

BoxDecoration _headerChipDecoration() {
  return BoxDecoration(
    color: const Color(0xEEF2E1C6),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xBC9A7A4C), width: 1),
  );
}

BoxDecoration _softButtonDecoration({required bool selected}) {
  return BoxDecoration(
    gradient: selected
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC8863B), Color(0xFFA85B25)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F0E2), Color(0xFFEEDDC1)],
          ),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: selected ? const Color(0xFFF1D39C) : const Color(0xBC9A7A4C),
      width: 1.0,
    ),
    boxShadow: selected
        ? const [
            BoxShadow(
              color: Color(0x26A35B22),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ]
        : null,
  );
}

Widget _filledActionButton({
  required String label,
  required VoidCallback onTap,
  bool completed = false,
  bool compact = false,
  double? minWidth,
  double? minHeight,
  double? horizontalPadding,
  double? radius,
  double? fontSize,
}) {
  final height = minHeight ?? (compact ? 34.0 : 42.0);
  final horizontal = horizontalPadding ?? (compact ? 12.0 : 18.0);
  final resolvedRadius = radius ?? (compact ? 12.0 : 15.0);
  final resolvedFontSize = fontSize ?? (compact ? 11.5 : 12.5);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(resolvedRadius),
      child: Container(
        constraints: BoxConstraints(
          minWidth: minWidth ?? 92,
          minHeight: height,
        ),
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: completed
                ? const [Color(0xFF58B573), Color(0xFF2D8754)]
                : const [Color(0xFFD89A47), Color(0xFFB96B2D)],
          ),
          borderRadius: BorderRadius.circular(resolvedRadius),
          border: Border.all(
            color: completed
                ? const Color(0xFFD7EFCE)
                : const Color(0xFFF2D8A6),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: completed
                  ? const Color(0x223D8758)
                  : const Color(0x26A35B22),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFFFDF8EE),
            fontSize: resolvedFontSize,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    ),
  );
}

Widget _modalCloseButton({required VoidCallback onTap, double size = 34}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size * 0.38),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xECF7EBD7),
          borderRadius: BorderRadius.circular(size * 0.38),
          border: Border.all(color: const Color(0xBC9A7A4C), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.close_rounded,
          size: size * 0.52,
          color: const Color(0xFF5C4326),
        ),
      ),
    ),
  );
}

Widget _mapControlButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
}) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xCC2A2118),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD8BF99)),
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFFF8EED9), size: 20),
    ),
  );
}

Widget _topUtilityButton({
  required String label,
  required VoidCallback onTap,
  bool selected = false,
  bool enabled = true,
  Color? backgroundColor,
  Color? borderColor,
  Color? foregroundColor,
  List<BoxShadow>? boxShadow,
}) {
  final resolvedBackgroundColor =
      backgroundColor ??
      (selected ? const Color(0xD06A401E) : const Color(0xB02A2118));
  final resolvedBorderColor =
      borderColor ??
      (selected ? const Color(0xFFF0C36B) : const Color(0xBFD8BF99));
  final resolvedForegroundColor = foregroundColor ?? const Color(0xFFF8EED9);
  final resolvedBoxShadow =
      boxShadow ??
      (selected
          ? [
              BoxShadow(
                color: const Color(0x45F0C36B),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null);

  return Opacity(
    opacity: enabled ? 1 : 0.42,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: resolvedBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: resolvedBorderColor,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: resolvedBoxShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: resolvedForegroundColor,
              fontSize: 13.4,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _bibleDropdownFrame<T>({
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return SizedBox(
    height: 38,
    child: DecoratedBox(
      decoration: _softButtonDecoration(selected: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            iconSize: 12,
            borderRadius: BorderRadius.circular(10),
            dropdownColor: const Color(0xFFF3E4CC),
            iconEnabledColor: const Color(0xFF5B4327),
            style: const TextStyle(
              color: Color(0xFF4A331D),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

class _BibleBookMeta {
  const _BibleBookMeta({required this.name, required this.chapters});

  final String name;
  final int chapters;
}

class _BibleNavigationTarget {
  const _BibleNavigationTarget({
    required this.bookNo,
    required this.chapterNo,
    required this.verseNo,
  });

  final int bookNo;
  final int chapterNo;
  final int verseNo;
}

String _normalizeBibleBookKey(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
}

final Map<String, int> _kBibleRefBookLookup = () {
  final map = <String, int>{};
  for (var i = 0; i < _kBibleBooks.length; i++) {
    map[_normalizeBibleBookKey(_kBibleBooks[i].name)] = i + 1;
  }
  map.addAll(_kBibleRefAliasBookLookup);
  return map;
}();

const Map<String, int> _kBibleRefAliasBookLookup = {
  '창': 1,
  '출': 2,
  '레': 3,
  '민': 4,
  '신': 5,
  '수': 6,
  '삿': 7,
  '룻': 8,
  '삼상': 9,
  '삼하': 10,
  '왕상': 11,
  '왕하': 12,
  '대상': 13,
  '대하': 14,
  '스': 15,
  '느': 16,
  '에': 17,
  '욥': 18,
  '시': 19,
  '잠': 20,
  '전': 21,
  '아': 22,
  '사': 23,
  '렘': 24,
  '애': 25,
  '겔': 26,
  '단': 27,
  '호': 28,
  '욜': 29,
  '암': 30,
  '옵': 31,
  '욘': 32,
  '미': 33,
  '나': 34,
  '합': 35,
  '습': 36,
  '학': 37,
  '슥': 38,
  '말': 39,
  '마': 40,
  '막': 41,
  '눅': 42,
  '요': 43,
  '행': 44,
  '롬': 45,
  '고전': 46,
  '고후': 47,
  '갈': 48,
  '엡': 49,
  '빌': 50,
  '골': 51,
  '살전': 52,
  '살후': 53,
  '딤전': 54,
  '딤후': 55,
  '딛': 56,
  '몬': 57,
  '히': 58,
  '약': 59,
  '벧전': 60,
  '벧후': 61,
  '요일': 62,
  '요이': 63,
  '요삼': 64,
  '유': 65,
  '계': 66,
};

_BibleNavigationTarget? _parseBibleNavigationTarget(String? rawRef) {
  if (rawRef == null) {
    return null;
  }
  final normalized = rawRef
      .replaceAll('：', ':')
      .replaceAll('∼', '-')
      .replaceAll('~', '-')
      .trim();
  if (normalized.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^([가-힣]+)\s*(\d+)\s*[:장]\s*(\d+)',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final rawBook = match.group(1) ?? '';
  final bookNo = _kBibleRefBookLookup[_normalizeBibleBookKey(rawBook)];
  if (bookNo == null) {
    return null;
  }

  final chapterNo = int.tryParse(match.group(2) ?? '');
  final verseNo = int.tryParse(match.group(3) ?? '');
  if (chapterNo == null || chapterNo <= 0 || verseNo == null || verseNo <= 0) {
    return null;
  }

  final maxChapter = _kBibleBooks[bookNo - 1].chapters;
  final safeChapter = chapterNo > maxChapter ? maxChapter : chapterNo;
  return _BibleNavigationTarget(
    bookNo: bookNo,
    chapterNo: safeChapter,
    verseNo: verseNo,
  );
}

const List<_BibleBookMeta> _kBibleBooks = [
  _BibleBookMeta(name: '창세기', chapters: 50),
  _BibleBookMeta(name: '출애굽기', chapters: 40),
  _BibleBookMeta(name: '레위기', chapters: 27),
  _BibleBookMeta(name: '민수기', chapters: 36),
  _BibleBookMeta(name: '신명기', chapters: 34),
  _BibleBookMeta(name: '여호수아', chapters: 24),
  _BibleBookMeta(name: '사사기', chapters: 21),
  _BibleBookMeta(name: '룻기', chapters: 4),
  _BibleBookMeta(name: '사무엘상', chapters: 31),
  _BibleBookMeta(name: '사무엘하', chapters: 24),
  _BibleBookMeta(name: '열왕기상', chapters: 22),
  _BibleBookMeta(name: '열왕기하', chapters: 25),
  _BibleBookMeta(name: '역대상', chapters: 29),
  _BibleBookMeta(name: '역대하', chapters: 36),
  _BibleBookMeta(name: '에스라', chapters: 10),
  _BibleBookMeta(name: '느헤미야', chapters: 13),
  _BibleBookMeta(name: '에스더', chapters: 10),
  _BibleBookMeta(name: '욥기', chapters: 42),
  _BibleBookMeta(name: '시편', chapters: 150),
  _BibleBookMeta(name: '잠언', chapters: 31),
  _BibleBookMeta(name: '전도서', chapters: 12),
  _BibleBookMeta(name: '아가', chapters: 8),
  _BibleBookMeta(name: '이사야', chapters: 66),
  _BibleBookMeta(name: '예레미야', chapters: 52),
  _BibleBookMeta(name: '예레미야애가', chapters: 5),
  _BibleBookMeta(name: '에스겔', chapters: 48),
  _BibleBookMeta(name: '다니엘', chapters: 12),
  _BibleBookMeta(name: '호세아', chapters: 14),
  _BibleBookMeta(name: '요엘', chapters: 3),
  _BibleBookMeta(name: '아모스', chapters: 9),
  _BibleBookMeta(name: '오바댜', chapters: 1),
  _BibleBookMeta(name: '요나', chapters: 4),
  _BibleBookMeta(name: '미가', chapters: 7),
  _BibleBookMeta(name: '나훔', chapters: 3),
  _BibleBookMeta(name: '하박국', chapters: 3),
  _BibleBookMeta(name: '스바냐', chapters: 3),
  _BibleBookMeta(name: '학개', chapters: 2),
  _BibleBookMeta(name: '스가랴', chapters: 14),
  _BibleBookMeta(name: '말라기', chapters: 4),
  _BibleBookMeta(name: '마태복음', chapters: 28),
  _BibleBookMeta(name: '마가복음', chapters: 16),
  _BibleBookMeta(name: '누가복음', chapters: 24),
  _BibleBookMeta(name: '요한복음', chapters: 21),
  _BibleBookMeta(name: '사도행전', chapters: 28),
  _BibleBookMeta(name: '로마서', chapters: 16),
  _BibleBookMeta(name: '고린도전서', chapters: 16),
  _BibleBookMeta(name: '고린도후서', chapters: 13),
  _BibleBookMeta(name: '갈라디아서', chapters: 6),
  _BibleBookMeta(name: '에베소서', chapters: 6),
  _BibleBookMeta(name: '빌립보서', chapters: 4),
  _BibleBookMeta(name: '골로새서', chapters: 4),
  _BibleBookMeta(name: '데살로니가전서', chapters: 5),
  _BibleBookMeta(name: '데살로니가후서', chapters: 3),
  _BibleBookMeta(name: '디모데전서', chapters: 6),
  _BibleBookMeta(name: '디모데후서', chapters: 4),
  _BibleBookMeta(name: '디도서', chapters: 3),
  _BibleBookMeta(name: '빌레몬서', chapters: 1),
  _BibleBookMeta(name: '히브리서', chapters: 13),
  _BibleBookMeta(name: '야고보서', chapters: 5),
  _BibleBookMeta(name: '베드로전서', chapters: 5),
  _BibleBookMeta(name: '베드로후서', chapters: 3),
  _BibleBookMeta(name: '요한일서', chapters: 5),
  _BibleBookMeta(name: '요한이서', chapters: 1),
  _BibleBookMeta(name: '요한삼서', chapters: 1),
  _BibleBookMeta(name: '유다서', chapters: 1),
  _BibleBookMeta(name: '요한계시록', chapters: 22),
];
