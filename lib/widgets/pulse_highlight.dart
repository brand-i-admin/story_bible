import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 자식 위젯 외곽에 부드럽게 깜빡이는 골드 glow 를 그린다.
///
/// `active` 가 true 인 동안 1.4초 사이클로 0→1→0 부드럽게 박동.
/// false 가 되면 즉시 멈추고 glow 가 사라진다.
///
/// EventDetailPage 의 "다음 이야기" 카드에 부착해 완료 후 다음 이동 동선을
/// 시각적으로 유도하기 위해 만들어졌다.
class PulseHighlight extends StatefulWidget {
  const PulseHighlight({
    super.key,
    required this.child,
    required this.active,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.color = const Color(0xFFE8A33D),
  });

  final Widget child;
  final bool active;
  final BorderRadius borderRadius;
  final Color color;

  @override
  State<PulseHighlight> createState() => _PulseHighlightState();
}

class _PulseHighlightState extends State<PulseHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 0 → 1 → 0 부드러운 박동.
        final t = (1 - math.cos(_controller.value * 2 * math.pi)) / 2;
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 + 0.55 * t),
                blurRadius: 8 + 20 * t,
                spreadRadius: 1 + 5 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
