// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// "진행률 표시" 섹션 — 다이어리 컨텐츠. 넓은 화면은 섹션 내부 스크롤,
// 좁은 화면은 프로필 페이지 전체 스크롤이 본문 끝까지 담당한다.
part of '../profile_tab_page.dart';

extension ProfileProgressSectionExt on ProfileTabPageState {
  Widget _buildProfileProgressSection({bool scrollBody = true}) {
    final palette = AppPaletteTheme.of(context);
    final selectedAccent = palette.currentAccentDeep;
    final body = Container(
      margin: const EdgeInsets.all(4),
      decoration: _profileLinkedTabBodyDecoration(
        context,
        accent: selectedAccent,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: scrollBody
            ? SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _profileProgressLifeBody(),
              )
            : _profileProgressLifeBody(),
      ),
    );
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: _profileLinkedTabGroupDecoration(
        context,
        accent: palette.currentAccentDeep,
      ),
      child: Column(
        mainAxisSize: scrollBody ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [if (scrollBody) Expanded(child: body) else body],
      ),
    );
  }

  // ───────────────────────── 다이어리 탭 본문 ─────────────────────────
  Widget _profileProgressLifeBody() {
    final state = ref.watch(storyControllerProvider);
    final bibleProgress = _profileBibleProgress(state);
    return ProfileEmotionDiary(
      eventEmotionMarks: state.eventEmotionMarks,
      companionDiaryEntries: _profileCompanionDiaryEntries,
      companionDiaryLoading: _profileCompanionDiaryLoading,
      companionDiaryError: _profileCompanionDiaryError,
      onSaveCompanionDiary: _saveCompanionDiaryEntry,
      onDeleteCompanionDiary: _deleteCompanionDiaryEntry,
      bibleProgress: ProfileBibleProgressSummary(
        completed: bibleProgress.completed,
        total: bibleProgress.total,
        fraction: bibleProgress.fraction,
        lastVerse: _profileSavedVersesPreview.firstOrNull,
      ),
      onOpenBibleProgress: _openBibleProgressDialog,
      onContinueBibleReading: () {
        unawaited(_openBibleReaderFromLatestSavedVerse());
      },
    );
  }
}
