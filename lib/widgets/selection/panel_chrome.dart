// 부모 라이브러리: lib/widgets/story_selection_panel.dart
//
// 패널 외곽(텍스처/페이드/접힘 미리보기/탑바/핸들/스텝 버튼) 관련 위젯과
// 단계별 액센트 색상 헬퍼를 모은 파트 파일.
part of '../story_selection_panel.dart';

Color _stageAccentColor(StorySelectionPanelStage stage) {
  return switch (stage) {
    StorySelectionPanelStage.collapsed => const Color(0xFFD2873E),
    StorySelectionPanelStage.half => const Color(0xFF77A85A),
    StorySelectionPanelStage.expanded => const Color(0xFF77A85A),
  };
}

class _PanelTexturePainter extends CustomPainter {
  const _PanelTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x0E845D38);
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x08FFFFFF);

    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.12 + (i * 0.12));
      final path = Path()
        ..moveTo(size.width * 0.05, y)
        ..quadraticBezierTo(
          size.width * 0.52,
          y + (i.isEven ? 8 : -8),
          size.width * 0.95,
          y + (i.isEven ? -3 : 3),
        );
      canvas.drawPath(path, linePaint);
    }

    final glowOffsets = <Offset>[
      Offset(size.width * 0.18, size.height * 0.16),
      Offset(size.width * 0.82, size.height * 0.26),
      Offset(size.width * 0.24, size.height * 0.64),
      Offset(size.width * 0.74, size.height * 0.82),
    ];
    for (final offset in glowOffsets) {
      canvas.drawCircle(offset, 24, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PanelTextureLayer extends StatelessWidget {
  const _PanelTextureLayer();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.16,
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xFFB88A57),
          BlendMode.multiply,
        ),
        child: Image.asset(
          'assets/elements/parchment_texture.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _BottomFadeHint extends StatelessWidget {
  const _BottomFadeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F2E5CC), Color(0xD7E8D2B1)],
        ),
      ),
    );
  }
}

class _CollapsedSelectionPeek extends StatelessWidget {
  const _CollapsedSelectionPeek({
    required this.scrollController,
    required this.bottomInset,
    required this.stage,
    required this.onStepUp,
    required this.onStepDown,
  });

  final ScrollController scrollController;
  final double bottomInset;
  final StorySelectionPanelStage stage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final peekBottomPadding = math.max(4.0, bottomInset * 0.22);

    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, peekBottomPadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: _SelectionSheetTopBar(
                stage: stage,
                onStepUp: onStepUp,
                onStepDown: onStepDown,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionSheetTopBar extends StatelessWidget {
  const _SelectionSheetTopBar({
    required this.stage,
    required this.onStepUp,
    required this.onStepDown,
  });

  final StorySelectionPanelStage stage;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final accentColor = _stageAccentColor(stage);
    final containerColor = Color.lerp(
      const Color(0xFFF8F0DB),
      accentColor,
      0.30,
    )!;
    final canStepDown = stage != StorySelectionPanelStage.collapsed;
    final canStepUp = stage == StorySelectionPanelStage.collapsed;

    return Material(
      color: Colors.transparent,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accentColor, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetStepButton(
              icon: Icons.keyboard_arrow_down_rounded,
              semanticsLabel: '선택 창 한 단계 접기',
              enabled: canStepDown,
              accentColor: accentColor,
              onTap: canStepDown ? onStepDown : null,
            ),
            const SizedBox(width: 5),
            _SelectionSheetHandle(accentColor: accentColor),
            const SizedBox(width: 5),
            _SheetStepButton(
              icon: Icons.keyboard_arrow_up_rounded,
              semanticsLabel: '선택 창 한 단계 펼치기',
              enabled: canStepUp,
              accentColor: accentColor,
              onTap: canStepUp ? onStepUp : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSheetHandle extends StatelessWidget {
  const _SelectionSheetHandle({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 24,
        height: 3,
        decoration: BoxDecoration(
          color: const Color(0xAA6E573E),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _SheetStepButton extends StatelessWidget {
  const _SheetStepButton({
    required this.icon,
    required this.semanticsLabel,
    required this.enabled,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final bool enabled;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = enabled
        ? Color.lerp(const Color(0xFFFFFFFF), accentColor, 0.20)!
        : const Color(0xFFE5DDCC);
    final foregroundColor = enabled
        ? const Color(0xFF5F4529)
        : const Color(0xFFAA977D);

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: enabled ? accentColor : const Color(0xFFCABAA3),
                width: 0.9,
              ),
            ),
            child: Center(child: Icon(icon, color: foregroundColor, size: 15)),
          ),
        ),
      ),
    );
  }
}
