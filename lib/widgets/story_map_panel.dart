import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/era_boundary.dart';
import '../models/event_emotion_mark.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';
import '../theme/era_colors.dart';
import '../theme/tokens.dart';
import '../utils/map_math.dart' as map_math;
import 'emotion_badge_icon.dart';
import 'map/era_polygon_glow_layer.dart';
import 'parchment_multiply_layer.dart';
import 'shared/event_short_popup.dart';

// 핀 마커 위젯/데이터 클래스를 별도 파트 파일로 분리.
part 'map/pin_marker.dart';
part 'story_map_panel_state.dart';
part 'story_map_panel_widgets.dart';

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
    this.eventEmotionMarks = const {},
    this.regionPickerMode = false,
    this.onMapInteraction,
    this.suppressRegionLabels = false,
  });

  /// 사용자가 지도와 상호작용 (drag/zoom/pan/탭) 했을 때 호출. 부모는 이를
  /// 활용해 "지도를 움직여 보세요" 같은 hint overlay 를 dismiss 한다.
  /// programmatic 카메라 이동(focusEvents 등) 은 제외 — `MapEventSource` 가
  /// 사용자 제스처일 때만 호출된다.
  final VoidCallback? onMapInteraction;

  /// true 면 `_buildRegionLabels` 가 그리는 검정 캡슐 라벨(가나안·시내 광야·
  /// 애굽 등) 을 숨긴다. 인물 모드에서 인물 path 점선이 그 라벨에 가려져
  /// 잘 안 보이는 문제를 해결하기 위해 부모가 토글한다.
  final bool suppressRegionLabels;

  /// true 일 때 step 2 (장소 선택) UI: 나라/region 핀 라벨 숨기고, 폴리곤 자체가
  /// 선택 가능한 큰 단위로 노출 (폴리곤 중앙에 region 이름 + 사건 개수 배지).
  final bool regionPickerMode;

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

  /// era_id (uuid) → era_code (text) 매핑. 시대 정보를 코드 단위로 다뤄야
  /// 하는 기능에서 사용 (legend/필터/외부 리소스 매칭 등). null 이면 era_id
  /// 자체로 fallback.
  final String? Function(String eraId)? eraCodeForId;

  /// region 마커 라벨에 표시할 사건 개수 — landmark.id → count.
  /// 부모가 region(+ 자식 anchor/minor + alias_group) 사건 합산해 넘겨 준다.
  /// null 이거나 키 없으면 배지 미표시.
  final Map<String, int>? eventCountByLandmarkId;

  /// 사용자가 지도 위에 새긴 감정. 번호 핀 옆의 작은 아이콘 배지로 표시한다.
  final Map<String, EventEmotionMark> eventEmotionMarks;

  @override
  State<StoryMapPanel> createState() => _StoryMapPanelState();
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

  /// 상세 페이지 prev/next 이동 전, 지도 위에서 현재 사건과 목표 사건 핀을
  /// 함께 빛나게 하는 1회성 전환 애니메이션을 재생한다.
  Future<void> playEventTransition({
    required StoryEvent from,
    required StoryEvent to,
  }) {
    return _state?._playEventTransition(from: from, to: to) ?? Future.value();
  }
}

/// 줌에 비례해 축소되는 landmark 마커. region 인 경우 큰 location pin +
/// ripple 애니메이션 (선택 시), non-region 은 작은 둥근 아이콘.
