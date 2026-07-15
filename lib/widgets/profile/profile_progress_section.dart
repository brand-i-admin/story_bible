// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// "진행률 표시" 섹션 — 다이어리 컨텐츠. 넓은 화면은 섹션 내부 스크롤,
// 좁은 화면은 프로필 페이지 전체 스크롤이 본문 끝까지 담당한다.
part of '../profile_tab_page.dart';

extension ProfileProgressSectionExt on ProfileTabPageState {
  Widget _buildProfileProgressSection({bool scrollBody = true}) {
    final body = ProfileLeftPanelExt(
      this,
    )._buildProfileBodyShell(child: _profileProgressLifeBody());
    if (!scrollBody) {
      return body;
    }
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: body,
    );
  }

  // ───────────────────────── 다이어리 탭 본문 ─────────────────────────
  Widget _profileProgressLifeBody() {
    final state = ref.watch(storyControllerProvider);
    final bibleProgress = _profileBibleProgress(state);
    final lastCompletedChapter = _profileLastCompletedBibleChapter(
      state.completedBibleChapterKeys,
    );
    final today = toKst(DateTime.now());
    final todayCompanionDiary = _profileCompanionDiaryEntries
        .where((entry) => _isSameProfileDate(entry.entryDate, today))
        .firstOrNull;
    final bibleProgressSummary = ProfileBibleProgressSummary(
      completed: bibleProgress.completed,
      total: bibleProgress.total,
      fraction: bibleProgress.fraction,
      lastCompletedBookNo: lastCompletedChapter?.bookNo,
      lastCompletedChapterNo: lastCompletedChapter?.chapterNo,
      completedToday: _hasBibleReadToday(state, today),
    );
    return ProfileLeftPanelExt(this)._buildProfileStoryExplorationDashboard(
      featureSection: ProfileDiaryFeatureCards(
        today: today,
        todayCompanionDiary: todayCompanionDiary,
        companionDiaryEntries: _profileCompanionDiaryEntries,
        companionDiaryLoading: _profileCompanionDiaryLoading,
        companionDiaryError: _profileCompanionDiaryError,
        onSaveCompanionDiary: _saveCompanionDiaryEntry,
        onDeleteCompanionDiary: _deleteCompanionDiaryEntry,
        bibleProgress: bibleProgressSummary,
        onOpenBibleProgress: _openBibleProgressPage,
        onContinueBibleReading: null,
        profileSummaryMode: true,
      ),
    );
  }

  bool _isSameProfileDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _hasBibleReadToday(StoryState state, DateTime today) {
    return state.completedBibleChapterReadAts.values.any((readAt) {
      if (readAt == null) {
        return false;
      }
      return _isSameProfileDate(toKst(readAt), today);
    });
  }
}
