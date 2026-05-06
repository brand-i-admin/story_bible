import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../state/story_state.dart';
import '../../theme/era_colors.dart';

/// 첫 화면 — "오늘은 성경 어디를 여행해볼까요?" 패널.
///
/// 두 단계로 구성:
///   1. 여행할 시대를 골라보세요 — 구약/신약 두 줄로 분리된 시대 칩. **단일 선택**.
///      각 칩은 그 시대의 고유 색 ([EraColors.forCode]) 으로 활성 표시되고,
///      같은 색이 지도 폴리곤에도 사용된다.
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
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _StepHeader(number: 1, title: '여행할 시대를 골라보세요', enabled: true),
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
          _StepHeader(number: 2, title: '어떻게 볼까요?', enabled: canPickMode),
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
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
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
  });
  final int number;
  final String title;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.outline;
    return Row(
      children: [
        Icon(Icons.access_time, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$number. $title',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
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
    final theme = Theme.of(context);
    final eraColor = EraColors.forCode(era.code);

    final bg = selected ? eraColor : theme.colorScheme.surfaceContainerLow;
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    final border = selected ? eraColor : eraColor.withValues(alpha: 0.45);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border, width: selected ? 2 : 1.4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 시대 색 점 — 비선택 상태에서도 어떤 색인지 미리 보여 줌.
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : eraColor,
                  border: selected
                      ? Border.all(color: Colors.white, width: 1)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                era.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle, size: 16, color: Colors.white),
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
    final theme = Theme.of(context);
    return Material(
      color: accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
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
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      sample,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
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
