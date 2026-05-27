import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/story_event.dart';
import '../../theme/tokens.dart';
import '../sub_page_scaffold.dart';
import '../weekly_tab_page.dart';
import 'daily_quiz_section.dart';

/// 홈 상단 "퀴즈" 버튼이 여는 페이지.
///
/// 두 탭으로 구성:
///  - 매일 퀴즈: `daily_quiz` 테이블의 최신 1문제 + 가변 선택지 + 제출 → 도장+별가루.
///  - 주간 퀴즈: 기존 [WeeklyTabPage] 본문 (embedded 모드, scaffold 생략).
class QuizTabPage extends ConsumerStatefulWidget {
  const QuizTabPage({
    super.key,
    required this.onStartQuiz,
    required this.onOpenEventDetail,
  });

  final void Function(String eventId) onStartQuiz;
  final void Function(StoryEvent event, {String? quizWeekKey})
  onOpenEventDetail;

  @override
  ConsumerState<QuizTabPage> createState() => _QuizTabPageState();
}

class _QuizTabPageState extends ConsumerState<QuizTabPage> {
  int _selectedTab = 0;
  bool _dailyCompleted = false;

  @override
  Widget build(BuildContext context) {
    return SubPageScaffold(
      title: '퀴즈',
      compactBackOnly: true,
      child: Column(
        children: [
          _tabBar(),
          const SizedBox(height: 8),
          Expanded(
            child: _selectedTab == 0
                ? _DailyTabBody(
                    scrollPadding: _bodyPadding(),
                    onCompletedChanged: (done) {
                      if (_dailyCompleted != done) {
                        setState(() => _dailyCompleted = done);
                      }
                    },
                  )
                : WeeklyTabPage(
                    embedded: true,
                    onStartQuiz: widget.onStartQuiz,
                    onOpenEventDetail: widget.onOpenEventDetail,
                  ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _bodyPadding() =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 4);

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1E1C0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xAA8E6F48), width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: _tabButton(
                label: '매일 퀴즈',
                selected: _selectedTab == 0,
                completed: _dailyCompleted,
                onTap: () => setState(() => _selectedTab = 0),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _tabButton(
                label: '주간 퀴즈',
                selected: _selectedTab == 1,
                completed: false,
                onTap: () => setState(() => _selectedTab = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool selected,
    required bool completed,
    required VoidCallback onTap,
  }) {
    // 우선순위: completed > selected > 기본. 완료된 매일 퀴즈는 항상 초록 표시.
    final Color bg;
    final Color textColor;
    if (completed) {
      bg = const Color(0xFF7AAC4C);
      textColor = Colors.white;
    } else if (selected) {
      bg = AppColors.brownWarm;
      textColor = Colors.white;
    } else {
      bg = Colors.transparent;
      textColor = const Color(0xFF6A4C2E);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            boxShadow: (completed || selected)
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (completed) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyTabBody extends StatelessWidget {
  const _DailyTabBody({
    required this.scrollPadding,
    required this.onCompletedChanged,
  });

  final EdgeInsets scrollPadding;
  final ValueChanged<bool> onCompletedChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: scrollPadding.copyWith(bottom: 24),
      child: DailyQuizSection(onCompletedChanged: onCompletedChanged),
    );
  }
}
