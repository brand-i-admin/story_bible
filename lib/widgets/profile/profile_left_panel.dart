// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 좌측 패널 (아바타/헤더/콘텐츠 탭/노트·말씀·기도 미리보기).
part of '../profile_tab_page.dart';

extension ProfileLeftPanelExt on ProfileTabPageState {
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
            // 컴팩트 헤더 — 한 줄에 [아바타 40][이름][수정][개인정보][로그아웃].
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildCurrentUserAvatar(profile: profile, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink500,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _profileTinyIconButton(
                  tooltip: '프로필 수정',
                  onTap: _openProfileEditor,
                  icon: Icons.edit_rounded,
                ),
                const SizedBox(width: 4),
                _profileTinyIconButton(
                  tooltip: '설정',
                  onTap: _openProfileSettingsSheet,
                  icon: Icons.settings_outlined,
                ),
              ],
            ),
            // 헤더와 탭 사이 간격 0 — 컴팩트.
            _buildProfileContentTabs(),
            const SizedBox(height: 8),
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
          height: 34,
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
          // ignore: invalid_use_of_protected_member
          setState(() => _profileContentTab = tab);
        },
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // "내 기도/중보 기도" 섹션 타이틀과 동일한 14.7pt 통일.
              style: TextStyle(
                color: selected
                    ? const Color(0xFFB26B28)
                    : const Color(0xFF7E735F),
                fontSize: 14.7,
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
                    color: AppColors.ink200,
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
        // 중보 기도 리스트 — 부모 leftPanel 의 남은 높이를 채움. 넘치면 내부
        // 스크롤. leftPanel 자체가 30% 비율로 제한되므로 자연스럽게 짧음.
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
                      color: AppColors.ink200,
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
                      color: AppColors.ink200,
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
                    color: AppColors.ink500,
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
                        color: AppColors.ink500,
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
}
