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
import '../theme/era_colors.dart';
import '../theme/tokens.dart';
import '../utils/map_math.dart' as map_math;
import 'map_deco_layer.dart';
import 'parchment_multiply_layer.dart';
import 'shared/event_short_popup.dart';

// 핀 마커 위젯/데이터 클래스를 별도 파트 파일로 분리.
part 'map/pin_marker.dart';

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

/// 폴리곤 bbox 면적 (단위: deg²) — 정확한 면적이 아니라 폴리곤 hit 우선순위
/// 비교용. 작은 region (예: 밧단아람) 이 큰 region (예: 메소포타미아) 안에
/// 있을 때 작은 쪽이 hit 우선이 되도록 면적 정렬에 쓰인다.
double _polygonBboxArea(Landmark lm) {
  final pts = lm.polygon;
  if (pts.length < 3) return double.maxFinite; // polygon 없으면 가장 큰 값으로
  var minLat = pts.first.latitude;
  var maxLat = minLat;
  var minLng = pts.first.longitude;
  var maxLng = minLng;
  for (final p in pts) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return (maxLat - minLat) * (maxLng - minLng);
}

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
    this.activeEraBoundaries = const [],
    this.onLandmarkTap,
    this.onMeasureResult,
    this.eraPreviewEvents = const [],
    this.hullEvents = const [],
    this.eraRegionLandmarks = const [],
    this.selectedLandmarkId,
    this.revealEventsKey,
    this.revealInstantly = false,
    this.onRevealComplete,
    this.nameForCharacter,
    this.eraCodeForId,
    this.eventCountByLandmarkId,
  });

  /// 현재 선택된 region/landmark id. 선택된 region 핀에 ripple 애니메이션 활성.
  final String? selectedLandmarkId;

  /// 사건 핀 0.3초 순차 reveal 트리거 키. 같은 키면 reveal 재시작 안 함.
  /// 부모가 region 변경/인물 변경/step 진입마다 새 키를 넘기면 reveal 재시작.
  /// null 이면 reveal 안 함 (또는 selectedLandmarkId 변화로 폴백).
  final String? revealEventsKey;

  /// true 면 0.3초 순차 reveal 을 건너뛰고 즉시 모든 핀을 보여 줌. 사용자가
  /// reveal 도중 panel ^ 클릭으로 수동 expand 했을 때 부모가 toggle 한다.
  final bool revealInstantly;

  /// 핀 reveal 이 마지막 핀까지 도달했을 때 1회 호출. 부모는 이 콜백으로
  /// panel 을 자동 expand 한다. (수동 expand 시 [revealInstantly]=true 로
  /// 즉시 reveal 된 경우에도 동일하게 호출.)
  final VoidCallback? onRevealComplete;

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

  /// 시대 영역(dynamic hull) 폴리곤을 빌드할 입력 사건들. 인물 모드 + 인물
  /// 선택 시 그 인물 사건만 넘겨 폴리곤을 사건 분포에 정확히 맞춰 잡는다.
  /// 비어 있으면 [eraPreviewEvents] 로 폴백.
  final List<StoryEvent> hullEvents;

  /// 현재 시대(activeEraBoundaries 의 eraId 들)에 속하는 region 종류 landmark.
  /// 이 region 들의 polygon 합집합을 시대 영역 폴리곤으로 그린다 (사건 hull
  /// 대신). 비어 있으면 폴리곤 미표시.
  final List<Landmark> eraRegionLandmarks;

  /// 인물 코드 → 표시 이름 반환. legend 에서 사용. null 이면 코드를 이름으로
  /// 사용 (fallback).
  final String Function(String characterCode)? nameForCharacter;

  /// era_id (uuid) → era_code (text) 매핑. 시대 폴리곤 색상을 [EraColors]
  /// 와 동일하게 맞추기 위함. null 이면 era_id 자체로 fallback.
  final String? Function(String eraId)? eraCodeForId;

  /// region 마커 라벨에 표시할 사건 개수 — landmark.id → count.
  /// 부모가 region(+ 자식 anchor/minor + alias_group) 사건 합산해 넘겨 준다.
  /// null 이거나 키 없으면 배지 미표시.
  final Map<String, int>? eventCountByLandmarkId;

  @override
  State<StoryMapPanel> createState() => _StoryMapPanelState();
}

class _StoryMapPanelState extends State<StoryMapPanel> {
  final MapController _controller = MapController();
  Timer? _revealTimer;
  Timer? _cameraTimer;
  List<Polyline> _countryBorderPolylines = const [];
  List<Marker> _countryLabelMarkers = const [];
  int _visibleCount = 0;
  Size _lastMapSize = const Size(900, 600);
  int _revealRunId = 0;
  bool _mapReady = false;

  /// 시대 region 폴리곤 클릭 hit-test 용. flutter_map 8.x 의 hitNotifier API.
  /// Polygon 에 hitValue=Landmark 부여 → 사용자가 onTap 시 hitValue 로 어떤
  /// region 이 눌렸는지 식별.
  final LayerHitNotifier<Landmark> _polygonHitNotifier = LayerHitNotifier(null);

  /// 사건 핀 0.3초 순차 reveal 카운터. revealEventsKey 또는 selectedLandmarkId
  /// 가 변경되면 0 으로 리셋 후 매 300ms +1.
  int _eventRevealCount = 0;
  Timer? _eventRevealTimer;
  String? _lastRevealKey;

  /// 시간순 번호 핀 모드 활성 여부 — region 선택 OR revealEventsKey set.
  bool get _orderedEventsActive =>
      widget.selectedLandmarkId != null ||
      (widget.revealEventsKey != null && widget.revealEventsKey!.isNotEmpty);

  /// 거리 측정 모드. true 면 랜드마크 탭이 측정 시작/끝점 선택으로 바뀐다.
  // v3 — 거리 재기 기능 제거. 호환을 위해 final false 로 남겨둠 (기존 분기 dead).
  final bool _measureMode = false;
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
    _eventRevealTimer?.cancel();
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

    // 사건 핀 0.3초 순차 reveal 트리거 — revealEventsKey 또는 selectedLandmarkId
    // 가 변경되면 reveal 재시작 (region 모드/character step 3 모두 대응).
    final newKey = widget.revealEventsKey ?? widget.selectedLandmarkId;
    if (newKey != _lastRevealKey) {
      _lastRevealKey = newKey;
      _eventRevealTimer?.cancel();
      _eventRevealCount = 0;
      if (newKey != null && newKey.isNotEmpty) {
        final total = widget.events.where((e) => e.hasCoordinate).length;
        if (total > 0) {
          if (widget.revealInstantly) {
            // 수동 expand 등으로 즉시 reveal 요청 — Timer 스킵, 한 번에 노출.
            _eventRevealCount = total;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onRevealComplete?.call();
            });
          } else {
            _eventRevealTimer = Timer.periodic(
              const Duration(milliseconds: 300),
              (timer) {
                if (!mounted) {
                  timer.cancel();
                  return;
                }
                if (_eventRevealCount >= total) {
                  timer.cancel();
                  // 마지막 핀까지 노출 완료 — 부모에게 알려 panel auto-expand.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) widget.onRevealComplete?.call();
                  });
                  return;
                }
                setState(() => _eventRevealCount++);
              },
            );
          }
        }
      }
    } else if (widget.revealInstantly && !oldWidget.revealInstantly) {
      // 같은 reveal 키 안에서 instant 토글 — 진행 중인 stagger 를 건너뛰고
      // 즉시 모든 핀 노출. 사용자 ^ 클릭 케이스.
      _eventRevealTimer?.cancel();
      final total = widget.events.where((e) => e.hasCoordinate).length;
      if (total > 0) {
        setState(() => _eventRevealCount = total);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onRevealComplete?.call();
        });
      }
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
                  // 지도 빈 곳 또는 폴리곤 위 클릭 시 호출. 폴리곤 hit 가 있으면
                  // 그 region 을 선택. 마커 클릭은 자체 GestureDetector 가 먼저
                  // 처리하므로 onTap 은 빈 곳 + 폴리곤 위만 잡는다.
                  onTap: (tapPos, latlng) {
                    final hit = _polygonHitNotifier.value;
                    if (hit != null && hit.hitValues.isNotEmpty) {
                      // 여러 폴리곤이 동시에 hit 되면 가장 작은(specific) 폴리곤
                      // 우선. 예: 메소포타미아 안의 밧단아람을 클릭하면 밧단아람
                      // 이 선택돼야 함. polygon 면적 = lat-bbox * lng-bbox 근사.
                      Landmark pick = hit.hitValues.first;
                      double pickArea = _polygonBboxArea(pick);
                      for (final lm in hit.hitValues.skip(1)) {
                        final a = _polygonBboxArea(lm);
                        if (a < pickArea) {
                          pick = lm;
                          pickArea = a;
                        }
                      }
                      // 사건 0 region 은 클릭 비활성 (회색 핀과 일관).
                      final cnt = widget.eventCountByLandmarkId?[pick.id] ?? 0;
                      if (cnt == 0) return;
                      widget.onLandmarkTap?.call(pick);
                    }
                  },
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
                  // 양피지/세피아 톤 + 강·바다 파랑 (Carto voyager_nolabels).
                  // 이전에 G 채널만 약화하는 ColorFilter.matrix 를 시도했으나
                  // 베이지(R~G~B 비슷한 영역) 에서 G 만 줄이면 R/B 가 dominant
                  // 가 되어 land 전체가 핑크/보라로 변색되는 부작용. 매트릭스
                  // 는 폐기하고 단순 sepia overlay 만 사용 — voyager 의
                  // 산림 연두는 sepia 에 살짝 묻히면서 부드러운 베이지·올리브
                  // 톤이 된다.
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.story.bible',
                    tileBuilder: (context, tileWidget, _) {
                      // v3.7 — desaturate 매트릭스 완전히 제거. 매트릭스 자체가
                      // 채도를 깎아 (a) 화면을 뿌옇게 만들고 (b) water 의 blue
                      // 를 회색으로 죽임. voyager 의 자연 컬러를 그대로 두고
                      // 매우 가벼운 tan multiply (α 13%) 만 더해 살짝 sepia 톤.
                      // water blue 가 vibrant 하게 살아남고 land 는 부드럽게
                      // warm 해진다. 양피지 입자감은 ParchmentTextureLayer
                      // (화면 오버레이) 가 담당.
                      return ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0x22A88555), // 알파 13%, very light tan
                          BlendMode.multiply,
                        ),
                        child: tileWidget,
                      );
                    },
                  ),
                  PolylineLayer(polylines: _countryBorderPolylines),
                  // 시대 영역 폴리곤 — 그 시대의 region 들의 polygon 합집합을
                  // 같은 시대 색으로 칠해 표시. hitNotifier 로 클릭 hit-test
                  // 정보를 노출하고, MapOptions.onTap 에서 hit.hitValues 로 어느
                  // region 이 눌렸는지 식별 → onLandmarkTap 호출.
                  if (widget.eraRegionLandmarks.isNotEmpty)
                    PolygonLayer<Landmark>(
                      hitNotifier: _polygonHitNotifier,
                      polygons: _buildEraRegionUnionPolygons(),
                    ),
                  // 양피지 톤 데코 레이어 — 산·도시·나무·피라미드 등 분위기
                  // 일러스트. 시대 필터로 그 시대 데코만 보임. PNG 가 아직 없는
                  // kind 는 자연스럽게 미표시.
                  MapDecoLayer(
                    activeEraCodes: {
                      for (final b in widget.activeEraBoundaries)
                        if (widget.eraCodeForId?.call(b.eraId) != null)
                          widget.eraCodeForId!.call(b.eraId)!,
                      for (final r in widget.eraRegionLandmarks) ...r.eraCodes,
                    },
                  ),
                  MarkerLayer(markers: _countryLabelMarkers),
                  // 시대 미리보기 — 인물별 사건 path 를 색깔 실선으로.
                  // 선택 인물 alpha 0.95 + 굵기 4.5, 미선택 alpha 0.40 + 2.5.
                  // step 3 (_orderedEventsActive) 진입 시에는 dashed path + 번호
                  // 핀이 그 자리를 대체하므로 실선 preview 를 숨겨 화면을 정리.
                  if (widget.eraPreviewEvents.isNotEmpty &&
                      !_orderedEventsActive)
                    PolylineLayer(polylines: _buildEraPreviewPolylines()),
                  if (widget.eraPreviewEvents.isNotEmpty &&
                      !_orderedEventsActive)
                    MarkerLayer(markers: _buildEraPreviewDots()),
                  if (widget.eraPreviewEvents.isNotEmpty &&
                      widget.selectedCharacterCodes.isNotEmpty &&
                      !_orderedEventsActive)
                    MarkerLayer(markers: _buildEraPreviewArrowHeads()),
                  // region(영역) 폴리곤 — 큰 묶음 region 의 polygon 을 시대 색
                  // 으로 채워 어떤 영역이 어디까지 커버하는지 시각화. 사용자가
                  // region 마커 대신 폴리곤을 직접 탭해도 region 선택과 동일하게
                  // 다룰 수 있다 (마커가 폴리곤 위에 겹쳐 그려진다).
                  if (widget.activeLandmarks.isNotEmpty)
                    PolygonLayer(
                      polygons: _buildRegionPolygons(widget.activeLandmarks),
                    ),
                  // 시대별 랜드마크 — 클러스터링 없이 단순 표시. 시대 필터로
                  // 이미 충분히 적어 (15~25개), 클러스터로 묶이는 게 정보를
                  // 압축해 오히려 가린다.
                  if (widget.activeLandmarks.isNotEmpty)
                    MarkerLayer(
                      markers: _buildLandmarkMarkers(
                        _landmarksHidingEventLocations(),
                      ),
                    ),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: _buildRegionLabels()),
                  // 순서 점선 path + 번호 핀 — region 선택이든 character step3
                  // 든 revealEventsKey 가 set 되었으면 활성. widget.events 가
                  // 시간순으로 정렬된 사건들이라고 가정.
                  if (_orderedEventsActive && widget.events.length >= 2)
                    PolylineLayer(
                      polylines: _buildOrderedEventPath(widget.events),
                    ),
                  if (_orderedEventsActive && widget.events.length >= 2)
                    MarkerLayer(
                      markers: _buildOrderedPathArrows(widget.events),
                    ),
                  if (_orderedEventsActive)
                    MarkerLayer(
                      markers: _buildNumberedEventMarkers(widget.events),
                    )
                  else
                    MarkerLayer(markers: _buildMarkers(widget.events)),
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
                  // 비지리적 region 카드 — 종말 환상(하늘 보좌·새 예루살렘 등)
                  // 처럼 polygon 이 빈 region 을 지도 좌하단 카드로 표시.
                  // era_nt_consummation 시대에서만 활성화.
                  if (_nonGeographicRegions.isNotEmpty)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10, bottom: 30),
                        child: _NonGeographicRegionCard(
                          regions: _nonGeographicRegions,
                        ),
                      ),
                    ),
                  // v3 — 우측 상단 검색/거리 측정 버튼 제거. 부모(StoryHomeScreen)
                  // 가 같은 위치에 _SelectionStepper 를 둔다.
                ],
              );
            },
          ),
          // 양피지 grain — BlendMode.multiply 로 paper grain 이 backdrop 에
          // 비침. strength 0.55 로 parchment image 의 flat 영역은 ~white 가
          // 되어 water 같은 균일색 영역은 거의 영향 없음. grain spot 만 land
          // 에 visible.
          const Positioned.fill(child: ParchmentMultiplyLayer(strength: 0.55)),
        ],
      ),
    );
  }

  /// 랜드마크 탭 처리. onLandmarkTap 콜백 (popup) 호출.
  /// (거리 측정 모드는 v3 에서 제거됨.)
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

  /// region polygon 의 모든 정점이 화면에 들어오도록 카메라 fit.
  /// 하단 시트가 가리는 영역(bottomObscuredFraction)만큼 bottom padding 을 늘려
  /// 선택된 region 핀이 시트 위쪽에 보이도록 보정.
  void _focusRegionPolygon(List<LatLng> polygon) {
    if (!_mapReady || polygon.isEmpty) return;
    try {
      double minLat = polygon.first.latitude;
      double maxLat = polygon.first.latitude;
      double minLng = polygon.first.longitude;
      double maxLng = polygon.first.longitude;
      for (final p in polygon) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      // 시트가 화면 아래 가리는 만큼 bottom padding 확장 → 폴리곤이 시트 위로
      // 들리며 핀의 ripple 애니메이션도 가시 영역에 그려진다.
      final bottomGap = (widget.bottomObscuredFraction * _lastMapSize.height)
          .clamp(0.0, 600.0);
      final bottomPadding = math.max(80.0, bottomGap + 60.0);
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat - 0.3, minLng - 0.3),
            LatLng(maxLat + 0.3, maxLng + 0.3),
          ),
          padding: EdgeInsets.fromLTRB(60, 80, 60, bottomPadding),
        ),
      );
    } catch (_) {
      /* 비가용 무시 */
    }
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
  /// 시대 영역 폴리곤 — 그 시대에 속하는 region(kind='region') 들의 polygon 을
  /// 같은 시대 색으로 칠해 [Polygon] 리스트로 반환. flutter_map 은 단일 다각형
  /// 리스트를 union 으로 그릴 별도 API 가 없어, 인접한 region 들이 같은 색·같은
  /// alpha 로 칠해지면 시각적으로 한 덩어리로 보이는 효과를 사용한다.
  ///
  /// 색은 region 의 era_codes 중 현재 표시 중인 시대(eraCodeForId 콜백으로 푼
  /// activeEraBoundaries 의 eraId 가 매칭되는 코드)를 우선 사용해 [EraColors]
  /// 에서 받는다.
  /// 비지리적 region (polygon 빈 배열) — 종말 환상 등. 지도 모서리 카드로
  /// 표시하기 위해 따로 뽑아낸다. eraRegionLandmarks 에서 lat/lng=0 + polygon
  /// 빈 region 들을 필터.
  List<Landmark> get _nonGeographicRegions => widget.eraRegionLandmarks
      .where((lm) => lm.isRegion && lm.polygon.isEmpty)
      .toList(growable: false);

  List<Polygon<Landmark>> _buildEraRegionUnionPolygons() {
    // 현재 표시 중인 시대(들)의 era_code 집합. activeEraBoundaries 가 비어 있으면
    // region 의 첫 era_code 로 폴백.
    final visibleEraCodes = <String>{};
    for (final b in widget.activeEraBoundaries) {
      final code = widget.eraCodeForId?.call(b.eraId);
      if (code != null && code.isNotEmpty) visibleEraCodes.add(code);
    }

    final result = <Polygon<Landmark>>[];
    for (final lm in widget.eraRegionLandmarks) {
      if (!lm.isRegion || lm.polygon.isEmpty) continue;
      final eventCount = widget.eventCountByLandmarkId?[lm.id] ?? 0;
      final disabled = eventCount == 0;
      // 사건 0 region 은 회색·옅게 + hitValue=null 로 클릭 비활성.
      final fillColor = disabled
          ? const Color(0xFF9E9285).withValues(alpha: 0.10)
          : EraColors.forCode(
              lm.eraCodes.firstWhere(
                visibleEraCodes.contains,
                orElse: () => lm.eraCodes.isNotEmpty ? lm.eraCodes.first : '',
              ),
            ).withValues(alpha: 0.22);
      final borderColor = disabled
          ? const Color(0xFFB8B0A4).withValues(alpha: 0.55)
          : EraColors.forCode(
              lm.eraCodes.firstWhere(
                visibleEraCodes.contains,
                orElse: () => lm.eraCodes.isNotEmpty ? lm.eraCodes.first : '',
              ),
            ).withValues(alpha: 0.95);
      result.add(
        Polygon<Landmark>(
          points: lm.polygon,
          color: fillColor,
          borderColor: borderColor,
          borderStrokeWidth: disabled ? 1.2 : 2.0,
          // disabled region 은 hitValue 를 null 로 둘 수 없으니 onTap 단계에서
          // 사건 0 인 region 무시.
          hitValue: lm,
        ),
      );
    }
    return result;
  }

  /// 시대별 랜드마크 마커 빌드.
  /// 이모지 + 작은 라벨. 일반 사건 핀과 시각적으로 구분되게 둥근 캡슐 디자인.
  /// region(영역) 폴리곤 — 사용자가 어떤 영역이 어디까지 커버하는지 직관적으로
  /// 보게 하기 위해 polygon 이 비어있지 않은 region kind landmark 만 렌더.
  /// 색은 region 의 era_codes 첫 시대 → [EraColors] 매핑.
  List<Polygon> _buildRegionPolygons(List<Landmark> landmarks) {
    final polygons = <Polygon>[];
    for (final lm in landmarks) {
      if (!lm.isRegion) continue;
      if (lm.polygon.isEmpty) continue;
      final eraCode = lm.eraCodes.isNotEmpty ? lm.eraCodes.first : null;
      final color = EraColors.forCode(eraCode);
      polygons.add(
        Polygon(
          points: lm.polygon,
          color: color.withValues(alpha: 0.16),
          borderColor: color.withValues(alpha: 0.85),
          borderStrokeWidth: 2.0,
        ),
      );
    }
    return polygons;
  }

  /// 시간순 사건 좌표 — 같은 lat/lng 사건은 [buildAdjustedPoints] 로 살짝
  /// 분산해 핀/path/화살표가 겹치지 않게 한다.
  List<({StoryEvent event, LatLng point})> _adjustedOrderedEventPoints(
    List<StoryEvent> events,
  ) {
    final ordered = events.where((e) => e.hasCoordinate).toList()
      ..sort((a, b) => a.globalRank.compareTo(b.globalRank));
    final visible = ordered.take(_eventRevealCount).toList(growable: false);
    final adjusted = map_math.buildAdjustedPoints(visible);
    return [
      for (final e in visible) (event: e, point: adjusted[e.id] ?? e.latLng),
    ];
  }

  /// region/character 선택 시 사건들을 시간순으로 잇는 점선 path.
  List<Polyline> _buildOrderedEventPath(List<StoryEvent> events) {
    final pts = _adjustedOrderedEventPoints(events);
    if (pts.length < 2) return const [];
    return [
      Polyline(
        points: pts.map((e) => e.point).toList(growable: false),
        color: const Color(0xFF3D6BB8),
        strokeWidth: 2.5,
        pattern: StrokePattern.dashed(segments: const [8, 6]),
      ),
    ];
  }

  /// path 중간 방향 화살표. 두 사건이 서로 너무 가까우면(겹친 좌표) 화살표
  /// 생략 — 회전이 의미 없고 시각만 어수선해짐.
  List<Marker> _buildOrderedPathArrows(List<StoryEvent> events) {
    final pts = _adjustedOrderedEventPoints(events);
    if (pts.length < 2) return const [];
    final result = <Marker>[];
    const minDeltaDeg = 0.05; // 약 5km 이상 떨어진 segment 만 화살표
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i].point;
      final b = pts[i + 1].point;
      final dy = b.latitude - a.latitude;
      final dx = b.longitude - a.longitude;
      if (dx.abs() < minDeltaDeg && dy.abs() < minDeltaDeg) continue;
      final mid = LatLng(
        (a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2,
      );
      final angle = math.atan2(-dy, dx);
      result.add(
        Marker(
          point: mid,
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: Icon(
                Icons.play_arrow,
                size: 36,
                color: const Color(0xFF3D6BB8),
                shadows: [
                  Shadow(
                    color: AppColors.parchmentCream.withValues(alpha: 0.85),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }

  /// region 선택 시 그 region 사건 마커 — 핀 + 큰 순서 번호.
  /// 그림 3 처럼 1, 2, 3... 표시. 클릭 시 onSelectEvent 호출.
  /// _eventRevealCount 만큼만 그려져 0.3초 간격 순차 reveal.
  /// 선택된 사건 핀은 다른 핀들 위(z-order 끝)로 옮겨 가려지지 않게 한다.
  /// 같은 좌표 사건들은 buildAdjustedPoints 로 분산되어 핀이 겹치지 않는다.
  List<Marker> _buildNumberedEventMarkers(List<StoryEvent> events) {
    final pts = _adjustedOrderedEventPoints(events);
    final markers = pts.asMap().entries.map((entry) {
      final order = entry.key + 1;
      final event = entry.value.event;
      final point = entry.value.point;
      final selected = widget.selectedEventId == event.id;
      return _MarkerWithSelection(
        selected: selected,
        marker: _buildSingleEventMarker(event, point, order, selected),
      );
    }).toList();
    // 선택된 사건 핀이 list 마지막 → MarkerLayer 가 마지막을 위에 그림.
    markers.sort((a, b) => (a.selected ? 1 : 0).compareTo(b.selected ? 1 : 0));
    return markers.map((m) => m.marker).toList(growable: false);
  }

  Marker _buildSingleEventMarker(
    StoryEvent event,
    LatLng point,
    int order,
    bool selected,
  ) {
    return Marker(
      point: point,
      width: 80,
      height: 80,
      alignment: Alignment.center,
      child: Builder(
        builder: (context) {
          final zoom = MapCamera.of(context).zoom;
          final scale = (zoom / 8.0).clamp(0.5, 1.0).toDouble();
          return Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectEvent(event.id),
              child: _NumberedEventPin(
                number: order,
                placeName: (event.placeName ?? '').trim(),
                isSelected: selected,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 사건 핀 reveal 중일 때, 사건과 동일 landmark id 의 landmark 마커는
  /// 가린다 (사건 핀이 이미 그 장소를 표현하므로 시각적 중복).
  List<Landmark> _landmarksHidingEventLocations() {
    if (!_orderedEventsActive || widget.events.isEmpty) {
      return widget.activeLandmarks;
    }
    final hidden = <String>{
      for (final e in widget.events) e.landmarkId,
    };
    return widget.activeLandmarks
        .where((lm) => !hidden.contains(lm.id))
        .toList(growable: false);
  }

  List<Marker> _buildLandmarkMarkers(List<Landmark> landmarks) {
    return landmarks
        .map((obj) {
          final isMeasureSelected =
              _measureMode &&
              (obj.code == _measureFirst?.code ||
                  obj.code == _measureSecond?.code);
          // region 핀은 더 큰 location pin + ripple, non-region 은 작은 둥근
          // 아이콘. 둘 다 MapCamera.zoom 에 비례해 축소.
          final isRegion = obj.isRegion;
          final isSelectedRegion =
              isRegion && obj.id == widget.selectedLandmarkId;
          return Marker(
            point: obj.latLng,
            width: isRegion ? 120 : 80,
            height: isRegion ? 110 : 60,
            alignment: Alignment.center,
            child: _ZoomScaledLandmark(
              landmark: obj,
              isMeasureSelected: isMeasureSelected,
              isSelected: isSelectedRegion,
              eventCount: widget.eventCountByLandmarkId?[obj.id] ?? 0,
              onTap: () => _handleLandmarkTap(obj),
            ),
          );
        })
        .toList(growable: false);
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
    double zoomBoost = 0.0,
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
      final singleZoom =
          ((widget.initialZoom ?? 5.3) + 0.35 + zoomBoost).clamp(2.4, 13.0);
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
    // 자동 fit 줌 → tight cluster cap → 그 위에 사용자 요청 zoomBoost.
    // boost 를 cap 보다 먼저 더하면 cap 이 무효화되므로 단계 분리.
    var fittedZoom = (_computeRevealZoom(fittedPoints) + zoomAdjust).clamp(
      2.4,
      13.0,
    );
    if (isTightlyClustered) {
      fittedZoom = math.min(fittedZoom, 7.15);
    }
    fittedZoom = (fittedZoom + zoomBoost).clamp(2.4, 13.0);
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

  /// region polygon 모든 정점이 화면에 들어오도록 카메라 fit.
  void focusRegion(List<LatLng> polygon) =>
      _state?._focusRegionPolygon(polygon);

  /// 사건들의 좌표 영역을 viewport 에 fit + 추가 줌인. 사건 reveal 트리거 시점에
  /// 호출하면 핀이 화면 가운데 모이고 자세히 보인다.
  void focusEvents({double zoomBoost = 1.0}) =>
      _state?._focusAllEvents(zoomBoost: zoomBoost);
}

/// 줌에 비례해 축소되는 landmark 마커. region 인 경우 큰 location pin +
/// ripple 애니메이션 (선택 시), non-region 은 작은 둥근 아이콘.
class _ZoomScaledLandmark extends StatelessWidget {
  const _ZoomScaledLandmark({
    required this.landmark,
    required this.isMeasureSelected,
    required this.isSelected,
    required this.eventCount,
    required this.onTap,
  });

  final Landmark landmark;
  final bool isMeasureSelected;
  final bool isSelected;
  final int eventCount;
  final VoidCallback onTap;

  static const double _baseZoom = 8.0;
  static const double _minScale = 0.4;
  static const double _maxScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.of(context).zoom;
    // region + 사건 0개 → 작게 + 회색 + 클릭 비활성. 새 이야기가 추가되어
    // eventCount > 0 이 되면 자동으로 활성 상태로 전환.
    final disabled = landmark.isRegion && eventCount == 0;
    final disabledScale = disabled ? 0.55 : 1.0;
    final scale =
        (zoom / _baseZoom).clamp(_minScale, _maxScale).toDouble() *
        disabledScale;
    final inner = landmark.isRegion
        ? _RegionPin(
            name: landmark.name,
            eventCount: eventCount,
            isSelected: isSelected,
            disabled: disabled,
          )
        : _PointPin(emoji: landmark.emoji, name: landmark.name);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
        child: ColorFiltered(
          colorFilter: isMeasureSelected
              ? const ColorFilter.mode(Color(0x55FF6B35), BlendMode.srcATop)
              : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: inner,
        ),
      ),
    );
  }
}

/// 사건 마커 + 선택 여부 페어. z-order 정렬 위해 사용.
class _MarkerWithSelection {
  const _MarkerWithSelection({required this.selected, required this.marker});
  final bool selected;
  final Marker marker;
}

/// 사건 핀 — 핀 모양 + 안에 큰 순서 번호 (1, 2, 3...). 핀 아래 작은 장소명.
/// 선택 시 더 큰 사이즈 + 진한 색.
class _NumberedEventPin extends StatelessWidget {
  const _NumberedEventPin({
    required this.number,
    required this.placeName,
    required this.isSelected,
  });

  final int number;
  final String placeName;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final pinColor = isSelected
        ? const Color(0xFF3D6BB8)
        : const Color(0xFF6B4A2A);
    final pinSize = isSelected ? 38.0 : 32.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: pinSize,
          height: pinSize * 1.3,
          child: Stack(
            children: [
              // 핀 모양 — 흰 점 없이 그림 (그 자리에 숫자가 들어가야).
              Positioned.fill(
                child: CustomPaint(
                  painter: _LocationPinPainter(
                    color: pinColor,
                    drawCenterDot: false,
                  ),
                ),
              ),
              // 핀 머리 가운데에 큰 흰 숫자.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: pinSize * 0.9, // 핀 머리 영역
                child: Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: isSelected ? 17 : 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (placeName.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF3D2A14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              placeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF5E9C8),
                height: 1.05,
              ),
            ),
          ),
      ],
    );
  }
}

/// 큰 region 핀 — 위 둥근 머리 + 아래 핀촉 + 라벨. 선택 시 ripple 애니메이션.
/// 라벨 폭이 핀 부모 width 를 넘지 않도록 maxWidth 제약 + ellipsis.
class _RegionPin extends StatelessWidget {
  const _RegionPin({
    required this.name,
    required this.eventCount,
    required this.isSelected,
    this.disabled = false,
  });

  final String name;
  final int eventCount;
  final bool isSelected;

  /// 사건 0개인 region — 회색 톤 + 사용자가 클릭해도 동작 X (부모 GestureDetector
  /// 가 onTap=null 처리). 새 이야기가 추가되어 사건이 1개 이상이면 자동 활성.
  final bool disabled;

  static const Color _pinColorDefault = Color(0xFF3D2A14); // 갈색
  static const Color _pinColorSelected = Color(0xFFE8A33D); // 금색
  static const Color _pinColorDisabled = Color(0xFF9E9285); // 회색
  static const Color _accentColor = Color(0xFF8C6743);
  static const Color _accentColorDisabled = Color(0xFFB8B0A4);
  static const Color _rippleColor = Color(0xFFE8A33D);

  @override
  Widget build(BuildContext context) {
    final pinColor = disabled
        ? _pinColorDisabled
        : (isSelected ? _pinColorSelected : _pinColorDefault);
    final labelTextColor = disabled
        ? const Color(0xFFE6DFD2)
        : (isSelected ? const Color(0xFF3D2A14) : const Color(0xFFF5E9C8));
    final accent = disabled ? _accentColorDisabled : _accentColor;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // ripple 애니메이션 — 선택된 경우만. 핀 아래 동심원 4겹 (금색).
        // disabled (사건 0) 일 땐 선택 자체가 안 되므로 ripple 도 자동 안 그려짐.
        if (isSelected && !disabled)
          const Positioned.fill(
            child: IgnorePointer(child: _RegionRipple(color: _rippleColor)),
          ),
        // 핀 + 라벨 (세로 정렬)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핀 머리(둥근 원 + 흰 점) + 핀촉 — 선택 시 금색.
            CustomPaint(
              size: const Size(38, 50),
              painter: _LocationPinPainter(color: pinColor),
            ),
            const SizedBox(height: 3),
            // 라벨 — 핀 색깔 캡슐 + 사건 개수 배지. maxWidth 로 overflow 방지.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pinColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent, width: 1.2),
                  boxShadow: disabled
                      ? const []
                      : const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: labelTextColor,
                          height: 1.1,
                        ),
                      ),
                    ),
                    if (eventCount > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3D2A14)
                              : const Color(0xFFE8A33D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$eventCount',
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFE8A33D)
                                : const Color(0xFF3D2A14),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 작은 non-region 마커 — 원형 배경 없이 이모지 + 그 아래 plain text 라벨.
/// 흰 stroke shadow 로 가독성 보강 (지도 위 어떤 색에서도 잘 보이게).
class _PointPin extends StatelessWidget {
  const _PointPin({required this.emoji, required this.name});
  final String emoji;
  final String name;

  static const List<Shadow> _textOutline = [
    Shadow(color: Color(0xFFFFFBEF), blurRadius: 3),
    Shadow(color: Color(0xFFFFFBEF), blurRadius: 3),
    Shadow(color: Color(0xFFFFFBEF), blurRadius: 2),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 이모지만 — 원형 배경 없음.
        Text(
          emoji,
          style: const TextStyle(
            fontSize: 22,
            height: 1.0,
            shadows: [
              Shadow(
                color: Color(0x44000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        // plain text 라벨 (rounded rectangle 없음)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3D2A14),
              height: 1.1,
              shadows: _textOutline,
            ),
          ),
        ),
      ],
    );
  }
}

/// region 핀 머리(둥근 원 + 흰 점) + 핀촉(아래로 뾰족) Custom 페인터.
/// [drawCenterDot] 가 true 면 머리 가운데 작은 흰 점을 그린다 (region 핀).
/// false 면 텍스트(숫자) 가 위에 그려질 자리를 비워둔다 (numbered 사건 핀).
class _LocationPinPainter extends CustomPainter {
  _LocationPinPainter({required this.color, this.drawCenterDot = true});
  final Color color;
  final bool drawCenterDot;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final headR = w * 0.45;
    final headCx = w / 2;
    final headCy = headR + 1;

    // 그림자
    final shadow = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(headCx, headCy + 2), headR, shadow);

    // 핀촉 (아래로 뾰족) — dart:ui.Path 명시 (flutter_map 의 Path<R> 와 충돌 회피).
    final pinPaint = Paint()..color = color;
    final tip = Offset(headCx, h - 1);
    final leftBase = Offset(headCx - headR * 0.85, headCy + headR * 0.5);
    final rightBase = Offset(headCx + headR * 0.85, headCy + headR * 0.5);
    final path = ui.Path()
      ..moveTo(leftBase.dx, leftBase.dy)
      ..quadraticBezierTo(headCx - headR * 0.3, h - 6, tip.dx, tip.dy)
      ..quadraticBezierTo(
        headCx + headR * 0.3,
        h - 6,
        rightBase.dx,
        rightBase.dy,
      )
      ..close();
    canvas.drawPath(path, pinPaint);

    // 머리 원
    canvas.drawCircle(Offset(headCx, headCy), headR, pinPaint);

    // 머리 안 흰 점 — region 핀 등 식별용. drawCenterDot=false 면 그 자리에
    // 텍스트(숫자) 가 그려질 거라 비워둔다.
    if (drawCenterDot) {
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(headCx, headCy), headR * 0.32, whitePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LocationPinPainter old) =>
      old.color != color || old.drawCenterDot != drawCenterDot;
}

/// 선택된 region 핀 아래 ripple 애니메이션 — 동심원 4겹 fade.
class _RegionRipple extends StatefulWidget {
  const _RegionRipple({required this.color});
  final Color color;

  @override
  State<_RegionRipple> createState() => _RegionRippleState();
}

class _RegionRippleState extends State<_RegionRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        return CustomPaint(
          painter: _RipplePainter(t: _ctl.value, color: widget.color),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.t, required this.color});
  final double t; // 0 ~ 1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // 핀촉이 아래쪽이라 ripple 의 중심은 핀촉(=핀 머리에서 약간 아래)
    final cy = size.height * 0.4;
    final maxR = math.min(size.width, size.height) * 0.55;
    for (var i = 0; i < 4; i++) {
      final phase = (t + i * 0.25) % 1.0;
      final r = phase * maxR;
      final alpha = ((1.0 - phase) * 0.6).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.t != t || old.color != color;
}

/// 비지리적 region (요한계시록 환상 등) 을 지도 좌하단에 작은 카드로 표시.
/// polygon 이 비어 지도에 그릴 수 없는 region 들을 사용자에게 노출하는 수단.
class _NonGeographicRegionCard extends StatelessWidget {
  const _NonGeographicRegionCard({required this.regions});

  final List<Landmark> regions;

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB89A66), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '✨ 환상 / 비지리적',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8C6743),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          for (final r in regions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2A14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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
