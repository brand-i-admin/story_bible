import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 지도 위에 참고용 핀으로 보여줄 기존 이야기 좌표.
///
/// [highlighted] 가 true 면 "사용자가 Step 2 에서 '이 이야기 뒤에' 고른 이야기"
/// 로 해석되어 더 눈에 띄는 색(보조 강조 색)으로 렌더한다. 새 이야기는
/// 보통 이 근처에 있을 확률이 높아 참고하기 쉽다.
class ProposalReferencePin {
  const ProposalReferencePin({
    required this.lat,
    required this.lng,
    required this.label,
    this.highlighted = false,
  });
  final double lat;
  final double lng;
  final String label;
  final bool highlighted;
}

/// 지도에서 탭/확대로 위도·경도를 고르는 피커.
///
/// - [referencePins]: 선택된 인물들이 등장하는 기존 이야기의 좌표.
///   흐린 마커로 미리 박혀 있어 새 이야기를 어디에 둘지 맥락을 준다.
/// - [initialLat]/[initialLng]: 수정 모드 또는 기존 선택 복원용.
/// - 탭하면 선택 마커가 이동 + [onChanged] 콜백.
class ProposalLocationPicker extends StatefulWidget {
  const ProposalLocationPicker({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.onChanged,
    this.referencePins = const [],
  });

  final double? initialLat;
  final double? initialLng;
  final void Function(double? lat, double? lng) onChanged;
  final List<ProposalReferencePin> referencePins;

  @override
  State<ProposalLocationPicker> createState() => _ProposalLocationPickerState();
}

class _ProposalLocationPickerState extends State<ProposalLocationPicker> {
  static const LatLng _defaultCenter = LatLng(31.78, 35.22); // 예루살렘 근방
  final MapController _mapController = MapController();
  late double _lat;
  late double _lng;
  bool _hasValue = false;

  @override
  void initState() {
    super.initState();
    _lat =
        widget.initialLat ?? _pickCenterFromPins() ?? _defaultCenter.latitude;
    _lng = widget.initialLng ?? _pickCenterLng() ?? _defaultCenter.longitude;
    _hasValue = widget.initialLat != null && widget.initialLng != null;
  }

  double? _pickCenterFromPins() {
    if (widget.referencePins.isEmpty) return null;
    final avg =
        widget.referencePins.map((p) => p.lat).reduce((a, b) => a + b) /
        widget.referencePins.length;
    return avg;
  }

  double? _pickCenterLng() {
    if (widget.referencePins.isEmpty) return null;
    final avg =
        widget.referencePins.map((p) => p.lng).reduce((a, b) => a + b) /
        widget.referencePins.length;
    return avg;
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _hasValue = true;
    });
    widget.onChanged(_lat, _lng);
  }

  void _clear() {
    setState(() {
      _hasValue = false;
    });
    widget.onChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_lat, _lng),
                    initialZoom: widget.referencePins.isNotEmpty ? 5.2 : 5,
                    minZoom: 2.4,
                    maxZoom: 16,
                    onTap: _onMapTap,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.story.bible',
                    ),
                    if (widget.referencePins.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          // 비-강조 핀을 먼저 깔아두고, 강조 핀이 위에 오도록
                          for (final p in widget.referencePins)
                            if (!p.highlighted)
                              Marker(
                                point: LatLng(p.lat, p.lng),
                                width: 24,
                                height: 24,
                                child: Tooltip(
                                  message: p.label,
                                  child: Icon(
                                    Icons.place,
                                    size: 22,
                                    color: theme.colorScheme.tertiary
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                          for (final p in widget.referencePins)
                            if (p.highlighted)
                              Marker(
                                point: LatLng(p.lat, p.lng),
                                width: 36,
                                height: 36,
                                child: Tooltip(
                                  message: '이전 이야기: ${p.label}',
                                  child: Icon(
                                    Icons.star,
                                    size: 34,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    if (_hasValue)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_lat, _lng),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              color: theme.colorScheme.primary,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _hasValue
                            ? '${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}'
                            : '지도 탭 → 좌표 선택',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
                if (widget.referencePins.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Material(
                      color: theme.colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place,
                              size: 12,
                              color: theme.colorScheme.tertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '기존 이야기 ${widget.referencePins.length}곳',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_hasValue)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Material(
                      color: theme.colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _clear,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close, size: 14),
                              SizedBox(width: 4),
                              Text('초기화', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
