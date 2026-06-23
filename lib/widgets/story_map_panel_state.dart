part of 'story_map_panel.dart';

class _StoryMapPanelState extends State<StoryMapPanel> {
  static const _minMapZoom = 2.7;
  static const _maxMapZoom = 12.4;
  static const _eventTransitionZoomOut = 0.72;
  static const _eventTransitionMaxZoom = 8.2;
  static const _eventTransitionHorizontalPadding = 24.0;

  final StoryTerrain3dMapController _terrain3dController =
      StoryTerrain3dMapController();
  Timer? _revealTimer;
  List<List<LatLng>> _countryBorderLines3d = const [];
  List<StoryTerrainCountryLabel> _countryLabels3d = const [];
  int _visibleCount = 0;
  Size _lastMapSize = const Size(900, 600);
  int _revealRunId = 0;
  bool _mapReady = false;
  bool _pendingHomeIntroCameraHint = false;

  /// 사건 핀 0.3초 순차 reveal 카운터. revealEventsKey 또는 selectedLandmarkId
  /// 가 변경되면 0 으로 리셋 후 매 300ms +1.
  int _eventRevealCount = 0;
  Timer? _eventRevealTimer;
  String? _lastRevealKey;

  /// 시간순 번호 핀 모드 활성 여부 — region 선택 OR revealEventsKey set.
  bool get _orderedEventsActive =>
      widget.selectedLandmarkId != null ||
      (widget.revealEventsKey != null && widget.revealEventsKey!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(this);
    _loadCountryBoundaries();
    if (!_orderedEventsActive) {
      _visibleCount = widget.events
          .where((event) => event.hasCoordinate)
          .length;
    } else {
      _startRevealAnimation();
    }
    // numbered pin reveal 초기 설정. didUpdateWidget 은 같은 로직을 키 변경 시
    // 재트리거하지만, 첫 마운트에는 그게 안 불려서 _eventRevealCount=0 으로
    // 핀이 그려지지 않는다 (주간 탐험 첫 진입 시 발생).
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
      if (_pendingHomeIntroCameraHint) {
        _pendingHomeIntroCameraHint = false;
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted && _mapReady) {
            _playHomeIntroCameraHint();
          }
        });
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
    final tileSource = StoryMapTileStyles.sourceFor(
      StoryMapTileStyles.defaultStyle,
    );

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
          ),
          if (widget.bottomOverlay != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    _suppressMapTaps(const Duration(milliseconds: 1200)),
                onPointerMove: (_) =>
                    _suppressMapTaps(const Duration(milliseconds: 350)),
                onPointerUp: (_) =>
                    _suppressMapTaps(const Duration(milliseconds: 1200)),
                onPointerCancel: (_) =>
                    _suppressMapTaps(const Duration(milliseconds: 1200)),
                onPointerSignal: (_) =>
                    _suppressMapTaps(const Duration(milliseconds: 1200)),
                child: WebPointerInterceptor(child: widget.bottomOverlay!),
              ),
            ),
          if (widget.showCharacterLegend &&
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
          if (_nonGeographicRegions.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 30),
                child: _NonGeographicRegionCard(regions: _nonGeographicRegions),
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

  void _suppressMapTaps([
    Duration duration = const Duration(milliseconds: 650),
  ]) {
    _terrain3dController.suppressTapFor(duration);
  }

  void _clearMapTapSuppression() {
    _terrain3dController.clearTapSuppression();
  }

  /// 랜드마크 탭 처리. onLandmarkTap 콜백 (popup) 호출.
  void _handleLandmarkTap(Landmark landmark) {
    widget.onLandmarkTap?.call(landmark);
  }

  /// 외부 호출용 카메라 이동 (랜드마크 목록에서 항목을 골랐을 때).
  void _focusLandmark(LatLng point) {
    if (!_mapReady) return;
    _terrain3dController.moveTo(
      point,
      7.25,
      duration: const Duration(milliseconds: 420),
    );
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
      final topPadding = map_math.eventFitTopPadding(
        topObscuredPixels: widget.topObscuredPixels,
        bottomPadding: bottomPadding,
      );
      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );
      _terrain3dController.fitBounds(
        bounds,
        padding: EdgeInsets.fromLTRB(18, topPadding, 18, bottomPadding),
        maxZoom: 8.8,
        duration: const Duration(milliseconds: 520),
      );
    } catch (_) {
      /* 비가용 무시 */
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

  Map<String, LatLng> _numberedEventPointMap({required bool includeHidden}) {
    return map_math.buildRankedEventPointMap(
      widget.events,
      visibleCount: includeHidden ? null : _eventRevealCount,
      radiusDeg: 0.065,
      thresholdDeg: 0.08,
    );
  }

  /// 3D 지도에 올릴 국가 경계선과 한국어 국가 라벨 데이터를 로드한다.
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

      final borderLines3d = <List<LatLng>>[];
      final labelPoints3d = <StoryTerrainCountryLabel>[];

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
        }

        final labelPoint = _labelPoint(properties, rings.first);
        labelPoints3d.add(
          StoryTerrainCountryLabel(name: nameKo, point: labelPoint),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
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

  void _startRevealAnimation() {
    _revealRunId += 1;
    final runId = _revealRunId;
    _revealTimer?.cancel();

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
    final targetZoom = (widget.selectedFocusZoom ?? widget.initialZoom ?? 6.8)
        .clamp(4.0, 9.4)
        .toDouble();
    _terrain3dController.moveTo(
      selectedPoint,
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
    _terrain3dController.moveTo(
      selectedPoint,
      targetZoom.clamp(4.0, 9.6).toDouble(),
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
    final adjustedPointsById = _numberedEventPointMap(includeHidden: true);
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
    final bottomGap = (widget.bottomObscuredFraction * _lastMapSize.height)
        .clamp(0.0, 600.0);
    final bottomPadding = math.max(16.0, bottomGap + 8.0);
    final topPadding = map_math.eventFitTopPadding(
      topObscuredPixels: widget.topObscuredPixels,
      bottomPadding: bottomPadding,
    );
    _terrain3dController.fitBounds(
      bounds,
      padding: EdgeInsets.fromLTRB(18, topPadding, 18, bottomPadding),
      maxZoom: fittedZoom.toDouble(),
      duration: duration,
    );
  }

  void _focusToPoint(
    LatLng point,
    double zoom, {
    Duration duration = const Duration(milliseconds: 600),
  }) {
    if (!_mapReady) {
      return;
    }
    _terrain3dController.moveTo(
      point,
      zoom.clamp(_minMapZoom, _maxMapZoom).toDouble(),
      duration: duration,
    );
  }

  void zoomIn() {
    _terrain3dController.zoomIn();
  }

  void zoomOut() {
    _terrain3dController.zoomOut();
  }

  void _playHomeIntroCameraHint() {
    if (!_mapReady) {
      _pendingHomeIntroCameraHint = true;
      return;
    }
    final coordinateEvents = widget.events
        .where((event) => event.hasCoordinate)
        .toList(growable: false);
    final center =
        widget.initialCenter ??
        (coordinateEvents.isNotEmpty
            ? coordinateEvents.first.latLng
            : const LatLng(31.8, 35.2));
    final zoom = widget.initialZoom ?? 6.0;
    _terrain3dController.playHomeIntroCameraHint(
      center: center,
      zoom: zoom,
      duration: const Duration(milliseconds: 1000),
    );
  }

  void skipAnimation() {
    final all = widget.events.where((event) => event.hasCoordinate).toList();
    _revealTimer?.cancel();
    _eventRevealTimer?.cancel();
    final count = all.length;
    setState(() {
      _visibleCount = count;
      if (_orderedEventsActive) {
        _eventRevealCount = count;
      }
    });
    if (_orderedEventsActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRevealComplete?.call();
      });
    }
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

    final visiblePoints = _numberedEventPointMap(includeHidden: false);
    final finalPoints = _numberedEventPointMap(includeHidden: true);
    final fromPoint =
        visiblePoints[from.id] ?? finalPoints[from.id] ?? from.latLng;
    final toPoint = visiblePoints[to.id] ?? finalPoints[to.id] ?? to.latLng;
    final bounds = LatLngBounds.fromPoints([fromPoint, toPoint]);
    final targetZoom =
        (_computeRevealZoom([fromPoint, toPoint]) - _eventTransitionZoomOut)
            .clamp(3.0, _eventTransitionMaxZoom);
    final bottomGap = (widget.bottomObscuredFraction * _lastMapSize.height)
        .clamp(0.0, 600.0);
    final bottomPadding = math.max(44.0, bottomGap + 28.0);
    final topPadding = map_math.eventFitTopPadding(
      topObscuredPixels: widget.topObscuredPixels,
      bottomPadding: bottomPadding,
      minPadding: 24.0,
      baseGap: 10.0,
    );

    _terrain3dController.fitBounds(
      bounds,
      padding: EdgeInsets.fromLTRB(
        _eventTransitionHorizontalPadding,
        topPadding,
        _eventTransitionHorizontalPadding,
        bottomPadding,
      ),
      maxZoom: targetZoom.toDouble(),
      duration: const Duration(milliseconds: 360),
    );
    return _terrain3dController.playEventTransition(
      fromEventId: from.id,
      fromPoint: fromPoint,
      toEventId: to.id,
      toPoint: toPoint,
    );
  }

  Future<void> _playEmotionStamp({
    required StoryEvent event,
    required String stampLabel,
  }) async {
    if (!_mapReady || !event.hasCoordinate) {
      return;
    }
    final visiblePoints = _numberedEventPointMap(includeHidden: false);
    final finalPoints = _numberedEventPointMap(includeHidden: true);
    final point =
        visiblePoints[event.id] ?? finalPoints[event.id] ?? event.latLng;
    _focusToPoint(
      point,
      (widget.selectedFocusZoom ?? widget.initialZoom ?? 7.2)
          .clamp(4.2, 9.4)
          .toDouble(),
      duration: const Duration(milliseconds: 360),
    );
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _terrain3dController.playEmotionStamp(
      eventId: event.id,
      point: point,
      stampLabel: stampLabel,
    );
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
}
