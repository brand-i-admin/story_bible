
// 부모 라이브러리: lib/widgets/weekly_tab_page.dart
//
// 주간 이벤트 리스트 패널 + 인라인 퀴즈 버튼 + 인물 타이틀 배지.
part of '../weekly_tab_page.dart';

extension _WeeklyListPanelExt on _WeeklyTabPageState {
  Widget _buildWeeklyListPanel({
    required WeeklyStudyData weekly,
    required Set<String> completedEventIds,
    required Color Function(String personId) colorForPerson,
    required ValueChanged<String> onSelectEvent,
    required ValueChanged<String> onToggleChecked,
    required ValueChanged<String> onStartQuiz,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: floatingPanelDecoration(),
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
                              decoration: interactiveCardDecoration(
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
                                                      ? AppColors.parchmentCream
                                                      : isCompleted
                                                      ? const Color(0xFF2D5A39)
                                                      : AppColors.ink500,
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
                                                  : AppColors.parchmentLight,
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
                                                  ? AppColors.parchmentCream
                                                  : AppColors.ink100,
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
    return filledActionButton(
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
      decoration: headerChipDecoration(),
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
                color: AppColors.ink500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
