import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../utils/today_activity_summary.dart';
import '../parchment_dialog.dart';
import '../web_pointer_interceptor.dart';
import 'story_root_navigation_bar.dart';

class TodayActivityHeader extends StatelessWidget {
  const TodayActivityHeader({
    super.key,
    required this.nickname,
    required this.summary,
    this.actions,
    this.onStreakDialogVisibilityChanged,
  });

  static const double mapObscuredExtent = 88;

  final String nickname;
  final TodayActivitySummary summary;
  final Widget? actions;
  final ValueChanged<bool>? onStreakDialogVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final displayNickname = nickname.trim().isEmpty ? '사용자' : nickname.trim();
    return Container(
      key: const ValueKey('today-activity-header'),
      color: storyRootNavigationSurfaceColor(palette),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5,
            AppSpacing.x2,
            AppSpacing.x5,
            AppSpacing.x3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            key: const ValueKey('today-activity-greeting-line'),
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '샬롬 👋 ',
                                  style: _greetingStyle(palette),
                                ),
                                TextSpan(
                                  text: displayNickname,
                                  style: _greetingStyle(palette).copyWith(
                                    color: palette.currentAccentDeep,
                                    fontSize: 14.2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: '님,',
                                  style: _greetingStyle(palette),
                                ),
                              ],
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '오늘도 주님과 함께 걸어볼까요!',
                            key: const ValueKey(
                              'today-activity-invitation-line',
                            ),
                            maxLines: 1,
                            style: AppTextStyles.body.copyWith(
                              color: palette.mutedText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions != null) ...[
                    const SizedBox(width: AppSpacing.x3),
                    actions!,
                  ],
                ],
              ),
              const SizedBox(height: 6),
              TodayActivityLabelRail(
                summary: summary,
                onStreakDialogVisibilityChanged:
                    onStreakDialogVisibilityChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _greetingStyle(AppColorPalette palette) {
    return AppTextStyles.body.copyWith(
      color: palette.text,
      fontSize: 13.5,
      fontWeight: FontWeight.w900,
      height: 1.15,
    );
  }
}

class TodayActivityLabelRail extends StatelessWidget {
  const TodayActivityLabelRail({
    super.key,
    required this.summary,
    this.onStreakDialogVisibilityChanged,
  });

  final TodayActivitySummary summary;
  final ValueChanged<bool>? onStreakDialogVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final streakActive = summary.hasActivityToday && summary.streakDays > 0;
    return Row(
      key: const ValueKey('today-activity-label-rail'),
      children: [
        Expanded(
          child: _TodayActivityLabel(
            icon: Icons.local_fire_department_rounded,
            text: '연속: ${summary.streakDays}일',
            accent: palette.currentAccentDeep,
            completed: streakActive,
            contentKey: const ValueKey('today-streak-label-content'),
            completionOverlay: streakActive
                ? _StreakFireCelebration(
                    accent: palette.currentAccentDeep,
                    streakDays: summary.streakDays,
                  )
                : null,
            onTap: () => _showStreakInfo(context),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: _TodayActivityLabel(
            icon: Icons.explore_rounded,
            text: '이야기: ${summary.explorationCount}개',
            accent: palette.regionAccent,
            completed: summary.explorationCount > 0,
            completionMarkKey: const ValueKey('today-story-completion-mark'),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: _TodayActivityLabel(
            icon: Icons.edit_note_rounded,
            text: '다이어리: ${summary.hasDiary ? 'o' : 'x'}',
            accent: palette.successBottom,
            completed: summary.hasDiary,
            completionMarkKey: const ValueKey('today-diary-completion-mark'),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Expanded(
          child: _TodayActivityLabel(
            icon: Icons.menu_book_rounded,
            text: '통독: ${summary.bibleChapterCount}장',
            accent: palette.primary,
            completed: summary.bibleChapterCount > 0,
            completionMarkKey: const ValueKey('today-bible-completion-mark'),
          ),
        ),
      ],
    );
  }

  Future<void> _showStreakInfo(BuildContext context) async {
    onStreakDialogVisibilityChanged?.call(true);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => const WebPointerInterceptor(
          child: ParchmentDialog(
            title: '연속일은 이렇게 계산해요',
            subtitle: '한국시간 자정을 기준으로 하루 활동을 계산합니다.',
            showCloseButton: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StreakRuleRow(icon: '🧭', text: '탐험 완료 조건: 감정 새기기'),
                SizedBox(height: 7),
                _StreakRuleRow(icon: '📝', text: '다이어리 완료 조건: 작성 완료'),
                SizedBox(height: 7),
                _StreakRuleRow(icon: '📖', text: '통독 완료 조건: 1장 이상 읽음 처리'),
                SizedBox(height: 12),
                _StreakRuleSummary(),
              ],
            ),
          ),
        ),
      );
    } finally {
      onStreakDialogVisibilityChanged?.call(false);
    }
  }
}

class _TodayActivityLabel extends StatelessWidget {
  const _TodayActivityLabel({
    required this.icon,
    required this.text,
    required this.accent,
    this.onTap,
    this.completed = false,
    this.completionMarkKey,
    this.completionOverlay,
    this.contentKey,
  });

  final IconData icon;
  final String text;
  final Color accent;
  final VoidCallback? onTap;
  final bool completed;
  final Key? completionMarkKey;
  final Widget? completionOverlay;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.12),
              palette.cardSurface,
            ),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: accent.withValues(alpha: 0.36)),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Opacity(
                key: contentKey,
                opacity: completed ? 0.18 : 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: accent),
                      const SizedBox(width: 2),
                      Text(
                        text,
                        maxLines: 1,
                        softWrap: false,
                        style: AppTextStyles.counter.copyWith(
                          color: accent,
                          fontSize: 10.2,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (completed)
                completionOverlay ??
                    Icon(
                      Icons.check_circle_rounded,
                      key: completionMarkKey,
                      size: 22,
                      color: accent,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakFireCelebration extends StatefulWidget {
  const _StreakFireCelebration({
    required this.accent,
    required this.streakDays,
  });

  final Color accent;
  final int streakDays;

  @override
  State<_StreakFireCelebration> createState() => _StreakFireCelebrationState();
}

class _StreakFireCelebrationState extends State<_StreakFireCelebration>
    with SingleTickerProviderStateMixin {
  static const Duration _replayDelay = Duration(milliseconds: 900);
  late final AnimationController _controller;
  late final Animation<double> _scale;
  Timer? _replayTimer;
  var _remainingReplays = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1, end: 1.32), weight: 45),
          TweenSequenceItem(tween: Tween(begin: 1.32, end: 1), weight: 55),
        ]).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
        );
    _controller.addStatusListener(_handleAnimationStatus);
    _controller.forward();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    if (_remainingReplays <= 0) {
      return;
    }
    _remainingReplays -= 1;
    _replayTimer?.cancel();
    _replayTimer = Timer(_replayDelay, () {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _StreakFireCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streakDays > oldWidget.streakDays) {
      _replayTimer?.cancel();
      _remainingReplays = 1;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('today-streak-fire-celebration'),
      width: 30,
      height: 30,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          key: const ValueKey('today-streak-fire-scale'),
          scale: _scale.value,
          child: child,
        ),
        child: Icon(
          Icons.local_fire_department_rounded,
          key: const ValueKey('today-streak-fire-icon'),
          size: 26,
          color: widget.accent,
        ),
      ),
    );
  }
}

class _StreakRuleRow extends StatelessWidget {
  const _StreakRuleRow({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: palette.subtleBorder),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 17, height: 1)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.text,
                fontSize: 12.4,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakRuleSummary extends StatelessWidget {
  const _StreakRuleSummary();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.currentAccent.withValues(alpha: 0.14),
          palette.cardSurface,
        ),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: palette.currentAccentDeep.withValues(alpha: 0.42),
        ),
      ),
      child: Text(
        '세 가지 중 1개 이상 완료한 날이 연속일에 카운팅됩니다.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.text,
          fontSize: 12.2,
          fontWeight: FontWeight.w900,
          height: 1.35,
        ),
      ),
    );
  }
}
