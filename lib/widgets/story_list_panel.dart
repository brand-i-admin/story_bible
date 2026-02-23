import 'package:flutter/material.dart';

import '../models/story_event.dart';
import 'game_ui_skin.dart';

class StoryListPanel extends StatefulWidget {
  const StoryListPanel({
    super.key,
    required this.events,
    required this.selectedEventId,
    required this.onSelectEvent,
    required this.onStartQuiz,
    required this.completedEventIds,
    required this.colorForPerson,
    required this.selectedPersonIds,
    this.emptyMessage = '선택된 인물의 사건이 없습니다.',
  });

  final List<StoryEvent> events;
  final String? selectedEventId;
  final ValueChanged<String> onSelectEvent;
  final ValueChanged<String> onStartQuiz;
  final Set<String> completedEventIds;
  final Color Function(String personId) colorForPerson;
  final Set<String> selectedPersonIds;
  final String emptyMessage;

  @override
  State<StoryListPanel> createState() => _StoryListPanelState();
}

class _StoryListPanelState extends State<StoryListPanel> {
  bool _isQuizButtonPressed = false;

  @override
  Widget build(BuildContext context) {
    final canStartQuiz = widget.selectedEventId != null;
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: panelFrameDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelPadding = panelContentPaddingForSize(constraints.biggest);
          return Padding(
            padding: panelPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: statesButtonLabel(
                      text: '이야기 리스트',
                      width: 132,
                      height: 36,
                    ),
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.45)),
                Expanded(
                  child: widget.events.isEmpty
                      ? Center(
                          child: Text(
                            widget.emptyMessage,
                            style: const TextStyle(color: Color(0xFFF8EED9)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          itemCount: widget.events.length,
                          itemBuilder: (context, index) {
                            final event = widget.events[index];
                            final selected = event.id == widget.selectedEventId;
                            final isCompleted = widget.completedEventIds
                                .contains(event.id);
                            final highlightedPersonIds = event.personIds
                                .where(widget.selectedPersonIds.contains)
                                .toList(growable: false);

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4.0,
                              ),
                              child: GestureDetector(
                                onTap: () => widget.onSelectEvent(event.id),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 54,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                                  decoration: tabItemDecoration(
                                    selected: selected,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (isCompleted)
                                        const Icon(
                                          Icons.check_circle,
                                          size: 12,
                                          color: Color(0xFF89E492),
                                        ),
                                      if (isCompleted) const SizedBox(width: 4),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            ...highlightedPersonIds.map(
                                              (personId) => Container(
                                                width: 9,
                                                height: 9,
                                                margin: const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: widget.colorForPerson(
                                                    personId,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (highlightedPersonIds.isNotEmpty)
                                              const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${index + 1}. ${event.title}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFFDF8EE),
                                                  height: 1.2,
                                                  shadows: [
                                                    Shadow(
                                                      color: Color(0xAA000000),
                                                      blurRadius: 3,
                                                      offset: Offset(0, 1),
                                                    ),
                                                  ],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Align(
                    alignment: Alignment.center,
                    child: FractionallySizedBox(
                      widthFactor: 0.82,
                      child: Transform.translate(
                        offset: const Offset(0, -2),
                        child: GestureDetector(
                          onTapDown: canStartQuiz
                              ? (_) =>
                                    setState(() => _isQuizButtonPressed = true)
                              : null,
                          onTapCancel: canStartQuiz
                              ? () =>
                                    setState(() => _isQuizButtonPressed = false)
                              : null,
                          onTapUp: canStartQuiz
                              ? (_) =>
                                    setState(() => _isQuizButtonPressed = false)
                              : null,
                          onTap: canStartQuiz
                              ? () =>
                                    widget.onStartQuiz(widget.selectedEventId!)
                              : null,
                          behavior: HitTestBehavior.opaque,
                          child: Opacity(
                            opacity: canStartQuiz ? 1 : 0.64,
                            child: Container(
                              height: 38,
                              decoration: actionButtonDecoration(
                                selected: _isQuizButtonPressed,
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '퀴즈 시작!',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFDF8EE),
                                  shadows: [
                                    Shadow(
                                      color: Color(0xAA000000),
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
