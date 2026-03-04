import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class ParchmentBackground extends StatelessWidget {
  const ParchmentBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.parch, Color(0xFFE8D9B0)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ParchmentLinePainter()),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ParchmentLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x14A07846);
    const step = 28.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
