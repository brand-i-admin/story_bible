import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import '../models/event_emotion_mark.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';
import '../utils/map_math.dart' as map_math;
import 'map/map_tile_style.dart';
import 'map/story_terrain_3d_map.dart';

part 'story_map_panel_state.dart';
part 'story_map_panel_widgets.dart';

class StoryMapPanel extends StatefulWidget {
  const StoryMapPanel({
    super.key,
    required this.events,
    required this.selectedEventId,
    required this.onSelectEvent,
    this.onCloseSelectedCallout,
    this.onOpenDetail,
    required this.colorForCharacter,
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
    this.initialCenter,
    this.initialZoom,
    this.bottomObscuredFraction = 0.0,
    this.topObscuredPixels = 0.0,
    this.activeLandmarks = const [],
    this.onLandmarkTap,
    this.eraRegionLandmarks = const [],
    this.selectedLandmarkId,
    this.revealEventsKey,
    this.revealInstantly = false,
    this.onRevealComplete,
    this.nameForCharacter,
    this.eventCountByLandmarkId,
    this.eventEmotionMarks = const {},
    this.regionPickerMode = false,
    this.onMapInteraction,
  });

  /// 사용자가 지도와 상호작용 (drag/zoom/pan/탭) 했을 때 호출. 부모는 이를
  /// 활용해 "지도를 움직여 보세요" 같은 hint overlay 를 dismiss 한다.
  /// MapLibre 쪽에서 실제 사용자 제스처만 Flutter 로 전달한다.
  final VoidCallback? onMapInteraction;

  /// true 일 때 step 2 (장소 선택) UI: 3D region polygon 과 hit-zone 을
  /// 선택 가능한 큰 단위로 노출한다.
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
  final LatLng? initialCenter;
  final double? initialZoom;
  final double bottomObscuredFraction;
  final double topObscuredPixels;

  /// 현재 시대에 노출되는 랜드마크 (예루살렘 성전, 시내산 등). 일반적으로
  /// 부모가 selectedEraId 의 era code 로 필터해 넘긴다. 비어 있으면 미표시.
  final List<Landmark> activeLandmarks;

  /// 랜드마크 탭 콜백. 부모(StoryHomeScreen) 가 다이얼로그/시트로 상세를
  /// 띄운다. null 이면 탭 무반응.
  final ValueChanged<Landmark>? onLandmarkTap;

  /// 현재 시대에 속하는 region 종류 landmark.
  /// 3D MapLibre 레이어가 이 region polygon 과 hit-zone 을 렌더링한다.
  final List<Landmark> eraRegionLandmarks;

  /// 인물 코드 → 표시 이름 반환. legend 에서 사용. null 이면 코드를 이름으로
  /// 사용 (fallback).
  final String Function(String characterCode)? nameForCharacter;

  /// region 라벨에 표시할 사건 개수 — landmark.id → count.
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

  void suppressMapTaps([
    Duration duration = const Duration(milliseconds: 650),
  ]) => _state?._suppressMapTaps(duration);

  void clearMapTapSuppression() => _state?._clearMapTapSuppression();

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

  /// 감정 새김 직후 지도 위 해당 사건 핀에 감정 도장을 1회 재생한다.
  Future<void> playEmotionStamp({
    required StoryEvent event,
    required String stampLabel,
  }) {
    return _state?._playEmotionStamp(event: event, stampLabel: stampLabel) ??
        Future.value();
  }
}
