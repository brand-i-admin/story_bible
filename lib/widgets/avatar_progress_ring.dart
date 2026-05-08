import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';
import 'character_avatar.dart';

/// 아바타 둘레에 원형 progress ring 을 그린다.
///
/// 아바타는 항상 또렷이 보이고, 둘레 호가 0→100% 시계방향으로 차오른다 (초록).
/// `name` 이 주어지면 아바타 내부 하단에 반투명 그라데이션 + 이름 라벨을
/// 오버레이해서 별도 텍스트 라인 없이도 인물 식별이 가능하게 한다.
class AvatarProgressRing extends StatelessWidget {
  const AvatarProgressRing({
    super.key,
    required this.character,
    required this.size,
    required this.progress,
    this.name,
    this.strokeWidth = 3.5,
    this.gap = 2.0,
  });

  /// ring 포함 전체 지름.
  final double size;

  /// 0..1
  final double progress;

  final Character character;
  final double strokeWidth;

  /// ring 과 아바타 사이 빈 공간.
  final double gap;

  /// 비어있지 않으면 아바타 내부 하단에 라벨로 렌더한다.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final inner = (size - 2 * (strokeWidth + gap)).clamp(0.0, double.infinity);
    final clamped = progress.clamp(0.0, 1.0);
    final hasName = (name ?? '').trim().isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        // 이름 pill 이 원 바깥 하단으로 살짝 overflow 하므로 clip 끄기.
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(progress: clamped, strokeWidth: strokeWidth),
          ),
          // 아바타는 ring 안쪽에 그대로.
          ClipOval(
            child: SizedBox(
              width: inner,
              height: inner,
              child: CharacterAvatar(character: character, size: inner),
            ),
          ),
          // 이름 pill — 원의 맨 아래 가장자리에 가운데 정렬로 걸치게.
          // ClipOval 바깥에 있어서 아바타 몸통을 가리지 않고, 일부만 ring
          // 외곽 아래로 살짝 튀어나옴.
          if (hasName)
            Positioned(
              bottom: -2,
              child: _NamePill(name: name!, maxWidth: size * 0.95),
            ),
        ],
      ),
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill({required this.name, required this.maxWidth});

  final String name;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xEE2A1A0A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x55FFFFFF), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            name,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  static const _trackColor = Color(0x554E3A26);
  // 진행 호는 항상 초록 — 양피지 배경에서 가장 또렷하게 보이는 색.
  static const _ringColor = Color(0xFF7AAC4C);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    if (radius <= 0) return;

    final track = Paint()
      ..color = _trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final fg = Paint()
      ..color = _ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 12시 방향에서 시작
      2 * math.pi * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.strokeWidth != strokeWidth;
}
