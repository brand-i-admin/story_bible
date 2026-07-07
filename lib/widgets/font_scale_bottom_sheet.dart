import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/color_palette_providers.dart';
import '../state/font_scale_providers.dart';
import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import 'web_pointer_interceptor.dart';

/// 색 조합과 글자 크기 선택 바텀시트를 띄운다.
///
/// 탭 시 즉시 전역 provider가 갱신되어 앱 전체 테마/텍스트가 다시 그려진다.
Future<void> showFontScaleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const WebPointerInterceptor(child: FontScaleBottomSheet()),
  );
}

class FontScaleBottomSheet extends ConsumerWidget {
  const FontScaleBottomSheet({super.key});

  static const String _previewText = '태초에 하나님이 천지를 창조하시니라 (창세기 1:1)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fontScaleProvider);
    final currentPalette = ref.watch(colorPaletteProvider);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: currentPalette.panelSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: currentPalette.panelBorder)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '색/글자 설정',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: currentPalette.text,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '색 조합',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: currentPalette.text,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: AppColorPalette.values
                    .map(
                      (palette) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _PaletteChoiceButton(
                            palette: palette,
                            selected: palette == currentPalette,
                            onTap: () => ref
                                .read(colorPaletteProvider.notifier)
                                .set(palette),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              Text(
                '글자 크기',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: currentPalette.text,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: currentPalette.cardSurface,
                  border: Border.all(color: currentPalette.selectedBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _previewText,
                  style: TextStyle(
                    fontSize: 16,
                    color: currentPalette.text,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: FontScale.values
                    .map(
                      (scale) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _FontScaleChoiceButton(
                            scale: scale,
                            palette: currentPalette,
                            selected: scale == current,
                            onTap: () =>
                                ref.read(fontScaleProvider.notifier).set(scale),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteChoiceButton extends StatelessWidget {
  const _PaletteChoiceButton({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppColorPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = selected ? palette.text : AppColors.ink700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('color-palette-button-${palette.storageKey}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? palette.selectedSurface
                : AppColors.parchmentCard.withValues(alpha: 0.92),
            border: Border.all(
              color: selected ? palette.selectedBorder : AppColors.borderCard,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PaletteWheel(palette: palette),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        palette.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.2,
                          fontWeight: FontWeight.w900,
                          color: labelColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? palette.currentAccentDeep : AppColors.ink300,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteWheel extends StatelessWidget {
  const _PaletteWheel({required this.palette});

  final AppColorPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('color-palette-wheel-${palette.storageKey}'),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.parchmentLight.withValues(alpha: 0.88),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _PaletteWheelPainter(
            colors: [
              palette.primary,
              palette.currentAccent,
              palette.stepStory,
              palette.successBottom,
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteWheelPainter extends CustomPainter {
  const _PaletteWheelPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sweep = 2 * 3.141592653589793 / colors.length;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < colors.length; i += 1) {
      paint.color = colors[i];
      canvas.drawArc(
        rect,
        -3.141592653589793 / 2 + sweep * i,
        sweep,
        true,
        paint,
      );
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.62);
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PaletteWheelPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}

class _FontScaleChoiceButton extends StatelessWidget {
  const _FontScaleChoiceButton({
    required this.scale,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final FontScale scale;
  final AppColorPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('font-scale-button-${scale.storageKey}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? palette.selectedSurface
                : AppColors.parchmentCard.withValues(alpha: 0.82),
            border: Border.all(
              color: selected ? palette.selectedBorder : AppColors.borderCard,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                child: selected
                    ? const Icon(Icons.check, size: 18, color: AppColors.ink700)
                    : null,
              ),
              Text(
                scale.label,
                textAlign: TextAlign.center,
                maxLines: largeText ? 2 : 1,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink900,
                ),
              ),
              Text(
                '${scale.ratio.toStringAsFixed(1)}x',
                style: TextStyle(fontSize: 12, color: palette.mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
