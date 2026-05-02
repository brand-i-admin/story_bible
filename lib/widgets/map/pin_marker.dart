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

  /// 핀 badge 가 캐릭터 아바타 스택을 담을 너비. 인물 1명이면 정원형(=badgeHeight),
  /// 2~3명이면 살짝 옆으로 펼쳐 캡슐 모양으로 늘어난다.
  double badgeWidthForAvatars(int count) {
    if (count <= 1) return badgeHeight;
    final extra = (count.clamp(2, 3) - 1) * (badgeHeight - 9);
    return badgeHeight + extra;
  }

  double get visualHeight => badgeHeight + 4 + arrowHeight;

  double get markerHeight => visualHeight + anchorGap;
}

class _MarkerNode {
  const _MarkerNode({
    required this.event,
    required this.point,
    required this.placeLabel,
    required this.showCallout,
    required this.characterCodes,
    required this.characterColors,
  });

  final StoryEvent event;
  final LatLng point;
  final String placeLabel;
  final bool showCallout;

  /// 핀 badge 에 얼굴 표시할 인물 코드들 (Step 2 에서 선택된 인물 ∩ event 출연자).
  /// 없으면 핀 색깔 dot 만.
  final List<String> characterCodes;
  final List<Color> characterColors;
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _CompactPinMarker extends StatelessWidget {
  const _CompactPinMarker({
    required this.characterCodes,
    required this.characterColors,
    required this.selected,
    required this.style,
    required this.avatarAssetForCharacter,
    this.popKey,
  });

  /// 핀 badge 에 얼굴로 표시할 인물 코드들. 비어 있으면 색 dot fallback.
  final List<String> characterCodes;

  /// 인물이 없을 때 fallback 색깔 또는 multi-char chip 에 쓰일 색들.
  final List<Color> characterColors;
  final bool selected;
  final _PinStyle style;
  final String Function(String characterCode) avatarAssetForCharacter;

  /// pop-in 스케일 애니메이션을 다시 재생할 때 쓰는 key. 같은 key 면 이미 애니메이션
  /// 이 끝난 인스턴스를 재사용해 깜빡거리지 않고, 새 key 가 들어오면 (예: 다음 버튼
  /// 으로 reveal 재생) 0 → 1 스케일 애니메이션이 처음부터 다시 돈다.
  final Object? popKey;

  @override
  Widget build(BuildContext context) {
    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PinAvatarBadge(
          characterCodes: characterCodes,
          characterColors: characterColors,
          selected: selected,
          badgeHeight: style.badgeHeight,
          avatarAssetForCharacter: avatarAssetForCharacter,
        ),
        const SizedBox(height: 4),
        CustomPaint(
          size: Size(style.arrowWidth, style.arrowHeight),
          painter: _PinPointerPainter(selected: selected),
        ),
        SizedBox(height: style.anchorGap),
      ],
    );
    return TweenAnimationBuilder<double>(
      key: popKey == null ? null : ValueKey(popKey),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: t.clamp(0.0, 1.2),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: inner,
    );
  }
}

/// 핀 위쪽 badge — 캐릭터 얼굴 스택. 1명이면 원형, 2~3명이면 캡슐 모양으로
/// 살짝 겹쳐 옆으로 펼친다. 인물 정보가 비어 있으면 색 dot fallback.
class _PinAvatarBadge extends StatelessWidget {
  const _PinAvatarBadge({
    required this.characterCodes,
    required this.characterColors,
    required this.selected,
    required this.badgeHeight,
    required this.avatarAssetForCharacter,
  });

  final List<String> characterCodes;
  final List<Color> characterColors;
  final bool selected;
  final double badgeHeight;
  final String Function(String characterCode) avatarAssetForCharacter;

  @override
  Widget build(BuildContext context) {
    final visibleCodes = characterCodes.take(3).toList();
    if (visibleCodes.isEmpty) {
      return _DotBadge(
        color: characterColors.firstOrNull ?? const Color(0xFF8C5A2E),
        selected: selected,
        size: badgeHeight * 0.7,
      );
    }
    final overlap = badgeHeight * 0.36;
    final stride = badgeHeight - overlap;
    final width = badgeHeight + (visibleCodes.length - 1) * stride;
    final borderColor = selected ? const Color(0xFF7B4B21) : Colors.white;
    return SizedBox(
      width: width,
      height: badgeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visibleCodes.length; i++)
            Positioned(
              left: i * stride,
              child: Container(
                width: badgeHeight,
                height: badgeHeight,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEEDFC4),
                  border: Border.all(
                    color: borderColor,
                    width: selected ? 1.6 : 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _AvatarImage(
                  assetPath: avatarAssetForCharacter(visibleCodes[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotBadge extends StatelessWidget {
  const _DotBadge({
    required this.color,
    required this.selected,
    required this.size,
  });

  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: selected ? const Color(0xFF7B4B21) : Colors.white,
          width: selected ? 1.8 : 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
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

    const leftTop = Offset(0, 0);
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
