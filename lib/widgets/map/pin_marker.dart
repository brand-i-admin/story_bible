// 부모 라이브러리: lib/widgets/story_map_panel.dart
//
// 지도 핀 시각 표현 위젯과 핀 메타데이터 데이터 클래스를 모은 파트 파일.
// 모두 presentational - 외부 state 의존성 없음.
part of '../story_map_panel.dart';

class _PinStyle {
  const _PinStyle({
    required this.badgeHeight,
    required this.labelFontSize,
    required this.arrowWidth,
    required this.arrowHeight,
    required this.anchorGap,
  });

  final double badgeHeight;
  final double labelFontSize;
  final double arrowWidth;
  final double arrowHeight;
  final double anchorGap;

  double badgeWidthFor(String label) {
    return label.length > 2
        ? (badgeHeight + 12).clamp(24.0, 42.0)
        : badgeHeight;
  }

  double get visualHeight => badgeHeight + 4 + arrowHeight;

  double get markerHeight => visualHeight + anchorGap;
}

class _MarkerNode {
  const _MarkerNode({
    required this.event,
    required this.point,
    required this.pinLabel,
    required this.placeLabel,
    required this.showCallout,
    required this.personColors,
  });

  final StoryEvent event;
  final LatLng point;
  final String pinLabel;
  final String placeLabel;
  final bool showCallout;
  final List<Color> personColors;
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _CompactPinMarker extends StatelessWidget {
  const _CompactPinMarker({
    required this.label,
    required this.selected,
    required this.style,
  });

  final String label;
  final bool selected;
  final _PinStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PinNumberBadge(
          label,
          selected: selected,
          fontSize: style.labelFontSize,
          badgeHeight: style.badgeHeight,
        ),
        const SizedBox(height: 4),
        CustomPaint(
          size: Size(style.arrowWidth, style.arrowHeight),
          painter: _PinPointerPainter(selected: selected),
        ),
        SizedBox(height: style.anchorGap),
      ],
    );
  }
}

class _PinNumberBadge extends StatelessWidget {
  const _PinNumberBadge(
    this.label, {
    required this.selected,
    required this.fontSize,
    required this.badgeHeight,
  });

  final String label;
  final bool selected;
  final double fontSize;
  final double badgeHeight;

  @override
  Widget build(BuildContext context) {
    final isMultiChar = label.length > 2;
    final badgeWidth = isMultiChar
        ? (badgeHeight + 12).clamp(24.0, 42.0)
        : badgeHeight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFF8E4A8)
            : Colors.white.withValues(alpha: 0.96),
        shape: isMultiChar ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isMultiChar
            ? BorderRadius.circular(badgeHeight / 2)
            : null,
        border: Border.all(
          color: selected ? const Color(0xFF7B4B21) : const Color(0xFF2A2A2A),
          width: 1.0,
        ),
      ),
      child: SizedBox(
        width: badgeWidth,
        height: badgeHeight,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? const Color(0xFF5A3519) : Colors.black,
              fontSize: (fontSize * 0.64).clamp(9.0, 12.0),
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPointerPainter extends CustomPainter {
  const _PinPointerPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..color = selected ? const Color(0xFFD18B37) : const Color(0xFF4A3827);

    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.38);

    final leftTop = Offset(0, 0);
    final tip = Offset(size.width / 2, size.height);
    final rightTop = Offset(size.width, 0);

    canvas.drawLine(leftTop, tip, shadow);
    canvas.drawLine(rightTop, tip, shadow);
    canvas.drawLine(leftTop, tip, paint);
    canvas.drawLine(rightTop, tip, paint);
  }

  @override
  bool shouldRepaint(covariant _PinPointerPainter oldDelegate) {
    return oldDelegate.selected != selected;
  }
}
