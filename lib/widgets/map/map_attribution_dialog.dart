import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../parchment_dialog.dart';
import 'map_tile_style.dart';

/// 운영 지도 배경의 출처와 라이선스를 안내한다.
Future<void> showMapAttributionDialog(BuildContext context) {
  final source = StoryMapTileStyles.sourceFor(StoryMapTileStyles.defaultStyle);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ParchmentDialog(
      title: '지도 출처',
      subtitle: '현재 배경: ${source.label}',
      showCloseButton: true,
      onClose: () => Navigator.of(dialogContext).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < source.attributionLines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _MapAttributionLine(
              source: source.attributionLines[i].source,
              license: source.attributionLines[i].license,
            ),
          ],
        ],
      ),
    ),
  );
}

class _MapAttributionLine extends StatelessWidget {
  const _MapAttributionLine({required this.source, this.license});

  final String source;
  final String? license;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Icon(Icons.circle, size: 5, color: palette.currentAccentDeep),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, height: 1.5, color: palette.text),
              children: [
                TextSpan(text: source),
                if (license != null) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: license!,
                    style: TextStyle(
                      color: palette.primaryDeep,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
