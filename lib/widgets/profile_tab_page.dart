import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../models/app_notification.dart';
import '../models/app_user_profile.dart';
import '../models/character.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/quiz_attempt_summary.dart';
import '../models/saved_bible_verse.dart';
import '../models/story_event.dart';
import '../models/user_companion_diary_entry.dart';
import '../screens/bible_progress_screen.dart';
import '../screens/companion_diary_editor_screen.dart';
import '../screens/legal_documents_screen.dart';
import '../screens/saved_verses_screen.dart';
import '../services/app_analytics_event.dart';
import '../services/app_monitoring_service.dart';
import '../state/auth_providers.dart';
import '../state/daily_mission_provider.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/bible_book_meta.dart';
import '../utils/bible_reading_progress.dart';
import '../utils/kst_date.dart';
import '../utils/scene_asset_loader.dart';
import '../utils/story_visibility.dart';
import '../utils/today_activity_summary.dart';
import 'home/story_root_navigation_bar.dart';
import 'home/today_activity_header.dart';
import 'inline_login_prompt_card.dart';
import 'map/map_attribution_dialog.dart';
import 'notification/notification_bell_button.dart';
import 'parchment_dialog.dart';
import 'parchment_page_scaffold.dart';
import 'profile/companion_diary_entry_card.dart';
import 'profile/glowing_add_button.dart';
import 'profile/profile_activity_badge.dart';
import 'profile/profile_emotion_diary.dart';
import 'profile/profile_event_review_grid.dart';
import 'profile/profile_feature_flags.dart';
import 'profile/profile_quiz_stats.dart';
import 'profile_editor_dialog.dart';
import 'saved_verse_row.dart';
import 'share_id_input_dialog.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';
import 'v2/era_pick_rows.dart';
import 'v2/region_event_list.dart' show StoryEventThumbCard;

// 화면 코드를 도메인별로 part 파일로 분리.
// 각 part 파일은 ProfileTabPageState에 대한 extension으로 메소드를 추가한다.
part 'profile/profile_helpers.dart';
part 'profile/profile_intercessory_prayer.dart';
part 'profile/profile_left_panel.dart';
part 'profile/profile_progress_section.dart';
part 'profile/profile_right_panel.dart';
part 'profile/profile_settings_sheet.dart';

enum ProfileEventOpenSource { general, targetOnly, detailOnly }

typedef ProfileEventDetailCallback =
    void Function(StoryEvent event, {ProfileEventOpenSource? source});

const Map<String, int> _profileStoryEraCodeOrder = {
  'era_primeval': 0,
  'era_patriarch': 1,
  'era_exodus': 2,
  'era_judges': 3,
  'era_monarchy': 4,
  'era_divided_kingdom': 5,
  'era_exile_return': 6,
  'era_nt_public_ministry': 7,
  'era_nt_apostolic': 8,
  'era_nt_post_apostolic': 9,
};

/// 프로필 탭 페이지 (프로필 정보 + 이야기 탐험/진행 대시보드).
///
/// 기도 기능은 pending 상태로 코드/DB 배관만 보존하고 현재 화면에는 노출하지 않는다.
///
/// 외부 콜백:
/// - [onStartQuiz]: 인물 상세에서 이벤트 퀴즈 시작
/// - [onOpenEventDetail]: 이벤트 상세 페이지 열기
/// - [onOpenBibleReader]: 저장 구절 이동 시 성경 리더 열기
/// - [onOpenAppPublications]: 공지사항과 사용법 페이지 열기
/// - [onBackToHome]: 프로필 뒤로가기 시 홈 초기 화면으로 복귀
class ProfileTabPage extends ConsumerStatefulWidget {
  const ProfileTabPage({
    super.key,
    required this.onStartQuiz,
    required this.onOpenEventDetail,
    required this.onOpenBibleReader,
    required this.onOpenAppPublications,
    required this.onNavigateNotification,
    required this.onOpenNotificationHistory,
    this.onExploreStoriesFromHome,
    this.onBackToHome,
    this.embedded = false,
    this.activitySummary = TodayActivitySummary.empty,
  });

  final void Function(String eventId) onStartQuiz;
  final ProfileEventDetailCallback onOpenEventDetail;
  final Future<void> Function({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  })
  onOpenBibleReader;
  final VoidCallback onOpenAppPublications;
  final void Function(AppNotification notification) onNavigateNotification;
  final VoidCallback onOpenNotificationHistory;
  final VoidCallback? onExploreStoriesFromHome;
  final VoidCallback? onBackToHome;
  final bool embedded;
  final TodayActivitySummary activitySummary;

  @override
  ConsumerState<ProfileTabPage> createState() => ProfileTabPageState();
}

enum _ProfileContentTab { prayer, saved, verses }

enum _StoryProgressFilter { all, completed, incomplete }

class ProfileTabPageState extends ConsumerState<ProfileTabPage> {
  static const int _intercessoryPrayerPageSize = 12;
  static const int _profilePreviewPageSize = 5;

  final ScrollController _intercessoryPrayerScrollController =
      ScrollController();

  List<Character> _profileAllPeople = const [];
  List<StoryEvent> _profileAllEvents = const [];
  AppUserProfile? _profileUser;
  _ProfileContentTab _profileContentTab = _ProfileContentTab.prayer;
  List<StoryEvent> _profileSavedEventsPreview = const [];
  List<SavedBibleVerse> _profileSavedVersesPreview = const [];
  List<UserCompanionDiaryEntry> _profileCompanionDiaryEntries = const [];
  int _profileSavedVersesCount = 0;
  bool _profileSavedEventsLoading = false;
  bool _profileSavedVersesLoading = false;
  bool _profileCompanionDiaryLoading = false;
  String? _profileSavedEventsError;
  String? _profileSavedVersesError;
  String? _profileCompanionDiaryError;
  List<IntercessoryPrayerItem> _intercessoryPrayerItems = const [];
  bool _intercessoryPrayerLoading = false;
  bool _intercessoryPrayerLoadingMore = false;
  bool _intercessoryPrayerHasNextPage = false;
  String? _intercessoryPrayerError;
  int _intercessoryPrayerPageIndex = 0;
  bool _profileLoading = false;
  String? _profileError;
  bool _signingOut = false;
  bool _deletingAccount = false;
  Timer? _profileKstMidnightTimer;
  ProviderSubscription<User?>? _authUserSubscription;

  @override
  void initState() {
    super.initState();
    _intercessoryPrayerScrollController.addListener(
      _handleIntercessoryPrayerScroll,
    );
    _authUserSubscription = ref.listenManual<User?>(signedInUserProvider, (
      previous,
      next,
    ) {
      if (previous?.id == next?.id) {
        return;
      }
      _handleProfileAuthUserChanged(next);
    });
    _scheduleProfileKstMidnightRefresh();
    Future.microtask(_loadInitialProfileData);
  }

  @override
  void dispose() {
    _profileKstMidnightTimer?.cancel();
    _authUserSubscription?.close();
    _intercessoryPrayerScrollController
      ..removeListener(_handleIntercessoryPrayerScroll)
      ..dispose();
    super.dispose();
  }

  void _handleProfileAuthUserChanged(User? user) {
    // 루트 탭으로 포함된 화면은 StoryHomeScreen이 인증 범위를 한 번만
    // 초기화한다. 단독 화면으로 사용될 때에만 여기서 컨트롤러를 정리해,
    // 같은 인증 변경을 두 번 처리하며 진행 중인 요청을 무효화하지 않는다.
    if (!widget.embedded) {
      ref.read(storyControllerProvider.notifier).clearUserScopedData();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profileUser = null;
      _profileContentTab = _ProfileContentTab.prayer;
      _profileSavedEventsPreview = const [];
      _profileSavedVersesPreview = const [];
      _profileCompanionDiaryEntries = const [];
      _profileSavedVersesCount = 0;
      _profileSavedEventsLoading = false;
      _profileSavedVersesLoading = false;
      _profileCompanionDiaryLoading = false;
      _profileSavedEventsError = null;
      _profileSavedVersesError = null;
      _profileCompanionDiaryError = null;
      _intercessoryPrayerItems = const [];
      _intercessoryPrayerLoading = false;
      _intercessoryPrayerLoadingMore = false;
      _intercessoryPrayerHasNextPage = false;
      _intercessoryPrayerError = null;
      _intercessoryPrayerPageIndex = 0;
      _profileLoading = false;
      _profileError = null;
    });
    if (user != null) {
      unawaited(_loadInitialProfileData());
    }
  }

  Future<void> _loadInitialProfileData() async {
    // 루트 탭에서는 StoryHomeScreen이 인증 데이터 초기화를 소유한다. 단독
    // 프로필 화면만 자체 갱신해, 앱 탭 진입 때 동일한 사용자 쿼리를 반복하지
    // 않으면서 독립 라우트의 기존 동작은 유지한다.
    if (!widget.embedded) {
      await ref.read(storyControllerProvider.notifier).refreshUserScopedData();
    }
    if (!mounted) {
      return;
    }
    await _loadProfilePeople(forceRefresh: true);
  }

  bool _isCurrentProfileUser(String userId) =>
      ref.read(signedInUserProvider)?.id == userId;

  void _scheduleProfileKstMidnightRefresh() {
    _profileKstMidnightTimer?.cancel();
    final delay =
        durationUntilNextKstMidnight(DateTime.now()) +
        const Duration(seconds: 1);
    _profileKstMidnightTimer = Timer(delay, _handleProfileKstDateChanged);
  }

  void _handleProfileKstDateChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(
      ref.read(storyControllerProvider.notifier).refreshEventEmotionMarks(),
    );
    unawaited(
      ref
          .read(storyControllerProvider.notifier)
          .refreshCompletedBibleChapterKeys(),
    );
    unawaited(_loadProfileCompanionDiaryEntries(showLoading: false));
    _scheduleProfileKstMidnightRefresh();
  }

  /// 외부에서 퀴즈 완료 후 프로필 진행도를 다시 불러올 때 호출한다.
  Future<void> refreshProgressAfterQuizCompletion() async {
    if (!mounted) {
      return;
    }
    if (_profileUser == null && _profileAllPeople.isEmpty) {
      return;
    }
    await _loadProfilePeople(forceRefresh: true);
  }

  /// 프로필 탭에 진입하거나 저장/말씀 탭을 다시 열 때 최신 저장 목록을 읽는다.
  Future<void> refreshSavedContentPreviews({bool showLoading = true}) async {
    if (!mounted) {
      return;
    }
    await _refreshProfileTabPreviews(showLoading: showLoading);
  }

  Future<void> _refreshProfilePage() async {
    if (!mounted) {
      return;
    }
    await ref.read(storyControllerProvider.notifier).refreshUserScopedData();
    await _loadProfilePeople(forceRefresh: true);
  }

  void _selectProfileContentTab(_ProfileContentTab tab) {
    setState(() => _profileContentTab = tab);
    switch (tab) {
      case _ProfileContentTab.saved:
        unawaited(_loadProfileSavedEventsPreview(showLoading: true));
      case _ProfileContentTab.verses:
        unawaited(_loadProfileSavedVersesPreview(showLoading: true));
      case _ProfileContentTab.prayer:
        break;
    }
  }

  void _setDeletingAccount(bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _deletingAccount = value;
    });
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
      if (!mounted || !_isCurrentProfileUser(user.id)) {
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
    } catch (error) {
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _intercessoryPrayerLoading = false;
        _intercessoryPrayerLoadingMore = false;
        _intercessoryPrayerError = '중보할 기도제목을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _loadProfileSavedEventsPreview({bool showLoading = true}) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedEventsPreview = const [];
        _profileSavedEventsLoading = false;
        _profileSavedEventsError = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        if (showLoading) {
          _profileSavedEventsLoading = true;
        }
        _profileSavedEventsError = null;
      });
    }

    try {
      await ref.read(storyControllerProvider.notifier).refreshSavedEventIds();
      if (!_isCurrentProfileUser(user.id)) {
        return;
      }
      final savedIds = ref.read(storyControllerProvider).savedEventIds;
      final events = await ref
          .read(storyRepositoryProvider)
          .fetchEventsByIds(savedIds);
      final sorted = _sortEventsByEraThenIndex(
        events,
        ref.read(storyControllerProvider).eras,
      );
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileSavedEventsPreview = sorted;
        _profileSavedEventsLoading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileSavedEventsLoading = false;
        _profileSavedEventsError = '저장한 이야기를 불러오지 못했습니다.\n$error';
      });
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
        _profileSavedVersesCount = 0;
        _profileSavedVersesLoading = false;
        _profileSavedVersesError = null;
      });
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
      if (!_isCurrentProfileUser(user.id)) {
        return;
      }
      final totalCount = await ref
          .read(userRepositoryProvider)
          .countSavedVerses(userId: user.id);
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileSavedVersesPreview = result.items;
        _profileSavedVersesCount = totalCount;
        _profileSavedVersesLoading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileSavedVersesLoading = false;
        _profileSavedVersesError = '저장한 말씀을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _loadProfileCompanionDiaryEntries({
    bool showLoading = true,
  }) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileCompanionDiaryEntries = const [];
        _profileCompanionDiaryLoading = false;
        _profileCompanionDiaryError = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        if (showLoading) {
          _profileCompanionDiaryLoading = true;
        }
        _profileCompanionDiaryError = null;
      });
    }

    try {
      final entries = await ref
          .read(userRepositoryProvider)
          .fetchCompanionDiaryEntries(userId: user.id);
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileCompanionDiaryEntries = entries;
        _profileCompanionDiaryLoading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentProfileUser(user.id)) {
        return;
      }
      setState(() {
        _profileCompanionDiaryLoading = false;
        _profileCompanionDiaryError = '동행 일지를 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<UserCompanionDiaryEntry> _saveCompanionDiaryEntry({
    required DateTime entryDate,
    required String title,
    required String body,
  }) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      throw StateError('로그인 정보를 찾을 수 없습니다.');
    }
    final isUpdate = _profileCompanionDiaryEntries.any(
      (entry) => _isSameCompanionDiaryDate(entry.entryDate, entryDate),
    );

    late final UserCompanionDiaryEntry saved;
    try {
      saved = await ref
          .read(userRepositoryProvider)
          .upsertCompanionDiaryEntry(
            userId: user.id,
            entryDate: entryDate,
            title: title,
            body: body,
          );
    } catch (error, stackTrace) {
      AppMonitoringService.instance.recordNonFatal(
        error,
        stackTrace,
        reason: 'Companion diary save failed',
      );
      rethrow;
    }
    await AppMonitoringService.instance.logAnalyticsEvent(
      AppAnalyticsEvent.diaryEntrySaved(isUpdate: isUpdate),
    );
    if (mounted) {
      setState(() {
        _profileCompanionDiaryEntries = _replaceCompanionDiaryEntry(
          _profileCompanionDiaryEntries,
          saved,
        );
        _profileCompanionDiaryError = null;
      });
    }
    return saved;
  }

  Future<void> _deleteCompanionDiaryEntry(UserCompanionDiaryEntry entry) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      throw StateError('로그인 정보를 찾을 수 없습니다.');
    }

    await ref
        .read(userRepositoryProvider)
        .deleteCompanionDiaryEntry(userId: user.id, entryDate: entry.entryDate);
    if (!mounted) {
      return;
    }
    setState(() {
      _profileCompanionDiaryEntries = _profileCompanionDiaryEntries
          .where((item) => item.id != entry.id)
          .toList(growable: false);
      _profileCompanionDiaryError = null;
    });
  }

  Future<void> _refreshProfileTabPreviews({bool showLoading = true}) async {
    await Future.wait([
      _loadProfileSavedEventsPreview(showLoading: showLoading),
      _loadProfileSavedVersesPreview(showLoading: showLoading),
      _loadProfileCompanionDiaryEntries(showLoading: showLoading),
    ]);
  }

  Future<void> _loadProfilePeople({bool forceRefresh = false}) async {
    if (!forceRefresh && (_profileAllPeople.isNotEmpty || _profileLoading)) {
      return;
    }
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });

    final requestedUserId = ref.read(signedInUserProvider)?.id;
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
      final eras = state.eras;
      final catalogResults = await Future.wait<Object?>([
        ref.read(dailyExplorationCatalogProvider.future),
        repo.fetchAllActiveCharacters(),
      ]);
      final allCatalogEvents = catalogResults[0]! as List<StoryEvent>;
      final activeCharacters = catalogResults[1]! as List<Character>;
      final allEvents = _sortEventsByEraThenIndex(allCatalogEvents, eras);
      final characterOrder = <String, int>{};
      for (final event in allEvents) {
        for (final code in event.characterCodes) {
          characterOrder.putIfAbsent(code, () => characterOrder.length);
        }
      }
      final allPeople =
          activeCharacters
              .where((character) => characterOrder.containsKey(character.code))
              .toList()
            ..sort((a, b) {
              final order = (characterOrder[a.code] ?? 1 << 30).compareTo(
                characterOrder[b.code] ?? 1 << 30,
              );
              return order != 0 ? order : _compareProfilePeople(a, b);
            });

      AppUserProfile? profile;

      if (user != null) {
        profile = await userRepo.ensureSignedInUser(user);
      }

      if (!mounted || ref.read(signedInUserProvider)?.id != requestedUserId) {
        return;
      }
      setState(() {
        _profileAllPeople = allPeople;
        _profileAllEvents = allEvents;
        _profileUser = profile;
        if (user == null) {
          _intercessoryPrayerItems = const [];
          _intercessoryPrayerHasNextPage = false;
          _intercessoryPrayerPageIndex = 0;
          _intercessoryPrayerError = null;
          _profileCompanionDiaryEntries = const [];
          _profileCompanionDiaryLoading = false;
          _profileCompanionDiaryError = null;
        }
        _profileLoading = false;
        _profileError = allPeople.isEmpty ? '인물 데이터가 없습니다.' : null;
      });
      if (user != null) {
        await Future.wait([
          if (!profilePrayerFeaturePending) _loadIntercessoryPrayerPage(),
          _refreshProfileTabPreviews(),
        ]);
      }
    } catch (error) {
      if (!mounted || ref.read(signedInUserProvider)?.id != requestedUserId) {
        return;
      }
      setState(() {
        _profileLoading = false;
        _profileError = '프로필 인물 데이터를 불러오지 못했습니다: $error';
      });
    }
  }

  List<StoryEvent> _sortEventsByEraThenIndex(
    List<StoryEvent> events,
    List<Era> eras,
  ) {
    final eraById = <String, Era>{for (final era in eras) era.id: era};
    final sorted = events.where((event) {
      final era = eraById[event.eraId];
      if (era == null || !isStoryEventVisibleInApp(event, eraById: eraById)) {
        return false;
      }
      return _profileStoryEraCodeOrder.containsKey(era.code);
    }).toList();
    sorted.sort((a, b) {
      final aEra = eraById[a.eraId];
      final bEra = eraById[b.eraId];
      final eraOrder = (_profileStoryEraCodeOrder[aEra?.code] ?? 1 << 30)
          .compareTo(_profileStoryEraCodeOrder[bEra?.code] ?? 1 << 30);
      if (eraOrder != 0) {
        return eraOrder;
      }
      final storyOrder = a.storyIndex.compareTo(b.storyIndex);
      if (storyOrder != 0) {
        return storyOrder;
      }
      final rankInEraOrder = a.rankInEra.compareTo(b.rankInEra);
      if (rankInEraOrder != 0) {
        return rankInEraOrder;
      }
      return a.globalRank.compareTo(b.globalRank);
    });
    return sorted;
  }

  int _compareProfilePeople(Character a, Character b) {
    final displayOrder = a.displayOrder.compareTo(b.displayOrder);
    if (displayOrder != 0) {
      return displayOrder;
    }
    return a.name.compareTo(b.name);
  }

  bool _stringSetEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }

  List<UserCompanionDiaryEntry> _replaceCompanionDiaryEntry(
    List<UserCompanionDiaryEntry> entries,
    UserCompanionDiaryEntry next,
  ) {
    final replaced = <UserCompanionDiaryEntry>[];
    var didReplace = false;
    for (final entry in entries) {
      if (_isSameCompanionDiaryDate(entry.entryDate, next.entryDate)) {
        if (!didReplace) {
          replaced.add(next);
          didReplace = true;
        }
      } else {
        replaced.add(entry);
      }
    }
    if (!didReplace) {
      replaced.add(next);
    }
    replaced.sort((a, b) {
      final dateOrder = b.entryDate.compareTo(a.entryDate);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return replaced;
  }

  bool _isSameCompanionDiaryDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
    final profile = _profileUser ?? _guestPreviewProfile();
    if (_profileLoading && _profileAllPeople.isEmpty) {
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
            style: const TextStyle(color: AppColors.parchmentCream),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 세로 모드(좁은 폭): 내 정보(왼쪽 패널) 를 위에, 출석/인물 정보(오른쪽
        // 패널) 를 아래에 세로로 쌓는다. 두 패널 내부에 Expanded + ListView 가
        // 있어서 부모 Column 에서 unbounded height 가 되면 안 되므로 각각 고정
        // 높이로 감싼다.
        final isNarrow = constraints.maxWidth < 720;
        final showPrayerActivitySection = !profilePrayerFeaturePending;
        final activitySectionHeight = _profileLeftCardHeight(
          isAuthenticated: isAuthenticated,
        );
        if (isNarrow) {
          return RefreshIndicator(
            color: AppPaletteTheme.of(context).primary,
            onRefresh: _refreshProfilePage,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileHeader(profile),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x2,
                    ),
                    child: TodayActivityLabelRail(
                      summary: widget.activitySummary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProfileProgressSection(scrollBody: false),
                  if (showPrayerActivitySection) ...[
                    const SizedBox(height: 8),
                    _profileSectionsFrame(
                      child: SizedBox(
                        height: activitySectionHeight,
                        child: _buildProfileActivitySection(
                          profile: profile,
                          isAuthenticated: isAuthenticated,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        final gap = (constraints.maxWidth * 0.012).clamp(4.0, 10.0).toDouble();
        final leftWidth = (constraints.maxWidth * 0.425)
            .clamp(278.0, 416.0)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProfileHeader(profile),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
                child: TodayActivityLabelRail(summary: widget.activitySummary),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: showPrayerActivitySection
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildProfileProgressSection()),
                          SizedBox(width: gap),
                          SizedBox(
                            width: leftWidth,
                            child: _profileSectionsFrame(
                              child: SizedBox(
                                height: activitySectionHeight,
                                child: _buildProfileActivitySection(
                                  profile: profile,
                                  isAuthenticated: isAuthenticated,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildProfileProgressSection(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileSectionsFrame({required Widget child}) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: floatingPanelDecoration(color: palette.panelSurface),
      child: Padding(padding: const EdgeInsets.all(8), child: child),
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
          ProfileEditorDialog(initialProfile: profile, userId: user.id),
    );
    if (!mounted || updatedProfile == null) {
      return;
    }
    setState(() {
      _profileUser = updatedProfile;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프로필이 저장되었어요.')));
  }

  Future<void> _openSavedVersesPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedVersesScreen(
          onOpenVerse: (verse) {
            return widget.onOpenBibleReader(
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

  Future<void> _openLegalDocumentsPage() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LegalDocumentsScreen()),
    );
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
      builder: (_) => const ShareIdInputDialog(),
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

  @override
  Widget build(BuildContext context) {
    ref.listen<StoryState>(storyControllerProvider, (previous, next) {
      if (previous == null ||
          _stringSetEquals(previous.savedEventIds, next.savedEventIds)) {
        return;
      }
      unawaited(_loadProfileSavedEventsPreview(showLoading: false));
    });
    final state = ref.watch(storyControllerProvider);
    final isAuthenticated = ref.watch(signedInUserProvider) != null;
    final palette = AppPaletteTheme.of(context);
    return SubPageScaffold(
      title: '',
      compactBackOnly: true,
      showBackButton: !widget.embedded,
      compactTopPadding: 0,
      topSurfaceColor: storyRootNavigationSurfaceColor(palette),
      topSurfaceExtent: 80,
      onBack: widget.onBackToHome,
      child: Stack(
        children: [
          Positioned.fill(
            child: isAuthenticated
                ? _buildProfileBody(state: state, isAuthenticated: true)
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                    child: IgnorePointer(
                      key: const ValueKey('profile-locked-content-blocker'),
                      child: Opacity(
                        opacity: 0.96,
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
              child: lockedPreviewOverlay(
                child: InlineLoginPromptCard(
                  title: '내정보를 보려면 로그인이 필요해요',
                  description: '내정보, 저장한 이야기와 말씀, 공부 기록은 로그인 후 사용할 수 있어요.',
                  onSignedIn: () async {
                    if (!mounted) {
                      return;
                    }
                    await _loadProfilePeople(forceRefresh: true);
                  },
                ),
              ),
            ),
        ],
      ),
    );
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
}
