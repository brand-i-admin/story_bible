import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 자식 위젯 외곽에 부드럽게 깜빡이는 골드 glow 를 그린다.
///
/// `active` 가 true 로 바뀌면 1.4초 사이클로 0→1→0 부드럽게 몇 번 박동한다.
/// 정해진 횟수 뒤에는 active 가 true 여도 glow 를 숨긴다. false 가 되면 즉시
/// 멈추고 glow 가 사라진다.
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
    this.pulseCount = 2,
  }) : assert(pulseCount > 0);

  final Widget child;
  final bool active;
  final BorderRadius borderRadius;
  final Color color;
  final int pulseCount;

  @override
  State<PulseHighlight> createState() => _PulseHighlightState();
}

class _PulseHighlightState extends State<PulseHighlight>
    with SingleTickerProviderStateMixin {
  // dispose 시점에 처음 초기화되면 deactivated context 에서 TickerMode 를
  // 조회하면서 assert 가 터진다. initState 에서 즉시 생성해 그 경로 차단.
  late final AnimationController _controller;
  var _remainingPulses = 0;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener(_handleStatus);
    if (widget.active) {
      _startPulse();
    }
  }

  @override
  void didUpdateWidget(covariant PulseHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startPulse();
    } else if (!widget.active && oldWidget.active) {
      _stopPulse();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    if (!widget.active) {
      _stopPulse();
      return;
    }
    _remainingPulses -= 1;
    if (_remainingPulses > 0) {
      _controller.forward(from: 0);
      return;
    }
    _controller.value = 0;
    if (!mounted) {
      _visible = false;
      return;
    }
    setState(() {
      _visible = false;
    });
  }

  void _startPulse() {
    _remainingPulses = math.max(1, widget.pulseCount);
    _visible = true;
    _controller.forward(from: 0);
  }

  void _stopPulse() {
    _remainingPulses = 0;
    _controller
      ..stop()
      ..value = 0;
    if (!mounted) {
      _visible = false;
      return;
    }
    if (_visible) {
      setState(() {
        _visible = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || !_visible) {
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
