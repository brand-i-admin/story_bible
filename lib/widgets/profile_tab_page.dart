import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/era.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/person.dart';
import '../models/person_study_progress.dart';
import '../models/saved_bible_verse.dart';
import '../models/story_event.dart';
import '../models/user_note.dart';
import '../screens/legal_documents_screen.dart';
import '../screens/profile_notes_screen.dart';
import '../screens/saved_verses_screen.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import 'inline_login_prompt_card.dart';
import 'parchment_dialog.dart';
import 'person_avatar.dart';
import 'profile_editor_dialog.dart';
import 'share_id_input_dialog.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

// 화면 코드를 도메인별로 part 파일로 분리.
// 각 part 파일은 ProfileTabPageState에 대한 extension으로 메소드를 추가한다.
part 'profile/profile_helpers.dart';
part 'profile/profile_intercessory_prayer.dart';
part 'profile/profile_left_panel.dart';
part 'profile/profile_person_overview.dart';
part 'profile/profile_right_panel.dart';

/// 프로필 탭 페이지 (프로필 정보 + 인물 진행도 + 노트/말씀/중보기도 미리보기).
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
  final void Function(StoryEvent event) onOpenEventDetail;
  final Future<void> Function({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  })
  onOpenBibleReader;

  @override
  ConsumerState<ProfileTabPage> createState() => ProfileTabPageState();
}

enum _ProfileContentTab { notes, verses, prayer }

class ProfileTabPageState extends ConsumerState<ProfileTabPage> {
  static const int _intercessoryPrayerPageSize = 12;
  static const int _profilePreviewPageSize = 5;

  final ScrollController _intercessoryPrayerScrollController =
      ScrollController();

  List<Person> _profileAllPeople = const [];
  Map<String, String> _profilePersonTestamentById = const {};
  AppUserProfile? _profileUser;
  Map<String, PersonStudyProgress> _profileStudyProgressByPersonId = const {};
  Map<String, double> _profilePersonTimelineOrderById = const {};
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profileNotesLoading = false;
        _profileNotesError = '노트를 불러오지 못했습니다.\n$error';
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
      _loadProfileNotesPreview(showLoading: showLoading),
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
    required Map<String, double> timelineOrderById,
  }) {
    final aTimeline = timelineOrderById[a.id];
    final bTimeline = timelineOrderById[b.id];
    if (aTimeline != null || bTimeline != null) {
      final timelineOrder = (aTimeline ?? double.infinity).compareTo(
        bTimeline ?? double.infinity,
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
            style: const TextStyle(color: AppColors.parchmentCream),
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
                  description: '프로필, 노트, 저장한 말씀, 공부 기록은 로그인 후 사용할 수 있어요.',
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
