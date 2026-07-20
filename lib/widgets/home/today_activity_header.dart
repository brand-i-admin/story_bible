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
                ? _StreakFireCelebration(accent: palette.currentAccentDeep)
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
  const _StreakFireCelebration({required this.accent});

  final Color accent;

  @override
  State<_StreakFireCelebration> createState() => _StreakFireCelebrationState();
}

class _StreakFireCelebrationState extends State<_StreakFireCelebration>
    with SingleTickerProviderStateMixin {
  static const _sparklePositions = [
    Offset(11, 0),
    Offset(23, 9),
    Offset(6, 22),
    Offset(0, 10),
  ];
  static const _sparklePhases = [0.0, 0.22, 0.5, 0.72];

  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1, end: 1.28).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _sparkleIntensity(int index) {
    final progress = (_controller.value + _sparklePhases[index]) % 1;
    return 1 - (progress - 0.5).abs() * 2;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final sparkleColor = _streakSparkleColor(palette);
    return SizedBox(
      key: const ValueKey('today-streak-fire-celebration'),
      width: 30,
      height: 30,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glowIntensity = Curves.easeInOutSine.transform(
            _controller.value,
          );
          final glowColor = Color.alphaBlend(
            AppColors.goldHi.withValues(alpha: 0.42),
            widget.accent,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: SizedBox(
                  width: 17 + glowIntensity * 7,
                  height: 17 + glowIntensity * 7,
                  child: DecoratedBox(
                    key: const ValueKey('today-streak-fire-glow'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withValues(
                        alpha: 0.06 + glowIntensity * 0.12,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withValues(
                            alpha: 0.14 + glowIntensity * 0.24,
                          ),
                          blurRadius: 5 + glowIntensity * 9,
                          spreadRadius: 0.5 + glowIntensity * 1.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < _sparklePositions.length; index++)
                _StreakFireSparkle(
                  opacityKey: ValueKey('today-streak-fire-sparkle-$index'),
                  position: _sparklePositions[index],
                  intensity: _sparkleIntensity(index),
                  color: sparkleColor,
                ),
              Center(
                child: Transform.scale(
                  key: const ValueKey('today-streak-fire-scale'),
                  scale: _scale.value,
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    key: const ValueKey('today-streak-fire-icon'),
                    size: 27,
                    color: widget.accent,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakFireSparkle extends StatelessWidget {
  const _StreakFireSparkle({
    required this.opacityKey,
    required this.position,
    required this.intensity,
    required this.color,
  });

  final Key opacityKey;
  final Offset position;
  final double intensity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Transform.scale(
        scale: 0.68 + intensity * 0.52,
        child: Opacity(
          key: opacityKey,
          opacity: 0.18 + intensity * 0.82,
          child: Icon(Icons.auto_awesome_rounded, size: 8, color: color),
        ),
      ),
    );
  }
}

Color _streakSparkleColor(AppColorPalette palette) {
  return palette == AppColorPalette.blackMap
      ? AppColors.goldHi
      : palette.primaryDeep;
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
