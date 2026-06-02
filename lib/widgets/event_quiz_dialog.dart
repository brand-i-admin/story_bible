import 'package:flutter/material.dart';

import '../models/quiz_question.dart';

class EventQuizResult {
  const EventQuizResult({
    required this.selectedAnswers,
    required this.score,
    required this.confusedCount,
  });

  final List<int?> selectedAnswers;
  final int score;
  final int confusedCount;
}

class EventQuizDialog extends StatefulWidget {
  const EventQuizDialog({
    super.key,
    required this.title,
    required this.questions,
  });

  final String title;
  final List<QuizQuestion> questions;

  @override
  State<EventQuizDialog> createState() => _EventQuizDialogState();
}

class _EventQuizDialogState extends State<EventQuizDialog> {
  late final List<int?> _selectedAnswers;
  late final List<bool> _submittedQuestions;

  int _currentIndex = 0;
  bool _showReview = false;

  @override
  void initState() {
    super.initState();
    _selectedAnswers = List<int?>.filled(widget.questions.length, null);
    _submittedQuestions = List<bool>.filled(widget.questions.length, false);
  }

  EventQuizResult _buildResult() {
    var score = 0;
    var confusedCount = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      final selected = _selectedAnswers[i];
      final question = widget.questions[i];
      if (question.isConfusedChoiceIndex(selected)) {
        confusedCount += 1;
      } else if (selected == question.answerIndex) {
        score += 1;
      }
    }
    return EventQuizResult(
      selectedAnswers: List<int?>.unmodifiable(_selectedAnswers),
      score: score,
      confusedCount: confusedCount,
    );
  }

  void _handlePrimaryAction() {
    final isSubmitted = _submittedQuestions[_currentIndex];
    final isLast = _currentIndex == widget.questions.length - 1;

    if (!isSubmitted) {
      setState(() {
        _submittedQuestions[_currentIndex] = true;
      });
      return;
    }

    if (isLast) {
      setState(() {
        _showReview = true;
      });
      return;
    }

    setState(() {
      _currentIndex += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _buildResult();
    final didPass = result.score == widget.questions.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6EAD8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB58A47), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: _showReview
              ? _QuizReviewPane(
                  questions: widget.questions,
                  result: result,
                  didPass: didPass,
                )
              : _QuizQuestionPane(
                  title: widget.title,
                  question: widget.questions[_currentIndex],
                  questionIndex: _currentIndex,
                  totalCount: widget.questions.length,
                  selectedAnswer: _selectedAnswers[_currentIndex],
                  submitted: _submittedQuestions[_currentIndex],
                  onSelectAnswer: (answerIndex) {
                    if (_submittedQuestions[_currentIndex]) {
                      return;
                    }
                    setState(() {
                      _selectedAnswers[_currentIndex] = answerIndex;
                    });
                  },
                  onClose: () => Navigator.of(context).pop(),
                  onPrevious: _currentIndex > 0
                      ? () {
                          setState(() {
                            _currentIndex -= 1;
                          });
                        }
                      : null,
                  onPrimary: _selectedAnswers[_currentIndex] == null
                      ? null
                      : _handlePrimaryAction,
                ),
        ),
      ),
    );
  }
}

class _QuizQuestionPane extends StatelessWidget {
  const _QuizQuestionPane({
    required this.title,
    required this.question,
    required this.questionIndex,
    required this.totalCount,
    required this.selectedAnswer,
    required this.submitted,
    required this.onSelectAnswer,
    required this.onClose,
    required this.onPrevious,
    required this.onPrimary,
  });

  final String title;
  final QuizQuestion question;
  final int questionIndex;
  final int totalCount;
  final int? selectedAnswer;
  final bool submitted;
  final ValueChanged<int> onSelectAnswer;
  final VoidCallback onClose;
  final VoidCallback? onPrevious;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final isLast = questionIndex == totalCount - 1;
    final progress = (questionIndex + 1) / totalCount;
    final primaryLabel = submitted ? (isLast ? '결과 보기' : '다음') : '정답 확인';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF5A4326),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE5D2A8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${questionIndex + 1} / $totalCount',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5A4326),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: const Color(0xFFEBD9B2),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(999),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.close_rounded,
                    color: Color(0xFF6A4A25),
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFE5D2A8),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB58A47)),
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF1DD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD9C18B)),
                  ),
                  child: Text(
                    question.question,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF332A1D),
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < question.choices.length; i++)
                  _QuizChoiceCard(
                    index: i,
                    text: question.choices[i],
                    selected: selectedAnswer == i,
                    submitted: submitted,
                    isCorrect: i == question.answerIndex,
                    isConfusedChoice: question.isConfusedChoiceIndex(i),
                    onTap: submitted ? null : () => onSelectAnswer(i),
                  ),
                if (submitted) ...[
                  const SizedBox(height: 10),
                  _QuestionFeedbackBlock(
                    question: question,
                    selectedAnswer: selectedAnswer,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: onPrevious,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7A6748),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              child: const Text(
                '이전',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB58A47),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              child: Text(primaryLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionFeedbackBlock extends StatelessWidget {
  const _QuestionFeedbackBlock({
    required this.question,
    required this.selectedAnswer,
  });

  final QuizQuestion question;
  final int? selectedAnswer;

  @override
  Widget build(BuildContext context) {
    final isCorrect = selectedAnswer == question.answerIndex;
    final isConfused = question.isConfusedChoiceIndex(selectedAnswer);
    final accent = isCorrect
        ? const Color(0xFF1F7A3A)
        : isConfused
        ? const Color(0xFFB58A47)
        : const Color(0xFFB0392F);
    final title = isCorrect
        ? '정답입니다!'
        : isConfused
        ? '헷갈렸군요'
        : '오답이에요';
    final correctChoice = question.choices[question.answerIndex];
    final explanation = (question.explanation ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCorrect ? Icons.check_circle : Icons.info_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '정답: ${question.answerIndex + 1}번 $correctChoice',
            style: const TextStyle(
              color: Color(0xFF332A1D),
              fontWeight: FontWeight.w800,
              fontSize: 12.8,
              height: 1.4,
            ),
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 7),
            const Text(
              '해설',
              style: TextStyle(
                color: Color(0xFF5A4326),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              explanation,
              style: const TextStyle(
                color: Color(0xFF5A4326),
                fontWeight: FontWeight.w600,
                fontSize: 12.2,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizReviewPane extends StatelessWidget {
  const _QuizReviewPane({
    required this.questions,
    required this.result,
    required this.didPass,
  });

  final List<QuizQuestion> questions;
  final EventQuizResult result;
  final bool didPass;

  @override
  Widget build(BuildContext context) {
    final total = questions.length;
    final wrong = total - result.score - result.confusedCount;
    final headerColor = didPass
        ? const Color(0xFF1F7A3A)
        : const Color(0xFFB58A47);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              didPass ? Icons.emoji_events : Icons.fact_check_outlined,
              color: headerColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                didPass ? '모두 정답!' : '결과 확인',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: headerColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF1DD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD9C18B)),
          ),
          child: Row(
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF5A4326),
                  ),
                  children: [
                    TextSpan(
                      text: '${result.score}',
                      style: TextStyle(fontSize: 28, color: headerColor),
                    ),
                    const TextSpan(text: ' / ', style: TextStyle(fontSize: 18)),
                    TextSpan(
                      text: '$total',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ScorePill(
                      label: '정답',
                      count: result.score,
                      color: const Color(0xFF1F7A3A),
                    ),
                    _ScorePill(
                      label: '오답',
                      count: wrong < 0 ? 0 : wrong,
                      color: const Color(0xFFB0392F),
                    ),
                    if (result.confusedCount > 0)
                      _ScorePill(
                        label: '헷갈림',
                        count: result.confusedCount,
                        color: const Color(0xFFB58A47),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < questions.length; i++)
                  _QuizReviewItem(
                    index: i,
                    question: questions[i],
                    userAnswer: result.selectedAnswers[i],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(result),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB58A47),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: const Text('확인'),
          ),
        ),
      ],
    );
  }
}

class _QuizChoiceCard extends StatelessWidget {
  const _QuizChoiceCard({
    required this.index,
    required this.text,
    required this.selected,
    required this.submitted,
    required this.isCorrect,
    required this.isConfusedChoice,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool selected;
  final bool submitted;
  final bool isCorrect;
  final bool isConfusedChoice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _choiceColors();
    final icon = _trailingIcon();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colors.border,
                width: selected || (submitted && isCorrect) ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.badgeBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: colors.badgeForeground,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: selected || (submitted && isCorrect)
                          ? FontWeight.w800
                          : FontWeight.w600,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                if (icon != null)
                  Padding(padding: const EdgeInsets.only(left: 6), child: icon),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ChoiceColors _choiceColors() {
    if (submitted && isCorrect) {
      return const _ChoiceColors(
        background: Color(0xFFE2F1E5),
        border: Color(0xFF1F7A3A),
        badgeBackground: Color(0xFF1F7A3A),
        badgeForeground: Colors.white,
        text: Color(0xFF1F4F2D),
      );
    }
    if (submitted && selected && isConfusedChoice) {
      return const _ChoiceColors(
        background: Color(0xFFF3E4BE),
        border: Color(0xFFB58A47),
        badgeBackground: Color(0xFFB58A47),
        badgeForeground: Colors.white,
        text: Color(0xFF5A4326),
      );
    }
    if (submitted && selected) {
      return const _ChoiceColors(
        background: Color(0xFFF4D9D6),
        border: Color(0xFFB0392F),
        badgeBackground: Color(0xFFB0392F),
        badgeForeground: Colors.white,
        text: Color(0xFF6C241F),
      );
    }
    if (selected) {
      return const _ChoiceColors(
        background: Color(0xFFEFD9A2),
        border: Color(0xFFB58A47),
        badgeBackground: Color(0xFFB58A47),
        badgeForeground: Colors.white,
        text: Color(0xFF332A1D),
      );
    }
    return const _ChoiceColors(
      background: Color(0xFFFAF1DD),
      border: Color(0xFFD9C18B),
      badgeBackground: Color(0xFFE5D2A8),
      badgeForeground: Color(0xFF5A4326),
      text: Color(0xFF332A1D),
    );
  }

  Widget? _trailingIcon() {
    if (submitted && isCorrect) {
      return const Icon(Icons.check_circle, size: 18, color: Color(0xFF1F7A3A));
    }
    if (submitted && selected && isConfusedChoice) {
      return const Icon(Icons.help_rounded, size: 18, color: Color(0xFFB58A47));
    }
    if (submitted && selected) {
      return const Icon(Icons.cancel, size: 18, color: Color(0xFFB0392F));
    }
    if (selected) {
      return const Icon(Icons.check_circle, size: 18, color: Color(0xFFB58A47));
    }
    return null;
  }
}

class _ChoiceColors {
  const _ChoiceColors({
    required this.background,
    required this.border,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color badgeBackground;
  final Color badgeForeground;
  final Color text;
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _QuizReviewItem extends StatelessWidget {
  const _QuizReviewItem({
    required this.index,
    required this.question,
    required this.userAnswer,
  });

  final int index;
  final QuizQuestion question;
  final int? userAnswer;

  @override
  Widget build(BuildContext context) {
    final isCorrect = userAnswer == question.answerIndex;
    final isConfused = question.isConfusedChoiceIndex(userAnswer);
    final accent = isCorrect
        ? const Color(0xFF1F7A3A)
        : isConfused
        ? const Color(0xFFB58A47)
        : const Color(0xFFB0392F);
    final explanation = (question.explanation ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9C18B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Q${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Color(0xFF5A4326),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect
                    ? '정답'
                    : isConfused
                    ? '헷갈렸어요'
                    : '오답',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question.question,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: Color(0xFF332A1D),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var ci = 0; ci < question.choices.length; ci++)
            _ReviewChoiceRow(
              index: ci,
              text: question.choices[ci],
              isCorrect: ci == question.answerIndex,
              isUserPick: ci == userAnswer,
            ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE0C5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCBB58A).withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '해설',
                    style: TextStyle(
                      color: Color(0xFF5A4326),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    explanation,
                    style: const TextStyle(
                      color: Color(0xFF5A4326),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewChoiceRow extends StatelessWidget {
  const _ReviewChoiceRow({
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.isUserPick,
  });

  final int index;
  final String text;
  final bool isCorrect;
  final bool isUserPick;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Widget marker;
    FontWeight weight;
    if (isCorrect) {
      textColor = const Color(0xFF1F7A3A);
      marker = const Icon(
        Icons.check_circle,
        size: 16,
        color: Color(0xFF1F7A3A),
      );
      weight = FontWeight.w800;
    } else if (isUserPick) {
      textColor = const Color(0xFFB0392F);
      marker = const Icon(Icons.cancel, size: 16, color: Color(0xFFB0392F));
      weight = FontWeight.w700;
    } else {
      textColor = const Color(0xFF7A6748);
      marker = const Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: Color(0xFFB89F75),
      );
      weight = FontWeight.w500;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: marker),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${index + 1}. $text',
              style: TextStyle(
                color: textColor,
                fontWeight: weight,
                fontSize: 12.6,
                height: 1.4,
              ),
            ),
          ),
          if (isUserPick && !isCorrect)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text(
                '내 답',
                style: TextStyle(
                  color: Color(0xFFB0392F),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
