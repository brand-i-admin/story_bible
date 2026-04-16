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
import 'inline_login_prompt_card.dart';
import 'parchment_dialog.dart';
import 'person_avatar.dart';
import 'profile_editor_dialog.dart';
import 'share_id_input_dialog.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

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

  Widget _buildProfileLeftPanel({
    required AppUserProfile profile,
    required bool isAuthenticated,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: floatingPanelDecoration(),
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
                                tooltip: '법적 안내',
                                onTap: _openLegalDocumentsPage,
                                icon: Icons.policy_outlined,
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
        onTap: () => widget.onOpenBibleReader(
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
          decoration: floatingPanelDecoration(),
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
      decoration: floatingPanelDecoration(
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
          decoration: softButtonDecoration(selected: false),
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
          decoration: softButtonDecoration(selected: selected),
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
      decoration: floatingPanelDecoration(
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
                            if (stacked)
                              Column(
                                children: [
                                  PersonAvatar(
                                    person: person,
                                    size: compact ? 24 : 26,
                                  ),
                                  SizedBox(height: compact ? 4 : 5),
                                  Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF4A331D),
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 10.2 : 11.8,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  PersonAvatar(person: person, size: 28),
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
                  decoration: modalSurfaceDecoration(),
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
                                PersonAvatar(person: person, size: 58),
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
                                                      headerChipDecoration(),
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
                                            widget.onOpenEventDetail(event);
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
                        child: modalCloseButton(
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
}
