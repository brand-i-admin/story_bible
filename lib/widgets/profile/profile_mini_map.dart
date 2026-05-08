import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../models/era.dart';
import '../../models/landmark.dart';
import '../../models/story_event.dart';
import '../../state/story_controller.dart';
import '../../theme/era_colors.dart';
import '../../utils/region_membership.dart';

/// 프로필 "장소로 시작" 탭의 미니 맵.
///
/// 사건↔region 매핑 우선순위:
///   1. event.landmarkId 의 landmark 가 kind='region' 이면 그 region.
///   2. landmark.parentLandmarkId 가 region 이면 그 region.
///   3. event.lat/lng 가 이 시대의 region 폴리곤 안에 있으면 그 region (fallback).
///
/// 자체적으로 `era.id` 기준 events 를 fetch 한다 (state.events 는 홈에서 선택된
/// era 한정이라 프로필에서 다른 era 를 보여주려면 별도 로드 필요).
class ProfileMiniMap extends ConsumerStatefulWidget {
  const ProfileMiniMap({
    super.key,
    required this.era,
    required this.landmarks,
    required this.completedEventIds,
    this.height = 280,
  });

  final Era era;
  final List<Landmark> landmarks;
  final Set<String> completedEventIds;
  final double height;

  @override
  ConsumerState<ProfileMiniMap> createState() => _ProfileMiniMapState();
}

class _ProfileMiniMapState extends ConsumerState<ProfileMiniMap> {
  late Future<List<StoryEvent>> _eventsFuture;
  String? _loadedEraId;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEventsFor(widget.era.id);
    _loadedEraId = widget.era.id;
  }

  @override
  void didUpdateWidget(covariant ProfileMiniMap old) {
    super.didUpdateWidget(old);
    if (widget.era.id != _loadedEraId) {
      _eventsFuture = _loadEventsFor(widget.era.id);
      _loadedEraId = widget.era.id;
    }
  }

  Future<List<StoryEvent>> _loadEventsFor(String eraId) {
    return ref.read(storyRepositoryProvider).fetchEventsByEra(eraId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoryEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: widget.height,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: widget.height, child: _emptyEra()),
          );
        }
        return _buildBody(snapshot.data ?? const <StoryEvent>[]);
      },
    );
  }

  Widget _buildBody(List<StoryEvent> events) {
    final era = widget.era;
    final landmarks = widget.landmarks;
    final completedEventIds = widget.completedEventIds;
    final height = widget.height;
    final landmarkById = {for (final l in landmarks) l.id: l};
    // 모든 region 후보 — point-in-polygon fallback 용. eraCodes 필터를 두지
    // 않는 이유: 데이터에서 region.era_codes 가 누락된 경우에도 사건 좌표가
    // 폴리곤 안에 있으면 그 region 으로 매핑되도록 (이 시대는 사건 데이터가
    // 있는 지역이 없습니다 false-positive 방지).
    final allPolygonRegions = landmarks
        .where((l) => l.kind == 'region' && l.polygon.length >= 3)
        .toList();

    final progress = <String, _RegionProgress>{};
    final eventBearingById = <String, Landmark>{};
    // region 매핑 실패 이벤트 — 좌표만 핀으로 fallback.
    final orphanEvents = <StoryEvent>[];

    for (final ev in events) {
      if (ev.eraId != era.id) continue;
      Landmark? region;
      final lm = landmarkById[ev.landmarkId];
      if (lm != null) {
        if (lm.kind == 'region' && lm.polygon.length >= 3) {
          region = lm;
        } else if (lm.parentLandmarkId != null) {
          final parent = landmarkById[lm.parentLandmarkId];
          if (parent != null &&
              parent.kind == 'region' &&
              parent.polygon.length >= 3) {
            region = parent;
          }
        }
      }
      // Fallback: 이벤트 좌표가 어떤 region 안에 있으면 그 region 으로.
      // (region.era_codes 무시 — 데이터 누락 대응)
      if (region == null && ev.lat != null && ev.lng != null) {
        final p = LatLng(ev.lat!, ev.lng!);
        for (final r in allPolygonRegions) {
          if (isPointInPolygon(p, r.polygon)) {
            region = r;
            break;
          }
        }
      }
      if (region == null) {
        // 사도의 시대처럼 region 폴리곤이 없는 시대(소아시아·로마 등) — 좌표가
        // 있으면 단순 점 핀으로 표시.
        if (ev.lat != null && ev.lng != null) {
          orphanEvents.add(ev);
        }
        continue;
      }

      eventBearingById[region.id] = region;
      final cur = progress[region.id] ?? const _RegionProgress();
      progress[region.id] = _RegionProgress(
        done: cur.done + (completedEventIds.contains(ev.id) ? 1 : 0),
        total: cur.total + 1,
      );
    }

    final eventBearing = eventBearingById.values.toList();
    final eraColor = EraColors.forCode(era.code);

    // bounds: region 폴리곤이 있으면 그 정점들로, 없으면 orphan 이벤트 좌표로.
    final fitBounds = eventBearing.isNotEmpty
        ? _computeBounds(eventBearing)
        : _computeBoundsFromEvents(orphanEvents);

    if (fitBounds == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(height: height, child: _emptyEra()),
      );
    }

    // 라벨 위치 계산 — 폴리곤 중심에 두되, 인접 라벨과 너무 가까우면 stagger.
    final labelAnchors = _staggeredAnchors(eventBearing);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          // era 변경 시 재마운트 → initialCameraFit 재적용.
          key: ValueKey('mini-map-${era.id}'),
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: fitBounds,
              padding: const EdgeInsets.all(36),
            ),
            minZoom: 3.0,
            maxZoom: 10.0,
            // 모든 zoom 제스처 활성 — pinch / 드래그 / 더블탭 / 스크롤휠 / fling.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.story.bible',
            ),
            if (eventBearing.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final r in eventBearing)
                    Polygon(
                      points: r.polygon,
                      color: _fillColorFor(eraColor, progress[r.id]!.fraction),
                      borderColor: _borderColorFor(
                        eraColor,
                        progress[r.id]!.fraction,
                      ),
                      borderStrokeWidth: progress[r.id]!.fraction >= 1.0
                          ? 2.4
                          : 1.2,
                    ),
                ],
              ),
            if (eventBearing.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var i = 0; i < eventBearing.length; i++)
                    Marker(
                      point: labelAnchors[i],
                      width: 110,
                      height: 28,
                      child: _RegionLabel(
                        name: eventBearing[i].name,
                        done: progress[eventBearing[i].id]!.done,
                        total: progress[eventBearing[i].id]!.total,
                        completed:
                            progress[eventBearing[i].id]!.fraction >= 1.0,
                      ),
                    ),
                ],
              ),
            // region 매핑 실패 이벤트는 단순 점 핀으로 (예: 사도의 시대 = 소아시아).
            if (orphanEvents.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final ev in orphanEvents)
                    Marker(
                      point: LatLng(ev.lat!, ev.lng!),
                      width: 18,
                      height: 18,
                      child: _OrphanEventDot(
                        completed: completedEventIds.contains(ev.id),
                        eraColor: eraColor,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// orphan event 좌표로 bounds 계산 — region 폴리곤이 없는 시대 fallback.
  LatLngBounds? _computeBoundsFromEvents(List<StoryEvent> events) {
    if (events.isEmpty) return null;
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final ev in events) {
      final lat = ev.lat!;
      final lng = ev.lng!;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    // 너무 작은 영역(점 1개) 인 경우 살짝 padding.
    if ((maxLat - minLat).abs() < 0.5 && (maxLng - minLng).abs() < 0.5) {
      minLat -= 0.5;
      maxLat += 0.5;
      minLng -= 0.5;
      maxLng += 0.5;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  /// 라벨 위치 stagger — 인접 라벨이 일정 거리 내에 있으면 위/아래로 살짝
  /// 밀어서 겹침을 완화. degree 기반 단순 휴리스틱.
  List<LatLng> _staggeredAnchors(List<Landmark> regions) {
    final centers = regions.map((r) => polygonCenter(r.polygon)).toList();
    final result = List<LatLng>.from(centers);
    const minLatGap = 0.45;
    const minLngGap = 1.0;

    for (var i = 1; i < result.length; i++) {
      var lat = result[i].latitude;
      final lng = result[i].longitude;
      var moved = true;
      var iters = 0;
      while (moved && iters < 6) {
        moved = false;
        iters += 1;
        for (var j = 0; j < i; j++) {
          final dLat = (lat - result[j].latitude).abs();
          final dLng = (lng - result[j].longitude).abs();
          if (dLat < minLatGap && dLng < minLngGap) {
            // 위 또는 아래로 밀기 (lat 기준).
            lat = lat <= result[j].latitude
                ? result[j].latitude - minLatGap
                : result[j].latitude + minLatGap;
            moved = true;
          }
        }
      }
      result[i] = LatLng(lat, lng);
    }
    return result;
  }

  /// 진행도 → 폴리곤 채움 색.
  Color _fillColorFor(Color eraColor, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    final r = ((eraColor.r * 255) * f).round();
    final g = ((eraColor.g * 255) * f).round();
    final b = ((eraColor.b * 255) * f).round();
    final alpha = (0.78 - 0.23 * f) * 255;
    return Color.fromARGB(alpha.round(), r, g, b);
  }

  Color _borderColorFor(Color eraColor, double fraction) {
    if (fraction >= 1.0) return const Color(0xFFE8A33D);
    if (fraction <= 0) return const Color(0xCC1F1409);
    return eraColor.withValues(alpha: 0.85);
  }

  LatLngBounds? _computeBounds(List<Landmark> regions) {
    if (regions.isEmpty) return null;
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final r in regions) {
      for (final p in r.polygon) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  Widget _emptyEra() {
    return Container(
      color: const Color(0x55F1E1C0),
      alignment: Alignment.center,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          '이 시대는 사건 데이터가 있는 지역이 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6A4C2E),
            fontWeight: FontWeight.w800,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _RegionProgress {
  const _RegionProgress({this.done = 0, this.total = 0});
  final int done;
  final int total;
  double get fraction => total <= 0 ? 0 : done / total;
}

class _RegionLabel extends StatelessWidget {
  const _RegionLabel({
    required this.name,
    required this.done,
    required this.total,
    required this.completed,
  });

  final String name;
  final int done;
  final int total;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: completed ? const Color(0xF0FFF6E2) : const Color(0xE8FFF6E2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: completed
                ? const Color(0xFFB07220)
                : const Color(0xAA8E6F48),
            width: completed ? 1.2 : 0.8,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (completed) ...[
              const Icon(
                Icons.flag_rounded,
                size: 12,
                color: Color(0xFFB07220),
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: completed
                      ? const Color(0xFFB07220)
                      : const Color(0xFF6A4C2E),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: -0.2,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$done/$total',
              style: TextStyle(
                color: completed
                    ? const Color(0xFFB07220)
                    : const Color(0xFF8C6743),
                fontWeight: FontWeight.w800,
                fontSize: 10,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// region 매핑 실패 이벤트(예: 사도의 시대 = 소아시아 도시) 의 단순 점 핀.
class _OrphanEventDot extends StatelessWidget {
  const _OrphanEventDot({required this.completed, required this.eraColor});

  final bool completed;
  final Color eraColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: completed ? const Color(0xFF7AAC4C) : eraColor,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
