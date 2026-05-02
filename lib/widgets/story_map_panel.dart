import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/era_boundary.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';
import '../theme/tokens.dart';
import '../utils/map_math.dart' as map_math;
import 'shared/event_short_popup.dart';

// 핀 마커 위젯/데이터 클래스를 별도 파트 파일로 분리.
part 'map/pin_marker.dart';

/// "현 지도에서 검색" 콜백. 사용자가 buton 을 누르면 현재 viewport 의 가운데
/// 80% 영역(lat/lng 박스)을 인자로 받아 부모가 검색을 트리거한다.
typedef ViewportSearchCallback =
    void Function({
      required double minLat,
      required double maxLat,
      required double minLng,
      required double maxLng,
    });

/// 두 랜드마크 사이 거리 측정 결과. 부모 (Home) 가 SnackBar / 다이얼로그로
/// 사용자에게 표시한다.
class MeasureResult {
  const MeasureResult({
    required this.fromName,
    required this.toName,
    required this.kilometers,
    required this.koreanComparison,
  });
  final String fromName;
  final String toName;
  final double kilometers;
  final String koreanComparison;
}

/// 두 위경도 사이 직선 거리(km, Haversine). 한국 비교 라벨 매칭용.
double haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLng = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return earthRadiusKm * c;
}

double _deg2rad(double deg) => deg * (math.pi / 180.0);

/// 거리(km)를 가까운 한국 도시 간 거리에 비유해 한 줄로 반환.
String koreanDistanceComparison(double km) {
  const anchors = <(double, String)>[
    (1.5, '광화문 ↔ 명동 정도'),
    (4.0, '강남역 ↔ 잠실역 정도'),
    (8.0, '강남역 ↔ 사당역 정도'),
    (15.0, '강남 ↔ 김포공항 정도'),
    (40.0, '서울 ↔ 인천 정도'),
    (80.0, '서울 ↔ 천안 정도'),
    (140.0, '서울 ↔ 대전 정도'),
    (260.0, '서울 ↔ 대구 정도'),
    (325.0, '서울 ↔ 부산 정도'),
    (500.0, '서울 ↔ 제주 (직선) 정도'),
    (900.0, '서울 ↔ 일본 도쿄 (직선) 정도'),
    (1500.0, '서울 ↔ 베이징 너머 정도'),
    (3500.0, '서울 ↔ 인도 델리 정도'),
  ];
  for (final (threshold, label) in anchors) {
    if (km <= threshold) {
      return label;
    }
  }
  return '서울에서 유럽 가는 정도';
}

class StoryMapPanel extends StatefulWidget {
  const StoryMapPanel({
    super.key,
    required this.events,
    required this.selectedEventId,
    required this.onSelectEvent,
    this.onCloseSelectedCallout,
    this.onOpenDetail,
    required this.colorForCharacter,
    required this.avatarAssetForCharacter,
    required this.selectedCharacterCodes,
    this.controller,
    this.bottomOverlay,
    this.decorate = true,
    this.showSelectedCallout = true,
    this.animateReveal = true,
    this.centerSelectedOnReady = false,
    this.fitAllEventsOnReady = false,
    this.fitAllZoomAdjust = -0.95,
    this.selectedFocusZoom,
    this.pinScale = 1.0,
    this.initialCenter,
    this.initialZoom,
    this.bottomObscuredFraction = 0.0,
    this.topObscuredPixels = 0.0,
    this.activeLandmarks = const [],
    this.viewportSearchResults = const [],
    this.onSearchInViewport,
    this.onClearViewportSearch,
    this.activeEraBoundaries = const [],
    this.onLandmarkTap,
    this.onMeasureResult,
    this.eraPreviewEvents = const [],
    this.nameForCharacter,
  });

  final List<StoryEvent> events;
  final String? selectedEventId;
  final ValueChanged<String> onSelectEvent;
  final VoidCallback? onCloseSelectedCallout;
  final ValueChanged<String>? onOpenDetail;
  final Color Function(String characterId) colorForCharacter;
  final String Function(String characterId) avatarAssetForCharacter;
  final Set<String> selectedCharacterCodes;
  final StoryMapPanelController? controller;
  final Widget? bottomOverlay;
  final bool decorate;
  final bool showSelectedCallout;
  final bool animateReveal;
  final bool centerSelectedOnReady;
  final bool fitAllEventsOnReady;
  final double fitAllZoomAdjust;
  final double? selectedFocusZoom;
  final double pinScale;
  final LatLng? initialCenter;
  final double? initialZoom;
  final double bottomObscuredFraction;
  final double topObscuredPixels;

  /// 현재 시대에 노출되는 랜드마크 (예루살렘 성전, 시내산 등). 일반적으로
  /// 부모가 selectedEraId 의 era code 로 필터해 넘긴다. 비어 있으면 미표시.
  final List<Landmark> activeLandmarks;

  /// "현 지도에서 검색" 결과 사건들. 비어있으면 결과 핀 미표시.
  /// 일반 events 와는 별도 레이어로 그려진다 (얼굴 + 제목 패널 핀).
  final List<StoryEvent> viewportSearchResults;

  /// "현 지도에서 검색" 버튼 콜백. null 이면 버튼 미표시.
  /// 인자: 현재 viewport 의 가운데 50% 영역 (lat/lng 박스).
  final ViewportSearchCallback? onSearchInViewport;

  /// 검색 결과를 비우고 일반 핀 표시로 돌아가는 콜백. viewportSearchResults 가
  /// 비어있지 않을 때 우상단 버튼이 "✕ 검색 취소 (N개)" 로 바뀌어 이 콜백을 호출.
  final VoidCallback? onClearViewportSearch;

  /// 지도에 그릴 시대 영역 폴리곤. 일반적으로 부모가 selectedEraId 로 필터해
  /// 현재 시대 분량만 넘긴다. 비어있으면 폴리곤 미표시.
  final List<EraBoundary> activeEraBoundaries;

  /// 랜드마크 탭 콜백. 부모(StoryHomeScreen) 가 다이얼로그/시트로 상세를
  /// 띄운다. null 이면 탭 무반응.
  final ValueChanged<Landmark>? onLandmarkTap;

  /// 거리 측정 모드 활성 여부. true 면 랜드마크 탭이 측정 시작점/끝점 선택으로
  /// 동작하고 popup 은 뜨지 않는다.
  ///
  /// 이 값을 부모에서 토글하지 않고 패널이 자체 토글 버튼을 우상단에 띄운다.
  /// 부모는 거리 측정 결과 (km, 한국 거리 비교)만 [onMeasureResult] 로 받는다.
  final ValueChanged<MeasureResult>? onMeasureResult;

  /// 시대 선택 후 "다음" 누르기 전 단계에서 지도에 미리 그릴 모든 사건들.
  /// 인물별로 그룹핑되어 각자 색깔의 path 로 그려진다 — 선택된 인물은 진하게,
  /// 미선택은 흐리게. 비어있으면 미리보기 path 미표시.
  final List<StoryEvent> eraPreviewEvents;

  /// 인물 코드 → 표시 이름 반환. legend 에서 사용. null 이면 코드를 이름으로
  /// 사용 (fallback).
  final String Function(String characterCode)? nameForCharacter;

  @override
  State<StoryMapPanel> createState() => _StoryMapPanelState();
}

class _StoryMapPanelState extends State<StoryMapPanel> {
  final MapController _controller = MapController();
  Timer? _revealTimer;
  Timer? _cameraTimer;
  List<Polyline> _countryBorderPolylines = const [];
  List<Marker> _countryLabelMarkers = const [];
  // 시대 영역이 바다로 흘러나가지 않게 ray-cast point-in-polygon 으로 검출하기
  // 위해 country GeoJSON 의 outer ring 들을 평면 좌표 그대로 보관한다.
  List<List<LatLng>> _landRings = const [];
  int _visibleCount = 0;
  Size _lastMapSize = const Size(900, 600);
  int _revealRunId = 0;
  bool _mapReady = false;

  /// 거리 측정 모드. true 면 랜드마크 탭이 측정 시작/끝점 선택으로 바뀐다.
  bool _measureMode = false;
  Landmark? _measureFirst;
  Landmark? _measureSecond;

  static const _PinStyle _normalPinStyle = _PinStyle(
    badgeHeight: 24,
    labelFontSize: 12.5,
    arrowWidth: 14,
    arrowHeight: 8,
    anchorGap: 3,
  );
  static const _PinStyle _selectedPinStyle = _PinStyle(
    badgeHeight: 28,
    labelFontSize: 13.5,
    arrowWidth: 16,
    arrowHeight: 9,
    anchorGap: 3,
  );

  static const double _selectedCalloutEstimatedWidth = 268;
  static const double _selectedCalloutEstimatedHeight = 196;
  static const double _selectedCalloutTopMargin = 14;

  _PinStyle _scaledPinStyle(_PinStyle base) {
    final scale = widget.pinScale.clamp(0.6, 1.25);
    return _PinStyle(
      badgeHeight: base.badgeHeight * scale,
      labelFontSize: base.labelFontSize * scale,
      arrowWidth: base.arrowWidth * scale,
      arrowHeight: base.arrowHeight * scale,
      anchorGap: base.anchorGap * scale,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _loadCountryBoundaries();
    _startRevealAnimation();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _cameraTimer?.cancel();
    widget.controller?._unbind(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StoryMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind(this);
      widget.controller?._bind(this);
    }

    // Era 변경 감지 → hull bounds 로 카메라 fit. 사건/랜드마크가 화면에 다
    // 들어오게.
    final oldEraId = oldWidget.activeEraBoundaries.firstOrNull?.eraId;
    final newEraId = widget.activeEraBoundaries.firstOrNull?.eraId;
    if (oldEraId != newEraId && newEraId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeFitToEraHull();
      });
    }

    if (map_math.eventListSignature(oldWidget.events) !=
            map_math.eventListSignature(widget.events) ||
        oldWidget.selectedCharacterCodes != widget.selectedCharacterCodes) {
      // 사건 토글마다 reveal 을 재생하면 핀이 깜빡이듯 사라졌다 다시 박힘.
      // 단순 토글에서는 모든 핀을 즉시 노출하고, "다음" 버튼처럼 외부에서
      // `replayReveal()` 을 명시 호출할 때만 시간 순 reveal 이 돌아간다.
      _showAllPinsImmediately();
      if (_mapReady &&
          (widget.centerSelectedOnReady || widget.fitAllEventsOnReady)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          if (widget.fitAllEventsOnReady) {
            _focusAllEvents(duration: const Duration(milliseconds: 360));
          } else {
            _centerSelectedEvent();
          }
        });
      }
    }

    if (oldWidget.selectedEventId != widget.selectedEventId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (widget.fitAllEventsOnReady) {
          return;
        }
        if (widget.centerSelectedOnReady) {
          _centerSelectedEvent();
        } else {
          _focusSelectedEventIfNeeded();
        }
      });
    }

    if ((oldWidget.bottomObscuredFraction - widget.bottomObscuredFraction)
                .abs() >
            0.015 &&
        widget.selectedEventId != null &&
        !widget.fitAllEventsOnReady &&
        !widget.centerSelectedOnReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _focusSelectedEventIfNeeded(force: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinateEvents = widget.events
        .where((event) => event.hasCoordinate)
        .toList();

    final center =
        widget.initialCenter ??
        (coordinateEvents.isNotEmpty
            ? coordinateEvents.first.latLng
            : const LatLng(31.8, 35.2));

    final zoom = widget.initialZoom ?? 5.3;
    final polylines = _buildPolylines(widget.events);

    return Container(
      decoration: widget.decorate
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBDA076), width: 1.2),
            )
          : null,
      clipBehavior: widget.decorate ? Clip.antiAlias : Clip.none,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFFE5D2B5))),
          LayoutBuilder(
            builder: (context, constraints) {
              final mapSize = constraints.biggest;
              if (mapSize.width > 0 && mapSize.height > 0) {
                _lastMapSize = mapSize;
              }

              return FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
                  minZoom: 2.4,
                  maxZoom: 13,
                  onMapReady: () {
                    _mapReady = true;
                    _startRevealAnimation();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      if (widget.fitAllEventsOnReady) {
                        _focusAllEvents(
                          duration: const Duration(milliseconds: 360),
                        );
                        Future.delayed(const Duration(milliseconds: 180), () {
                          if (!mounted) {
                            return;
                          }
                          _focusAllEvents(
                            duration: const Duration(milliseconds: 240),
                          );
                        });
                      } else if (widget.centerSelectedOnReady) {
                        _centerSelectedEvent();
                        Future.delayed(const Duration(milliseconds: 180), () {
                          if (!mounted) {
                            return;
                          }
                          _centerSelectedEvent();
                        });
                      } else {
                        _focusSelectedEventIfNeeded();
                      }
                    });
                  },
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
                    tileBuilder: (context, tileWidget, _) {
                      return ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0x2EB99563),
                          BlendMode.srcATop,
                        ),
                        child: tileWidget,
                      );
                    },
                  ),
                  PolylineLayer(polylines: _countryBorderPolylines),
                  // 시대 영역 폴리곤 — 사건/랜드마크 좌표 기반 동적 convex hull.
                  // GeoJSON 정밀 폴리곤(`activeEraBoundaries`) 대신 그 시대에
                  // 실제로 등장하는 사건들이 모인 영역만 보여주므로 새 사건
                  // 추가 시 자동으로 영역이 확장된다.
                  if (widget.activeEraBoundaries.isNotEmpty &&
                      widget.eraPreviewEvents.isNotEmpty)
                    PolygonLayer(polygons: _buildDynamicEraHullPolygons()),
                  MarkerLayer(markers: _countryLabelMarkers),
                  // 시대 미리보기 — 인물별 사건 path 를 색깔 실선으로.
                  // 선택 인물 alpha 0.95 + 굵기 4.5, 미선택 alpha 0.40 + 2.5.
                  if (widget.eraPreviewEvents.isNotEmpty)
                    PolylineLayer(polylines: _buildEraPreviewPolylines()),
                  // 미리보기 dot 마커 — 사건 위치마다 작은 색깔 동그라미. 선택
                  // 인물 큰 dot, 미선택 작은 dot. 단일 사건 인물도 점으로 시각화.
                  if (widget.eraPreviewEvents.isNotEmpty)
                    MarkerLayer(markers: _buildEraPreviewDots()),
                  // 선택 인물 path 끝점 화살표 — 마지막 사건 위치에 ▶ 모양.
                  // 시간 흐름의 종착지를 명확히 보여줌.
                  if (widget.eraPreviewEvents.isNotEmpty &&
                      widget.selectedCharacterCodes.isNotEmpty)
                    MarkerLayer(markers: _buildEraPreviewArrowHeads()),
                  // 시대별 랜드마크 — 클러스터링 없이 단순 표시. 시대 필터로
                  // 이미 충분히 적어 (15~25개), 클러스터로 묶이는 게 정보를
                  // 압축해 오히려 가린다.
                  if (widget.activeLandmarks.isNotEmpty)
                    MarkerLayer(
                      markers: _buildLandmarkMarkers(widget.activeLandmarks),
                    ),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: _buildRegionLabels()),
                  MarkerLayer(markers: _buildMarkers(widget.events)),
                  // "현 지도에서 검색" 결과 핀 (얼굴 + 제목 패널). 일반 사건 핀
                  // 위 레이어에 배치해 상호작용 우선.
                  if (widget.viewportSearchResults.isNotEmpty)
                    MarkerLayer(
                      markers: _buildViewportSearchMarkers(
                        widget.viewportSearchResults,
                      ),
                    ),
                  // 거리 측정 폴리라인 (두 점이 모두 선택됐을 때만).
                  if (_measureMode)
                    PolylineLayer(polylines: _buildMeasurePolylines()),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.only(left: 6, bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x88FFFFFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '© OpenStreetMap · CARTO · Natural Earth',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: Color(0xFF2D2D2D),
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.bottomOverlay != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: widget.bottomOverlay!,
                    ),
                  // 선택된 인물 색깔 범례 — 지도 좌상단(랜드마크 토글 버튼 아래)
                  // 에 작은 카드. 선택 인물이 1명 이상일 때만 표시.
                  if (widget.selectedCharacterCodes.isNotEmpty)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60, left: 10),
                        child: _CharacterColorLegend(
                          codes: widget.selectedCharacterCodes,
                          colorForCharacter: widget.colorForCharacter,
                          nameForCharacter: widget.nameForCharacter,
                        ),
                      ),
                    ),
                  if (widget.onSearchInViewport != null)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, right: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            widget.viewportSearchResults.isNotEmpty &&
                                    widget.onClearViewportSearch != null
                                ? _ViewportSearchClearButton(
                                    count: widget.viewportSearchResults.length,
                                    onTap: widget.onClearViewportSearch!,
                                  )
                                : _ViewportSearchButton(
                                    onTap: _handleViewportSearchTap,
                                  ),
                            const SizedBox(height: 8),
                            _MeasureToggleButton(
                              active: _measureMode,
                              onTap: _toggleMeasureMode,
                            ),
                            if (_measureMode) ...[
                              const SizedBox(height: 6),
                              _MeasureHintBanner(
                                first: _measureFirst,
                                second: _measureSecond,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 현재 카메라 viewport 의 가운데 50% 박스를 lat/lng 로 계산해 콜백으로 전달.
  /// 화면 중심 기준으로 양쪽에서 25% 씩 깎아 들어간 "포커스 영역" — 사용자가
  /// 보고 있는 화면 한가운데에 들어온 사건만 검색 결과로 잡히게 한다.
  void _handleViewportSearchTap() {
    final callback = widget.onSearchInViewport;
    if (callback == null) {
      return;
    }
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final bounds = camera.visibleBounds;
    final minLat = bounds.southWest.latitude;
    final maxLat = bounds.northEast.latitude;
    final minLng = bounds.southWest.longitude;
    final maxLng = bounds.northEast.longitude;
    final latShrink = (maxLat - minLat) * 0.25;
    final lngShrink = (maxLng - minLng) * 0.25;
    callback(
      minLat: minLat + latShrink,
      maxLat: maxLat - latShrink,
      minLng: minLng + lngShrink,
      maxLng: maxLng - lngShrink,
    );
  }

  /// 랜드마크 탭 처리. 일반 모드 → onLandmarkTap 콜백 (popup). 거리 측정 모드
  /// → 첫 번째/두 번째 점 선택해 두 점이 모이면 거리 계산 후 onMeasureResult.
  void _handleLandmarkTap(Landmark landmark) {
    if (!_measureMode) {
      widget.onLandmarkTap?.call(landmark);
      return;
    }
    setState(() {
      if (_measureFirst == null || _measureSecond != null) {
        // 새 측정 시작
        _measureFirst = landmark;
        _measureSecond = null;
      } else if (_measureFirst!.code == landmark.code) {
        // 같은 점 다시 선택 → 취소
        _measureFirst = null;
      } else {
        _measureSecond = landmark;
      }
    });
    if (_measureFirst != null && _measureSecond != null) {
      final km = haversineKm(_measureFirst!.latLng, _measureSecond!.latLng);
      widget.onMeasureResult?.call(
        MeasureResult(
          fromName: _measureFirst!.name,
          toName: _measureSecond!.name,
          kilometers: km,
          koreanComparison: koreanDistanceComparison(km),
        ),
      );
    }
  }

  /// 외부 호출용 카메라 이동 (랜드마크 목록에서 항목을 골랐을 때).
  void _focusLandmark(LatLng point) {
    if (!_mapReady) return;
    try {
      final camera = _controller.camera;
      final currentZoom = (camera.zoom as num?)?.toDouble() ?? 6.0;
      final targetZoom = math.max(currentZoom, 7.5);
      _controller.move(point, targetZoom);
    } catch (_) {
      // 카메라 비가용 — 무시
    }
  }

  /// 거리 측정 모드 토글 (우상단 작은 버튼).
  void _toggleMeasureMode() {
    setState(() {
      _measureMode = !_measureMode;
      _measureFirst = null;
      _measureSecond = null;
    });
  }

  /// 측정 점 두 개를 잇는 폴리라인 1개. 한쪽만 선택된 상태면 빈 리스트.
  List<Polyline> _buildMeasurePolylines() {
    if (_measureFirst == null || _measureSecond == null) {
      return const [];
    }
    return [
      Polyline(
        points: [_measureFirst!.latLng, _measureSecond!.latLng],
        color: const Color(0xFFFF6B35),
        strokeWidth: 3.5,
        pattern: const StrokePattern.dotted(),
      ),
    ];
  }

  /// 인물별 미세 offset — 같은 좌표에 align 된 사건들이 인물별로 다른 미세
  /// 위치에 그려지도록. 한 사건에 여러 인물이 등장하면 그 점에서 인물 색깔
  /// dot 들이 자연스럽게 부채꼴로 흩어져 모두 보인다. 또 path 가 한 점에
  /// 모이지 않고 부드럽게 흐름이 보임.
  ///
  /// 거리는 약 0.025° ≒ 2.5km — 지도 줌 레벨에서 인지 가능하지만 위치를
  /// 크게 왜곡하지 않는 수준.
  LatLng _shiftedForCharacter(LatLng base, String code) {
    if (code.isEmpty) return base;
    final hash = code.hashCode.abs();
    final angle = (hash % 360) * (math.pi / 180.0);
    const distance = 0.025;
    return LatLng(
      base.latitude + math.cos(angle) * distance,
      base.longitude + math.sin(angle) * distance,
    );
  }

  /// 시대 미리보기 — 그 시대의 모든 사건을 인물별로 그룹핑한 뒤 각 인물의
  /// 시간순 path 를 자기 색의 실선으로 그린다. 선택 인물은 진하게(0.95),
  /// 미선택은 흐리게(0.40) → 사용자가 인물을 골라가며 비교 가능.
  ///
  /// 같은 좌표(예: 헤브론에 모인 여러 사건)에서 path 가 겹쳐 안 보이는 문제는
  /// `buildAdjustedPoints` 로 약간 분산해 해결. 한 사건에 여러 인물이 등장하면
  /// 각 인물 path 에 모두 포함되어 그 점에 여러 색의 선이 자연스럽게 겹친다
  /// (의도된 동작 — 인물 간 만남이 시각화).
  List<Polyline> _buildEraPreviewPolylines() {
    final events = widget.eraPreviewEvents;
    if (events.isEmpty) {
      return const [];
    }
    final coordinateEvents = events
        .where((e) => e.hasCoordinate)
        .toList(growable: false);
    if (coordinateEvents.isEmpty) {
      return const [];
    }
    final adjusted = map_math.buildAdjustedPoints(coordinateEvents);

    final byCharacter = <String, List<StoryEvent>>{};
    for (final event in coordinateEvents) {
      for (final code in event.characterCodes) {
        byCharacter.putIfAbsent(code, () => <StoryEvent>[]).add(event);
      }
    }
    final result = <Polyline>[];
    final selected = widget.selectedCharacterCodes;
    // 선택 안 된 path 먼저, 선택된 path 나중 → z-order 가 위로 올라와 잘 보임.
    final orderedCodes = byCharacter.keys.toList()
      ..sort((a, b) {
        final aSel = selected.contains(a) ? 1 : 0;
        final bSel = selected.contains(b) ? 1 : 0;
        return aSel.compareTo(bSel);
      });
    for (final code in orderedCodes) {
      final list = byCharacter[code]!;
      list.sort((a, b) => a.globalRank.compareTo(b.globalRank));
      if (list.length < 2) {
        continue;
      }
      // 인물별 미세 offset 적용 — 같은 좌표 사건들이 한 점에 모이는 문제 해결.
      final points = list
          .map((e) {
            final base = adjusted[e.id] ?? e.latLng;
            return _shiftedForCharacter(base, code);
          })
          .toList(growable: false);
      final color = widget.colorForCharacter(code);
      final isSelected = selected.contains(code);
      if (isSelected) {
        // 선택 인물 — segment 별 alpha 그라디언트 (시작 0.6 → 끝 1.0)
        // + 굵은 6.0px 실선. 시간 흐름이 진해지는 자연스러운 방향성.
        for (var i = 0; i < points.length - 1; i++) {
          final t = (points.length <= 2) ? 1.0 : (i + 1) / (points.length - 1);
          final segAlpha = 0.6 + 0.4 * t;
          result.add(
            Polyline(
              points: [points[i], points[i + 1]],
              color: color.withValues(alpha: segAlpha),
              strokeWidth: 6.0,
            ),
          );
        }
      } else {
        // 미선택 — 거의 안 보일 정도(alpha 0.06) + 매우 가늘게.
        // 선택 인물 path 만 두드러지게 강한 대비.
        result.add(
          Polyline(
            points: points,
            color: color.withValues(alpha: 0.06),
            strokeWidth: 1.5,
          ),
        );
      }
    }
    return result;
  }

  /// 시대 미리보기 dot 마커.
  /// - **선택 인물의 시작점** = 36px 아바타 + 4px 인물색 테두리 (탭하면 사건 진입)
  /// - **선택 인물의 중간 점** = 12px 인물색 dot (탭하면 사건 진입)
  /// - **선택 인물의 끝점** = `_buildEraPreviewArrowHeads` 가 화살촉으로 처리 → dot 생략
  /// - **미선택 인물 사건 위치** = 5px alpha 0.35 dot (식별 정도만)
  List<Marker> _buildEraPreviewDots() {
    final events = widget.eraPreviewEvents;
    if (events.isEmpty) return const [];
    final coordinateEvents = events
        .where((e) => e.hasCoordinate)
        .toList(growable: false);
    if (coordinateEvents.isEmpty) return const [];

    final adjusted = map_math.buildAdjustedPoints(coordinateEvents);
    final selected = widget.selectedCharacterCodes;

    // 선택 인물별 첫/마지막 사건 id 미리 계산.
    final startEventByCode = <String, String>{};
    final endEventByCode = <String, String>{};
    for (final code in selected) {
      StoryEvent? earliest;
      StoryEvent? latest;
      for (final event in coordinateEvents) {
        if (!event.characterCodes.contains(code)) continue;
        if (earliest == null || event.globalRank < earliest.globalRank) {
          earliest = event;
        }
        if (latest == null || event.globalRank > latest.globalRank) {
          latest = event;
        }
      }
      if (earliest != null) startEventByCode[code] = earliest.id;
      if (latest != null && latest.id != earliest?.id) {
        endEventByCode[code] = latest.id;
      }
    }

    final markers = <Marker>[];
    final seen = <String>{};
    // 미선택 → 선택 순서 정렬 (z-order).
    final ordered = <(StoryEvent, String, bool)>[];
    for (final event in coordinateEvents) {
      for (final code in event.characterCodes) {
        if (code.isEmpty) continue;
        ordered.add((event, code, selected.contains(code)));
      }
    }
    ordered.sort((a, b) => (a.$3 ? 1 : 0).compareTo(b.$3 ? 1 : 0));

    for (final (event, code, isSel) in ordered) {
      final key = '${event.id}|$code';
      if (!seen.add(key)) continue;
      // 인물별 미세 offset — polyline 과 같은 위치에 dot 이 떨어지도록.
      final basePoint = adjusted[event.id] ?? event.latLng;
      final point = _shiftedForCharacter(basePoint, code);
      final color = widget.colorForCharacter(code);

      if (!isSel) {
        // 미선택 인물 — 작은 흐린 dot. 식별만 가능한 수준.
        markers.add(
          Marker(
            point: point,
            width: 9,
            height: 9,
            alignment: Alignment.center,
            child: IgnorePointer(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // 선택 인물 — 시작 / 중간 / 끝 분기.
      final isStart = startEventByCode[code] == event.id;
      final isEnd = endEventByCode[code] == event.id;
      if (isEnd && !isStart) {
        // 끝점은 화살촉이 처리 → 여기서 dot 생략 (겹침 방지).
        continue;
      }

      if (isStart) {
        // 시작점 — 아바타 + 인물색 테두리 + 탭 가능.
        markers.add(
          Marker(
            point: point,
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSelectEvent(event.id);
                widget.onOpenDetail?.call(event.id);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: color, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 4,
                      offset: Offset(0, 1.5),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _AvatarImage(
                  assetPath: widget.avatarAssetForCharacter(code),
                ),
              ),
            ),
          ),
        );
      } else {
        // 중간 점 — 인물색 dot, 탭 가능.
        markers.add(
          Marker(
            point: point,
            width: 16,
            height: 16,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSelectEvent(event.id);
                widget.onOpenDetail?.call(event.id);
              },
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 1.6),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 2.5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  /// 선택 인물 path 의 끝점에 그릴 화살촉 마커. 시간 흐름의 종착지를 명확히
  /// 보여줘 "어디서 시작 → 어디서 끝났는지" 가 직관적이 된다.
  ///
  /// 각도는 마지막 두 점을 잇는 벡터로 계산해 화살촉이 path 방향을 가리키도록.
  List<Marker> _buildEraPreviewArrowHeads() {
    final events = widget.eraPreviewEvents;
    if (events.isEmpty) return const [];
    final coordinateEvents = events
        .where((e) => e.hasCoordinate)
        .toList(growable: false);
    if (coordinateEvents.isEmpty) return const [];
    final adjusted = map_math.buildAdjustedPoints(coordinateEvents);

    final byCharacter = <String, List<StoryEvent>>{};
    for (final event in coordinateEvents) {
      for (final code in event.characterCodes) {
        if (!widget.selectedCharacterCodes.contains(code)) continue;
        byCharacter.putIfAbsent(code, () => <StoryEvent>[]).add(event);
      }
    }

    final markers = <Marker>[];
    byCharacter.forEach((code, list) {
      list.sort((a, b) => a.globalRank.compareTo(b.globalRank));
      if (list.length < 2) return;
      final last = list.last;
      final prev = list[list.length - 2];
      // polyline 끝점과 같은 좌표가 되도록 인물 offset 적용.
      final lastPt = _shiftedForCharacter(
        adjusted[last.id] ?? last.latLng,
        code,
      );
      final prevPt = _shiftedForCharacter(
        adjusted[prev.id] ?? prev.latLng,
        code,
      );
      final color = widget.colorForCharacter(code);
      // atan2 기반 방향 — flutter_map 좌표는 lat 위, lng 오른쪽이라
      // y = -dLat (북쪽이 위), x = dLng.
      final dy = -(lastPt.latitude - prevPt.latitude);
      final dx = lastPt.longitude - prevPt.longitude;
      final angle = math.atan2(dy, dx);
      markers.add(
        Marker(
          point: lastPt,
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: CustomPaint(
                size: const Size(24, 24),
                painter: _ArrowHeadPainter(color: color),
              ),
            ),
          ),
        ),
      );
    });
    return markers;
  }

  /// 시대 변경 시 사건+랜드마크 영역에 카메라 fit. hull bounds 로 줌인.
  void _maybeFitToEraHull() {
    if (!_mapReady) return;
    final points = <LatLng>[];
    for (final e in widget.eraPreviewEvents) {
      if (e.hasCoordinate) points.add(e.latLng);
    }
    for (final lm in widget.activeLandmarks) {
      points.add(lm.latLng);
    }
    if (points.length < 2) return;
    final bounds = LatLngBounds.fromPoints(points);
    try {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(60, 100, 60, 60),
        ),
      );
    } catch (_) {
      // 카메라 비가용 시 무시
    }
  }

  /// 동적 시대 영역 — 사건/랜드마크 좌표 + **해안선 정점** 의 convex hull.
  ///
  /// 핵심 아이디어: 이미 로드된 country GeoJSON 의 해안선/국경 정점들 중
  /// 사건 bbox 안에 있는 것들을 hull input 에 추가한다. hull 이 land 정점에
  /// 의해 외곽이 잡혀 자동으로 바다(만, 해변)를 회피하는 자연스러운 모양이
  /// 된다. 더 많은 land 정점이 있을수록 hull 이 정확한 해안선을 따라간다.
  ///
  /// 예: 가나안 ↔ 우르 두 점만 있으면 직선이 사우디 사막 + 페르시아만 가로
  /// 지른다. 해안선 정점이 hull input 에 들어가면 hull 변이 메소포타미아 +
  /// 시리아 land 정점들로 휘어 바다 회피.
  List<Polygon> _buildDynamicEraHullPolygons() {
    final eventPoints = <LatLng>[];
    for (final event in widget.eraPreviewEvents) {
      if (event.hasCoordinate) {
        eventPoints.add(event.latLng);
      }
    }
    for (final lm in widget.activeLandmarks) {
      eventPoints.add(lm.latLng);
    }
    if (eventPoints.length < 3) {
      return const [];
    }

    // 1) 사건 점들의 bbox + padding (해안선 정점 추출 범위)
    var minLat = eventPoints.first.latitude;
    var maxLat = eventPoints.first.latitude;
    var minLng = eventPoints.first.longitude;
    var maxLng = eventPoints.first.longitude;
    for (final p in eventPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // 해안선 정점이 사건 외곽까지 들어가야 hull 변이 land 따라 휘므로
    // padding 을 충분히 크게 잡는다 (사건 영역 외곽 ~3° = ~330km).
    const paddingDeg = 3.0;
    minLat -= paddingDeg;
    maxLat += paddingDeg;
    minLng -= paddingDeg;
    maxLng += paddingDeg;

    // 2) 이미 로드된 국경/해안선 정점 중 bbox 안 → hull input 의 추가 attractor
    final coastPoints = <LatLng>[];
    for (final polyline in _countryBorderPolylines) {
      for (final p in polyline.points) {
        if (p.latitude >= minLat &&
            p.latitude <= maxLat &&
            p.longitude >= minLng &&
            p.longitude <= maxLng) {
          coastPoints.add(p);
        }
      }
    }

    // 3) hull 계산 — 사건 + 해안선 정점 모두 input. land 정점이 외곽을 잡아
    //    hull 이 자연스럽게 land 따라간다.
    final all = <LatLng>[...eventPoints, ...coastPoints];
    final hull = map_math.convexHull(all);
    if (hull.length < 3) {
      return const [];
    }

    // 4) 변 densification — 등분 수 16, pullFactor 0.85 로 끌어당겨 hull 의
    //    긴 변(예: 가나안 → 우르)이 land 정점들을 따라 zigzag 로 휘게 한다.
    final densified = _densifyHullToward(
      hull: hull,
      attractors: all,
      segmentsPerEdge: 16,
      pullFactor: 0.85,
    );

    // 5) land mask 투영 — densification 후에도 바다 위에 떠 있는 정점은
    //    가장 가까운 land 정점(coastPoints) 으로 옮긴다. country GeoJSON 의
    //    outer ring 에 ray-cast 해서 inside/outside 판정. 이게 진짜 바다 회피.
    final clipped = _projectOntoLand(densified, coastPoints);

    final ref = widget.activeEraBoundaries.firstOrNull;
    final color = ref?.color ?? const Color(0xFFB89A66);
    final fillAlpha = (ref?.fillOpacity ?? 0.18).clamp(0.0, 1.0);
    return [
      Polygon(
        points: clipped,
        color: color.withValues(alpha: fillAlpha),
        borderColor: color.withValues(alpha: 0.85),
        borderStrokeWidth: 2.0,
      ),
    ];
  }

  /// densified hull 정점 중 land mask(국가 폴리곤 union) 밖에 있는 점을 가장
  /// 가까운 land 정점으로 옮긴다. land mask 가 비어 있으면(GeoJSON 로딩 전)
  /// 입력을 그대로 반환.
  List<LatLng> _projectOntoLand(
    List<LatLng> points,
    List<LatLng> landAttractors,
  ) {
    if (_landRings.isEmpty || landAttractors.isEmpty) {
      return points;
    }
    final result = <LatLng>[];
    for (final p in points) {
      if (_isInsideAnyLand(p)) {
        result.add(p);
      } else {
        result.add(_nearestPoint(p.latitude, p.longitude, landAttractors));
      }
    }
    return result;
  }

  /// 국가 outer ring 들에 대해 ray-cast point-in-polygon. 한 개라도 inside 면 true.
  bool _isInsideAnyLand(LatLng p) {
    for (final ring in _landRings) {
      if (_pointInRing(p, ring)) {
        return true;
      }
    }
    return false;
  }

  /// 표준 even-odd ray casting. ring 은 닫혀 있다고 가정하지 않고 마지막 →
  /// 첫 정점도 변으로 친다.
  bool _pointInRing(LatLng p, List<LatLng> ring) {
    final lat = p.latitude;
    final lng = p.longitude;
    var inside = false;
    final n = ring.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final yi = ring[i].latitude;
      final xi = ring[i].longitude;
      final yj = ring[j].latitude;
      final xj = ring[j].longitude;
      final intersect =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// hull 의 각 변을 [segmentsPerEdge] 등분 → 각 중간점을 가장 가까운 attractor
  /// 좌표 쪽으로 [pullFactor] 비율만큼 끌어당긴 정점 리스트 반환.
  /// 결과: 변이 사건 점 따라 휘어 바다 가로지르는 직선이 안쪽으로 굽어진다.
  List<LatLng> _densifyHullToward({
    required List<LatLng> hull,
    required List<LatLng> attractors,
    required int segmentsPerEdge,
    required double pullFactor,
  }) {
    final result = <LatLng>[];
    for (var i = 0; i < hull.length; i++) {
      final p1 = hull[i];
      final p2 = hull[(i + 1) % hull.length];
      result.add(p1);
      for (var k = 1; k < segmentsPerEdge; k++) {
        final t = k / segmentsPerEdge;
        final midLat = p1.latitude + (p2.latitude - p1.latitude) * t;
        final midLng = p1.longitude + (p2.longitude - p1.longitude) * t;
        final nearest = _nearestPoint(midLat, midLng, attractors);
        final pulledLat = midLat + (nearest.latitude - midLat) * pullFactor;
        final pulledLng = midLng + (nearest.longitude - midLng) * pullFactor;
        result.add(LatLng(pulledLat, pulledLng));
      }
    }
    return result;
  }

  LatLng _nearestPoint(double lat, double lng, List<LatLng> candidates) {
    var nearest = candidates.first;
    var minDist = double.infinity;
    for (final c in candidates) {
      final dLat = c.latitude - lat;
      final dLng = c.longitude - lng;
      final d = dLat * dLat + dLng * dLng;
      if (d < minDist) {
        minDist = d;
        nearest = c;
      }
    }
    return nearest;
  }

  /// 시대별 랜드마크 마커 빌드.
  /// 이모지 + 작은 라벨. 일반 사건 핀과 시각적으로 구분되게 둥근 캡슐 디자인.
  List<Marker> _buildLandmarkMarkers(List<Landmark> landmarks) {
    return landmarks
        .map((obj) {
          final isMeasureSelected =
              _measureMode &&
              (obj.code == _measureFirst?.code ||
                  obj.code == _measureSecond?.code);
          return Marker(
            point: obj.latLng,
            width: 100,
            height: 56,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleLandmarkTap(obj),
              child: ColorFiltered(
                colorFilter: isMeasureSelected
                    ? const ColorFilter.mode(
                        Color(0x55FF6B35),
                        BlendMode.srcATop,
                      )
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xF2FFFBEF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFB89A66),
                          width: 0.8,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 3,
                            offset: Offset(0, 1.5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            obj.emoji,
                            style: const TextStyle(fontSize: 13, height: 1.0),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              obj.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3D2A14),
                                height: 1.05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFB89A66),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        })
        .toList(growable: false);
  }

  /// "현 지도에서 검색" 결과 사건 핀. 인물 아바타(최대 3개 겹침) + 짧은 제목.
  List<Marker> _buildViewportSearchMarkers(List<StoryEvent> events) {
    final visibleEvents = events.where((e) => e.hasCoordinate).toList();
    return visibleEvents
        .map((event) {
          final firstThreeCodes = event.characterCodes.take(3).toList();
          return Marker(
            point: event.latLng,
            width: 180,
            height: 78,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSelectEvent(event.id);
                widget.onOpenDetail?.call(event.id);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 174),
                    padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: const Color(0xF5FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF8C5A2E),
                        width: 1.0,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (firstThreeCodes.isNotEmpty)
                          _StackedAvatars(
                            characterCodes: firstThreeCodes,
                            avatarAssetForCharacter:
                                widget.avatarAssetForCharacter,
                          ),
                        if (firstThreeCodes.isNotEmpty)
                          const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _stripLeadingNumber(event.title),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2D1A06),
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF8C5A2E),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        })
        .toList(growable: false);
  }

  String _stripLeadingNumber(String title) {
    final trimmed = title.trim();
    final match = RegExp(r'^\d{1,3}\s+(.*)$').firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    return (match.group(1) ?? trimmed).trim();
  }

  List<Polyline> _buildPolylines(List<StoryEvent> events) {
    // 선택된 사건들 사이를 잇는 dashed 연결선은 의도적으로 비워둔다.
    // 인물별 이동 경로는 era preview path (`_buildEraPreviewPolylines`) 로
    // 이미 그려지고 있고, 사건 핀은 그 path 위 어디에 위치하는지만 보여주면
    // 충분하다. 사건 ↔ 사건 직선 연결은 "정확하지 않은 이동 경로"라는 인상을
    // 주므로 제거.
    return const [];
  }

  List<Marker> _buildMarkers(List<StoryEvent> events) {
    final withCoordinate = events
        .where((event) => event.hasCoordinate)
        .toList();
    final visible = withCoordinate.take(_visibleCount).toList(growable: true);
    final selectedEventId = widget.selectedEventId;
    if (selectedEventId != null &&
        !visible.any((event) => event.id == selectedEventId)) {
      final selectedEvent = withCoordinate
          .where((event) => event.id == selectedEventId)
          .firstOrNull;
      if (selectedEvent != null) {
        visible.add(selectedEvent);
      }
    }

    final adjustedPoints = map_math.buildAdjustedPoints(withCoordinate);
    final nodes = <_MarkerNode>[];
    for (final event in visible) {
      final basePoint = adjustedPoints[event.id] ?? event.latLng;
      final placeName = (event.placeName ?? '').trim();
      final colors = _colorsForEvent(event);
      final pinCodes = _pinCharacterCodes(event);
      if (map_math.hasMultiPlacePin(placeName)) {
        final parts = map_math.splitPlaceParts(placeName);
        final points = map_math.buildSplitPinPoints(basePoint);
        nodes.add(
          _MarkerNode(
            event: event,
            point: points.$1,
            placeLabel: parts.$1,
            showCallout: true,
            characterCodes: pinCodes,
            characterColors: colors,
          ),
        );
        nodes.add(
          _MarkerNode(
            event: event,
            point: points.$2,
            placeLabel: parts.$2,
            showCallout: false,
            characterCodes: pinCodes,
            characterColors: colors,
          ),
        );
      } else {
        nodes.add(
          _MarkerNode(
            event: event,
            point: basePoint,
            placeLabel: placeName,
            showCallout: true,
            characterCodes: pinCodes,
            characterColors: colors,
          ),
        );
      }
    }

    final orderedNodes = nodes.toList()
      ..sort((a, b) {
        final aSelected = a.event.id == widget.selectedEventId;
        final bSelected = b.event.id == widget.selectedEventId;
        if (aSelected != bSelected) {
          return aSelected ? 1 : -1;
        }
        if (a.event.id == b.event.id && a.showCallout != b.showCallout) {
          return a.showCallout ? 1 : -1;
        }
        return 0;
      });

    return orderedNodes.map((node) {
      final event = node.event;
      final selected = widget.selectedEventId == event.id;
      final pinStyle = _scaledPinStyle(
        selected ? _selectedPinStyle : _normalPinStyle,
      );
      final shortText = (event.summary ?? '').trim();
      final pinWidth = math.max(
        pinStyle.badgeWidthForAvatars(node.characterCodes.length) + 10,
        pinStyle.arrowWidth + 10,
      );
      final markerWidth = selected && node.showCallout ? 320.0 : pinWidth;
      final markerHeight = selected && node.showCallout
          ? 238.0
          : pinStyle.markerHeight;
      final hasPlaceName = node.placeLabel.isNotEmpty;

      return Marker(
        point: node.point,
        width: markerWidth,
        height: markerHeight,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: markerWidth,
          height: markerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (selected && widget.showSelectedCallout && node.showCallout)
                Positioned(
                  bottom: pinStyle.visualHeight + 12,
                  child: EventShortPopup(
                    event: event,
                    shortText: shortText,
                    maxWidth: 268,
                    onClose: widget.onCloseSelectedCallout,
                    onOpenDetail: widget.onOpenDetail == null
                        ? null
                        : () => widget.onOpenDetail!(event.id),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onSelectEvent(event.id),
                child: SizedBox(
                  width: pinWidth,
                  height: pinStyle.markerHeight,
                  child: _CompactPinMarker(
                    characterCodes: node.characterCodes,
                    characterColors: node.characterColors,
                    selected: selected,
                    style: pinStyle,
                    avatarAssetForCharacter: widget.avatarAssetForCharacter,
                    // popKey 를 (runId, eventId) 로 묶음 → replayReveal() 로 runId
                    // 가 증가할 때마다 새 ValueKey 가 되어 TweenAnimationBuilder 가
                    // scale 0→1 애니메이션을 처음부터 다시 돌린다. 단순 토글로
                    // events 만 바뀌면 runId 가 그대로라 깜빡이지 않음.
                    popKey: '${_revealRunId}_${event.id}_${node.placeLabel}',
                  ),
                ),
              ),
              if (hasPlaceName)
                Positioned(
                  bottom: -24,
                  child: IgnorePointer(
                    child: _buildPlaceChip(node.placeLabel, selected: selected),
                  ),
                ),
              if (node.characterColors.length > 1)
                Positioned(
                  bottom: hasPlaceName ? -40 : -16,
                  child: IgnorePointer(
                    child: _buildCharacterColorDots(node.characterColors),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPlaceChip(String placeName, {required bool selected}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? Colors.black.withValues(alpha: 0.88)
            : const Color(0xCC1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        placeName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF6ECD7),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCharacterColorDots(List<Color> colors) {
    return SizedBox(
      width: 84,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: -2,
        children: colors
            .map(
              (color) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.65),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // 순수 함수들은 lib/utils/map_math.dart로 추출됨.
  // - hasMultiPlacePin, splitPlaceParts, buildSplitPinPoints,
  //   buildAdjustedPoints, easeInOut, mercatorY, normalizedLongitudeDelta,
  //   rotateOffset, eventListSignature

  List<Marker> _buildRegionLabels() {
    final labels = <(String, LatLng)>[
      ('가나안', const LatLng(31.7, 35.2)),
      ('애굽', const LatLng(30.8, 31.2)),
      ('시내 광야', const LatLng(28.7, 33.6)),
      ('바벨론', const LatLng(32.54, 44.42)),
      ('바사', const LatLng(32.2, 48.2)),
    ];

    return labels
        .map(
          (label) => Marker(
            point: label.$2,
            width: 72,
            height: 24,
            child: IgnorePointer(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xAA1D1D1D),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.fgOnDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  Future<void> _loadCountryBoundaries() async {
    const countryKo = <String, String>{
      'Egypt': '이집트',
      'Israel': '이스라엘',
      'Jordan': '요르단',
      'Lebanon': '레바논',
      'Syria': '시리아',
      'Iraq': '이라크',
      'Iran': '이란',
      'Saudi Arabia': '사우디아라비아',
      'Turkey': '튀르키예',
      'Cyprus': '키프로스',
      // Europe (Paul's journey region)
      'Greece': '그리스',
      'Italy': '이탈리아',
      'Malta': '몰타',
      'Albania': '알바니아',
      'North Macedonia': '북마케도니아',
      'Bulgaria': '불가리아',
      'Romania': '루마니아',
      'Republic of Serbia': '세르비아',
      'Montenegro': '몬테네그로',
      'Bosnia and Herzegovina': '보스니아',
      'Croatia': '크로아티아',
    };

    try {
      final raw = await rootBundle.loadString(
        'assets/maps/ne_50m_admin_0_countries.geojson',
      );
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final features = (json['features'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();

      final borderPolylines = <Polyline>[];
      final labelMarkers = <Marker>[];
      final landRings = <List<LatLng>>[];

      for (final feature in features) {
        final properties =
            feature['properties'] as Map<String, dynamic>? ?? const {};
        final name = properties['ADMIN'] as String?;
        final nameKo = name == null ? null : countryKo[name];
        if (nameKo == null) {
          continue;
        }

        final geometry =
            feature['geometry'] as Map<String, dynamic>? ?? const {};
        final type = geometry['type'] as String?;
        final coordinates = geometry['coordinates'];
        if (type == null || coordinates == null) {
          continue;
        }

        final rings = <List<LatLng>>[];
        if (type == 'Polygon') {
          rings.addAll(_parsePolygonRings(coordinates));
        } else if (type == 'MultiPolygon') {
          final polygons = coordinates as List<dynamic>;
          for (final polygon in polygons) {
            rings.addAll(_parsePolygonRings(polygon));
          }
        } else {
          continue;
        }

        if (rings.isEmpty) {
          continue;
        }

        for (final ring in rings) {
          if (ring.length < 3) {
            continue;
          }
          borderPolylines.add(
            Polyline(
              points: [...ring, ring.first],
              color: const Color(0xA05A4A33),
              strokeWidth: 1.05,
            ),
          );
          landRings.add(ring);
        }

        final labelPoint = _labelPoint(properties, rings.first);
        labelMarkers.add(_countryLabelMarker(nameKo, labelPoint));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _countryBorderPolylines = borderPolylines;
        _countryLabelMarkers = labelMarkers;
        _landRings = landRings;
      });
    } catch (_) {
      // Keep map usable even if GeoJSON parsing fails.
    }
  }

  List<List<LatLng>> _parsePolygonRings(dynamic polygonCoordinates) {
    final rings = <List<LatLng>>[];
    final polygon = polygonCoordinates as List<dynamic>;
    for (final ringRaw in polygon) {
      final ringPoints = <LatLng>[];
      for (final coordRaw in (ringRaw as List<dynamic>)) {
        final coord = coordRaw as List<dynamic>;
        if (coord.length < 2) {
          continue;
        }
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        ringPoints.add(LatLng(lat, lng));
      }
      if (ringPoints.length >= 3) {
        rings.add(ringPoints);
      }
    }
    return rings;
  }

  LatLng _labelPoint(Map<String, dynamic> properties, List<LatLng> ring) {
    final labelX = properties['LABEL_X'] as num?;
    final labelY = properties['LABEL_Y'] as num?;
    if (labelX != null && labelY != null) {
      return LatLng(labelY.toDouble(), labelX.toDouble());
    }

    var latSum = 0.0;
    var lngSum = 0.0;
    for (final point in ring) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    return LatLng(latSum / ring.length, lngSum / ring.length);
  }

  Marker _countryLabelMarker(String nameKo, LatLng point) {
    return Marker(
      point: point,
      width: 86,
      height: 24,
      child: IgnorePointer(
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xBFEDE2CC),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xAA6B5438), width: 0.8),
          ),
          child: Text(
            nameKo,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF3A2D1D),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _startRevealAnimation() {
    _revealRunId += 1;
    final runId = _revealRunId;
    _revealTimer?.cancel();
    _cameraTimer?.cancel();

    final withCoordinate = widget.events
        .where((event) => event.hasCoordinate)
        .toList();
    if (withCoordinate.isEmpty) {
      setState(() => _visibleCount = 0);
      return;
    }

    if (!widget.animateReveal) {
      setState(() => _visibleCount = withCoordinate.length);
      return;
    }

    setState(() => _visibleCount = 1);

    final adjusted = map_math.buildAdjustedPoints(withCoordinate);
    final points = withCoordinate
        .map((event) => adjusted[event.id] ?? event.latLng)
        .toList();
    final bounds = LatLngBounds.fromPoints(points);
    // Slightly wider framing: zoom out one step from current auto-focus.
    final animationZoom = (_computeRevealZoom(points) - 1.0).clamp(2.4, 13.0);
    _focusToPoint(
      bounds.center,
      animationZoom,
      duration: const Duration(milliseconds: 700),
    );

    if (withCoordinate.length == 1) {
      return;
    }

    // 카메라가 era-fit 으로 자리잡은 뒤 핀을 한 개씩 시간 순서대로 떨어뜨린다.
    // 이전처럼 사건 ↔ 사건 사이를 점선이 이동하지 않으므로 _segmentT 는 더 이상
    // 의미가 없고, _visibleCount 만 일정 간격으로 증가시킨다.
    Future.delayed(const Duration(milliseconds: 730), () {
      if (!mounted || runId != _revealRunId) {
        return;
      }

      _revealTimer = Timer.periodic(const Duration(milliseconds: 280), (timer) {
        if (!mounted || runId != _revealRunId) {
          timer.cancel();
          return;
        }

        setState(() {
          _visibleCount = math.min(_visibleCount + 1, withCoordinate.length);
        });

        if (_visibleCount >= withCoordinate.length) {
          timer.cancel();
        }
      });
    });
  }

  void _focusSelectedEventIfNeeded({bool force = false}) {
    if (!_mapReady) {
      return;
    }
    if (!widget.showSelectedCallout) {
      return;
    }
    final selectedEventId = widget.selectedEventId;
    if (selectedEventId == null) {
      return;
    }

    final withCoordinate = widget.events
        .where((event) => event.hasCoordinate)
        .toList();
    final selectedEvent = withCoordinate
        .where((event) => event.id == selectedEventId)
        .firstOrNull;
    if (selectedEvent == null) {
      return;
    }

    final adjusted = map_math.buildAdjustedPoints(withCoordinate);
    final selectedPoint = adjusted[selectedEvent.id] ?? selectedEvent.latLng;
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final size = camera.nonRotatedSize;
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final selectedOffset = camera.latLngToScreenOffset(selectedPoint);
    final selectedMarkerHeight = _scaledPinStyle(
      _selectedPinStyle,
    ).visualHeight;
    final obscuredBottom =
        size.height * widget.bottomObscuredFraction.clamp(0.0, 0.82);
    final obscuredTop = widget.topObscuredPixels.clamp(0.0, size.height * 0.45);
    final minimumCalloutTop = math.max(
      _selectedCalloutTopMargin,
      obscuredTop + 12,
    );
    final calloutTop =
        selectedOffset.dy -
        selectedMarkerHeight -
        _selectedCalloutEstimatedHeight;
    final minimumPointY =
        selectedMarkerHeight +
        _selectedCalloutEstimatedHeight +
        minimumCalloutTop;
    final horizontalMargin = math.min(
      (size.width / 2) - 12,
      (_selectedCalloutEstimatedWidth / 2) + 20,
    );
    final verticalBottomMargin = math.max(28.0, selectedMarkerHeight * 0.95);
    final visibleBottom = math.max(
      minimumPointY + verticalBottomMargin + 8,
      size.height - obscuredBottom - 12,
    );
    final outOfHorizontalBounds =
        selectedOffset.dx < horizontalMargin ||
        selectedOffset.dx > size.width - horizontalMargin;
    final outOfVerticalBounds =
        selectedOffset.dy < minimumPointY ||
        selectedOffset.dy > visibleBottom - verticalBottomMargin;
    final needsFocus =
        calloutTop < minimumCalloutTop ||
        outOfHorizontalBounds ||
        outOfVerticalBounds;
    if (!needsFocus && !force) {
      return;
    }

    final minCalloutCenterY =
        minimumCalloutTop + (_selectedCalloutEstimatedHeight / 2);
    final maxCalloutCenterY =
        visibleBottom - (_selectedCalloutEstimatedHeight / 2) - 18;
    final desiredCalloutCenterY =
        (minCalloutCenterY + ((maxCalloutCenterY - minCalloutCenterY) * 0.42))
            .clamp(minCalloutCenterY, maxCalloutCenterY);
    final desiredPointY =
        desiredCalloutCenterY +
        (_selectedCalloutEstimatedHeight / 2) +
        selectedMarkerHeight +
        10;
    final maxPointY = math.max(
      minimumPointY,
      visibleBottom - verticalBottomMargin,
    );
    final targetY = desiredPointY.clamp(minimumPointY, maxPointY);
    final targetOffset = Offset(size.width / 2, targetY);
    final targetZoom = math.min(math.max(camera.zoom, 6.6), 7.7);
    final targetCenter = _targetCenterForPointAtScreenOffset(
      geoPoint: selectedPoint,
      targetOffset: targetOffset,
      zoom: targetZoom,
    );
    _focusToPoint(
      targetCenter,
      targetZoom,
      duration: const Duration(milliseconds: 520),
    );
  }

  void _centerSelectedEvent() {
    if (!_mapReady) {
      return;
    }
    final selectedEventId = widget.selectedEventId;
    if (selectedEventId == null) {
      return;
    }
    final withCoordinate = widget.events
        .where((event) => event.hasCoordinate)
        .toList();
    final selectedEvent = withCoordinate
        .where((event) => event.id == selectedEventId)
        .firstOrNull;
    if (selectedEvent == null) {
      return;
    }
    final selectedPoint = selectedEvent.latLng;
    final targetZoom = (widget.selectedFocusZoom ?? widget.initialZoom ?? 7.0)
        .clamp(2.4, 13.0);
    _focusToPoint(
      selectedPoint,
      targetZoom,
      duration: const Duration(milliseconds: 280),
    );
  }

  void _focusAllEvents({
    Duration duration = const Duration(milliseconds: 360),
  }) {
    if (!_mapReady) {
      return;
    }
    final visibleEvents = widget.events
        .where((event) => event.hasCoordinate)
        .toList(growable: false);
    if (visibleEvents.isEmpty) {
      return;
    }
    if (visibleEvents.length == 1) {
      final singleZoom = ((widget.initialZoom ?? 5.3) + 0.35).clamp(2.4, 13.0);
      _focusToPoint(visibleEvents.first.latLng, singleZoom, duration: duration);
      return;
    }

    final rawPoints = visibleEvents.map((event) => event.latLng).toList();
    final adjustedPointsById = map_math.buildAdjustedPoints(visibleEvents);
    final fittedPoints = visibleEvents
        .map((event) => adjustedPointsById[event.id] ?? event.latLng)
        .toList(growable: false);
    final bounds = LatLngBounds.fromPoints(fittedPoints);
    final rawBounds = LatLngBounds.fromPoints(rawPoints);
    final rawLonSpan = map_math
        .normalizedLongitudeDelta(rawBounds.west, rawBounds.east)
        .abs();
    final rawLatSpan = (rawBounds.north - rawBounds.south).abs();
    final isTightlyClustered = rawLonSpan < 0.35 && rawLatSpan < 0.28;
    final zoomAdjust = widget.fitAllZoomAdjust.clamp(-2.0, 2.0);
    var fittedZoom = (_computeRevealZoom(fittedPoints) + zoomAdjust).clamp(
      2.4,
      13.0,
    );
    if (isTightlyClustered) {
      fittedZoom = math.min(fittedZoom, 7.15);
    }
    _focusToPoint(bounds.center, fittedZoom, duration: duration);
  }

  LatLng _targetCenterForPointAtScreenOffset({
    required LatLng geoPoint,
    required Offset targetOffset,
    required double zoom,
  }) {
    final camera = _safeCamera();
    if (camera == null) {
      return geoPoint;
    }
    final projectedPoint = camera.projectAtZoom(geoPoint, zoom);
    final viewportCenter = camera.nonRotatedSize.center(Offset.zero);
    final offsetFromCenter = map_math.rotateOffset(
      targetOffset - viewportCenter,
      camera.rotationRad,
    );
    final projectedCenter = projectedPoint - offsetFromCenter;
    return camera.unprojectAtZoom(projectedCenter, zoom);
  }

  void _focusToPoint(
    LatLng point,
    double zoom, {
    Duration duration = const Duration(milliseconds: 600),
  }) {
    if (!_mapReady) {
      return;
    }
    final current = _safeCamera();
    if (current == null) {
      return;
    }
    final startCenter = current.center;
    final startZoom = current.zoom;
    if (startCenter == point && (startZoom - zoom).abs() < 0.001) {
      return;
    }

    _cameraTimer?.cancel();
    final startAt = DateTime.now();
    final durationMs = duration.inMilliseconds;

    _cameraTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final t = (DateTime.now().difference(startAt).inMilliseconds / durationMs)
          .clamp(0.0, 1.0);
      final eased = map_math.easeInOut(t);

      final next = LatLng(
        startCenter.latitude + (point.latitude - startCenter.latitude) * eased,
        startCenter.longitude +
            (point.longitude - startCenter.longitude) * eased,
      );
      final nextZoom = startZoom + (zoom - startZoom) * eased;
      if (!_mapReady) {
        timer.cancel();
        return;
      }
      _controller.move(next, nextZoom);

      if (t >= 1.0) {
        timer.cancel();
        _cameraTimer = null;
      }
    });
  }

  void zoomIn() {
    if (!_mapReady) {
      return;
    }
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final targetZoom = (camera.zoom + 0.7).clamp(2.4, 13.0);
    _focusToPoint(
      camera.center,
      targetZoom,
      duration: const Duration(milliseconds: 420),
    );
  }

  void zoomOut() {
    if (!_mapReady) {
      return;
    }
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final targetZoom = (camera.zoom - 0.7).clamp(2.4, 13.0);
    _focusToPoint(
      camera.center,
      targetZoom,
      duration: const Duration(milliseconds: 420),
    );
  }

  void skipAnimation() {
    final all = widget.events.where((event) => event.hasCoordinate).toList();
    _revealTimer?.cancel();
    setState(() => _visibleCount = all.isEmpty ? 0 : all.length);
  }

  /// 외부 트리거로 reveal 을 처음부터 재생. 현재 events 가 그대로여도 애니메이션
  /// 을 다시 보여주고 싶을 때 (예: step 3 "다음" 버튼).
  void replayReveal() {
    _startRevealAnimation();
  }

  /// 토글류 변화로 events 가 바뀌었을 때 핀을 즉시 모두 노출. 시간 순 애니메이션
  /// 없이 "선택 즉시 핀이 박혀 보이는" 상태를 유지한다.
  void _showAllPinsImmediately() {
    _revealTimer?.cancel();
    final count = widget.events.where((event) => event.hasCoordinate).length;
    setState(() => _visibleCount = count);
  }

  /// 핀 badge 에 얼굴 띄울 인물 코드들 — 사건 출연자 ∩ 현재 선택된 인물.
  /// 선택 인물이 한 명도 출연하지 않으면 빈 리스트 (badge 는 dot fallback).
  List<String> _pinCharacterCodes(StoryEvent event) {
    if (event.characterCodes.isEmpty) return const [];
    final selected = widget.selectedCharacterCodes;
    final codes = <String>[];
    final seen = <String>{};
    for (final code in event.characterCodes) {
      if (!selected.contains(code)) continue;
      if (seen.add(code)) codes.add(code);
    }
    return codes;
  }

  List<Color> _colorsForEvent(StoryEvent event) {
    if (event.characterCodes.isNotEmpty) {
      final colors = <Color>[];
      final seen = <Color>{};
      for (final code in event.characterCodes.where(
        widget.selectedCharacterCodes.contains,
      )) {
        final color = widget.colorForCharacter(code);
        if (seen.add(color)) {
          colors.add(color);
        }
      }
      if (colors.isNotEmpty) {
        return colors;
      }
    }
    return [const Color(0xFF6C5A44)];
  }

  double _computeRevealZoom(List<LatLng> points) {
    const minZoom = 2.4;
    const maxZoom = 13.0;
    final baseZoom = widget.initialZoom ?? 5.3;
    if (points.isEmpty) {
      return baseZoom.clamp(minZoom, maxZoom);
    }
    if (points.length == 1) {
      return math.max(baseZoom, 8.8).clamp(minZoom, maxZoom);
    }

    final bounds = LatLngBounds.fromPoints(points);
    final lonSpan = map_math
        .normalizedLongitudeDelta(bounds.west, bounds.east)
        .clamp(0.000001, 360.0);
    final northY = map_math.mercatorY(bounds.north);
    final southY = map_math.mercatorY(bounds.south);
    final latFraction = (southY - northY).abs().clamp(0.000001, 1.0);

    final viewportWidth = math.max(180.0, _lastMapSize.width * 0.86);
    final viewportHeight = math.max(180.0, _lastMapSize.height * 0.72);

    final zoomForLon =
        math.log((viewportWidth * 360.0) / (lonSpan * 256.0)) / math.ln2;
    final zoomForLat =
        math.log(viewportHeight / (latFraction * 256.0)) / math.ln2;

    final fittedZoom = math.min(zoomForLon, zoomForLat) - 0.2;
    return fittedZoom.clamp(minZoom, maxZoom);
  }

  dynamic _safeCamera() {
    try {
      return _controller.camera;
    } catch (_) {
      return null;
    }
  }
}

class StoryMapPanelController {
  _StoryMapPanelState? _state;

  void _bind(_StoryMapPanelState state) {
    _state = state;
  }

  void _unbind(_StoryMapPanelState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void zoomIn() => _state?.zoomIn();

  void zoomOut() => _state?.zoomOut();

  void skipAnimation() => _state?.skipAnimation();

  /// "다음" 버튼처럼 외부 트리거로 핀 reveal 애니메이션을 다시 재생한다.
  /// 현재 visibleCount 를 0 으로 되돌리고 첫 핀부터 시간 순으로 다시 박힘.
  void replayReveal() => _state?.replayReveal();

  void focusSelectedEvent({bool force = true}) =>
      _state?._focusSelectedEventIfNeeded(force: force);

  /// 외부(랜드마크 목록 패널)에서 특정 좌표로 카메라를 옮기고 싶을 때 사용.
  void focusLandmark(LatLng point) => _state?._focusLandmark(point);
}

/// 지도 우상단의 "현 지도에서 검색" 플로팅 버튼.
/// 네이버 지도의 동일 버튼과 비슷한 컨셉.
class _ViewportSearchButton extends StatelessWidget {
  const _ViewportSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF8C5A2E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 16, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '현 지도에서 검색',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 결과가 표시 중일 때 같은 자리에 나오는 "✕ 검색 취소 (N개)" 버튼.
class _ViewportSearchClearButton extends StatelessWidget {
  const _ViewportSearchClearButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3D2A14),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.close, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                '검색 취소 ($count개)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 거리 측정 모드 토글 버튼 (우상단 검색 버튼 아래).
class _MeasureToggleButton extends StatelessWidget {
  const _MeasureToggleButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6B35) : const Color(0xFF7B5D43),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.straighten, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                active ? '거리 재기 종료' : '거리 재기',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 거리 측정 모드 안내 + 진행 상태 표시.
class _MeasureHintBanner extends StatelessWidget {
  const _MeasureHintBanner({required this.first, required this.second});

  final Landmark? first;
  final Landmark? second;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (first == null) {
      text = '시작 랜드마크를 탭하세요';
    } else if (second == null) {
      text = '${first!.name} → 도착 랜드마크 탭';
    } else {
      text = '${first!.name} → ${second!.name}';
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6B35), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF3D2A14),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// 검색 결과 핀의 인물 아바타 1~3명 겹쳐 보여주는 위젯.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({
    required this.characterCodes,
    required this.avatarAssetForCharacter,
  });

  final List<String> characterCodes;
  final String Function(String characterId) avatarAssetForCharacter;

  static const double _avatarSize = 24;
  static const double _stackOverlap = 9;

  @override
  Widget build(BuildContext context) {
    final visible = characterCodes.take(3).toList();
    final width =
        _avatarSize +
        (visible.length - 1).clamp(0, 2) * (_avatarSize - _stackOverlap);
    return SizedBox(
      width: width.toDouble(),
      height: _avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (_avatarSize - _stackOverlap),
              child: Container(
                width: _avatarSize,
                height: _avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEEDFC4),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 1.5),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _AvatarImage(
                  assetPath: avatarAssetForCharacter(visible[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 선택 인물 색깔 범례 — 지도 좌상단 카드. 색깔 dot + 이름 가로 나열.
/// 인물이 5명 이상이면 두 줄로 wrap. 선택 인물이 0명이면 빌드 안 됨.
class _CharacterColorLegend extends StatelessWidget {
  const _CharacterColorLegend({
    required this.codes,
    required this.colorForCharacter,
    required this.nameForCharacter,
  });

  final Set<String> codes;
  final Color Function(String characterCode) colorForCharacter;
  final String Function(String characterCode)? nameForCharacter;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB89A66), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          for (final code in codes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorForCharacter(code),
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x44000000), blurRadius: 1.5),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  nameForCharacter?.call(code) ?? code,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3D2A14),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 시대 미리보기 path 끝점에 그리는 ▶ 모양 화살촉. 색은 인물의 path 색.
class _ArrowHeadPainter extends CustomPainter {
  _ArrowHeadPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true;

    // ▶ 모양 — 오른쪽 가운데 꼭짓점, 왼쪽 위/아래 꼭짓점.
    // dart:ui Path 를 명시 (flutter_map 의 Path<LatLng> 와 충돌 회피).
    final path = ui.Path()
      ..moveTo(size.width * 0.95, size.height * 0.5)
      ..lineTo(size.width * 0.20, size.height * 0.18)
      ..lineTo(size.width * 0.40, size.height * 0.5)
      ..lineTo(size.width * 0.20, size.height * 0.82)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowHeadPainter old) => old.color != color;
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    if (assetPath.isEmpty) {
      return const Icon(Icons.person, size: 14, color: Color(0xFF8C5A2E));
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.person, size: 14, color: Color(0xFF8C5A2E)),
    );
  }
}
