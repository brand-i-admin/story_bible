import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:story_bible/widgets/map/era_polygon_glow_layer.dart';

EraPolygonEntry _entry({
  required bool selected,
  double pulse = 0.0,
  Color color = const Color(0xFF6F8F58),
}) {
  return EraPolygonEntry(
    polygon: [const LatLng(0, 0), const LatLng(0, 1), const LatLng(1, 0)],
    eraColor: color,
    isSelected: selected,
    pulseT: pulse,
  );
}

void main() {
  group('EraPolygonGlowLayer outer glow', () {
    test('outerGlowAlphaFor 비선택 0.25, 선택 시 0.32~0.45', () {
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(entry: _entry(selected: false)),
        closeTo(0.25, 0.001),
      );
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(0.45, 0.01),
      );
    });

    test('outerGlowSigmaFor 비선택 12, 선택 시 14~18', () {
      expect(
        EraPolygonGlowLayer.outerGlowSigmaFor(entry: _entry(selected: false)),
        12.0,
      );
      expect(
        EraPolygonGlowLayer.outerGlowSigmaFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(18.0, 0.01),
      );
    });
  });

  group('EraPolygonGlowLayer parchment fill', () {
    test(
      'fillCenterAlphaFor 비선택 0.20, 선택 시 0.36~0.46 (노란 highlight boost)',
      () {
        expect(
          EraPolygonGlowLayer.fillCenterAlphaFor(
            entry: _entry(selected: false),
          ),
          closeTo(0.20, 0.001),
        );
        // pulseT=0.25 → pulse=1.0 → 0.36 + 1.0*0.10 = 0.46
        expect(
          EraPolygonGlowLayer.fillCenterAlphaFor(
            entry: _entry(selected: true, pulse: 0.25),
          ),
          closeTo(0.46, 0.01),
        );
      },
    );

    test('fillEdgeAlphaFor 가 fillCenterAlphaFor 보다 작아 radial fade', () {
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.fillEdgeAlphaFor(entry: entry),
        lessThan(EraPolygonGlowLayer.fillCenterAlphaFor(entry: entry)),
      );
    });

    test('fillColorFor: 선택 시 selectedFillColor (노란색), 비선택 시 era 색', () {
      expect(
        EraPolygonGlowLayer.fillColorFor(entry: _entry(selected: true)),
        EraPolygonGlowLayer.selectedFillColor,
      );
      const sage = Color(0xFF6F8F58);
      expect(
        EraPolygonGlowLayer.fillColorFor(
          entry: _entry(selected: false, color: sage),
        ),
        sage,
      );
    });
  });

  group('EraPolygonGlowLayer ink border', () {
    test('borderColorFor 비선택: era 색을 짙은 갈색 (#3A2418) 과 lerp', () {
      const sage = Color(0xFF6F8F58);
      final border = EraPolygonGlowLayer.borderColorFor(
        entry: _entry(selected: false, color: sage),
      );
      // Color.lerp(sage, brown, 0.55) — sage 의 green/blue 성분이 brown 쪽으로
      // 당겨져 어두워짐 (brown 의 R/G/B 가 sage 보다 모두 작음).
      expect(border.r, lessThan(sage.r));
      expect(border.g, lessThan(sage.g));
    });

    test('borderColorFor 선택: fill 과 동일한 selectedFillColor (노란색)', () {
      // 선택 시 border 가 fill 과 같은 노란색 → 한 덩어리로 인지.
      expect(
        EraPolygonGlowLayer.borderColorFor(entry: _entry(selected: true)),
        EraPolygonGlowLayer.selectedFillColor,
      );
    });

    test('borderStrokeWidthFor 비선택 2.5, 선택 시 3.2~4.0', () {
      expect(
        EraPolygonGlowLayer.borderStrokeWidthFor(
          entry: _entry(selected: false),
        ),
        2.5,
      );
      expect(
        EraPolygonGlowLayer.borderStrokeWidthFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(4.0, 0.01),
      );
    });

    test('borderHaloStrokeWidthFor 가 borderStrokeWidthFor 보다 굵음', () {
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.borderHaloStrokeWidthFor(entry: entry),
        greaterThan(EraPolygonGlowLayer.borderStrokeWidthFor(entry: entry)),
      );
    });

    test('innerFadeWidthFor 비선택 12, 선택 시 16~22', () {
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(entry: _entry(selected: false)),
        12.0,
      );
      // pulseT=0.25 → pulse=1.0 → 16 + 1.0*6 = 22
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(22.0, 0.01),
      );
    });

    test('innerFadeWidthFor 가 메인 borderStrokeWidthFor 보다 훨씬 굵음', () {
      // inner fade 가 폴리곤 안쪽으로 충분히 번질 수 있도록 메인 라인보다
      // 4배 이상 굵어야 함.
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(entry: entry),
        greaterThan(EraPolygonGlowLayer.borderStrokeWidthFor(entry: entry) * 4),
      );
    });
  });

  group('EraPolygonGlowLayer settle 애니메이션 helper', () {
    test('settleScaleBump: t=0 에서 0 (시작)', () {
      expect(EraPolygonGlowLayer.settleScaleBump(0.0), 0.0);
    });

    test('settleScaleBump: t=peak 에서 settleScalePeak (overshoot 정점)', () {
      expect(
        EraPolygonGlowLayer.settleScaleBump(0.20),
        closeTo(EraPolygonGlowLayer.settleScalePeak, 0.001),
      );
    });

    test('settleScaleBump: t=1 에서 settleScaleSettled (elevated 유지, 0 아님)', () {
      expect(
        EraPolygonGlowLayer.settleScaleBump(1.0),
        closeTo(EraPolygonGlowLayer.settleScaleSettled, 0.001),
      );
    });

    test(
      'settleScaleBump: peak 와 settled 사이에서 monotonically 감소 (settle phase)',
      () {
        final atPeak = EraPolygonGlowLayer.settleScaleBump(0.20);
        final mid = EraPolygonGlowLayer.settleScaleBump(0.50);
        final atEnd = EraPolygonGlowLayer.settleScaleBump(1.0);
        expect(atPeak, greaterThan(mid));
        expect(mid, greaterThan(atEnd));
      },
    );

    test('settleGlowFactor: t=0 에서 1.0 (진입 즉시 peak)', () {
      expect(EraPolygonGlowLayer.settleGlowFactor(0.0), 1.0);
    });

    test('settleGlowFactor: peak hold 동안 1.0 유지', () {
      // _glowPeakHoldUntil = 0.30 까지 1.0
      expect(EraPolygonGlowLayer.settleGlowFactor(0.10), 1.0);
      expect(EraPolygonGlowLayer.settleGlowFactor(0.25), 1.0);
    });

    test('settleGlowFactor: t=1 에서 settleGlowSettledFactor (elevated 유지)', () {
      expect(
        EraPolygonGlowLayer.settleGlowFactor(1.0),
        closeTo(EraPolygonGlowLayer.settleGlowSettledFactor, 0.001),
      );
    });

    test('settleGlowFactor: hold 후 monotonically 감쇠', () {
      final hold = EraPolygonGlowLayer.settleGlowFactor(0.30);
      final mid = EraPolygonGlowLayer.settleGlowFactor(0.65);
      final end = EraPolygonGlowLayer.settleGlowFactor(1.0);
      expect(hold, greaterThan(mid));
      expect(mid, greaterThan(end));
    });
  });

  testWidgets('새 region 선택 시 settle controller 가 forward 재생', (tester) async {
    Widget build({required bool firstSelected}) {
      return MaterialApp(
        home: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(31.5, 35.0),
            initialZoom: 6.0,
          ),
          children: [
            EraPolygonGlowLayer(
              entries: [
                EraPolygonEntry(
                  polygon: const [
                    LatLng(31.0, 34.5),
                    LatLng(31.0, 35.5),
                    LatLng(32.0, 35.5),
                    LatLng(32.0, 34.5),
                  ],
                  eraColor: const Color(0xFF6F8F58),
                  isSelected: firstSelected,
                  pulseT: 0.0,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 비선택 → 선택 전환 시 한 frame 안에 throw 없이 build 되어야 함.
    await tester.pumpWidget(build(firstSelected: false));
    await tester.pump();
    await tester.pumpWidget(build(firstSelected: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    // settle 종료까지 기다려도 throw 없음.
    await tester.pump(EraPolygonGlowLayer.settleDuration);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EraPolygonGlowLayer 가 FlutterMap 안에서 throw 없이 build', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(31.5, 35.0),
            initialZoom: 6.0,
          ),
          children: [
            EraPolygonGlowLayer(
              entries: [
                EraPolygonEntry(
                  polygon: [
                    LatLng(31.0, 34.5),
                    LatLng(31.0, 35.5),
                    LatLng(32.0, 35.5),
                    LatLng(32.0, 34.5),
                  ],
                  eraColor: Color(0xFF6F8F58),
                  isSelected: false,
                  pulseT: 0.0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
