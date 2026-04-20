import 'package:flutter/material.dart';

/// 양피지 질감 레이어.
///
/// [assets/elements/parchment_texture.png]를 [opacity] / [tint]로 합성해
/// 고지도/양피지 분위기를 다른 위젯 위에 얹을 때 사용한다.
class ParchmentTextureLayer extends StatelessWidget {
  const ParchmentTextureLayer({
    super.key,
    required this.opacity,
    required this.tint,
  });

  final double opacity;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(tint, BlendMode.multiply),
        child: Image.asset(
          'assets/elements/parchment_texture.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
