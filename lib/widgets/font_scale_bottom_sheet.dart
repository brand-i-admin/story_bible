// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import '../state/font_scale_providers.dart';

/// 글자 크기 선택 바텀시트를 띄운다.
///
/// 탭 시 즉시 전역 `fontScaleProvider`가 갱신되어 앱 전체 텍스트가 재스케일된다.
Future<void> showFontScaleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFF8F1E4),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const FontScaleBottomSheet(),
  );
}

class FontScaleBottomSheet extends ConsumerWidget {
  const FontScaleBottomSheet({super.key});

  static const String _previewText = '태초에 하나님이 천지를 창조하시니라 (창세기 1:1)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fontScaleProvider);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '글자 크기',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A331D),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E2),
                border: Border.all(color: const Color(0xFFD8BF99)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                _previewText,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF3A2816),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: FontScale.values
                  .map(
                    (scale) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _FontScaleChoiceButton(
                          scale: scale,
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
    );
  }
}

class _FontScaleChoiceButton extends StatelessWidget {
  const _FontScaleChoiceButton({
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  final FontScale scale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            color: selected ? const Color(0xFFE9D18E) : const Color(0xFFFDF5E2),
            border: Border.all(
              color: selected
                  ? const Color(0xFFB27A2B)
                  : const Color(0xFFD8BF99),
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
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: Color(0xFF6A401E),
                      )
                    : null,
              ),
              Text(
                scale.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A2816),
                ),
              ),
              Text(
                '${scale.ratio.toStringAsFixed(1)}×',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6A401E)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
