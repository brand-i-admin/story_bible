import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../theme/tokens.dart';

/// 단일 region polygon entry — 시각 layer 가 그릴 한 단위.
class EraPolygonEntry {
  const EraPolygonEntry({
    required this.polygon,
    required this.eraColor,
    required this.isSelected,
    required this.pulseT,
    this.pickerHighlight = false,
  });

  /// LatLng 정점들. ring 종결은 자동 — 마지막을 첫 정점으로 잇는다.
  final List<LatLng> polygon;

  /// 호환성 유지를 위한 필드. layer 는 더 이상 사용하지 않고, `isSelected` 만
  /// 보고 `AppColors.regionCandidate / regionSelected` 두 색으로 렌더한다.
  /// 향후 별도 cleanup PR 에서 호출자(`story_map_panel.dart`) 와 함께 제거 가능.
  final Color eraColor;

  /// 선택된 region 인지 — true 면 glow/fill alpha 가 강조되고 discovery
  /// particle 이 폴리곤 가장자리를 따라 반짝임.
  final bool isSelected;

  /// 0..1 한 사이클 펄스 위상. glow/border 펄스 + particle 위상에 사용.
  final double pulseT;

  /// region 선택 단계(`regionPickerMode`)의 후보 폴리곤인지. true 면 outer
  /// glow / fill alpha 가 +0.06~0.08 부스트되어 "여기를 누르세요" 인상을 강화.
  /// `isSelected` 가 우선되므로 선택된 폴리곤에는 영향 없음.
  final bool pickerHighlight;
}

/// flutter_map 위에 ancient parchment atlas 톤으로 region polygon 을 그리는
/// 커스텀 layer.
///
/// "지도에서 영역을 선택했다" 가 아니라 "고대 성경 세계의 한 지역을 발견했다"
/// 라는 느낌을 목표로 한다. GIS 식 striped/sharp polygon overlay 가 아니라
/// 3-layer 양식 + 정점 곡선화:
///
///   1. **Outer Glow** — `BlurStyle.outer` 로 폴리곤 바깥쪽으로 퍼지는 후광.
///   2. **Parchment Fill** — 폴리곤 안쪽 radial gradient (중앙 밝게, 가장
///      자리 페이드) + soft edge blur. watercolor 베이스 텍스처 비쳐 보임.
///   3. **Ancient Ink Border** — outer halo + inner fade gradient + 메인 ink
///      line 세 패스로 한 덩어리 강조.
///
/// **색 톤** — 후보(`AppColors.regionCandidate`, 따뜻한 금색) vs 선택
/// (`AppColors.regionSelected`, sage green) 두 가지로 통일된다. era 식별
/// 정보는 `lib/widgets/v2/era_pick_rows.dart` 의 점·아이콘 색이 별도로
/// 제공하므로 폴리곤 톤은 후보/선택의 두 상태만 표현.
///
/// **Selection settle 애니메이션** — 500ms production-grade 2-phase:
/// 빠른 attack 으로 region 이 +6% scale overshoot 에 도달 (~100ms, easeOutCubic),
/// 그 후 +3% elevated state 로 settle (~400ms, easeOutQuad). 1.0 으로
/// 돌아가지 않고 elevated 에서 머무르며 — 선택된 region 은 영구히 살짝
/// 부풀어 "선택됨" 상태가 시각적으로 유지된다. Glow/halo 도 같은 패턴으로
/// peak factor 1.0 → settled factor 0.35 elevated 유지 (scale 보다 살짝
/// 늦게 settle 시작해 layered timing). 발동: `didUpdateWidget` 에서 selection
/// key 변화 감지 → `AnimationController.forward(from: 0)`. 자세한 곡선은
/// `settleScaleBump` / `settleGlowFactor` 참조.
///
/// 추가로 정점들은 Catmull-Rom spline 으로 곡선화해 사람이 손으로 찍은
/// jagged polygon 도 부드러운 양피지 곡선으로 재현된다.
///
/// 클릭 hit-test 는 동일 좌표의 투명 `PolygonLayer<Landmark>`
/// (story_map_panel.dart 가 이미 보유) 가 별도로 처리한다.
class EraPolygonGlowLayer extends StatefulWidget {
  const EraPolygonGlowLayer({super.key, required this.entries});

  final List<EraPolygonEntry> entries;

  /// 선택 settle 애니메이션 지속 시간 — 빠른 attack, 자연스러운 settle.
  static const Duration settleDuration = Duration(milliseconds: 500);

  /// 선택 settle 의 scale 곡선 정점 (overshoot peak).
  static const double settleScalePeak = 0.06;

  /// 선택 settle 완료 후 유지되는 elevated scale boost (peak 보다 작음 —
  /// 살짝 부풀었다가 그 사이값으로 settle. 1.0 으로 돌아가지 않아 "선택됨"
  /// 상태가 시각적으로 유지된다).
  static const double settleScaleSettled = 0.03;

  /// scale peak 도달 t (전체 duration 의 비율). 0.20 → 100ms / 500ms.
  /// glow 의 peak hold (`_glowPeakHoldUntil`) 보다 살짝 빨라서 layered timing.
  static const double _scalePeakAt = 0.20;

  /// 선택 settle peak 시 outer glow alpha 에 추가되는 부스트 (1.0 곱셈자에서
  /// 적용). settled 상태에서는 `settleGlowSettledFactor` 로 감쇠.
  static const double settleGlowAlphaBoost = 0.35;

  /// 선택 settle peak 시 outer glow sigma 에 추가되는 부스트(px).
  static const double settleGlowSigmaBoost = 12.0;

  /// 선택 settle peak 시 border halo alpha 에 추가되는 부스트.
  static const double settleHaloAlphaBoost = 0.25;

  /// 선택 settle 완료 후 유지되는 elevated glow factor (peak factor 1.0 의
  /// 비율). 0.35 = peak 의 35% 가 영구 유지. peak alpha boost 0.35 × 0.35
  /// = +0.12 alpha, peak sigma 12 × 0.35 = +4.2px.
  static const double settleGlowSettledFactor = 0.35;

  /// glow 가 peak 에 머무르는 t 비율. 0.30 → 150ms / 500ms.
  /// scale (`_scalePeakAt`) 가 먼저 settle 시작 → glow 가 뒤따라 settle = 깊이감.
  static const double _glowPeakHoldUntil = 0.30;

  // ─────────────────── Outer glow ────────────────────────
  //
  // 정적 단일 값 — 펄스 제거. 옛 sin 기반 alpha/sigma 변동이 사용자에게
  // "어두운 색의 깜빡거림" 으로 인식돼 양피지 톤과 충돌했음. entry.pulseT 인자는
  // 호환성 위해 EraPolygonEntry 에 남기되 더 이상 참조하지 않는다.

  /// Outer glow alpha. 비선택 0.12, 선택 0.18, picker 후보 0.20 (사용자가
  /// "노란 영역을 누르세요" 안내를 받을 때 시각적으로 더 또렷하게).
  static double outerGlowAlphaFor({required EraPolygonEntry entry}) {
    if (entry.isSelected) return 0.18;
    return entry.pickerHighlight ? 0.20 : 0.12;
  }

  /// Outer glow blur sigma. 비선택 9, 선택 12, picker 후보 11.
  static double outerGlowSigmaFor({required EraPolygonEntry entry}) {
    if (entry.isSelected) return 12.0;
    return entry.pickerHighlight ? 11.0 : 9.0;
  }

  // ─────────────────── Parchment fill ────────────────────

  /// Parchment fill 중앙 alpha. 비선택 0.50, 선택 0.62, picker 후보 0.56.
  /// (white wash 위로 칠해지므로 베이스 비침 차단된 상태에서 의도된 톤이
  /// 또렷이 살아남는 알파. 펄스 제거로 안정적 표시.)
  static double fillCenterAlphaFor({required EraPolygonEntry entry}) {
    if (entry.isSelected) return 0.62;
    return entry.pickerHighlight ? 0.56 : 0.50;
  }

  /// Parchment fill 가장자리 alpha. 비선택 0.36, 선택 0.48, picker 후보 0.42.
  static double fillEdgeAlphaFor({required EraPolygonEntry entry}) {
    if (entry.isSelected) return 0.48;
    return entry.pickerHighlight ? 0.42 : 0.36;
  }

  /// White wash 레이어 alpha — 양피지 베이스 중성화 강도.
  /// 0.45 ≈ 베이스가 거의 보이지 않지만 watercolor 결은 너머로 살짝 비치는 정도.
  static const double parchmentWashAlpha = 0.45;

  /// Region 강조의 단일 진실 소스. glow / fill / border 가 모두 이 색을 변형해
  /// 사용한다. era 색은 무시 — era 식별은 era_pick_rows 의 점·아이콘으로 별도 제공.
  ///
  /// 후보(시대 선택 시 자동 노출 region): 따뜻한 금색 → 양피지 톤과 자연 조화.
  /// 선택(특정 region 탭): sage green → "이 영역을 골랐다" 명확히 분리.
  static Color highlightColorFor({required EraPolygonEntry entry}) {
    return entry.isSelected
        ? AppColors.regionSelected
        : AppColors.regionCandidate;
  }

  /// Parchment fill 색 — 후보/선택 동일 톤 사용.
  static Color fillColorFor({required EraPolygonEntry entry}) =>
      highlightColorFor(entry: entry);

  // ─────────────────── Ink border ────────────────────────

  /// Border 색 — 후보/선택 모두 fill 과 동일한 candidate/selected 색을 그대로
  /// 사용. 옛 lerp(candidate, #3A2418, 0.20) 는 갈색이 섞여 사용자가 "어두운
  /// 노란"으로 인식했음. 같은 색이라도 strokeWidth + alpha + halo 로 충분히
  /// 외곽선이 식별된다.
  static Color borderColorFor({required EraPolygonEntry entry}) =>
      highlightColorFor(entry: entry);

  /// Border 메인 stroke width. 비선택 2.0, 선택 2.6 (펄스 제거).
  static double borderStrokeWidthFor({required EraPolygonEntry entry}) {
    return entry.isSelected ? 2.6 : 2.0;
  }

  /// Border 메인 stroke alpha. 비선택 0.70, 선택 0.85 (펄스 제거).
  static double borderAlphaFor({required EraPolygonEntry entry}) {
    return entry.isSelected ? 0.85 : 0.70;
  }

  /// Border halo (잉크 번짐) stroke width. 비선택 4.0, 선택 6.0 (펄스 제거).
  static double borderHaloStrokeWidthFor({required EraPolygonEntry entry}) {
    return entry.isSelected ? 6.0 : 4.0;
  }

  /// Border halo alpha. 비선택 0.12, 선택 0.20 (펄스 제거 + 절제).
  /// (옛 0.16 / 0.22~0.32 → halo 자체가 진하게 깜빡여 "어두운 애니메이션" 으로
  /// 인식 — alpha 낮추고 정적 값으로.)
  static double borderHaloAlphaFor({required EraPolygonEntry entry}) {
    return entry.isSelected ? 0.20 : 0.12;
  }

  /// 안쪽 페이드 띠의 폭(px) — 폴리곤 가장자리에서 안쪽으로 잉크가 번지는
  /// 효과의 너비. 비선택 8, 선택 12 (펄스 제거).
  ///
  /// 구현: 이 폭의 굵은 blurred stroke 를 폴리곤 path 에 그리고 내부로 clip
  /// 한다. stroke 가 path 위에 중심을 두므로 절반은 외부(잘림), 절반은
  /// 내부(보임). blur 가 가장자리부터 안쪽으로 부드럽게 페이드 → 선이 안쪽
  /// 으로 자연스럽게 머징되는 느낌.
  static double innerFadeWidthFor({required EraPolygonEntry entry}) {
    return entry.isSelected ? 12.0 : 8.0;
  }

  // ─────────────────── Settle helpers (테스트/외부 참조) ─

  /// 선택 settle scale bump — production-grade 2-phase 곡선.
  ///
  /// - t = 0          → 0 (시작)
  /// - t = `_scalePeakAt` (0.20) → `settleScalePeak` (0.06, overshoot peak)
  /// - t = 1          → `settleScaleSettled` (0.03, elevated 유지)
  ///
  /// 1.0 으로 안 돌아가고 `settleScaleSettled` 에서 멈춰 — 선택된 region 은
  /// 비선택 region 보다 영구히 살짝 부풀어 시각적으로 "선택됨" 강조.
  /// Phase 1: easeOutCubic 으로 빠른 attack. Phase 2: easeOutQuad 로 자연
  /// settle. 두 phase 가 peak 에서 연속 (값 일치).
  static double settleScaleBump(double t) {
    if (t <= 0.0) return 0.0;
    if (t < _scalePeakAt) {
      final p = t / _scalePeakAt;
      final eased = 1.0 - math.pow(1.0 - p, 3.0).toDouble();
      return eased * settleScalePeak;
    }
    final p = ((t - _scalePeakAt) / (1.0 - _scalePeakAt)).clamp(0.0, 1.0);
    final eased = 1.0 - math.pow(1.0 - p, 2.0).toDouble();
    return settleScalePeak - eased * (settleScalePeak - settleScaleSettled);
  }

  /// 선택 settle glow boost factor — production-grade hold-then-settle.
  ///
  /// - t = 0                       → 1.0 (peak — 진입 즉시 강조)
  /// - 0 < t < `_glowPeakHoldUntil` (0.30) → 1.0 (peak hold, layered timing)
  /// - t = 1                       → `settleGlowSettledFactor` (0.35, elevated 유지)
  ///
  /// 0 으로 안 떨어지고 `settleGlowSettledFactor` 에서 멈춰 — 선택된 region 의
  /// glow 가 영구히 elevated baseline 유지. 이 값을 alpha/sigma 부스트에 곱함.
  /// scale 보다 늦게 settle 시작해 layered depth 감.
  static double settleGlowFactor(double t) {
    if (t < _glowPeakHoldUntil) return 1.0;
    final p = ((t - _glowPeakHoldUntil) / (1.0 - _glowPeakHoldUntil)).clamp(
      0.0,
      1.0,
    );
    final eased = 1.0 - math.pow(1.0 - p, 2.0).toDouble();
    return 1.0 - eased * (1.0 - settleGlowSettledFactor);
  }

  @override
  State<EraPolygonGlowLayer> createState() => _EraPolygonGlowLayerState();
}

class _EraPolygonGlowLayerState extends State<EraPolygonGlowLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settleCtl;

  /// 현재 settle 애니메이션이 적용 중인 region 의 식별 키. 선택이 바뀌면
  /// `didUpdateWidget` 에서 갱신되고 동시에 controller 가 재생된다.
  String? _settleKey;

  @override
  void initState() {
    super.initState();
    _settleCtl = AnimationController(
      vsync: this,
      duration: EraPolygonGlowLayer.settleDuration,
    );
    _settleKey = _selectedKey(widget.entries);
  }

  @override
  void didUpdateWidget(covariant EraPolygonGlowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = _selectedKey(widget.entries);
    if (newKey != _settleKey) {
      _settleKey = newKey;
      if (newKey != null) {
        _settleCtl.forward(from: 0.0);
      } else {
        _settleCtl.reset();
      }
    }
  }

  @override
  void dispose() {
    _settleCtl.dispose();
    super.dispose();
  }

  /// 선택된 entry 가 있으면 그 region 의 첫 정점 좌표 기반 키, 없으면 null.
  /// 좌표 4자리 소수점이라 소폭 reprojection 차이는 무시된다.
  static String? _selectedKey(List<EraPolygonEntry> entries) {
    for (final e in entries) {
      if (e.isSelected && e.polygon.isNotEmpty) {
        final f = e.polygon.first;
        return '${f.latitude.toStringAsFixed(4)},'
            '${f.longitude.toStringAsFixed(4)}';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: AnimatedBuilder(
        animation: _settleCtl,
        builder: (_, __) => CustomPaint(
          painter: _AncientHighlightPainter(
            entries: widget.entries,
            camera: camera,
            settleT: _settleCtl.value,
            settleKey: _settleKey,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AncientHighlightPainter extends CustomPainter {
  _AncientHighlightPainter({
    required this.entries,
    required this.camera,
    required this.settleT,
    required this.settleKey,
  });

  final List<EraPolygonEntry> entries;
  final MapCamera camera;

  /// 0..1 — 선택 settle 애니메이션 진행도. 1.0 (또는 0.0) 이면 완료.
  final double settleT;

  /// 현재 settle 이 적용 중인 region 의 식별 키 (`_selectedKey`).
  final String? settleKey;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      if (entry.polygon.length < 3) continue;
      final points = entry.polygon
          .map(camera.getOffsetFromOrigin)
          .toList(growable: false);
      final path = _smoothPath(points);
      final bounds = path.getBounds();

      // settle 진행 중이고 이 entry 가 settle 대상이면 boost 적용.
      final isSettling = entry.isSelected && _entryKey(entry) == settleKey;
      final scaleBump = isSettling
          ? EraPolygonGlowLayer.settleScaleBump(settleT)
          : 0.0;
      final glowBoost = isSettling
          ? EraPolygonGlowLayer.settleGlowFactor(settleT)
          : 0.0;

      final useScale = scaleBump != 0.0;
      if (useScale) {
        canvas.save();
        canvas.translate(bounds.center.dx, bounds.center.dy);
        canvas.scale(1.0 + scaleBump);
        canvas.translate(-bounds.center.dx, -bounds.center.dy);
      }

      _paintOuterGlow(canvas, path, entry, glowBoost: glowBoost);
      _paintParchmentFill(canvas, path, bounds, entry);
      _paintInkBorder(canvas, path, entry, glowBoost: glowBoost);

      if (useScale) {
        canvas.restore();
      }
    }
  }

  // ─────────────────── Layer 1: Outer glow ────────────────

  void _paintOuterGlow(
    Canvas canvas,
    Path path,
    EraPolygonEntry entry, {
    required double glowBoost,
  }) {
    final baseAlpha = EraPolygonGlowLayer.outerGlowAlphaFor(entry: entry);
    final baseSigma = EraPolygonGlowLayer.outerGlowSigmaFor(entry: entry);
    final alpha =
        (baseAlpha + glowBoost * EraPolygonGlowLayer.settleGlowAlphaBoost)
            .clamp(0.0, 1.0);
    final sigma =
        baseSigma + glowBoost * EraPolygonGlowLayer.settleGlowSigmaBoost;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, sigma)
      ..color = EraPolygonGlowLayer.highlightColorFor(
        entry: entry,
      ).withValues(alpha: alpha);
    canvas.drawPath(path, paint);
  }

  // ─────────────────── Layer 2: Parchment fill ───────────
  //
  // 2-pass 구조:
  //   2a) White wash — cream-white 한 겹으로 양피지 베이지 베이스 중성화.
  //   2b) Color fill — radial gradient 로 candidate/selected 색을 입힘.
  // wash 가 베이스 톤을 중성화하므로 의도된 노랑/초록이 베이스+색 blend 로
  // 갈색·짙은녹이 되지 않고 또렷이 살아남는다. watercolor 결은 wash 너머로
  // 은은히 비쳐 ancient atlas 톤 유지.

  void _paintParchmentFill(
    Canvas canvas,
    Path path,
    Rect bounds,
    EraPolygonEntry entry,
  ) {
    // 2a) White wash — 베이스 중성화.
    final washPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.regionParchmentWash.withValues(
        alpha: EraPolygonGlowLayer.parchmentWashAlpha,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5);
    canvas.drawPath(path, washPaint);

    // 2b) Color fill — radial gradient.
    final fillColor = EraPolygonGlowLayer.fillColorFor(entry: entry);
    final centerAlpha = EraPolygonGlowLayer.fillCenterAlphaFor(entry: entry);
    final edgeAlpha = EraPolygonGlowLayer.fillEdgeAlphaFor(entry: entry);
    final shader = ui.Gradient.radial(
      bounds.center,
      math.max(bounds.width, bounds.height) * 0.65,
      [
        fillColor.withValues(alpha: centerAlpha),
        fillColor.withValues(alpha: edgeAlpha),
      ],
      [0.0, 1.0],
    );
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5);
    canvas.drawPath(path, paint);
  }

  // ─────────────────── Layer 3: Ink border ───────────────

  void _paintInkBorder(
    Canvas canvas,
    Path path,
    EraPolygonEntry entry, {
    required double glowBoost,
  }) {
    final borderColor = EraPolygonGlowLayer.borderColorFor(entry: entry);
    final baseHaloAlpha = EraPolygonGlowLayer.borderHaloAlphaFor(entry: entry);
    final mainAlpha = EraPolygonGlowLayer.borderAlphaFor(entry: entry);
    final haloAlpha =
        (baseHaloAlpha + glowBoost * EraPolygonGlowLayer.settleHaloAlphaBoost)
            .clamp(0.0, 1.0);

    // 1) 외곽 잉크 번짐 halo — 폴리곤 바깥쪽 atmospheric glow.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = EraPolygonGlowLayer.borderHaloStrokeWidthFor(entry: entry)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
      ..color = borderColor.withValues(alpha: haloAlpha);
    canvas.drawPath(path, halo);

    // 2) 안쪽 페이드 그라데이션 — 굵은 blurred stroke 를 path 위에 그리고
    //    내부로 clip 해 외부 절반을 잘라낸다. blur 가 가장자리부터 안쪽
    //    으로 부드럽게 페이드 → 같은 색·같은 시작 투명도에서 안쪽으로
    //    스며들며 사라지는 머징 효과. 잉크가 양피지에 번져 들어가는 느낌.
    final fadeWidth = EraPolygonGlowLayer.innerFadeWidthFor(entry: entry);
    canvas.save();
    canvas.clipPath(path);
    final innerFade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = fadeWidth
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeWidth * 0.5)
      ..color = borderColor.withValues(alpha: mainAlpha);
    canvas.drawPath(path, innerFade);
    canvas.restore();

    // 3) 메인 잉크 라인 — 가장자리 sharp 한 마무리. inner fade 위에 얹어
    //    polygon 경계를 또렷하게 잡는다. 살짝 blur 로 sharp vector 벗김.
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = EraPolygonGlowLayer.borderStrokeWidthFor(entry: entry)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8)
      ..color = borderColor.withValues(alpha: mainAlpha);
    canvas.drawPath(path, ink);
  }

  // ─────────────────── Path smoothing (Catmull-Rom) ─────

  Path _smoothPath(List<Offset> points) {
    final path = Path();
    final n = points.length;
    if (n < 4) {
      path.moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      return path;
    }

    path.moveTo(points[0].dx, points[0].dy);
    const tension = 0.5;
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) * tension / 3,
        p1.dy + (p2.dy - p0.dy) * tension / 3,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) * tension / 3,
        p2.dy - (p3.dy - p1.dy) * tension / 3,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  // ─────────────────── Helpers ───────────────────────────

  static String? _entryKey(EraPolygonEntry e) {
    if (e.polygon.isEmpty) return null;
    final f = e.polygon.first;
    return '${f.latitude.toStringAsFixed(4)},${f.longitude.toStringAsFixed(4)}';
  }

  @override
  bool shouldRepaint(covariant _AncientHighlightPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.entries != entries ||
        oldDelegate.settleT != settleT ||
        oldDelegate.settleKey != settleKey;
  }
}
