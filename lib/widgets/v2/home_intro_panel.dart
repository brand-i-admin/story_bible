import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../state/story_state.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../story_home_styles.dart';
import 'era_pick_rows.dart';

/// 첫 화면 — "오늘은 성경 어디를 여행해볼까요?" 패널.
///
/// 두 단계로 구성:
///   1. 여행할 시대를 골라보세요 — 구약/신약 두 줄로 분리된 시대 칩. **단일 선택**.
///      비선택 시 시대 고유 색 ([EraColors.forCode]) 을 점·아이콘으로 미리 보여주고,
///      선택 시 갈색 그라데이션으로 활성 표시한다. 같은 시대 색은 지도 폴리곤에도 사용된다.
///   2. 어떻게 볼까요? — 시대가 선택된 경우에만 활성.
///      [시간 순 / 인물과 걷기 / 장소로 시작].
class HomeIntroPanel extends StatelessWidget {
  const HomeIntroPanel({
    super.key,
    required this.eras,
    required this.selectedEraId,
    required this.onSelectEra,
    required this.onPickMode,
  });

  final List<Era> eras;
  final String? selectedEraId;

  /// 시대 칩을 누르면 호출. 같은 시대가 다시 눌리면 호출 측에서 해제 처리.
  final ValueChanged<String> onSelectEra;
  final ValueChanged<SelectionMode> onPickMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPickMode = selectedEraId != null;
    // 시대를 골랐으면 1번 영역(헤더+칩)은 흐리게 처리해 시선을 2번으로 유도.
    // 다시 고르려면 상단의 "시대 다시 선택" 또는 stepper 의 "시대/방법"을 사용한다.
    final eraStepOpacity = canPickMode ? 0.55 : 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '🌿  오늘은 성경 어디를 여행해볼까요?  🌿',
                maxLines: 1,
                style: AppTextStyles.h3.copyWith(
                  color: AppColors.ink800,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: eraStepOpacity,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            child: AbsorbPointer(
              absorbing: canPickMode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepHeader(
                    number: 1,
                    title: '여행할 시대를 골라보세요',
                    enabled: true,
                    done: canPickMode,
                    iconData: Icons.schedule_outlined,
                  ),
                  const SizedBox(height: 8),
                  EraPickRows(
                    eras: eras,
                    selectedEraId: selectedEraId,
                    onSelectEra: onSelectEra,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _StepHeader(
            number: 2,
            title: '어떻게 볼까요?',
            enabled: canPickMode,
            highlighted: canPickMode,
            iconData: Icons.explore_outlined,
          ),
          const SizedBox(height: 8),
          AnimatedOpacity(
            opacity: canPickMode ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !canPickMode,
              child: Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      key: const ValueKey('home-mode-timeline'),
                      icon: Icons.access_time_rounded,
                      title: '시간 순',
                      subtitle: '선택한 시대의 사건을 시간 순으로 봅니다',
                      accent: const Color(0xFF8C5A2E),
                      onTap: () => onPickMode(SelectionMode.timeline),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      key: const ValueKey('home-mode-character'),
                      icon: Icons.people,
                      title: '인물과 걷기',
                      subtitle: '선택한 인물들의 사건을 비교합니다',
                      accent: theme.colorScheme.tertiary,
                      onTap: () => onPickMode(SelectionMode.character),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      key: const ValueKey('home-mode-region'),
                      icon: Icons.location_on,
                      title: '장소로 시작',
                      subtitle: '한 장소에서 이야기를 시간 순으로 봅니다',
                      accent: theme.colorScheme.primary,
                      onTap: () => onPickMode(SelectionMode.region),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '💡  시대를 켜면 지도 위에 같은 색으로 영역이 표시됩니다.',
                maxLines: 1,
                style: AppTextStyles.hint.copyWith(color: AppColors.ink450),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.number,
    required this.title,
    required this.enabled,
    required this.iconData,
    this.done = false,
    this.highlighted = false,
  });
  final int number;
  final String title;
  final bool enabled;
  final IconData iconData;

  /// 이 단계가 이미 완료된 상태(다음 단계로 넘어가야 함). 완료 표식(✓) 노출.
  final bool done;

  /// 사용자가 지금 눌러야 할 단계임을 강조. 색을 ink800 + 굵은 글씨로 차별화.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (!enabled) {
      color = AppColors.ink150;
    } else if (highlighted) {
      color = AppColors.ink800;
    } else {
      color = AppColors.ink450;
    }
    return Row(
      children: [
        Icon(iconData, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$number. $title',
          style: AppTextStyles.sectionTitle.copyWith(
            color: color,
            fontWeight: highlighted ? FontWeight.w800 : null,
          ),
        ),
        if (done) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.check_circle,
            size: 14,
            color: color.withValues(alpha: 0.8),
          ),
        ],
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        splashColor: AppColors.brownWarm.withValues(alpha: 0.18),
        highlightColor: AppColors.brownWarm.withValues(alpha: 0.10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: softButtonDecoration(selected: false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeIcon(icon: icon, accent: accent, size: 23),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.2,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9.4,
                  height: 1.18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({
    required this.icon,
    required this.accent,
    required this.size,
  });
  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.parchmentCream, size: size * 0.58),
    );
  }
}
