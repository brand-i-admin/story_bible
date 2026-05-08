import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_quiz.dart';
import '../../state/auth_providers.dart';
import '../../state/story_controller.dart';
import '../../theme/tokens.dart';
import '../completion_celebration.dart';

/// 매일 퀴즈 섹션 — 4지선다 + 제출 + 정/오답 시 CompletionCelebration (도장+별가루)
/// + 해설 노출.
///
/// 사용자별 시도는 `user_daily_quiz_attempts` 테이블에 저장 — 같은 daily_quiz
/// 가 active 인 동안엔 같은 row 유지(재제출 불가). daily_quiz 가 새로 등록되면
/// (다른 PK) 자동으로 새 시도 가능 → "초기화" 가 자연스럽게 일어남.
class DailyQuizSection extends ConsumerStatefulWidget {
  const DailyQuizSection({super.key, this.onCompletedChanged});

  /// 사용자가 오늘의 매일 퀴즈를 완료한 상태(또는 사전 완료된 상태로 진입)
  /// 인지가 바뀔 때 호출. 부모(QuizTabPage)가 탭 버튼 색을 초록으로 전환할 때 사용.
  final ValueChanged<bool>? onCompletedChanged;

  @override
  ConsumerState<DailyQuizSection> createState() => _DailyQuizSectionState();
}

class _DailyQuizSectionState extends ConsumerState<DailyQuizSection> {
  Future<({DailyQuiz quiz, ({int selectedIndex, bool isCorrect})? attempt})?>?
  _future;
  int? _selectedIndex0;
  bool _submitted = false;
  String? _loadedQuizId;
  final GlobalKey<CompletionCelebrationState> _celebrationKey =
      GlobalKey<CompletionCelebrationState>();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({DailyQuiz quiz, ({int selectedIndex, bool isCorrect})? attempt})?>
  _load() async {
    final repo = ref.read(storyRepositoryProvider);
    final quiz = await repo.fetchLatestDailyQuiz();
    if (quiz == null) return null;
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return (quiz: quiz, attempt: null);
    }
    final attempt = await repo.fetchDailyQuizAttempt(
      userId: user.id,
      quizId: quiz.id,
    );
    return (quiz: quiz, attempt: attempt);
  }

  /// FutureBuilder 첫 빌드 직후 attempt 가 있으면 상태 복원 + 부모에 알림.
  void _maybeApplyAttempt({
    required String quizId,
    ({int selectedIndex, bool isCorrect})? attempt,
  }) {
    if (_loadedQuizId == quizId) return;
    _loadedQuizId = quizId;
    if (attempt != null) {
      // setState 는 build 도중 호출 금지 → postFrame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedIndex0 = attempt.selectedIndex - 1; // 1-based → 0-based
          _submitted = true;
        });
        widget.onCompletedChanged?.call(true);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onCompletedChanged?.call(false);
      });
    }
  }

  Future<void> _submit(DailyQuiz quiz) async {
    if (_selectedIndex0 == null || _submitted) return;
    final selectedIdx0 = _selectedIndex0!;
    setState(() => _submitted = true);
    _celebrationKey.currentState?.play();

    // DB 저장 (로그인 시에만). insert ignore 라 동시성 충돌도 안전.
    final user = ref.read(signedInUserProvider);
    if (user != null) {
      try {
        await ref
            .read(storyRepositoryProvider)
            .insertDailyQuizAttempt(
              userId: user.id,
              quizId: quiz.id,
              selectedIndex: selectedIdx0 + 1,
              isCorrect: quiz.isCorrect(selectedIdx0),
            );
      } catch (_) {
        // 저장 실패는 조용히 무시 — UI 는 이미 제출 상태.
      }
    }
    widget.onCompletedChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({DailyQuiz quiz, ({int selectedIndex, bool isCorrect})? attempt})?
    >(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        if (snapshot.hasError) {
          return _errorBox('매일 퀴즈를 불러오지 못했습니다.\n${snapshot.error}');
        }
        final result = snapshot.data;
        if (result == null) {
          return _errorBox('아직 등록된 매일 퀴즈가 없습니다.');
        }
        // 첫 빌드에 한 번 attempt 복원 + 부모에 완료 상태 알림.
        _maybeApplyAttempt(quizId: result.quiz.id, attempt: result.attempt);
        return _quizCard(result.quiz);
      },
    );
  }

  Widget _quizCard(DailyQuiz quiz) {
    return CompletionCelebration(
      key: _celebrationKey,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF1DC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD9B785), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.today_rounded, size: 16, color: Color(0xFFB07220)),
                SizedBox(width: 6),
                Text(
                  '매일 퀴즈',
                  style: TextStyle(
                    color: Color(0xFFB07220),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              quiz.question,
              style: const TextStyle(
                color: Color(0xFF3A2B15),
                fontWeight: FontWeight.w900,
                fontSize: 16,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < quiz.choices.length; i++) ...[
              _choiceRow(index0: i, label: quiz.choices[i], quiz: quiz),
              if (i < quiz.choices.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 14),
            if (!_submitted)
              _SubmitButton(
                enabled: _selectedIndex0 != null,
                onTap: () => _submit(quiz),
              )
            else
              _ExplanationBlock(quiz: quiz, selectedIndex0: _selectedIndex0!),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow({
    required int index0,
    required String label,
    required DailyQuiz quiz,
  }) {
    final isSelected = _selectedIndex0 == index0;
    final isCorrect = quiz.answerIndex == index0 + 1;
    final showResult = _submitted;

    Color bg;
    Color border;
    Color textColor;
    if (showResult) {
      if (isCorrect) {
        bg = const Color(0x33A6D58A);
        border = const Color(0xFF7AAC4C);
        textColor = const Color(0xFF335E1B);
      } else if (isSelected) {
        bg = const Color(0x33D08070);
        border = const Color(0xFFB05848);
        textColor = const Color(0xFF6E2D1F);
      } else {
        bg = const Color(0xCCFFF6E2);
        border = const Color(0xAA8E6F48);
        textColor = const Color(0xFF6A4C2E);
      }
    } else {
      bg = isSelected ? const Color(0xFFE8C68A) : const Color(0xCCFFF6E2);
      border = isSelected ? const Color(0xFFB07220) : const Color(0xAA8E6F48);
      textColor = isSelected
          ? const Color(0xFF3A2B15)
          : const Color(0xFF6A4C2E);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _submitted
            ? null
            : () => setState(() => _selectedIndex0 = index0),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border,
              width: isSelected || (showResult && isCorrect) ? 1.6 : 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: showResult && isCorrect
                      ? const Color(0xFF7AAC4C)
                      : isSelected
                      ? const Color(0xFFB07220)
                      : const Color(0xFFF1E1C0),
                  border: Border.all(
                    color: showResult && isCorrect
                        ? const Color(0xFF335E1B)
                        : isSelected
                        ? const Color(0xFF6A4220)
                        : const Color(0xAA8E6F48),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${index0 + 1}',
                  style: TextStyle(
                    color: showResult && isCorrect
                        ? Colors.white
                        : isSelected
                        ? Colors.white
                        : const Color(0xFF6A4C2E),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
              if (showResult && isCorrect)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: Color(0xFF7AAC4C),
                )
              else if (showResult && isSelected)
                const Icon(
                  Icons.cancel_rounded,
                  size: 20,
                  color: Color(0xFFB05848),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x55F1E1C0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x66B89A66), width: 0.8),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6A4C2E),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppColors.brownWarm : const Color(0xAACDAE7C),
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: const Text(
            '제출',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplanationBlock extends StatelessWidget {
  const _ExplanationBlock({required this.quiz, required this.selectedIndex0});

  final DailyQuiz quiz;
  final int selectedIndex0;

  @override
  Widget build(BuildContext context) {
    final isCorrect = quiz.isCorrect(selectedIndex0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: isCorrect ? const Color(0x33A6D58A) : const Color(0x22D08070),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? const Color(0xFF7AAC4C) : const Color(0xFFB05848),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: isCorrect
                    ? const Color(0xFF335E1B)
                    : const Color(0xFF6E2D1F),
              ),
              const SizedBox(width: 6),
              Text(
                isCorrect ? '정답입니다!' : '아쉬워요',
                style: TextStyle(
                  color: isCorrect
                      ? const Color(0xFF335E1B)
                      : const Color(0xFF6E2D1F),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '정답: ${quiz.answerIndex}번',
                style: const TextStyle(
                  color: Color(0xFF6A4C2E),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            quiz.explanation,
            style: const TextStyle(
              color: Color(0xFF3A2B15),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
