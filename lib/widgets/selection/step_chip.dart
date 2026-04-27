// 부모 라이브러리: lib/widgets/story_selection_panel.dart
//
// 단계 칩, 요약 필, 분절 토글, 주요 액션 버튼, 빈 단계 메시지 등
// 단계(step) 인터랙션 관련 위젯을 모은 파트 파일.
part of '../story_selection_panel.dart';

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.summaryLabels = const [],
  });

  final String title;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final List<String> summaryLabels;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? const LinearGradient(
            colors: [Color(0xFFD08943), Color(0xFF995B2C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0x4CFFFFF9), Color(0x12FFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              gradient: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF5D88F)
                    : const Color(0x77A57B56),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.4,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: selected
                        ? AppColors.parchmentCream
                        : const Color(0xFF6A4A31),
                  ),
                ),
                if (summaryLabels.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Row(
                    children: summaryLabels
                        .map(
                          (label) => Flexible(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: label == summaryLabels.last ? 0 : 3,
                              ),
                              child: _StepSummaryPill(
                                label: label,
                                selected: selected,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSummaryPill extends StatelessWidget {
  const _StepSummaryPill({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: selected ? const Color(0x2FFFFFFF) : const Color(0x28A57B56),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? const Color(0x66FFF4D6) : const Color(0x669E7A56),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 7.8,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.parchmentCream : const Color(0xFF6A4A31),
          height: 0.95,
        ),
      ),
    );
  }
}

class _CompactSegmentedToggle extends StatelessWidget {
  const _CompactSegmentedToggle({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onSelectFirst,
    required this.onSelectSecond,
  });

  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final VoidCallback onSelectFirst;
  final VoidCallback onSelectSecond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x30FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66A57B56)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactSegmentedToggleButton(
            label: firstLabel,
            selected: firstSelected,
            onTap: onSelectFirst,
          ),
          const SizedBox(width: 6),
          _CompactSegmentedToggleButton(
            label: secondLabel,
            selected: !firstSelected,
            onTap: onSelectSecond,
          ),
        ],
      ),
    );
  }
}

class _CompactSegmentedToggleButton extends StatelessWidget {
  const _CompactSegmentedToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 92,
          height: 38,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFB06C34), Color(0xFF7A4824)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0x17A57B56), Color(0x06A57B56)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF3D88C)
                  : const Color(0x6D9B795B),
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.6,
                fontWeight: FontWeight.w800,
                color: selected
                    ? AppColors.parchmentCream
                    : const Color(0xFF654A31),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.enabled,
    required this.pressed,
    required this.completed,
    required this.onPressed,
    required this.onPressedStateChanged,
    this.compact = false,
  });

  final String label;
  final bool enabled;
  final bool pressed;
  final bool completed;
  final VoidCallback? onPressed;
  final ValueChanged<bool> onPressedStateChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gradient = completed
        ? pressed
              ? const LinearGradient(
                  colors: [Color(0xFF2D8A56), Color(0xFF226342)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFF6CC482), Color(0xFF2F8E5D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
        : pressed
        ? const LinearGradient(
            colors: [Color(0xFFB56B1F), Color(0xFF8B4B12)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFE1AA4A), Color(0xFFB06B25)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return GestureDetector(
      onTapDown: enabled ? (_) => onPressedStateChanged(true) : null,
      onTapCancel: enabled ? () => onPressedStateChanged(false) : null,
      onTapUp: enabled ? (_) => onPressedStateChanged(false) : null,
      onTap: enabled ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.54,
        child: Container(
          height: compact ? 42 : 46,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
            border: Border.all(
              color: completed
                  ? const Color(0xFFC9F0CB)
                  : const Color(0xFFF7DA93),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: completed
                    ? const Color(0x2D256E41)
                    : const Color(0x3A6C3E15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 13.6 : 14.4,
              fontWeight: FontWeight.w800,
              color: AppColors.parchmentCream,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyStepMessage extends StatelessWidget {
  const _EmptyStepMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6A4C33),
            fontSize: 14.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
