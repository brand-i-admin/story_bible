import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/character.dart';
import '../models/character_study_progress.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/saved_bible_verse.dart';
import '../models/story_event.dart';
import '../screens/legal_documents_screen.dart';
import '../screens/saved_verses_screen.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import '../utils/scene_asset_loader.dart';
import 'avatar_progress_ring.dart';
import 'character_avatar.dart';
import 'emotion_badge_icon.dart';
import 'font_scale_bottom_sheet.dart';
import 'inline_login_prompt_card.dart';
import 'parchment_dialog.dart';
import 'profile/profile_emotion_diary.dart';
import 'profile/profile_emotion_stats.dart';
import 'profile/profile_event_review_grid.dart';
import 'profile/profile_mini_map.dart';
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
part 'profile/profile_character_overview.dart';
part 'profile/profile_progress_section.dart';
part 'profile/profile_right_panel.dart';
part 'profile/profile_settings_sheet.dart';

enum ProfileEventOpenSource { general, place, character }

typedef ProfileEventDetailCallback =
    void Function(
      StoryEvent event, {
      ProfileEventOpenSource? source,
      String? sourceId,
    });

/// 프로필 탭 페이지 (프로필 정보 + 인물 진행도 + 기록/기도/저장/말씀).
///
/// 외부 콜백:
/// - [onStartQuiz]: 인물 상세에서 이벤트 퀴즈 시작
/// - [onOpenEventDetail]: 이벤트 상세 페이지 열기
/// - [onOpenBibleReader]: 저장 구절 이동 시 성경 리더 열기
class ProfileTabPage extends ConsumerStatefulWidget {
  const ProfileTabPage({
    super.key,
    required this.onStartQuiz,
    required this.onOpenEventDetail,
    required this.onOpenBibleReader,
  });

  final void Function(String eventId) onStartQuiz;
  final ProfileEventDetailCallback onOpenEventDetail;
  final Future<void> Function({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  })
  onOpenBibleReader;

  @override
  ConsumerState<ProfileTabPage> createState() => ProfileTabPageState();
}

enum _ProfileContentTab { records, prayer, saved, verses }

enum _ProfileQuizReviewFilter { wrong, confused }

/// "진행률 표시" 섹션의 탭. `life` = 나의 다이어리,
/// `place` = 장소로 시작 (지도+region), `walk` = 인물과 걷기.
enum _ProfileProgressTab { life, place, walk }

class ProfileTabPageState extends ConsumerState<ProfileTabPage> {
  static const int _intercessoryPrayerPageSize = 12;
  static const int _profilePreviewPageSize = 5;

  final ScrollController _intercessoryPrayerScrollController =
      ScrollController();

  List<Character> _profileAllPeople = const [];
  Map<String, String> _profileCharacterTestamentByCode = const {};
  AppUserProfile? _profileUser;
  Map<String, CharacterStudyProgress> _profileStudyProgressByCharacterCode =
      const {};
  Map<String, int> _profileCharacterTimelineOrderByCode = const {};
  _ProfileContentTab _profileContentTab = _ProfileContentTab.records;
  List<StoryEvent> _profileSavedEventsPreview = const [];
  List<SavedBibleVerse> _profileSavedVersesPreview = const [];
  bool _profileSavedEventsLoading = false;
  bool _profileSavedVersesLoading = false;
  String? _profileSavedEventsError;
  String? _profileSavedVersesError;
  List<IntercessoryPrayerItem> _intercessoryPrayerItems = const [];
  bool _intercessoryPrayerLoading = false;
  bool _intercessoryPrayerLoadingMore = false;
  bool _intercessoryPrayerHasNextPage = false;
  String? _intercessoryPrayerError;
  int _intercessoryPrayerPageIndex = 0;
  String _profileSelectedTestament = 'old';
  // 진행률 섹션 — 기본 탭은 나의 다이어리 (감정 새김 기반 첫인상 강조).
  _ProfileProgressTab _profileProgressTab = _ProfileProgressTab.life;
  // "장소로 시작" 탭에서 사용자가 선택한 era id (null = 미선택, 안내 메시지).
  String? _profileProgressSelectedEraId;
  bool _profileLoading = false;
  String? _profileError;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _intercessoryPrayerScrollController.addListener(
      _handleIntercessoryPrayerScroll,
    );
    Future.microtask(() => _loadProfilePeople(forceRefresh: true));
  }

  @override
  void dispose() {
    _intercessoryPrayerScrollController
      ..removeListener(_handleIntercessoryPrayerScroll)
      ..dispose();
    super.dispose();
  }

  String _eraTestament(Era era) {
    final raw = era.testament.toString().trim().toLowerCase();
    if (raw == 'new' || raw == 'nt' || raw == 'new_testament') {
      return 'new';
    }
    if (era.code.toString().startsWith('era_nt_')) {
      return 'new';
    }
    return 'old';
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
    } catch (error) {
      if (!mounted) {
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
      final savedIds = ref.read(storyControllerProvider).savedEventIds;
      final events = await ref
          .read(storyRepositoryProvider)
          .fetchEventsByIds(savedIds);
      final sorted = _sortEventsByEraThenIndex(
        events,
        ref.read(storyControllerProvider).eras,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedEventsPreview = sorted;
        _profileSavedEventsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
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
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedVersesPreview = result.items;
        _profileSavedVersesLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileSavedVersesLoading = false;
        _profileSavedVersesError = '저장한 말씀을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _refreshProfileTabPreviews({bool showLoading = true}) async {
    await Future.wait([
      _loadProfileSavedEventsPreview(showLoading: showLoading),
      _loadProfileSavedVersesPreview(showLoading: showLoading),
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
        state.eras.map((era) => repo.fetchCharactersByEra(era.id)),
      );
      final characterTimelineOrderByCode = await repo
          .fetchCharacterTimelineOrder();

      final characterByCode = <String, Character>{};
      final testamentByCharacterCode = <String, String>{};
      for (var i = 0; i < state.eras.length; i++) {
        final era = state.eras[i];
        final eraPeople = peopleByEra[i];
        final testament = _eraTestament(era);
        for (final character in eraPeople) {
          characterByCode.putIfAbsent(character.code, () => character);
          testamentByCharacterCode.putIfAbsent(character.code, () => testament);
        }
      }

      final allPeople = characterByCode.values.toList()
        ..sort(
          (a, b) => _compareProfilePeople(
            a,
            b,
            timelineOrderByCode: characterTimelineOrderByCode,
          ),
        );

      AppUserProfile? profile;
      Map<String, CharacterStudyProgress> progressByCharacterCode = const {};

      if (user != null) {
        profile = await userRepo.ensureSignedInUser(user);
        final studyProgress = await userRepo.fetchCharacterStudyProgress(
          userId: user.id,
          people: allPeople,
        );
        progressByCharacterCode = {
          for (final progress in studyProgress)
            progress.character.code: progress,
        };
        await ref
            .read(storyControllerProvider.notifier)
            .refreshQuizAttemptSummaries();
        await ref.read(storyControllerProvider.notifier).refreshSavedEventIds();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _profileAllPeople = allPeople;
        _profileCharacterTestamentByCode = testamentByCharacterCode;
        _profileUser = profile;
        _profileStudyProgressByCharacterCode = progressByCharacterCode;
        _profileCharacterTimelineOrderByCode = characterTimelineOrderByCode;
        if (user == null) {
          _intercessoryPrayerItems = const [];
          _intercessoryPrayerHasNextPage = false;
          _intercessoryPrayerPageIndex = 0;
          _intercessoryPrayerError = null;
        }
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

  List<Character> _profilePeople(StoryState state) {
    final people =
        [
            ...(_profileAllPeople.isNotEmpty
                ? _profileAllPeople
                : state.characters),
          ]
          ..retainWhere((character) {
            final testament =
                _profileCharacterTestamentByCode[character.code] ?? 'old';
            return testament == _profileSelectedTestament;
          })
          ..sort(
            (a, b) => _compareProfilePeople(
              a,
              b,
              timelineOrderByCode: _profileCharacterTimelineOrderByCode,
            ),
          );
    return people;
  }

  List<StoryEvent> _sortEventsByEraThenIndex(
    List<StoryEvent> events,
    List<Era> eras,
  ) {
    final orderByEraId = <String, int>{
      for (final era in eras) era.id: era.displayOrder,
    };
    final sorted = [...events];
    sorted.sort((a, b) {
      final eraOrder = (orderByEraId[a.eraId] ?? 1 << 30).compareTo(
        orderByEraId[b.eraId] ?? 1 << 30,
      );
      if (eraOrder != 0) {
        return eraOrder;
      }
      final storyOrder = a.storyIndex.compareTo(b.storyIndex);
      if (storyOrder != 0) {
        return storyOrder;
      }
      return a.globalRank.compareTo(b.globalRank);
    });
    return sorted;
  }

  int _compareProfilePeople(
    Character a,
    Character b, {
    required Map<String, int> timelineOrderByCode,
  }) {
    final aTimeline = timelineOrderByCode[a.code];
    final bTimeline = timelineOrderByCode[b.code];
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
        if (isNarrow) {
          final totalHeight = constraints.maxHeight;
          // 프로필(좌측) 패널은 선택 탭과 콘텐츠 양에 맞춰 필요한 만큼만
          // 차지한다. 내부 리스트는 남은 높이에 맞춰 스크롤된다.
          final leftPanelHeight = _profileLeftPanelHeight(
            totalHeight,
            isAuthenticated: isAuthenticated,
          );
          final rightPanelHeight = (totalHeight * 0.65).clamp(420.0, 720.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                SizedBox(
                  height: leftPanelHeight.toDouble(),
                  child: _buildProfileLeftPanel(
                    profile: profile,
                    isAuthenticated: isAuthenticated,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: rightPanelHeight.toDouble(),
                  child: _buildProfileProgressSection(
                    people: people,
                    completedEventIds: state.completedEventIds,
                    selectedTestament: _profileSelectedTestament,
                    onSelectTestament: (testament) {
                      setState(() {
                        _profileSelectedTestament = testament;
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }
        final gap = (constraints.maxWidth * 0.012).clamp(4.0, 10.0).toDouble();
        final leftWidth = (constraints.maxWidth * 0.425)
            .clamp(278.0, 416.0)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: _buildProfileProgressSection(
                  people: people,
                  completedEventIds: state.completedEventIds,
                  selectedTestament: _profileSelectedTestament,
                  onSelectTestament: (testament) {
                    setState(() {
                      _profileSelectedTestament = testament;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _profileLeftPanelHeight(
    double totalHeight, {
    required bool isAuthenticated,
  }) {
    final desiredHeight = _profileLeftPanelDesiredHeight(
      isAuthenticated: isAuthenticated,
    );
    final maxHeight = math.max(260.0, totalHeight * 0.62);
    return math.min(desiredHeight, maxHeight);
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
    return SubPageScaffold(
      title: '프로필',
      compactBackOnly: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: isAuthenticated
                ? _buildProfileBody(state: state, isAuthenticated: true)
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
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
              child: lockedPreviewOverlay(
                child: InlineLoginPromptCard(
                  title: '프로필을 보려면 로그인이 필요해요',
                  description: '프로필, 저장한 이야기와 말씀, 공부 기록은 로그인 후 사용할 수 있어요.',
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
