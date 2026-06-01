part of 'story_map_panel.dart';

class _StoryMapPanelState extends State<StoryMapPanel> {
  static const _minMapZoom = 2.7;
  static const _maxMapZoom = 12.4;
  static final LatLngBounds _storyBibleMapBounds = LatLngBounds(
    const LatLng(-8.0, 4.0),
    const LatLng(50.5, 64.0),
  );

  // 옛 _polygonGlowCtl + SingleTickerProviderStateMixin 제거됨 —
  // EraPolygonGlowLayer 의 pulse 가 정적 값으로 바뀌어 매 프레임 rebuild 가
  // 불필요. settle 애니메이션은 layer 내부 _settleCtl 이 자체 처리.
  final MapController _controller = MapController();
  final StoryTerrain3dMapController _terrain3dController =
      StoryTerrain3dMapController();
  Timer? _revealTimer;
  Timer? _cameraTimer;
  Timer? _eventTransitionTimer;
  List<Polyline> _countryBorderPolylines = const [];
  List<Marker> _countryLabelMarkers = const [];
  List<List<LatLng>> _countryBorderLines3d = const [];
  List<StoryTerrainCountryLabel> _countryLabels3d = const [];
  int _visibleCount = 0;
  Size _lastMapSize = const Size(900, 600);
  int _revealRunId = 0;
  int _eventTransitionRunId = 0;
  bool _mapReady = false;
  _EventTransitionOverlay? _eventTransitionOverlay;
  Completer<void>? _eventTransitionCompleter;

  /// 줌 변경 디버그 로깅용 — 0.05 이상 변하면 콘솔 로그.
  double? _lastLoggedZoom;

  /// flutter_map [MapEventSource] 중 사용자 제스처(드래그·핀치·스크롤·탭·키보드
  /// 등) 인 경우 true. programmatic 카메라 이동 / fitCamera / size change 는
  /// false. hint overlay dismiss 등 "사용자가 지도를 만졌다" 를 판정할 때 사용.
  static bool _isUserGestureSource(MapEventSource s) {
    switch (s) {
      case MapEventSource.mapController:
      case MapEventSource.fitCamera:
      case MapEventSource.nonRotatedSizeChange:
      case MapEventSource.interactiveFlagsChanged:
      case MapEventSource.custom:
        return false;
      default:
        return true;
    }
  }

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

  bool get _isThreeDimensional =>
      StoryMapTileStyles.sourceFor(widget.tileStyle).isThreeDimensional;

  /// 3D 전환 중 랜드마크 좌표/라벨 충돌이 커져서 지도 위 랜드마크 마커는
  /// 2D/3D 공통으로 잠시 숨긴다. 지역 선택은 polygon hit layer 가 담당한다.
  bool get _showLandmarkMarkers => false;

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
    if (_isThreeDimensional && !_orderedEventsActive) {
      _visibleCount = widget.events
          .where((event) => event.hasCoordinate)
          .length;
    } else {
      _startRevealAnimation();
    }
    // numbered pin reveal 초기 설정. didUpdateWidget 은 같은 로직을 키 변경 시
    // 재트리거하지만, 첫 마운트에는 그게 안 불려서 _eventRevealCount=0 으로
    // 핀이 그려지지 않는다 (주간 퀴즈 첫 진입 시 발생).
    _initEventReveal();
  }

  void _initEventReveal() {
    final newKey = widget.revealEventsKey ?? widget.selectedLandmarkId;
    _restartEventReveal(newKey, notifyImmediately: false);
  }

  void _restartEventReveal(String? newKey, {bool notifyImmediately = true}) {
    _lastRevealKey = newKey;
    _eventRevealTimer?.cancel();
    _eventRevealCount = 0;
    if (newKey == null || newKey.isEmpty) return;
    final total = widget.events.where((e) => e.hasCoordinate).length;
    if (total <= 0) return;
    if (widget.revealInstantly) {
      if (notifyImmediately && mounted) {
        setState(() => _eventRevealCount = total);
      } else {
        _eventRevealCount = total;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRevealComplete?.call();
      });
    } else {
      _eventRevealTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final next = _eventRevealCount + 1;
        setState(() => _eventRevealCount = next);
        if (next >= total) {
          timer.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onRevealComplete?.call();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _cameraTimer?.cancel();
    _eventTransitionTimer?.cancel();
    _eventTransitionCompleter?.complete();
    _eventRevealTimer?.cancel();
    widget.controller?._unbind(this);
    super.dispose();
  }

  void _handleTerrain3dReady() {
    _mapReady = true;
    if (_orderedEventsActive) {
      _restartEventReveal(widget.revealEventsKey ?? widget.selectedLandmarkId);
    } else {
      _showAllPinsImmediately();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.fitAllEventsOnReady) {
        _focusAllEvents(duration: const Duration(milliseconds: 360));
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) {
            _focusAllEvents(duration: const Duration(milliseconds: 240));
          }
        });
      } else if (widget.centerSelectedOnReady) {
        _centerSelectedEvent();
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) {
            _centerSelectedEvent();
          }
        });
      } else {
        _focusSelectedEventIfNeeded();
      }
    });
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
      _restartEventReveal(newKey);
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

    final zoom = widget.initialZoom ?? 6.0;
    final polylines = _buildPolylines(widget.events);
    final tileSource = StoryMapTileStyles.sourceFor(widget.tileStyle);

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
          if (tileSource.isThreeDimensional)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mapSize = constraints.biggest;
                  if (mapSize.width > 0 && mapSize.height > 0) {
                    _lastMapSize = mapSize;
                  }
                  return StoryTerrain3dMap(
                    controller: _terrain3dController,
                    source: tileSource,
                    center: center,
                    zoom: zoom,
                    events: widget.events,
                    selectedEventId: widget.selectedEventId,
                    colorForCharacter: widget.colorForCharacter,
                    selectedCharacterCodes: widget.selectedCharacterCodes,
                    regionLandmarks: widget.eraRegionLandmarks,
                    activeLandmarks: widget.activeLandmarks,
                    selectedLandmarkId: widget.selectedLandmarkId,
                    eventCountByLandmarkId: widget.eventCountByLandmarkId,
                    visibleEventCount: _orderedEventsActive
                        ? _eventRevealCount
                        : _visibleCount,
                    orderedEventsActive: _orderedEventsActive,
                    eventEmotionMarks: widget.eventEmotionMarks,
                    regionPickerMode: widget.regionPickerMode,
                    countryBorderLines: _countryBorderLines3d,
                    countryLabels: _countryLabels3d,
                    onEventTap: _handle3dEventTap,
                    onLandmarkTap: _handle3dLandmarkTap,
                    onMapInteraction: widget.onMapInteraction,
                    onMapReady: _handleTerrain3dReady,
                  );
                },
              ),
            )
          else
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
                    minZoom: _minMapZoom,
                    maxZoom: _maxMapZoom,
                    cameraConstraint: CameraConstraint.containCenter(
                      bounds: _storyBibleMapBounds,
                    ),
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
                        final cnt =
                            widget.eventCountByLandmarkId?[pick.id] ?? 0;
                        if (cnt == 0) return;
                        widget.onLandmarkTap?.call(pick);
                      }
                    },
                    // 디버그 — 줌 변경 시 콘솔에 로깅 (0.05 이상 변할 때만).
                    // min/max 줌 튜닝용. release 시 제거.
                    // 추가로, 사용자 제스처(드래그/멀티터치/스크롤휠/더블탭) 시
                    // [onMapInteraction] 호출 — 부모의 hint overlay dismiss 트리거.
                    // programmatic 이동(focusEvents 등 mapController source) 은 제외.
                    onMapEvent: (event) {
                      final z = event.camera.zoom;
                      final last = _lastLoggedZoom;
                      if (last == null || (z - last).abs() > 0.05) {
                        _lastLoggedZoom = z;
                        debugPrint('[Map] zoom: ${z.toStringAsFixed(2)}');
                      }
                      if (_isUserGestureSource(event.source)) {
                        widget.onMapInteraction?.call();
                      }
                    },
                    onMapReady: () {
                      _mapReady = true;
                      debugPrint(
                        '[Map] onMapReady — initialZoom: ${widget.initialZoom}',
                      );
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
                      // Base tile source is selected by the parent so we can A/B
                      // the parchment map against terrain/topographic tiles
                      // without replacing the flutter_map overlay stack.
                      urlTemplate: tileSource.urlTemplate,
                      tileDimension: tileSource.tileDimension,
                      zoomOffset: tileSource.zoomOffset,
                      userAgentPackageName: 'com.story.bible',
                      // Some tile sources do not send a long Cache-Control
                      // freshness. 30일 overrideFreshAge 로 console noise 를
                      // 줄이고 스타일 전환 후에도 안정적으로 캐시한다.
                      tileProvider: NetworkTileProvider(
                        cachingProvider:
                            BuiltInMapCachingProvider.getOrCreateInstance(
                              overrideFreshAge: const Duration(days: 30),
                            ),
                      ),
                    ),
                    PolylineLayer(polylines: _countryBorderPolylines),
                    // 시대 영역 폴리곤 — 그 시대의 region 들의 polygon 합집합을
                    // 같은 시대 색으로 칠해 표시. hitNotifier 로 클릭 hit-test
                    // 정보를 노출하고, MapOptions.onTap 에서 hit.hitValues 로 어느
                    // region 이 눌렸는지 식별 → onLandmarkTap 호출.
                    if (widget.eraRegionLandmarks.isNotEmpty)
                      // 시각 layer — 정적 candidate/selected 색 (펄스 제거).
                      // settle 애니메이션은 EraPolygonGlowLayer 내부 _settleCtl 이
                      // 자체 처리하므로 외부 AnimatedBuilder 불필요.
                      Stack(
                        children: [
                          EraPolygonGlowLayer(
                            entries: _buildEraRegionGlowEntries(),
                          ),
                          // hit-test layer — 동일 좌표 투명 폴리곤.
                          // 시각은 EraPolygonGlowLayer 가, 클릭은 PolygonLayer 의
                          // hitNotifier 가 책임 분리.
                          PolygonLayer<Landmark>(
                            hitNotifier: _polygonHitNotifier,
                            polygons: _buildEraRegionHitPolygons(),
                          ),
                        ],
                      ),
                    if (!widget.regionPickerMode)
                      MarkerLayer(markers: _countryLabelMarkers),
                    // 시대 미리보기 — 선택된 인물의 사건 path 만 색깔 실선으로 표시
                    // (인물 미선택 시 + region picker mode 에서는 path 도 숨김).
                    // step 3 (_orderedEventsActive) 진입 시에는 dashed path + 번호
                    // 핀이 그 자리를 대체하므로 실선 preview 를 숨겨 화면을 정리.
                    // 사건 dot 마커는 v3 에서 제거 — region 선택 후에만 사건 핀 노출.
                    if (widget.eraPreviewEvents.isNotEmpty &&
                        widget.selectedCharacterCodes.isNotEmpty &&
                        !_orderedEventsActive &&
                        !widget.regionPickerMode)
                      PolylineLayer(polylines: _buildEraPreviewPolylines()),
                    if (widget.eraPreviewEvents.isNotEmpty &&
                        widget.selectedCharacterCodes.isNotEmpty &&
                        !_orderedEventsActive &&
                        !widget.regionPickerMode)
                      MarkerLayer(markers: _buildEraPreviewArrowHeads()),
                    // region(영역) 폴리곤 — 시대 영역 폴리곤(_buildEraRegionUnion
                    // Polygons, hitNotifier 보유)이 이미 위쪽에서 모든 era region
                    // 을 그리므로 여기서는 별도 layer 를 추가하지 않는다. 과거에는
                    // hitValue/hitNotifier 없는 두 번째 PolygonLayer 가 hit 을
                    // 가로채 폴리곤 클릭이 동작하지 않았다.
                    // 랜드마크 마커는 3D 전환 중 좌표/라벨 충돌을 만들고 있어
                    // 당분간 2D/3D 공통으로 숨긴다. 지역 선택은 폴리곤 hit layer 와
                    // 중앙 지역 라벨이 담당하고, 지도 위에는 사건 원형 핀만 남긴다.
                    if (_showLandmarkMarkers &&
                        widget.activeLandmarks.isNotEmpty)
                      MarkerLayer(
                        markers: _buildLandmarkMarkers(
                          _landmarksHidingEventLocations(),
                        ),
                      ),
                    PolylineLayer(polylines: polylines),
                    if (!widget.regionPickerMode &&
                        !widget.suppressRegionLabels)
                      MarkerLayer(markers: _buildRegionLabels()),
                    // 폴리곤 중앙에 region 이름 + 사건 개수 라벨.
                    // step 2 (regionPickerMode): 모든 era region 라벨 표시 (갈색).
                    // step 3 (region 선택됨): 선택된 region 만 노란 캡슐 라벨로 표시.
                    if (widget.eraRegionLandmarks.isNotEmpty &&
                        (widget.regionPickerMode ||
                            widget.selectedLandmarkId != null))
                      MarkerLayer(markers: _buildPolygonCenterLabels()),
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
                    if (_eventTransitionOverlay != null)
                      MarkerLayer(markers: _buildEventTransitionMarkers()),
                    // 거리 측정 폴리라인 (두 점이 모두 선택됐을 때만).
                    if (_measureMode)
                      PolylineLayer(polylines: _buildMeasurePolylines()),
                    // attribution 은 home screen 우측 상단 ⓘ 버튼으로 이동.
                    // 이전 좌하단 inline 텍스트는 bottomOverlay (사건 패널·intro 등)
                    // 에 가려져 의무 가시성을 충족하지 못해 제거.
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
          if (tileSource.isThreeDimensional && widget.bottomOverlay != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: widget.bottomOverlay!,
            ),
          if (tileSource.isThreeDimensional &&
              widget.selectedCharacterCodes.isNotEmpty)
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
          if (tileSource.isThreeDimensional && _nonGeographicRegions.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 30),
                child: _NonGeographicRegionCard(regions: _nonGeographicRegions),
              ),
            ),
          // 양피지 텍스처 overlay — 지도 위에 multiply 로 합성해 결을 살린다.
          // tileScale 0.5 → 텍스처를 절반 크기로 반복(stretch 시 흐릿한 얼룩 방지).
          // 지형 타일은 산지/등고선 식별이 중요하므로 texture 를 더 약하게 둔다.
          if (!tileSource.isThreeDimensional)
            Positioned.fill(
              child: IgnorePointer(
                child: ParchmentMultiplyLayer(
                  strength: tileSource.textureStrength,
                  tileScale: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handle3dLandmarkTap(String landmarkId) {
    for (final landmark in [
      ...widget.activeLandmarks,
      ...widget.eraRegionLandmarks,
    ]) {
      if (landmark.id == landmarkId) {
        _handleLandmarkTap(landmark);
        return;
      }
    }
  }

  void _handle3dEventTap(String eventId) {
    widget.onSelectEvent(eventId);
    widget.onOpenDetail?.call(eventId);
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
    if (_isThreeDimensional) {
      _terrain3dController.moveTo(
        point,
        7.25,
        duration: const Duration(milliseconds: 420),
      );
      return;
    }
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
      // 폴리곤이 화면을 가득 채우도록 padding 최소화. 단 시트/툴바 가림 영역만큼은
      // 보존해서 잘리지 않게.
      final bottomPadding = math.max(16.0, bottomGap + 8.0);
      final topPadding = math.max(16.0, widget.topObscuredPixels + 8.0);
      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );
      if (_isThreeDimensional) {
        _terrain3dController.fitBounds(
          bounds,
          padding: EdgeInsets.fromLTRB(18, topPadding, 18, bottomPadding),
          maxZoom: 8.8,
          duration: const Duration(milliseconds: 520),
        );
        return;
      }
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
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
        // + 가는 3.0px 실선. 시간 흐름이 진해지는 자연스러운 방향성.
        for (var i = 0; i < points.length - 1; i++) {
          final t = (points.length <= 2) ? 1.0 : (i + 1) / (points.length - 1);
          final segAlpha = 0.6 + 0.4 * t;
          result.add(
            Polyline(
              points: [points[i], points[i + 1]],
              color: color.withValues(alpha: segAlpha),
              strokeWidth: 3.0,
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

  /// (v3 — 사용 안 함) 시대 미리보기 dot 마커. 사용자가 dot 이 화면을 어수선하게
  /// 만든다고 판단해 비활성화. 인물 path polyline + 화살촉만 노출하며, 사건 핀은
  /// region 선택 후 `_buildNumberedEventMarkers` 가 그린다. 코드는 향후 재사용
  /// 가능성을 위해 보존하되 호출 지점만 제거.
  // ignore: unused_element
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
  /// 비지리적 region (polygon 빈 배열) — 종말 환상 등. 지도 모서리 카드로
  /// 표시하기 위해 따로 뽑아낸다. eraRegionLandmarks 에서 lat/lng=0 + polygon
  /// 빈 region 들을 필터.
  List<Landmark> get _nonGeographicRegions => widget.eraRegionLandmarks
      .where((lm) => lm.isRegion && lm.polygon.isEmpty)
      .toList(growable: false);

  /// 시각 layer (EraPolygonGlowLayer) 용 entry 생성. 사건 0건 region 은
  /// polygon 자체를 그리지 않는다 — 새 이야기 제안이 승인되어 eventCount > 0
  /// 이 되면 자동으로 polygon 이 등장한다.
  ///
  /// EraPolygonGlowLayer 는 후보/선택의 두 톤만 그리므로 eraColor 와 pulseT 는
  /// 호환성 위해 채우되 layer 내부에서 사용되지 않는다.
  List<EraPolygonEntry> _buildEraRegionGlowEntries() {
    final entries = <EraPolygonEntry>[];
    for (final lm in widget.eraRegionLandmarks) {
      if (!lm.isRegion || lm.polygon.isEmpty) continue;
      final eventCount = widget.eventCountByLandmarkId?[lm.id] ?? 0;
      if (eventCount == 0) continue;
      entries.add(
        EraPolygonEntry(
          polygon: lm.polygon,
          eraColor: _eraColorForRegion(lm),
          isSelected: lm.id == widget.selectedLandmarkId,
          pulseT: 0.0,
          // region 선택 단계에서 후보 폴리곤 (선택되지 않은 것) 을 시각적으로
          // 강화 — 사용자가 "여기를 누르세요" 안내와 함께 더 또렷하게 인식.
          pickerHighlight:
              widget.regionPickerMode && lm.id != widget.selectedLandmarkId,
        ),
      );
    }
    return entries;
  }

  /// region polygon 색 결정. **선택된 시대 색을 region 의 era_codes 와
  /// 무관하게 일관되게 사용한다** — 같은 region 이 여러 시대에 속해도
  /// (예: 유대 = 족장+사사+왕정+포로귀환+신약공생애+사도) 사용자가 선택한
  /// 시대 색으로 칠해져 컨텍스트가 바뀌어도 색이 흔들리지 않음.
  ///
  /// activeEraBoundaries 가 비어 있을 때만 region 의 첫 era_code 로 폴백.
  Color _eraColorForRegion(Landmark lm) {
    for (final b in widget.activeEraBoundaries) {
      final code = widget.eraCodeForId?.call(b.eraId);
      if (code != null && code.isNotEmpty) {
        return EraColors.forCode(code);
      }
    }
    return EraColors.forCode(lm.eraCodes.isNotEmpty ? lm.eraCodes.first : '');
  }

  /// hit-test layer 용 투명 폴리곤. 시각 효과는 EraPolygonGlowLayer 가
  /// 담당하고 클릭만 flutter_map 의 `PolygonLayer<Landmark>.hitNotifier` 가
  /// 책임진다.
  List<Polygon<Landmark>> _buildEraRegionHitPolygons() {
    final result = <Polygon<Landmark>>[];
    for (final lm in widget.eraRegionLandmarks) {
      if (!lm.isRegion || lm.polygon.isEmpty) continue;
      final eventCount = widget.eventCountByLandmarkId?[lm.id] ?? 0;
      if (eventCount == 0) continue;
      result.add(
        Polygon<Landmark>(
          points: lm.polygon,
          color: const Color(0x00000000),
          borderColor: const Color(0x00000000),
          borderStrokeWidth: 0.0,
          hitValue: lm,
        ),
      );
    }
    return result;
  }

  /// 시간순 사건 좌표 — 가까운 좌표 사건들을 거리 기반(spreadColocatedPoints) 으로
  /// 원형 분산해 핀/path/화살표가 겹치지 않게 한다. buildAdjustedPoints 의
  /// 2자리-반올림 키 방식은 31.52 vs 31.53 같은 경계 케이스를 못 묶음.
  List<({StoryEvent event, LatLng point})> _adjustedOrderedEventPoints(
    List<StoryEvent> events,
  ) {
    final ordered = events.where((e) => e.hasCoordinate).toList()
      ..sort((a, b) => a.globalRank.compareTo(b.globalRank));
    final visible = ordered.take(_eventRevealCount).toList(growable: false);
    final adjusted = map_math.buildRankedEventPointMap(
      events,
      visibleCount: _eventRevealCount,
    );
    return [
      for (final e in visible) (event: e, point: adjusted[e.id] ?? e.latLng),
    ];
  }

  Map<String, LatLng> _numberedEventPointMap({required bool includeHidden}) {
    final isThreeDimensional = _isThreeDimensional;
    return map_math.buildRankedEventPointMap(
      widget.events,
      visibleCount: includeHidden ? null : _eventRevealCount,
      radiusDeg: isThreeDimensional ? 0.018 : 0.045,
      thresholdDeg: isThreeDimensional ? 0.028 : 0.04,
    );
  }

  /// region/character 선택 시 사건들을 시간순으로 잇는 점선 path.
  List<Polyline> _buildOrderedEventPath(List<StoryEvent> events) {
    final pts = _adjustedOrderedEventPoints(events);
    if (pts.length < 2) return const [];
    return [
      Polyline(
        points: pts.map((e) => e.point).toList(growable: false),
        color: const Color(0xFF6B4A2A),
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
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: Icon(
                Icons.play_arrow,
                size: 18,
                color: const Color(0xFF6B4A2A),
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

  List<Marker> _buildEventTransitionMarkers() {
    final overlay = _eventTransitionOverlay;
    if (overlay == null) return const [];
    return [
      _transitionGlowMarker(overlay.fromPoint, overlay.progress),
      _transitionGlowMarker(overlay.toPoint, overlay.progress),
    ];
  }

  Marker _transitionGlowMarker(LatLng point, double progress) {
    return Marker(
      point: point,
      width: 72,
      height: 72,
      alignment: Alignment.center,
      child: IgnorePointer(
        child: CustomPaint(
          size: const Size.square(72),
          painter: _EventTransitionGlowPainter(progress: progress),
        ),
      ),
    );
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
    // 인물 모드: 사건에 등장하는 인물 중 사용자가 고른 인물의 색을 모은다.
    // 핀 동그라미를 N 색 가로 띠로 채워 "어느 인물 사건인지" 색으로 식별.
    // - 1명: 단색 fill
    // - 2명: 위/아래 반반
    // - 3+명: 균등 N 등분
    // 매칭이 없으면 (예: region 모드) 빈 리스트 → 기존 갈색 fill 폴백.
    // event.characterCodes 의 원래 순서를 유지해 카드 안 pill 정렬과 일치.
    final characterColors = <Color>[];
    if (widget.selectedCharacterCodes.isNotEmpty) {
      for (final code in event.characterCodes) {
        if (widget.selectedCharacterCodes.contains(code)) {
          characterColors.add(widget.colorForCharacter(code));
        }
      }
    }
    final emotionKey = widget.eventEmotionMarks[event.id]?.emotionKey;
    final hasEmotion = emotionKey != null && emotionKey.isNotEmpty;
    return Marker(
      point: point,
      width: hasEmotion ? 30 : 22,
      height: hasEmotion ? 30 : 22,
      alignment: Alignment.center,
      child: Builder(
        builder: (context) {
          final zoom = MapCamera.of(context).zoom;
          // 줌아웃 시만 살짝 작아짐. 확대해도 더 안 커짐 → 시트 카드 배지보다
          // 작게 유지해 폴리곤·라벨이 시야 우위.
          final raw = 0.55 + (zoom - 3.0) * 0.075;
          final scale = raw.clamp(0.55, 1.0).toDouble();
          return Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectEvent(event.id),
              child: _NumberedEventPin(
                number: order,
                isSelected: selected,
                characterColors: characterColors,
                emotionKey: emotionKey,
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
    final hidden = <String>{for (final e in widget.events) e.landmarkId};
    return widget.activeLandmarks
        .where((lm) => !hidden.contains(lm.id))
        .toList(growable: false);
  }

  List<Marker> _buildLandmarkMarkers(List<Landmark> landmarks) {
    // v3 — region 핀(검정 capsule + 노랑 selected ripple) 은 모든 단계에서 숨긴다.
    // step 2: 폴리곤 중앙 라벨이 region 을 표현, step 3: 선택 region 은 폴리곤
    // 자체가 노랑 glow 로 강조된다. non-region 랜드마크만 렌더.
    final filtered = landmarks
        .where((l) => !l.isRegion)
        .toList(growable: false);
    // 같은 좌표(2자리 lat/lng) 의 non-region 랜드마크들은 원형 분산해 PNG 가
    // 서로 가리지 않도록 한다. region 은 폴리곤 중심에 단일 핀이라 분산 불필요.
    final nonRegionPoints = <String, LatLng>{
      for (final lm in filtered)
        if (!lm.isRegion) lm.id: lm.latLng,
    };
    final adjusted = map_math.spreadColocatedPoints(nonRegionPoints);

    return filtered
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
          final point = isRegion
              ? obj.latLng
              : (adjusted[obj.id] ?? obj.latLng);
          // Marker 박스 크기는 시각적으로 필요한 만큼 (이모지 + 라벨 column).
          // 줄여 두면 _PointPin 의 Column 이 overflow 한다. regionPickerMode 의
          // 폴리곤 hit-through 는 GestureDetector 의 HitTestBehavior 로 처리.
          return Marker(
            point: point,
            width: isRegion ? 88 : 64,
            height: isRegion ? 78 : 50,
            alignment: Alignment.center,
            child: _ZoomScaledLandmark(
              landmark: obj,
              isMeasureSelected: isMeasureSelected,
              isSelected: isSelectedRegion,
              eventCount: widget.eventCountByLandmarkId?[obj.id] ?? 0,
              compactHit: widget.regionPickerMode,
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

  /// step 2 — 폴리곤 중앙에 region 이름 + 사건 개수 배지. 사용자가 폴리곤
  /// 자체를 큰 단위로 선택하도록 시각적으로 안내. 폴리곤 클릭은 PolygonLayer 의
  /// hitNotifier 가 처리.
  List<Marker> _buildPolygonCenterLabels() {
    final markers = <Marker>[];
    final selectedId = widget.selectedLandmarkId;
    for (final lm in widget.eraRegionLandmarks) {
      if (!lm.isRegion || lm.polygon.isEmpty) continue;
      // step 3 (region 선택됨): 선택된 region 라벨만 표시 (다른 region 라벨은
      // 사건 핀과 충돌). step 2 (regionPickerMode): 모든 region 라벨 표시.
      if (selectedId != null && lm.id != selectedId) continue;
      // 사건이 0개인 region 은 폴리곤이 안 그려지므로 라벨도 생략.
      final cnt = widget.eventCountByLandmarkId?[lm.id] ?? 0;
      if (cnt == 0) continue;
      // bbox 중심을 라벨 위치로 사용 (centroid 보다 직관적이고 빠름).
      double minLat = lm.polygon.first.latitude;
      double maxLat = minLat;
      double minLng = lm.polygon.first.longitude;
      double maxLng = minLng;
      for (final p in lm.polygon) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final isSelected = lm.id == widget.selectedLandmarkId;
      // 위치: 비선택 region 은 폴리곤 중앙, 선택 region 은 폴리곤 하단(아래쪽 가장자리)
      // — 가운데에 두면 사건 핀과 겹쳐 답답해 보임.
      final point = isSelected
          ? LatLng(minLat, (minLng + maxLng) / 2)
          : LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      final alignment = isSelected ? Alignment.bottomCenter : Alignment.center;
      final bgColor = isSelected
          ? const Color(0xF2FFE7A6) // 옅은 노랑 (95% opacity)
          : const Color(0xF2FBF1DC); // 양피지 크림
      final borderColor = isSelected
          ? const Color(0xFFB87A2E)
          : const Color(0xFFB89A66);
      const nameColor = Color(0xFF3D2A14);
      const countColor = Color(0xFF6B4A2A);
      markers.add(
        Marker(
          point: point,
          width: 110,
          height: 28,
          alignment: alignment,
          child: IgnorePointer(
            // Center 로 감싸 Container 가 marker box(110×22) 에 stretch 되지 않고
            // 내부 Row 의 intrinsic width 로 줄어들도록 한다.
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: borderColor, width: 0.8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 2.5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        lm.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: nameColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '+$cnt',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: countColor,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

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
      // Arabian Peninsula 인접국 — border 만 그리고 라벨도 표시되도록 추가.
      // 매핑 없으면 polygon 처리 자체가 skip 되어 사우디–예멘/오만 같은
      // land border 가 한 쪽만 그려져 비대칭으로 보임.
      'Yemen': '예멘',
      'Oman': '오만',
      'United Arab Emirates': '아랍에미리트',
      'Qatar': '카타르',
      'Bahrain': '바레인',
      'Kuwait': '쿠웨이트',
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
      final borderLines3d = <List<LatLng>>[];
      final labelPoints3d = <StoryTerrainCountryLabel>[];
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
          borderLines3d.add([...ring, ring.first]);
          // 색연필 같은 질감 — 3중 stroke + 미세 jitter 로 손그림 갈색 색연필
          // 결을 흉내. wide halo(매우 옅음) + medium halo + ink core 가 겹쳐
          // 단단한 vector 라인이 아닌 거친 결의 색연필 효과.
          final ringRand = math.Random(
            ring.fold<int>(
              0,
              (acc, p) =>
                  acc ^ p.latitude.hashCode ^ (p.longitude.hashCode << 1),
            ),
          );
          final jittered = ring.map((p) {
            final dx = (ringRand.nextDouble() - 0.5) * 0.012;
            final dy = (ringRand.nextDouble() - 0.5) * 0.012;
            return LatLng(p.latitude + dy, p.longitude + dx);
          }).toList();
          final ringWithClose = [...jittered, jittered.first];
          // 색연필 톤 — dusty rose (#9C5757). 갈색이 겹치면 너무 진해보여
          // 분홍빛 색연필 결로. watercolor sage/blue 와 보색 vintage 톤.
          borderPolylines.add(
            Polyline(
              points: ringWithClose,
              color: const Color(0x209C5757), // wide halo (12%)
              strokeWidth: 3.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          borderPolylines.add(
            Polyline(
              points: ringWithClose,
              color: const Color(0x489C5757), // medium halo (28%)
              strokeWidth: 1.6,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          borderPolylines.add(
            Polyline(
              points: ringWithClose,
              color: const Color(0xA09C5757), // 진한 코어 (63%)
              strokeWidth: 0.7,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          landRings.add(ring);
        }

        final labelPoint = _labelPoint(properties, rings.first);
        labelMarkers.add(_countryLabelMarker(nameKo, labelPoint));
        labelPoints3d.add(
          StoryTerrainCountryLabel(name: nameKo, point: labelPoint),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _countryBorderPolylines = borderPolylines;
        _countryLabelMarkers = labelMarkers;
        _countryBorderLines3d = borderLines3d;
        _countryLabels3d = labelPoints3d;
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
      width: 76,
      height: 20,
      child: IgnorePointer(
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            // 35% 알파 — 다른 정보 안 가리는 옅은 캡슐.
            color: const Color(0x59EDE2CC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x66745A3C), width: 0.6),
          ),
          child: Text(
            nameKo,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xCC332518), // 60→80% 알파, 더 또렷하게
              fontWeight: FontWeight.w800, // w600 → w800 굵게
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    final animationZoom = (_computeRevealZoom(points) - 1.0).clamp(
      _minMapZoom,
      _maxMapZoom,
    );
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
    if (_isThreeDimensional) {
      final targetZoom = (widget.selectedFocusZoom ?? widget.initialZoom ?? 6.8)
          .clamp(4.0, 9.4)
          .toDouble();
      _terrain3dController.moveTo(
        selectedPoint,
        targetZoom,
        duration: const Duration(milliseconds: 520),
      );
      return;
    }
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
        .clamp(_minMapZoom, _maxMapZoom);
    if (_isThreeDimensional) {
      _terrain3dController.moveTo(
        selectedPoint,
        targetZoom.clamp(4.0, 9.6).toDouble(),
        duration: const Duration(milliseconds: 280),
      );
      return;
    }
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
      final singleZoom = ((widget.initialZoom ?? 6.0) + 0.35 + zoomBoost).clamp(
        3.0,
        9.0,
      );
      _focusToPoint(visibleEvents.first.latLng, singleZoom, duration: duration);
      return;
    }

    final rawPoints = visibleEvents.map((event) => event.latLng).toList();
    final adjustedPointsById = (_isThreeDimensional || _orderedEventsActive)
        ? _numberedEventPointMap(includeHidden: true)
        : map_math.buildAdjustedPoints(visibleEvents);
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
      3.0,
      9.0,
    );
    if (isTightlyClustered) {
      fittedZoom = math.min(fittedZoom, 7.15);
    }
    fittedZoom = (fittedZoom + zoomBoost).clamp(_minMapZoom, _maxMapZoom);
    if (_isThreeDimensional) {
      final bottomGap = (widget.bottomObscuredFraction * _lastMapSize.height)
          .clamp(0.0, 600.0);
      final bottomPadding = math.max(16.0, bottomGap + 8.0);
      final topPadding = math.max(16.0, widget.topObscuredPixels + 8.0);
      _terrain3dController.fitBounds(
        bounds,
        padding: EdgeInsets.fromLTRB(18, topPadding, 18, bottomPadding),
        maxZoom: fittedZoom.toDouble(),
        duration: duration,
      );
      return;
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
    if (_isThreeDimensional) {
      _terrain3dController.moveTo(
        point,
        zoom.clamp(_minMapZoom, _maxMapZoom).toDouble(),
        duration: duration,
      );
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
    if (StoryMapTileStyles.sourceFor(widget.tileStyle).isThreeDimensional) {
      _terrain3dController.zoomIn();
      return;
    }
    if (!_mapReady) {
      return;
    }
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final targetZoom = (camera.zoom + 0.7).clamp(_minMapZoom, _maxMapZoom);
    _focusToPoint(
      camera.center,
      targetZoom,
      duration: const Duration(milliseconds: 420),
    );
  }

  void zoomOut() {
    if (StoryMapTileStyles.sourceFor(widget.tileStyle).isThreeDimensional) {
      _terrain3dController.zoomOut();
      return;
    }
    if (!_mapReady) {
      return;
    }
    final camera = _safeCamera();
    if (camera == null) {
      return;
    }
    final targetZoom = (camera.zoom - 0.7).clamp(_minMapZoom, _maxMapZoom);
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
    if (_orderedEventsActive) {
      _restartEventReveal(widget.revealEventsKey ?? widget.selectedLandmarkId);
      return;
    }
    _startRevealAnimation();
  }

  Future<void> _playEventTransition({
    required StoryEvent from,
    required StoryEvent to,
  }) async {
    if (!_mapReady || !from.hasCoordinate || !to.hasCoordinate) {
      return;
    }
    if (from.id == to.id) {
      return;
    }

    _eventTransitionRunId += 1;
    final runId = _eventTransitionRunId;
    _eventTransitionTimer?.cancel();
    if (_eventTransitionCompleter?.isCompleted == false) {
      _eventTransitionCompleter!.complete();
    }

    final visiblePoints = _numberedEventPointMap(includeHidden: false);
    final finalPoints = _numberedEventPointMap(includeHidden: true);
    final fromPoint =
        visiblePoints[from.id] ?? finalPoints[from.id] ?? from.latLng;
    final toPoint = visiblePoints[to.id] ?? finalPoints[to.id] ?? to.latLng;
    final bounds = LatLngBounds.fromPoints([fromPoint, toPoint]);
    final targetZoom = (_computeRevealZoom([fromPoint, toPoint]) - 0.28).clamp(
      3.0,
      8.8,
    );

    if (_isThreeDimensional) {
      _focusToPoint(
        bounds.center,
        targetZoom.toDouble(),
        duration: const Duration(milliseconds: 360),
      );
      return _terrain3dController.playEventTransition(
        fromPoint: fromPoint,
        toPoint: toPoint,
      );
    }

    final completer = Completer<void>();
    _eventTransitionCompleter = completer;
    _focusToPoint(
      bounds.center,
      targetZoom.toDouble(),
      duration: const Duration(milliseconds: 360),
    );
    setState(() {
      _eventTransitionOverlay = _EventTransitionOverlay(
        fromPoint: fromPoint,
        toPoint: toPoint,
        progress: 0,
      );
    });

    const duration = Duration(seconds: 2);
    final startAt = DateTime.now();
    _eventTransitionTimer = Timer.periodic(const Duration(milliseconds: 16), (
      timer,
    ) {
      if (!mounted || runId != _eventTransitionRunId) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      final elapsed = DateTime.now().difference(startAt).inMilliseconds;
      final rawT = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
      setState(() {
        _eventTransitionOverlay = _EventTransitionOverlay(
          fromPoint: fromPoint,
          toPoint: toPoint,
          progress: rawT,
        );
      });
      if (rawT >= 1.0) {
        timer.cancel();
        _eventTransitionTimer = null;
        if (mounted && runId == _eventTransitionRunId) {
          setState(() => _eventTransitionOverlay = null);
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  /// 토글류 변화로 events 가 바뀌었을 때 핀을 즉시 모두 노출. 시간 순 애니메이션
  /// 없이 "선택 즉시 핀이 박혀 보이는" 상태를 유지한다.
  void _showAllPinsImmediately() {
    _revealTimer?.cancel();
    _eventRevealTimer?.cancel();
    final count = widget.events.where((event) => event.hasCoordinate).length;
    setState(() {
      _visibleCount = count;
      if (_orderedEventsActive) {
        _eventRevealCount = count;
      }
    });
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
    const minZoom = _minMapZoom;
    const maxZoom = _maxMapZoom;
    final baseZoom = widget.initialZoom ?? 6.0;
    if (points.isEmpty) {
      return baseZoom.clamp(minZoom, maxZoom);
    }
    if (points.length == 1) {
      return math.max(baseZoom, 10.4).clamp(minZoom, maxZoom);
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

class _EventTransitionOverlay {
  const _EventTransitionOverlay({
    required this.fromPoint,
    required this.toPoint,
    required this.progress,
  });

  final LatLng fromPoint;
  final LatLng toPoint;
  final double progress;
}

class _EventTransitionGlowPainter extends CustomPainter {
  const _EventTransitionGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final t = progress.clamp(0.0, 1.0).toDouble();
    final fadeIn = Curves.easeOut.transform(
      (t / 0.16).clamp(0.0, 1.0).toDouble(),
    );
    final fadeOut =
        1.0 -
        Curves.easeIn.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0).toDouble());
    final wave = 0.5 + 0.5 * math.sin((t * math.pi * 4) - math.pi / 2);
    final intensity = (0.48 + wave * 0.52) * fadeIn * fadeOut;
    if (intensity <= 0.01) return;

    final glowPaint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.34 * intensity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 13 + wave * 8);
    canvas.drawCircle(center, 15 + wave * 9, glowPaint);

    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 + wave * 1.4
      ..color = AppColors.goldDeep.withValues(alpha: 0.58 * intensity);
    canvas.drawCircle(center, 17 + wave * 10, haloPaint);

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.parchmentCream.withValues(alpha: 0.72 * intensity);
    canvas.drawCircle(center, 13 + wave * 4, corePaint);
  }

  @override
  bool shouldRepaint(covariant _EventTransitionGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
