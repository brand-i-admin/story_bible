import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 지도에서 탭/확대로 위도·경도를 고르는 피커.
///
/// - [initialLat]/[initialLng] 가 주어지면 그 위치로 초기 이동 + 마커
/// - 유저가 지도 위를 탭하면 마커가 이동 + [onChanged] 로 콜백
/// - 우상단 "직접 입력" 토글로 숫자 필드 fallback 도 허용 (모바일에서 지도 줌 어려울 때)
///
/// 장소명([placeNameController])은 별도 TextField 로 관리 (지도 위치와 독립).
class ProposalLocationPicker extends StatefulWidget {
  const ProposalLocationPicker({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.onChanged,
  });

  final double? initialLat;
  final double? initialLng;

  /// (lat, lng) — 둘 다 null 이면 "미지정".
  final void Function(double? lat, double? lng) onChanged;

  @override
  State<ProposalLocationPicker> createState() => _ProposalLocationPickerState();
}

class _ProposalLocationPickerState extends State<ProposalLocationPicker> {
  static const LatLng _defaultCenter = LatLng(31.78, 35.22); // 예루살렘 근방
  final MapController _mapController = MapController();
  late double _lat;
  late double _lng;
  bool _hasValue = false;
  bool _manualMode = false;

  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat ?? _defaultCenter.latitude;
    _lng = widget.initialLng ?? _defaultCenter.longitude;
    _hasValue = widget.initialLat != null && widget.initialLng != null;
    _latCtrl = TextEditingController(text: widget.initialLat?.toString() ?? '');
    _lngCtrl = TextEditingController(text: widget.initialLng?.toString() ?? '');
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _hasValue = true;
      _latCtrl.text = _lat.toStringAsFixed(5);
      _lngCtrl.text = _lng.toStringAsFixed(5);
    });
    widget.onChanged(_lat, _lng);
  }

  void _onManualChanged() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat != null && lng != null) {
      setState(() {
        _lat = lat;
        _lng = lng;
        _hasValue = true;
      });
      widget.onChanged(lat, lng);
      _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
    } else {
      setState(() => _hasValue = false);
      widget.onChanged(null, null);
    }
  }

  void _clear() {
    setState(() {
      _hasValue = false;
      _latCtrl.clear();
      _lngCtrl.clear();
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
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_lat, _lng),
                    initialZoom: _hasValue ? 7 : 5,
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
                    if (_hasValue)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_lat, _lng),
                            width: 36,
                            height: 36,
                            child: Icon(
                              Icons.location_on,
                              color: theme.colorScheme.primary,
                              size: 36,
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
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _manualMode = !_manualMode),
              icon: Icon(_manualMode ? Icons.map_outlined : Icons.keyboard),
              label: Text(_manualMode ? '지도로 고르기' : '숫자 직접 입력'),
            ),
          ],
        ),
        if (_manualMode) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '위도 lat'),
                  onChanged: (_) => _onManualChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '경도 lng'),
                  onChanged: (_) => _onManualChanged(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
