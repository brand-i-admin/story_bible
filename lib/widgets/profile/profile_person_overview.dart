// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 인물별 학습 진행도 다이얼로그.
// ProfileTabPageState 확장으로 정의 (private 멤버 접근 가능).
part of '../profile_tab_page.dart';

extension ProfilePersonOverviewExt on ProfileTabPageState {
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
