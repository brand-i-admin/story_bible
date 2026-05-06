import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 양피지 톤 데코(decoration) 마커 — 산·도시·나무·피라미드 등 분위기용
/// 일러스트. `assets/decos/decos_catalog.json` 의 `placements` 배열을 시대 필터로
/// 거른 뒤 [MarkerLayer] 로 그린다. 사건과 무관한 시각 풍성함만 더함.
///
/// 일러스트 PNG 는 `tools/images/generate_decos_vertex.py` 가 Vertex AI 로
/// 생성해 `assets/decos/{kind}.png` 로 저장한다. PNG 가 아직 없으면 그 데코는
/// 자연스럽게 안 보임 (errorBuilder 로 SizedBox.shrink).
class MapDecoLayer extends StatefulWidget {
  const MapDecoLayer({super.key, required this.activeEraCodes});

  /// 화면에 노출 중인 시대 코드 집합. 비어있으면 모든 데코 (era 매칭 무시).
  final Set<String> activeEraCodes;

  @override
  State<MapDecoLayer> createState() => _MapDecoLayerState();
}

class _MapDecoLayerState extends State<MapDecoLayer> {
  Future<List<_DecoPlacement>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadCatalog();
  }

  Future<List<_DecoPlacement>> _loadCatalog() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/decos/decos_catalog.json',
      );
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final placements = (json['placements'] as List?) ?? const [];
      return placements
          .whereType<Map<String, dynamic>>()
          .map(_DecoPlacement.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DecoPlacement>>(
      future: _future,
      builder: (_, snap) {
        final all = snap.data ?? const <_DecoPlacement>[];
        // v2 — 시대 미선택 시(activeEraCodes 비어있음) 데코를 모두 숨긴다.
        // 이전엔 비어있을 때 ALL 을 보여줘서 step 1 인트로 화면이 너무 어수선
        // 하고 시대별 컨텍스트도 사라졌음. 이제는 era 가 선택돼야 그 시대의
        // 데코만 (era_codes 가 비었거나 매칭되는 것) 노출.
        if (widget.activeEraCodes.isEmpty) {
          return const SizedBox.shrink();
        }
        final filtered = all
            .where(
              (p) =>
                  p.eraCodes.isEmpty ||
                  p.eraCodes.any(widget.activeEraCodes.contains),
            )
            .toList(growable: false);
        if (filtered.isEmpty) return const SizedBox.shrink();
        return MarkerLayer(
          markers: [
            for (final p in filtered)
              Marker(
                point: LatLng(p.lat, p.lng),
                // v6 — kind 3가지 (산/도시/성전) 만 남기면서 base 사이즈 48 로
                // 살짝 줄임. 더 작게 + 더 투명하게 + 더 진한 sepia tint 로
                // "양피지 위 잉크 그림" 느낌 강화.
                width: 48 * p.scale,
                height: 48 * p.scale,
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: Builder(
                    builder: (context) {
                      // v5 — zoom 6.5 = 1.0 기준으로 부드러운 비례. zoom 8 에서
                      // ~1.23, zoom 10 에서 ~1.54, cap 1.7. 이전 v4 의 (zoom/7)
                      // clamp 0.65~1.4 는 zoom-in 에서 충분히 안 커서 sparse.
                      final zoom = MapCamera.of(context).zoom;
                      final s = (zoom / 6.5).clamp(0.7, 1.7).toDouble();
                      final imgPath = 'assets/decos/${p.kind}.png';
                      return Transform.rotate(
                        angle: p.rotationRad,
                        child: Transform.scale(
                          scale: s,
                          // v8 — 자연 합성: 살짝 투명 (0.72) + 진한 sepia tan
                          // modulate 로 데코 색감을 양피지 잉크 톤으로 동기화.
                          // drop shadow 는 가볍게 유지 — paper 위에 박힌 느낌.
                          child: Opacity(
                            opacity: 0.72,
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Transform.translate(
                                    offset: const Offset(0.6, 1.0),
                                    child: ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: 1.2,
                                        sigmaY: 1.2,
                                      ),
                                      child: Image.asset(
                                        imgPath,
                                        fit: BoxFit.contain,
                                        color: const Color(0x444A2E10),
                                        colorBlendMode: BlendMode.srcIn,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                                // 진한 sepia tan modulate — 데코 채도/색감을
                                // 양피지 잉크 톤으로 깊게 통합.
                                Image.asset(
                                  imgPath,
                                  fit: BoxFit.contain,
                                  color: const Color(0xFFB8945C),
                                  colorBlendMode: BlendMode.modulate,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DecoPlacement {
  const _DecoPlacement({
    required this.kind,
    required this.lat,
    required this.lng,
    required this.eraCodes,
    required this.scale,
    required this.rotationRad,
  });

  final String kind;
  final double lat;
  final double lng;
  final List<String> eraCodes;
  final double scale;
  final double rotationRad;

  static _DecoPlacement fromJson(Map<String, dynamic> j) {
    final eraCodes =
        (j['era_codes'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const [];
    final scaleRaw = j['scale'];
    final scale = (scaleRaw is num) ? scaleRaw.toDouble() : 1.0;
    final rotRaw = j['rotation_deg'];
    final rotationDeg = (rotRaw is num) ? rotRaw.toDouble() : 0.0;
    return _DecoPlacement(
      kind: j['kind'] as String,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      eraCodes: eraCodes,
      scale: scale,
      rotationRad: rotationDeg * 3.1415926535 / 180,
    );
  }
}
