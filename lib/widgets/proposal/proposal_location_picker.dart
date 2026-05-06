import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/landmark.dart';

/// 지도 위에 참고용 핀으로 보여줄 기존 이야기 좌표.
///
/// [highlighted] 가 true 면 "사용자가 Step 2 에서 '이 이야기 뒤에' 고른 이야기"
/// 로 해석되어 더 눈에 띄는 색(보조 강조 색)으로 렌더한다.
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

/// v2 위치 선택 — 지도에 region(영역)/anchor(대표점)/minor(작은 점) 들이 표시되고
/// 사용자가 그 중 하나를 클릭/칩으로 선택. 자유 좌표 입력은 폐기.
///
/// - [eraLandmarks]: 현재 시대(들)에 노출되는 landmarks. region 은 폴리곤,
///   anchor/minor 는 점 마커로 그려진다.
/// - [initialLandmarkId]: 수정 모드 또는 기존 선택 복원용.
/// - [onChanged]: 선택이 바뀔 때마다 호출 (null = 선택 해제).
class ProposalLocationPicker extends StatefulWidget {
  const ProposalLocationPicker({
    super.key,
    required this.eraLandmarks,
    required this.initialLandmarkId,
    required this.onChanged,
    this.referencePins = const [],
    this.height = 320,
  });

  final List<Landmark> eraLandmarks;
  final String? initialLandmarkId;
  final ValueChanged<String?> onChanged;
  final List<ProposalReferencePin> referencePins;
  final double height;

  @override
  State<ProposalLocationPicker> createState() => _ProposalLocationPickerState();
}

class _ProposalLocationPickerState extends State<ProposalLocationPicker> {
  static const LatLng _defaultCenter = LatLng(31.78, 35.22); // 예루살렘 근방
  final MapController _mapController = MapController();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialLandmarkId;
  }

  @override
  void didUpdateWidget(covariant ProposalLocationPicker old) {
    super.didUpdateWidget(old);
    if (old.initialLandmarkId != widget.initialLandmarkId) {
      _selectedId = widget.initialLandmarkId;
    }
  }

  Landmark? get _selected =>
      _selectedId == null ? null : _findById(_selectedId!);

  Landmark? _findById(String id) {
    for (final lm in widget.eraLandmarks) {
      if (lm.id == id) return lm;
    }
    return null;
  }

  LatLng _initialCenter() {
    final selected = _selected;
    if (selected != null) return selected.latLng;
    if (widget.eraLandmarks.isNotEmpty) {
      final regions = widget.eraLandmarks
          .where((lm) => lm.isRegion)
          .toList(growable: false);
      if (regions.isNotEmpty) return regions.first.latLng;
      return widget.eraLandmarks.first.latLng;
    }
    return _defaultCenter;
  }

  void _select(Landmark lm) {
    setState(() => _selectedId = lm.id);
    widget.onChanged(lm.id);
    _mapController.move(lm.latLng, _mapController.camera.zoom);
  }

  void _clear() {
    setState(() => _selectedId = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regions = widget.eraLandmarks.where((lm) => lm.isRegion).toList();
    // v3 — region 이 아닌 모든 landmark 를 마커로. v2 잔존 anchor/minor 도 포함.
    final points = widget.eraLandmarks.where((lm) => !lm.isRegion).toList();
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialCenter(),
                    initialZoom: 5.0,
                    minZoom: 2.4,
                    maxZoom: 16,
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
                    PolygonLayer(
                      polygons: [
                        for (final rgn in regions)
                          if (rgn.polygon.isNotEmpty)
                            Polygon(
                              points: rgn.polygon,
                              color: rgn.id == _selectedId
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.30,
                                    )
                                  : theme.colorScheme.tertiary.withValues(
                                      alpha: 0.12,
                                    ),
                              borderColor: rgn.id == _selectedId
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.tertiary.withValues(
                                      alpha: 0.55,
                                    ),
                              borderStrokeWidth: rgn.id == _selectedId
                                  ? 2.5
                                  : 1.2,
                            ),
                      ],
                    ),
                    if (widget.referencePins.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final p in widget.referencePins)
                            if (!p.highlighted)
                              Marker(
                                point: LatLng(p.lat, p.lng),
                                width: 18,
                                height: 18,
                                child: Tooltip(
                                  message: p.label,
                                  child: Icon(
                                    Icons.place,
                                    size: 16,
                                    color: theme.colorScheme.tertiary
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                          for (final p in widget.referencePins)
                            if (p.highlighted)
                              Marker(
                                point: LatLng(p.lat, p.lng),
                                width: 24,
                                height: 24,
                                child: Tooltip(
                                  message: '이전 이야기: ${p.label}',
                                  child: const Icon(
                                    Icons.place,
                                    size: 22,
                                    color: Color(0xFFE8A33D),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final lm in [...regions, ...points])
                          Marker(
                            point: lm.latLng,
                            width: 36,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => _select(lm),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: lm.id == _selectedId
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.surface.withValues(
                                          alpha: 0.92,
                                        ),
                                  border: Border.all(
                                    color: lm.id == _selectedId
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outline,
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  lm.emoji,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
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
                        selected != null
                            ? '선택: ${selected.name}'
                            : '지도 마커/아래 칩에서 위치 선택',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
                if (selected != null)
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
        const SizedBox(height: 12),
        if (regions.isNotEmpty) ...[
          const _ChipGroupHeader(label: '지역(region) — 빈 폴리곤 영역'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final lm in regions)
                _LandmarkChip(
                  landmark: lm,
                  selected: lm.id == _selectedId,
                  onTap: () => _select(lm),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (points.isNotEmpty) ...[
          const _ChipGroupHeader(label: '랜드마크 (산·도시·강·섬 등)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final lm in points)
                _LandmarkChip(
                  landmark: lm,
                  selected: lm.id == _selectedId,
                  onTap: () => _select(lm),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChipGroupHeader extends StatelessWidget {
  const _ChipGroupHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _LandmarkChip extends StatelessWidget {
  const _LandmarkChip({
    required this.landmark,
    required this.selected,
    required this.onTap,
  });
  final Landmark landmark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      avatar: Text(landmark.emoji, style: const TextStyle(fontSize: 14)),
      label: Text(landmark.name),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.18),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}
