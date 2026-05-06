import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 양피지 텍스처를 backdrop 위에 **multiply blend** 로 합성하는 overlay.
///
/// 기존 `ParchmentTextureLayer` 는 `Opacity` 기반 단순 알파 합성이라 강하게
/// 깔면 무조건 화면이 뿌옇게 (회색·갈색 평균값) 변했다. 이 위젯은 직접
/// `Canvas.drawImageRect` 에 `Paint.blendMode = BlendMode.multiply` 를 줘서
/// 양피지의 **밝은 부분 (1.0)** 은 backdrop 그대로, **어두운 결 (~0.5)** 은
/// backdrop 만 살짝 어두워지게 만든다 — 실제 종이 위에 인쇄된 듯한 grain.
///
/// `strength` (0..1) 로 효과 강도 조절. 내부적으로 image 를 white 와
/// 보간하는 색을 [Paint.color] 의 alpha 로 흉내 — strength=0 이면 영향 없음,
/// strength=1 이면 image 그대로 multiply.
///
/// 비동기 image 로드 — 처음 1 frame 은 빈 화면, 로드 완료 후 setState 로
/// 페인트.
class ParchmentMultiplyLayer extends StatefulWidget {
  const ParchmentMultiplyLayer({
    super.key,
    this.assetPath = 'assets/elements/parchment_texture.png',
    this.strength = 0.55,
    this.tileScale = 1.0,
  });

  /// 합성 강도 0~1. 기본 0.55 — parchment image 를 ~45% white 쪽으로 끌어올려
  /// flat 영역(water 등) 은 거의 영향 없음, grain spot 만 multiply 로 살아남아
  /// land 에 종이 결 visible. strength↑ = grain 진해짐 + water 도 더 영향.
  /// strength↓ = grain 약해짐 + water 보존.
  final double strength;

  /// 텍스처를 stretch 가 아니라 tile 처럼 반복하고 싶을 때 1 미만으로 (예 0.5
  /// = 가로/세로 절반 크기로 깔림). 기본 1.0 = 화면을 한 장으로 채움.
  final double tileScale;

  final String assetPath;

  @override
  State<ParchmentMultiplyLayer> createState() => _ParchmentMultiplyLayerState();
}

class _ParchmentMultiplyLayerState extends State<ParchmentMultiplyLayer> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(widget.assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _image = frame.image);
      }
    } catch (_) {
      // 자산 로드 실패 — silent. 페인터가 SizedBox.shrink 로 fallback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ParchmentMultiplyPainter(
          image: image,
          strength: widget.strength.clamp(0.0, 1.0),
          tileScale: widget.tileScale.clamp(0.1, 2.0),
        ),
      ),
    );
  }
}

class _ParchmentMultiplyPainter extends CustomPainter {
  _ParchmentMultiplyPainter({
    required this.image,
    required this.strength,
    required this.tileScale,
  });

  final ui.Image image;
  final double strength;
  final double tileScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // v3 — softLight 는 너무 약해서 land 에도 grain 이 안 보임 (사용자:
    // "양피지 느낌이 전부 사라졌다"). 다시 multiply 로 복귀.
    //
    // 물 영역 보존을 위한 트릭: parchment image 의 픽셀들을 강하게 white 쪽으로
    // 끌어올림 (lightenColor alpha 높음). 그러면 image 의 대부분이 ~흰색 →
    // multiply 시 backdrop 거의 변경 없음. 단 image 의 어두운 grain spot 만
    // 살아남아 multiply 시 backdrop 을 darken → 종이 결만 visible.
    //
    // 결과:
    //   - flat water (uniform light blue): grain spot 거의 없음 → 거의 그대로
    //   - flat land (light tan): 마찬가지지만 약간 더 어두운 mid-tone 이라
    //     grain spot 이 multiply 시 더 도드라짐 → 종이 결 명확
    //
    // 완벽한 water 제외는 아니지만 hue/색 차이로 water 가 land 보다 덜 영향.
    final lightenColor = Color.fromRGBO(
      255,
      255,
      255,
      (1.0 - strength).clamp(0.0, 1.0),
    );
    final paint = Paint()
      ..blendMode = BlendMode.multiply
      ..colorFilter = ColorFilter.mode(lightenColor, BlendMode.lighten);

    // tile 또는 stretch
    if (tileScale >= 0.99 && tileScale <= 1.01) {
      // 한 장으로 cover.
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(image, src, dst, paint);
    } else {
      // tile.
      final tileW = image.width.toDouble() * tileScale;
      final tileH = image.height.toDouble() * tileScale;
      for (var y = 0.0; y < size.height; y += tileH) {
        for (var x = 0.0; x < size.width; x += tileW) {
          final src = Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          );
          final dst = Rect.fromLTWH(x, y, tileW, tileH);
          canvas.drawImageRect(image, src, dst, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParchmentMultiplyPainter old) =>
      old.image != image ||
      old.strength != strength ||
      old.tileScale != tileScale;
}
