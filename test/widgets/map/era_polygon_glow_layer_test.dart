import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:story_bible/theme/tokens.dart';
import 'package:story_bible/widgets/map/era_polygon_glow_layer.dart';

EraPolygonEntry _entry({
  required bool selected,
  double pulse = 0.0,
  Color color = const Color(0xFF6F8F58),
  bool pickerHighlight = false,
}) {
  return EraPolygonEntry(
    polygon: [const LatLng(0, 0), const LatLng(0, 1), const LatLng(1, 0)],
    eraColor: color,
    isSelected: selected,
    pulseT: pulse,
    pickerHighlight: pickerHighlight,
  );
}

void main() {
  group('EraPolygonGlowLayer outer glow', () {
    test('outerGlowAlphaFor: 비선택 0.12, 선택 0.18 (정적 — pulse 무관)', () {
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(entry: _entry(selected: false)),
        closeTo(0.12, 0.001),
      );
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(0.18, 0.001),
      );
      // pulse 입력값을 바꿔도 결과 동일 (정적).
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(
          entry: _entry(selected: true, pulse: 0.0),
        ),
        EraPolygonGlowLayer.outerGlowAlphaFor(
          entry: _entry(selected: true, pulse: 0.75),
        ),
      );
    });

    test('outerGlowSigmaFor: 비선택 9, 선택 12 (정적)', () {
      expect(
        EraPolygonGlowLayer.outerGlowSigmaFor(entry: _entry(selected: false)),
        9.0,
      );
      expect(
        EraPolygonGlowLayer.outerGlowSigmaFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        12.0,
      );
    });

    test('pickerHighlight: 비선택 후보가 일반(0.12) 보다 부스트(>0.12), 선택(0.18) '
        '보다는 약함 — "여기를 누르세요" 안내 강화하되 선택 폴리곤이 더 또렷', () {
      final base = EraPolygonGlowLayer.outerGlowAlphaFor(
        entry: _entry(selected: false),
      );
      final picker = EraPolygonGlowLayer.outerGlowAlphaFor(
        entry: _entry(selected: false, pickerHighlight: true),
      );
      final selected = EraPolygonGlowLayer.outerGlowAlphaFor(
        entry: _entry(selected: true),
      );
      expect(picker, greaterThan(base));
      expect(picker, lessThanOrEqualTo(selected + 0.05));

      // fill 도 같은 방향 (center 기준).
      final fillBase = EraPolygonGlowLayer.fillCenterAlphaFor(
        entry: _entry(selected: false),
      );
      final fillPicker = EraPolygonGlowLayer.fillCenterAlphaFor(
        entry: _entry(selected: false, pickerHighlight: true),
      );
      expect(fillPicker, greaterThan(fillBase));

      // 선택된 폴리곤은 pickerHighlight 와 무관 (isSelected 가 우선).
      expect(
        EraPolygonGlowLayer.outerGlowAlphaFor(
          entry: _entry(selected: true, pickerHighlight: true),
        ),
        EraPolygonGlowLayer.outerGlowAlphaFor(entry: _entry(selected: true)),
      );
    });
  });

  group('EraPolygonGlowLayer parchment fill', () {
    test('fillCenterAlphaFor: 비선택 0.50, 선택 0.62 (정적, white wash 위에서 또렷)', () {
      expect(
        EraPolygonGlowLayer.fillCenterAlphaFor(entry: _entry(selected: false)),
        closeTo(0.50, 0.001),
      );
      expect(
        EraPolygonGlowLayer.fillCenterAlphaFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        closeTo(0.62, 0.001),
      );
    });

    test('parchmentWashAlpha 는 0.45 — 베이스 중성화 + 결은 비침', () {
      // 너무 높으면 양피지 결 사라짐, 너무 낮으면 효과 없음. 0.45 는 균형점.
      expect(EraPolygonGlowLayer.parchmentWashAlpha, closeTo(0.45, 0.001));
      expect(EraPolygonGlowLayer.parchmentWashAlpha, greaterThan(0.3));
      expect(EraPolygonGlowLayer.parchmentWashAlpha, lessThan(0.6));
    });

    test('fillEdgeAlphaFor 가 fillCenterAlphaFor 보다 작아 radial fade', () {
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.fillEdgeAlphaFor(entry: entry),
        lessThan(EraPolygonGlowLayer.fillCenterAlphaFor(entry: entry)),
      );
    });

    test(
      'fillColorFor: 선택 시 regionSelected (sage green), 비선택 시 regionCandidate (gold)',
      () {
        // era 색은 무시 — 후보/선택의 두 톤으로 통일.
        expect(
          EraPolygonGlowLayer.fillColorFor(entry: _entry(selected: true)),
          AppColors.regionSelected,
        );
        // entry.eraColor 를 임의 색으로 줘도 fill 은 candidate 색.
        expect(
          EraPolygonGlowLayer.fillColorFor(
            entry: _entry(selected: false, color: const Color(0xFF6F8F58)),
          ),
          AppColors.regionCandidate,
        );
      },
    );
  });

  group('EraPolygonGlowLayer ink border', () {
    test('borderColorFor: 후보/선택 모두 fill 과 동일한 톤 (lerp 제거)', () {
      // 옛 lerp(candidate, #3A2418, 0.20) 은 갈색이 섞여 어두워 보임 — 제거.
      expect(
        EraPolygonGlowLayer.borderColorFor(entry: _entry(selected: false)),
        AppColors.regionCandidate,
      );
      expect(
        EraPolygonGlowLayer.borderColorFor(entry: _entry(selected: true)),
        AppColors.regionSelected,
      );
    });

    test('borderStrokeWidthFor: 비선택 2.0, 선택 2.6 (정적)', () {
      expect(
        EraPolygonGlowLayer.borderStrokeWidthFor(
          entry: _entry(selected: false),
        ),
        2.0,
      );
      expect(
        EraPolygonGlowLayer.borderStrokeWidthFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        2.6,
      );
    });

    test('borderHaloStrokeWidthFor 가 borderStrokeWidthFor 보다 굵음', () {
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.borderHaloStrokeWidthFor(entry: entry),
        greaterThan(EraPolygonGlowLayer.borderStrokeWidthFor(entry: entry)),
      );
    });

    test('innerFadeWidthFor: 비선택 8, 선택 12 (정적)', () {
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(entry: _entry(selected: false)),
        8.0,
      );
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(
          entry: _entry(selected: true, pulse: 0.25),
        ),
        12.0,
      );
    });

    test('innerFadeWidthFor 가 메인 borderStrokeWidthFor 보다 굵어 잉크 번짐 효과', () {
      // inner fade 가 폴리곤 안쪽으로 번지려면 메인 라인보다 충분히 굵어야 함.
      // 옛 4배 조건은 너무 빡빡 — 3배 이상이면 시각적으로 inner-fade 가 식별됨.
      final entry = _entry(selected: false);
      expect(
        EraPolygonGlowLayer.innerFadeWidthFor(entry: entry),
        greaterThan(EraPolygonGlowLayer.borderStrokeWidthFor(entry: entry) * 3),
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
