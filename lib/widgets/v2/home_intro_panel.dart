import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../state/story_state.dart';
import '../../theme/era_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../story_home_styles.dart';

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

    final old = _filterAndSort(eras, isNew: false);
    final newT = _filterAndSort(eras, isNew: true);

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
          _EraRow(
            label: '구약',
            eras: old,
            selectedEraId: selectedEraId,
            onSelectEra: onSelectEra,
          ),
          const SizedBox(height: 8),
          _EraRow(
            label: '신약',
            eras: newT,
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
              child: LayoutBuilder(
                builder: (_, c) {
                  final wide = c.maxWidth >= 720;
                  final left = Expanded(
                    child: _ModeCard(
                      icon: Icons.location_on,
                      title: '장소에서 시작하기',
                      subtitle: '한 장소에 쌓인 여러 시대의 이야기를\n시간순으로 봅니다.',
                      sample: '예: 베들레헴, 요단강, 예루살렘',
                      accent: theme.colorScheme.primary,
                      onTap: () => onPickMode(SelectionMode.region),
                    ),
                  );
                  final orWidget = Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      '또는',
                      style: AppTextStyles.counter.copyWith(color: AppColors.ink450),
                    ),
                  );
                  final right = Expanded(
                    child: _ModeCard(
                      icon: Icons.people,
                      title: '인물과 걷기',
                      subtitle: '선택한 인물들의 사건을 시간의\n흐름에 따라 비교합니다.',
                      sample: '예: 예수님, 세례 요한, 베드로, 마리아',
                      accent: theme.colorScheme.tertiary,
                      onTap: () => onPickMode(SelectionMode.character),
                    ),
                  );
                  if (wide) {
                    return Row(children: [left, orWidget, right]);
                  }
                  return Column(
                    children: [
                      Row(children: [left]),
                      const SizedBox(height: 8),
                      Row(children: [right]),
                    ],
                  );
                },
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

  static List<Era> _filterAndSort(List<Era> all, {required bool isNew}) {
    bool isNt(Era e) {
      final t = e.testament.toLowerCase().trim();
      return t == 'new' || t == 'nt' || t == 'new_testament';
    }

    final filtered = all.where((e) => isNt(e) == isNew).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return filtered;
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

class _EraRow extends StatelessWidget {
  const _EraRow({
    required this.label,
    required this.eras,
    required this.selectedEraId,
    required this.onSelectEra,
  });
  final String label;
  final List<Era> eras;
  final String? selectedEraId;
  final ValueChanged<String> onSelectEra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '$label:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in eras)
                _EraChip(
                  era: e,
                  selected: selectedEraId == e.id,
                  onTap: () => onSelectEra(e.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EraChip extends StatelessWidget {
  const _EraChip({
    required this.era,
    required this.selected,
    required this.onTap,
  });
  final Era era;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eraColor = EraColors.forCode(era.code);
    final iconData = _eraIconFor(era.code);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        splashColor: AppColors.brownWarm.withValues(alpha: 0.18),
        highlightColor: AppColors.brownWarm.withValues(alpha: 0.10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x6,
            vertical: AppSpacing.x4,
          ),
          decoration: softButtonDecoration(selected: selected),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!selected) ...[
                // 시대 색 점 — 지도 폴리곤 색과 같은 톤이라는 시각적 단서.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: eraColor,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                iconData,
                size: 18,
                color: selected ? AppColors.parchmentCream : eraColor,
              ),
              const SizedBox(width: 6),
              Text(
                era.name,
                style: AppTextStyles.chipLabel.copyWith(
                  color: selected ? AppColors.parchmentCream : AppColors.ink800,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppColors.parchmentCream,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sample,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String sample;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        splashColor: AppColors.brownWarm.withValues(alpha: 0.18),
        highlightColor: AppColors.brownWarm.withValues(alpha: 0.10),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x6),
          decoration: softButtonDecoration(selected: false),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.parchmentCream, size: 20),
              ),
              const SizedBox(width: AppSpacing.x5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyles.sectionTitle.copyWith(
                              color: AppColors.ink800,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.ink450,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      subtitle,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.ink600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      sample,
                      style: AppTextStyles.counter.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
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
  }
}

/// 시대 코드 → Material 아이콘 매핑.
/// 향후 일러스트 PNG로 교체할 수 있게 한 곳에 격리한다.
IconData _eraIconFor(String code) {
  switch (code) {
    case 'era_primeval':
      return Icons.terrain;
    case 'era_patriarch':
      return Icons.holiday_village;
    case 'era_exodus':
      return Icons.directions_walk;
    case 'era_judges':
      return Icons.shield;
    case 'era_monarchy':
      return Icons.workspace_premium;
    case 'era_exile_return':
      return Icons.location_city;
    case 'era_nt_public_ministry':
      return Icons.auto_awesome;
    case 'era_nt_apostolic':
      return Icons.sailing;
    case 'era_nt_post_apostolic':
      return Icons.menu_book;
    case 'era_nt_consummation':
      return Icons.local_fire_department;
    default:
      return Icons.place;
  }
}
