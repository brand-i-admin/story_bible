// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 인물별 학습 진행도 다이얼로그.
// ProfileTabPageState 확장으로 정의 (private 멤버 접근 가능).
part of '../profile_tab_page.dart';

extension ProfileCharacterOverviewExt on ProfileTabPageState {
  Future<void> _openProfileCharacterOverview({
    required Character character,
    required Set<String> completedEventIds,
  }) async {
    final repo = ref.read(storyRepositoryProvider);
    final state = ref.read(storyControllerProvider);
    final progressData = _profileStudyProgressByCharacterCode[character.code];
    final completedCount = progressData?.completedCount ?? 0;
    final totalCount = progressData?.totalCount ?? 0;
    final progress = progressData?.fraction ?? 0.0;
    final eventsFuture = repo.fetchEventsForCharacter(character.code);
    // StoryEventThumbCard 가 받는 charactersByCode + era 조회용 lookup.
    final charactersByCode = {for (final c in state.characters) c.code: c};
    final eraById = {for (final e in state.eras) e.id: e};
    final loader = SceneAssetLoader();

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
                                CharacterAvatar(character: character, size: 58),
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
                                              character.name,
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
                                        ((character.description ?? '')
                                                    .trim()
                                                    .isNotEmpty
                                                ? character.description
                                                : character.tagline) ??
                                            '아직 등록된 인물 소개가 없습니다.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.ink450,
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
                                color: AppColors.ink450,
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
                                  // 홈 화면 하단 패널과 같은 StoryEventThumbCard
                                  // 를 재사용 — 완료 시 초록 카드. 3열 그리드.
                                  // childAspectRatio 는 카드의 자연 높이(아바타+
                                  // 제목+메타+요약+인물 pill 행) 에 맞춰 0.78.
                                  return GridView.builder(
                                    padding: const EdgeInsets.only(top: 4),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          mainAxisSpacing: 14,
                                          crossAxisSpacing: 12,
                                          childAspectRatio: 0.78,
                                        ),
                                    itemCount: events.length,
                                    itemBuilder: (context, index) {
                                      final event = events[index];
                                      final era = eraById[event.eraId];
                                      return StoryEventThumbCard(
                                        event: event,
                                        era: era,
                                        charactersByCode: charactersByCode,
                                        selected: false,
                                        completed: completedEventIds.contains(
                                          event.id,
                                        ),
                                        orderNumber: index + 1,
                                        loader: loader,
                                        onTap: () {
                                          Navigator.of(dialogContext).pop();
                                          widget.onOpenEventDetail(event);
                                        },
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
