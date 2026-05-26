import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 사건 상세 페이지의 완료 축하 효과.
///
/// `child` 를 감싸 두고, 부모가 GlobalKey 로 [CompletionCelebrationState.play]
/// 를 호출하면 두 효과가 **동시 시작**:
///  1. 별가루(sparkle) burst + 초록 글로우 링 (1.2s)
///  2. 도장이 쾅 찍히고 0.4s 흔들리다 페이드 (~0.95s)
/// burst 가 1.2s 길어 도장보다 늦게 끝나며, 도장 종료 시 [onComplete] 콜백.
class CompletionCelebration extends StatefulWidget {
  const CompletionCelebration({
    super.key,
    required this.child,
    this.stampLabel = '완료',
    this.onComplete,
  });

  final Widget child;
  final String stampLabel;

  static const burstDuration = Duration(milliseconds: 1200);
  static const stampDuration = Duration(milliseconds: 950);

  /// 도장 단계까지 끝났을 때 한 번 호출. (다음 이야기 카드 glow 트리거 등)
  final VoidCallback? onComplete;

  @override
  State<CompletionCelebration> createState() => CompletionCelebrationState();
}

class CompletionCelebrationState extends State<CompletionCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: CompletionCelebration.burstDuration,
  );
  late final AnimationController _stamp = AnimationController(
    vsync: this,
    duration: CompletionCelebration.stampDuration,
  )..addStatusListener(_onStampStatus);
  late final List<_Particle> _particles = _generateParticles();
  String? _activeStampLabel;

  void _onStampStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.onComplete?.call();
    }
  }

  void play({String? stampLabel}) {
    _activeStampLabel = stampLabel ?? widget.stampLabel;
    // 별가루 burst 와 도장 슬램을 동시 시작 — 한 번의 묵직한 햅틱으로 함께 알림.
    HapticFeedback.mediumImpact();
    _burst.forward(from: 0);
    _stamp.forward(from: 0);
  }

  @override
  void dispose() {
    _burst.dispose();
    _stamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (context, _) {
                if (!_burst.isAnimating && _burst.value == 0) {
                  return const SizedBox.shrink();
                }
                return CustomPaint(
                  painter: _CelebrationPainter(
                    progress: _burst.value,
                    particles: _particles,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _stamp,
              builder: (context, _) {
                if (!_stamp.isAnimating && _stamp.value == 0) {
                  return const SizedBox.shrink();
                }
                return _StampOverlay(
                  progress: _stamp.value,
                  label: _activeStampLabel ?? widget.stampLabel,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static List<_Particle> _generateParticles() {
    // 결정적 시드 → 매번 같은 분포 (디자인 의도 유지).
    final rng = math.Random(7);
    const count = 14;
    return List.generate(count, (i) {
      final baseAngle = (i / count) * 2 * math.pi;
      final jitter = (rng.nextDouble() - 0.5) * 0.45;
      return _Particle(
        angle: baseAngle + jitter,
        distance: 60.0 + rng.nextDouble() * 50.0,
        size: 4.0 + rng.nextDouble() * 4.0,
        delay: rng.nextDouble() * 0.18,
        // 골드/초록 교차 — 양피지 톤 + 완료(초록) 시그널 결합.
        color: i.isEven ? const Color(0xFFE8A33D) : const Color(0xFF7AAC4C),
      );
    });
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.color,
  });

  final double angle;
  final double distance;
  final double size;
  final double delay; // 0..1, 진행 시작 지연
  final Color color;
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);

    // 초록 글로우 링 — 외곽으로 퍼지며 페이드.
    final ringT = Curves.easeOut.transform(progress);
    final maxRing = math.max(size.width, size.height) * 0.55;
    final ringRadius = ringT * maxRing;
    final ringOpacity = (1 - progress) * 0.45;
    if (ringOpacity > 0) {
      final ringPaint = Paint()
        ..color = const Color(0xFF7AAC4C).withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // 별가루 파티클 — 각도 방향으로 날아가며 페이드.
    for (final p in particles) {
      final span = 1 - p.delay;
      final localProgress = ((progress - p.delay) / span).clamp(0.0, 1.0);
      if (localProgress <= 0) continue;
      final eased = Curves.easeOut.transform(localProgress);
      final dx = math.cos(p.angle) * p.distance * eased;
      final dy = math.sin(p.angle) * p.distance * eased;
      final position = center + Offset(dx, dy);
      // 끝 30% 구간에서 페이드 아웃.
      final fadeIn = (localProgress / 0.15).clamp(0.0, 1.0);
      final fadeOut = (1 - (localProgress - 0.7) / 0.3).clamp(0.0, 1.0);
      final opacity = math.min(fadeIn, fadeOut);
      // sin 곡선으로 사이즈 부풀었다 줄어듦.
      final sizeFactor = math.sin(localProgress * math.pi);
      final radius = p.size * (0.55 + 0.55 * sizeFactor);
      _drawSparkle(
        canvas,
        position,
        radius,
        p.color.withValues(alpha: opacity),
      );
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()..color = color;
    // 4점 스파클 (다이아몬드 + 좁은 허리).
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.32, c.dy - r * 0.32)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + r * 0.32, c.dy + r * 0.32)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.32, c.dy + r * 0.32)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - r * 0.32, c.dy - r * 0.32)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter old) =>
      old.progress != progress;
}

/// 금박 "완료" 도장 오버레이.
///
/// 950ms 동안 슬램(0~100ms) → 흔듦(100~500ms) → 페이드(500~950ms) 진행.
class _StampOverlay extends StatelessWidget {
  const _StampOverlay({required this.progress, required this.label});

  final double progress;
  final String label;

  // 도장 자체의 기본 기울기 (-12°). 실제 도장 같은 느낌.
  static const double _baseTilt = -0.21;

  @override
  Widget build(BuildContext context) {
    final ms = progress * 950;
    final double scale;
    final double opacity;
    final double shake;

    if (ms < 100) {
      // 슬램: scale 1.55 → 1.0, opacity 0 → 1.
      final p = ms / 100;
      final eased = Curves.easeOut.transform(p);
      scale = 1.55 - 0.55 * eased;
      opacity = eased;
      shake = 0;
    } else if (ms < 500) {
      // 흔듦: 4번 진동, 진폭 점차 감소.
      final p = (ms - 100) / 400;
      scale = 1.0;
      opacity = 1.0;
      shake = math.sin(p * math.pi * 4) * 0.07 * (1 - p);
    } else {
      // 페이드: opacity 1 → 0, 살짝 작아짐.
      final p = (ms - 500) / 450;
      scale = 1.0 - 0.05 * p;
      opacity = (1 - p).clamp(0.0, 1.0);
      shake = 0;
    }

    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: _baseTilt + shake,
          child: Transform.scale(
            scale: scale,
            child: _StampVisual(label: label),
          ),
        ),
      ),
    );
  }
}

class _StampVisual extends StatelessWidget {
  const _StampVisual({required this.label});

  final String label;

  // 짙은 금박. 양피지 톤과 어울리도록 brown 끼 살짝 섞은 골드.
  static const _ink = Color(0xFFB07220);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _ink, width: 4),
        // 살짝 비치는 금색 채움 — 진짜 도장 잉크 느낌.
        color: const Color(0x22B07220),
      ),
      child: Container(
        margin: const EdgeInsets.all(5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _ink, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: label == '완료' ? 26 : (label.length <= 2 ? 31 : 24),
            fontWeight: FontWeight.w900,
            color: _ink,
            letterSpacing: label == '완료' ? 2 : 0,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
