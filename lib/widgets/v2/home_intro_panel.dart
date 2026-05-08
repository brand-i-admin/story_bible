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
///   2. 어떻게 볼까요? — 시대가 선택된 경우에만 활성. [장소에서 시작하기 / 인물과 걷기].
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '🌿  오늘은 성경 어디를 여행해볼까요?  🌿',
              style: AppTextStyles.h3.copyWith(
                color: AppColors.ink800,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _StepHeader(
            number: 1,
            title: '여행할 시대를 골라보세요',
            enabled: true,
            iconData: Icons.schedule_outlined,
          ),
          const SizedBox(height: 8),
          EraPickRows(
            eras: eras,
            selectedEraId: selectedEraId,
            onSelectEra: onSelectEra,
          ),
          const SizedBox(height: 18),
          _StepHeader(
            number: 2,
            title: '어떻게 볼까요?',
            enabled: canPickMode,
            iconData: Icons.explore_outlined,
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: canPickMode ? 1.0 : 0.45,
            child: IgnorePointer(
              ignoring: !canPickMode,
              child: Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.location_on,
                      title: '장소에서 시작하기',
                      subtitle: '한 장소의 이야기를\n시간순으로 봅니다.',
                      accent: theme.colorScheme.primary,
                      onTap: () => onPickMode(SelectionMode.region),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.people,
                      title: '인물과 걷기',
                      subtitle: '선택한 인물들의\n사건을 비교합니다.',
                      accent: theme.colorScheme.tertiary,
                      onTap: () => onPickMode(SelectionMode.character),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '💡  시대를 켜면 지도 위에 같은 색으로 영역이 표시됩니다.',
              style: AppTextStyles.hint.copyWith(color: AppColors.ink450),
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
  });
  final int number;
  final String title;
  final bool enabled;
  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.ink450 : AppColors.ink150;
    return Row(
      children: [
        Icon(iconData, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$number. $title',
          style: AppTextStyles.sectionTitle.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
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
          padding: const EdgeInsets.all(8),
          decoration: softButtonDecoration(selected: false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      color: AppColors.parchmentCream,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
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
