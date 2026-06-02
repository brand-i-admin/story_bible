import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/landmark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../state/story_controller.dart';
import '../../theme/era_colors.dart';
import '../../theme/tokens.dart';
import '../../utils/region_membership.dart';
import '../../utils/scene_asset_loader.dart';
import '../emotion_badge_icon.dart';

/// 프로필 "장소로 시작" 탭의 미니 맵.
///
/// 사건↔region 매핑 우선순위:
///   1. event.landmarkId 의 landmark 가 kind='region' 이면 그 region.
///   2. landmark.parentLandmarkId 가 region 이면 그 region.
///   3. event.lat/lng 가 이 시대의 region 폴리곤 안에 있으면 그 region (fallback).
///
/// 자체적으로 `era.id` 기준 events 를 fetch 한다 (state.events 는 홈에서 선택된
/// era 한정이라 프로필에서 다른 era 를 보여주려면 별도 로드 필요). region 또는
/// 라벨을 누르면 그 지역의 사건별 퀴즈 결과 팝업을 보여 준다.
class ProfileMiniMap extends ConsumerStatefulWidget {
  const ProfileMiniMap({
    super.key,
    required this.era,
    required this.landmarks,
    required this.completedEventIds,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.onOpenEventDetail,
    this.height = 280,
  });

  final Era era;
  final List<Landmark> landmarks;
  final Set<String> completedEventIds;
  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final void Function(StoryEvent event, {String? regionLandmarkId})
  onOpenEventDetail;
  final double height;

  @override
  ConsumerState<ProfileMiniMap> createState() => _ProfileMiniMapState();
}

class _ProfileMiniMapState extends ConsumerState<ProfileMiniMap> {
  final SceneAssetLoader _sceneAssetLoader = SceneAssetLoader();

  final LayerHitNotifier<Landmark> _polygonHitNotifier = LayerHitNotifier(null);
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
    final eventEmotionMarks = widget.eventEmotionMarks;
    final quizAttemptSummaries = widget.quizAttemptSummaries;
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
    final regionEventsById = <String, List<StoryEvent>>{};
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
      (regionEventsById[region.id] ??= <StoryEvent>[]).add(ev);
      final cur = progress[region.id] ?? const _RegionProgress();
      final attempt = quizAttemptSummaries[ev.id];
      progress[region.id] = _RegionProgress(
        done: cur.done + (completedEventIds.contains(ev.id) ? 1 : 0),
        emotionCount:
            cur.emotionCount + (eventEmotionMarks.containsKey(ev.id) ? 1 : 0),
        quizCorrect: cur.quizCorrect + (attempt?.correctCount ?? 0),
        quizAnswered: cur.quizAnswered + (attempt?.totalCount ?? 0),
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
            onTap: (_, __) {
              final hit = _polygonHitNotifier.value;
              if (hit == null || hit.hitValues.isEmpty) {
                return;
              }
              Landmark pick = hit.hitValues.first;
              var pickArea = _polygonBboxArea(pick);
              for (final region in hit.hitValues.skip(1)) {
                final area = _polygonBboxArea(region);
                if (area < pickArea) {
                  pick = region;
                  pickArea = area;
                }
              }
              final regionEvents = regionEventsById[pick.id];
              if (regionEvents == null || regionEvents.isEmpty) {
                return;
              }
              _showRegionReviewDialog(region: pick, events: regionEvents);
            },
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
              PolygonLayer<Landmark>(
                hitNotifier: _polygonHitNotifier,
                polygons: [
                  for (final r in eventBearing)
                    Polygon<Landmark>(
                      points: r.polygon,
                      hitValue: r,
                      color: _fillColorFor(
                        eraColor,
                        progress[r.id]!.fraction,
                        progress[r.id]!.allEmotionsEngraved,
                      ),
                      borderColor: _borderColorFor(
                        eraColor,
                        progress[r.id]!.fraction,
                        progress[r.id]!.allEmotionsEngraved,
                      ),
                      borderStrokeWidth: progress[r.id]!.allEmotionsEngraved
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
                      width: 148,
                      height: 30,
                      child: _RegionLabel(
                        name: eventBearing[i].name,
                        done: progress[eventBearing[i].id]!.done,
                        total: progress[eventBearing[i].id]!.total,
                        quizCorrect: progress[eventBearing[i].id]!.quizCorrect,
                        quizAnswered:
                            progress[eventBearing[i].id]!.quizAnswered,
                        completed:
                            progress[eventBearing[i].id]!.fraction >= 1.0,
                        onTap: () {
                          final region = eventBearing[i];
                          final regionEvents =
                              regionEventsById[region.id] ??
                              const <StoryEvent>[];
                          if (regionEvents.isEmpty) {
                            return;
                          }
                          _showRegionReviewDialog(
                            region: region,
                            events: regionEvents,
                          );
                        },
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
                        emotionMark: eventEmotionMarks[ev.id],
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

  double _polygonBboxArea(Landmark region) {
    if (region.polygon.isEmpty) return double.infinity;
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final point in region.polygon) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return (maxLat - minLat).abs() * (maxLng - minLng).abs();
  }

  void _showRegionReviewDialog({
    required Landmark region,
    required List<StoryEvent> events,
  }) {
    final sortedEvents = [...events]..sort(_compareRegionReviewEvents);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: size.height * 0.78,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.parchmentCream,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.brownEdge, width: 1.2),
                boxShadow: AppShadows.xl,
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          region.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink800,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Material(
                        color: AppColors.parchmentCard,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          borderRadius: BorderRadius.circular(12),
                          child: const SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(
                              Icons.close_rounded,
                              color: AppColors.ink300,
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sortedEvents.length}개 이야기',
                    style: const TextStyle(
                      color: AppColors.ink200,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sortedEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final event = sortedEvents[index];
                        return _RegionReviewEventCard(
                          event: event,
                          orderNumber: index + 1,
                          attempt: widget.quizAttemptSummaries[event.id],
                          loader: _sceneAssetLoader,
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            widget.onOpenEventDetail(
                              event,
                              regionLandmarkId: region.id,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _compareRegionReviewEvents(StoryEvent a, StoryEvent b) {
    final rankCompare = a.globalRank.compareTo(b.globalRank);
    if (rankCompare != 0) return rankCompare;
    final storyCompare = a.storyIndex.compareTo(b.storyIndex);
    if (storyCompare != 0) return storyCompare;
    return a.title.compareTo(b.title);
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
  Color _fillColorFor(Color eraColor, double fraction, bool collected) {
    if (collected) {
      return const Color(0x18FFF6E2);
    }
    final f = fraction.clamp(0.0, 1.0);
    final r = ((eraColor.r * 255) * f).round();
    final g = ((eraColor.g * 255) * f).round();
    final b = ((eraColor.b * 255) * f).round();
    final alpha = (0.78 - 0.23 * f) * 255;
    return Color.fromARGB(alpha.round(), r, g, b);
  }

  Color _borderColorFor(Color eraColor, double fraction, bool collected) {
    if (collected) return const Color(0xDDB07220);
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
  const _RegionProgress({
    this.done = 0,
    this.emotionCount = 0,
    this.quizCorrect = 0,
    this.quizAnswered = 0,
    this.total = 0,
  });
  final int done;
  final int emotionCount;
  final int quizCorrect;
  final int quizAnswered;
  final int total;
  double get fraction => total <= 0 ? 0 : done / total;
  bool get allEmotionsEngraved => total > 0 && emotionCount >= total;
}

class _RegionLabel extends StatelessWidget {
  const _RegionLabel({
    required this.name,
    required this.done,
    required this.total,
    required this.quizCorrect,
    required this.quizAnswered,
    required this.completed,
    required this.onTap,
  });

  final String name;
  final int done;
  final int total;
  final int quizCorrect;
  final int quizAnswered;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: completed
                ? const Color(0xF0FFF6E2)
                : const Color(0xE8FFF6E2),
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
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$done/$total · $quizCorrect/$quizAnswered',
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
      ),
    );
  }
}

class _RegionReviewEventCard extends StatelessWidget {
  const _RegionReviewEventCard({
    required this.event,
    required this.orderNumber,
    required this.attempt,
    required this.loader,
    required this.onTap,
  });

  final StoryEvent event;
  final int orderNumber;
  final QuizAttemptSummary? attempt;
  final SceneAssetLoader loader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _RegionQuizTone.fromAttempt(attempt);
    final hasAttempt = attempt != null && attempt!.totalCount > 0;
    return Material(
      color: tone?.background ?? Colors.white.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 9, 8, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tone?.border ?? AppColors.borderCard,
              width: 1.1,
            ),
          ),
          child: Row(
            children: [
              _RegionReviewOrderBadge(number: orderNumber),
              const SizedBox(width: 8),
              _RegionReviewThumbnail(event: event, loader: loader),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink800,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (hasAttempt)
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _RegionQuizCountChip(
                            label: '정답 ${attempt!.correctCount}',
                            color: AppColors.greenBot,
                          ),
                          _RegionQuizCountChip(
                            label: '오답 ${attempt!.wrongCount}',
                            color: AppColors.dangerBot,
                          ),
                          _RegionQuizCountChip(
                            label: '헷갈려요 ${attempt!.confusedCount}',
                            color: AppColors.goldDeep,
                          ),
                        ],
                      )
                    else
                      const _RegionQuizCountChip(
                        label: '아직 안 풀었어요',
                        color: AppColors.ink200,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink200,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionReviewOrderBadge extends StatelessWidget {
  const _RegionReviewOrderBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ink500,
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          color: AppColors.parchmentCream,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _RegionReviewThumbnail extends StatelessWidget {
  const _RegionReviewThumbnail({required this.event, required this.loader});

  final StoryEvent event;
  final SceneAssetLoader loader;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: loader.loadForEvent(event),
      builder: (context, snapshot) {
        final assets = snapshot.data ?? const <String>[];
        final asset = assets.isEmpty ? null : assets.first;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 58,
            height: 58,
            child: asset == null
                ? const _RegionReviewThumbnailPlaceholder()
                : _RegionReviewThumbnailImage(asset: asset),
          ),
        );
      },
    );
  }
}

class _RegionReviewThumbnailImage extends StatelessWidget {
  const _RegionReviewThumbnailImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    if (asset.startsWith('http://') || asset.startsWith('https://')) {
      return Image.network(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _RegionReviewThumbnailPlaceholder(),
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _RegionReviewThumbnailPlaceholder(),
    );
  }
}

class _RegionReviewThumbnailPlaceholder extends StatelessWidget {
  const _RegionReviewThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentCard,
        border: Border.all(color: AppColors.borderCard),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.ink200,
        size: 22,
      ),
    );
  }
}

class _RegionQuizCountChip extends StatelessWidget {
  const _RegionQuizCountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.7),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10.4,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _RegionQuizTone {
  const _RegionQuizTone({required this.background, required this.border});

  final Color background;
  final Color border;

  static _RegionQuizTone? fromAttempt(QuizAttemptSummary? attempt) {
    if (attempt == null || attempt.totalCount <= 0) {
      return null;
    }
    if (attempt.correctCount <= 0) {
      return const _RegionQuizTone(
        background: Color(0xFFF7DAD2),
        border: AppColors.dangerBot,
      );
    }
    if (attempt.correctCount >= attempt.totalCount) {
      return const _RegionQuizTone(
        background: AppColors.greenTint1,
        border: AppColors.greenBorder,
      );
    }
    return const _RegionQuizTone(
      background: Color(0xFFF6E7B8),
      border: AppColors.goldDeep,
    );
  }
}

/// region 매핑 실패 이벤트(예: 사도의 시대 = 소아시아 도시) 의 단순 점 핀.
class _OrphanEventDot extends StatelessWidget {
  const _OrphanEventDot({
    required this.completed,
    required this.emotionMark,
    required this.eraColor,
  });

  final bool completed;
  final EventEmotionMark? emotionMark;
  final Color eraColor;

  @override
  Widget build(BuildContext context) {
    final emotionKey = emotionMark?.emotionKey;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: emotionKey == null || emotionKey.isEmpty
            ? (completed ? const Color(0xFF7AAC4C) : eraColor)
            : const Color(0xFFFFF4D8),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: emotionKey == null || emotionKey.isEmpty
          ? null
          : EmotionBadgeIcon(
              emotionKey: emotionKey,
              size: 14,
              iconSize: 8,
              elevation: false,
            ),
    );
  }
}
