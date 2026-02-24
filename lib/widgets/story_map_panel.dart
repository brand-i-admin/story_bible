import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/story_event.dart';
import 'game_ui_skin.dart';

class StoryMapPanel extends StatefulWidget {
  const StoryMapPanel({
    super.key,
    required this.events,
    required this.selectedEventId,
    required this.onSelectEvent,
    this.onOpenDetail,
    required this.colorForPerson,
    required this.avatarAssetForPerson,
    required this.selectedPersonIds,
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
  });

  final List<StoryEvent> events;
  final String? selectedEventId;
  final ValueChanged<String> onSelectEvent;
  final ValueChanged<String>? onOpenDetail;
  final Color Function(String personId) colorForPerson;
  final String Function(String personId) avatarAssetForPerson;
  final Set<String> selectedPersonIds;
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
  double _segmentT = 0;
  bool _isAnimatingPath = false;
  Size _lastMapSize = const Size(900, 600);
  int _revealRunId = 0;
  bool _mapReady = false;

  static const _PinStyle _normalPinStyle = _PinStyle(
    // Doubled from the previous size.
    size: 70,
    avatarDiameter: 30,
    avatarAlignment: Alignment(-0.002, -0.34),
  );
  static const _PinStyle _selectedPinStyle = _PinStyle(
    // Keep selected marker at the same size as normal to avoid jump on select.
    size: 70,
    avatarDiameter: 30,
    avatarAlignment: Alignment(-0.002, -0.34),
  );

  static const double _selectedCalloutEstimatedHeight = 176;
  static const double _selectedCalloutTopMargin = 14;

  _PinStyle _scaledPinStyle(_PinStyle base) {
    final scale = widget.pinScale.clamp(0.6, 1.25);
    return _PinStyle(
      size: base.size * scale,
      avatarDiameter: base.avatarDiameter * scale,
      avatarAlignment: base.avatarAlignment,
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

    if (_signature(oldWidget.events) != _signature(widget.events) ||
        oldWidget.selectedPersonIds != widget.selectedPersonIds) {
      _startRevealAnimation();
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
                  MarkerLayer(markers: _countryLabelMarkers),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: _buildRegionLabels()),
                  MarkerLayer(markers: _buildMarkers(widget.events)),
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
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildPolylines(List<StoryEvent> events) {
    final allWithCoords = events.where((event) => event.hasCoordinate).toList();
    final adjustedAll = _buildAdjustedPoints(allWithCoords);
    final visible = events
        .where((event) => event.hasCoordinate)
        .take(_visibleCount)
        .toList();
    final visiblePoints = visible
        .map((event) => adjustedAll[event.id] ?? event.latLng)
        .toList();
    final polylines = <Polyline>[];

    for (var i = 0; i < visiblePoints.length - 1; i++) {
      final eventColor = _markerColorForEvent(visible[i]);
      polylines.add(
        Polyline(
          points: [visiblePoints[i], visiblePoints[i + 1]],
          color: eventColor.withValues(alpha: 0.9),
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: [3.5, 7]),
        ),
      );
    }

    if (_isAnimatingPath &&
        _visibleCount > 0 &&
        _visibleCount < allWithCoords.length) {
      final from =
          adjustedAll[allWithCoords[_visibleCount - 1].id] ??
          allWithCoords[_visibleCount - 1].latLng;
      final to =
          adjustedAll[allWithCoords[_visibleCount].id] ??
          allWithCoords[_visibleCount].latLng;
      final animatedEnd = LatLng(
        from.latitude + (to.latitude - from.latitude) * _segmentT,
        from.longitude + (to.longitude - from.longitude) * _segmentT,
      );

      polylines.add(
        Polyline(
          points: [from, animatedEnd],
          color: _markerColorForEvent(
            allWithCoords[_visibleCount - 1],
          ).withValues(alpha: 0.85),
          strokeWidth: 4.5,
          pattern: const StrokePattern.dotted(),
        ),
      );
    }

    return polylines;
  }

  List<Marker> _buildMarkers(List<StoryEvent> events) {
    final withCoordinate = events
        .where((event) => event.hasCoordinate)
        .toList();
    final visible = withCoordinate.take(_visibleCount).toList();
    final orderedEntries = visible.asMap().entries.toList()
      ..sort((a, b) {
        final aSelected = a.value.id == widget.selectedEventId;
        final bSelected = b.value.id == widget.selectedEventId;
        if (aSelected == bSelected) {
          return 0;
        }
        return aSelected ? 1 : -1;
      });
    // Keep offsets stable by calculating from the full visible timeline.
    final adjustedPoints = _buildAdjustedPoints(withCoordinate);

    return orderedEntries.map((entry) {
      final event = entry.value;
      final selected = widget.selectedEventId == event.id;
      final colors = _colorsForEvent(event);
      final pinAsset = selected ? kPinSelectedAsset : kPinNormalAsset;
      final pinStyle = _scaledPinStyle(
        selected ? _selectedPinStyle : _normalPinStyle,
      );
      final primaryPersonId = _primaryPersonIdForEvent(event);
      final avatarAssetPath = primaryPersonId == null
          ? ''
          : widget.avatarAssetForPerson(primaryPersonId);
      final shortText =
          (event.shortStory ??
                  event.shortText ??
                  event.story ??
                  event.summary ??
                  '')
              .trim();
      final markerWidth = selected ? 338.0 : 150.0;
      final markerHeight = selected ? 320.0 : pinStyle.size;
      final placeName = (event.placeName ?? '').trim();
      final hasPlaceName = placeName.isNotEmpty;

      return Marker(
        point: adjustedPoints[event.id] ?? event.latLng,
        width: markerWidth,
        height: markerHeight,
        // Anchor geographic point to the marker widget's bottom center
        // (pin tip), so zoom/selection never drifts.
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: markerWidth,
          height: markerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (selected && widget.showSelectedCallout)
                Positioned(
                  bottom: pinStyle.size - 8,
                  child: _buildEventCallout(
                    event: event,
                    shortText: shortText,
                    onOpenDetail: widget.onOpenDetail,
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onSelectEvent(event.id),
                child: SizedBox(
                  width: pinStyle.size,
                  height: pinStyle.size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(pinAsset, fit: BoxFit.contain),
                      Align(
                        alignment: pinStyle.avatarAlignment,
                        child: _buildPinAvatar(
                          event: event,
                          avatarAssetPath: avatarAssetPath,
                          diameter: pinStyle.avatarDiameter,
                          selected: selected,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasPlaceName)
                Positioned(
                  bottom: -24,
                  child: IgnorePointer(
                    child: _buildPlaceChip(placeName, selected: selected),
                  ),
                ),
              if (colors.length > 1)
                Positioned(
                  bottom: hasPlaceName ? -40 : -16,
                  child: IgnorePointer(child: _buildPersonColorDots(colors)),
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

  Widget _buildPersonColorDots(List<Color> colors) {
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

  String? _primaryPersonIdForEvent(StoryEvent event) {
    for (final personId in event.personIds) {
      if (widget.selectedPersonIds.contains(personId)) {
        return personId;
      }
    }
    return event.personIds.firstOrNull;
  }

  Widget _buildPinAvatar({
    required StoryEvent event,
    required String avatarAssetPath,
    required double diameter,
    required bool selected,
  }) {
    final path = avatarAssetPath.trim();
    final fallbackText = _avatarFallbackText(event);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFFFF3D3) : const Color(0xFFF3E7CC),
          width: selected ? 1.8 : 1.4,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: path.isNotEmpty
            ? Image.asset(
                path,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _buildAvatarFallback(fallbackText, selected: selected),
              )
            : _buildAvatarFallback(fallbackText, selected: selected),
      ),
    );
  }

  Widget _buildAvatarFallback(String fallbackText, {required bool selected}) {
    return Container(
      color: selected ? const Color(0xFFC88A31) : const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        fallbackText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? const Color(0xFFFFF8E9) : const Color(0xFFF3EAD6),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _avatarFallbackText(StoryEvent event) {
    final title = event.title.trim();
    if (title.isEmpty) {
      return '?';
    }
    return title.substring(0, 1);
  }

  Widget _buildEventCallout({
    required StoryEvent event,
    required String shortText,
    required ValueChanged<String>? onOpenDetail,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 268),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: shortDescriptionDecoration(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF3D2D18),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (shortText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  shortText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4C3A21),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: onOpenDetail == null
                      ? null
                      : () => onOpenDetail(event.id),
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 96,
                      minHeight: 30,
                    ),
                    decoration: actionButtonDecoration(selected: true),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: const Text(
                      '자세히 보기',
                      style: TextStyle(
                        color: Color(0xFFFDF8EE),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Color(0xAA000000),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
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
    );
  }

  Map<String, LatLng> _buildAdjustedPoints(List<StoryEvent> visible) {
    final grouped = <String, List<StoryEvent>>{};
    for (final event in visible) {
      final key =
          '${event.lat!.toStringAsFixed(2)}:${event.lng!.toStringAsFixed(2)}';
      grouped.putIfAbsent(key, () => []).add(event);
    }

    final adjusted = <String, LatLng>{};
    for (final group in grouped.values) {
      if (group.length == 1) {
        final event = group.first;
        adjusted[event.id] = event.latLng;
        continue;
      }

      final radiusDeg = group.length > 6 ? 0.10 : 0.065;
      final baseLat = group.first.lat!;
      final cosLat = math.cos(baseLat * math.pi / 180).abs().clamp(0.3, 1.0);
      for (var i = 0; i < group.length; i++) {
        final angle = (2 * math.pi * i) / group.length;
        final dLat = radiusDeg * math.sin(angle);
        final dLng = (radiusDeg * math.cos(angle)) / cosLat;
        final event = group[i];
        adjusted[event.id] = LatLng(event.lat! + dLat, event.lng! + dLng);
      }
    }
    return adjusted;
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
                    color: Color(0xFFF8EED9),
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
      setState(() {
        _visibleCount = 0;
        _segmentT = 0;
        _isAnimatingPath = false;
      });
      return;
    }

    if (!widget.animateReveal) {
      setState(() {
        _visibleCount = withCoordinate.length;
        _segmentT = 1;
        _isAnimatingPath = false;
      });
      return;
    }

    setState(() {
      _visibleCount = 1;
      _segmentT = 0;
      _isAnimatingPath = withCoordinate.length > 1;
    });

    final points = withCoordinate.map((event) => event.latLng).toList();
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

    Future.delayed(const Duration(milliseconds: 730), () {
      if (!mounted || runId != _revealRunId) {
        return;
      }

      _revealTimer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
        if (!mounted || runId != _revealRunId) {
          timer.cancel();
          return;
        }

        setState(() {
          _segmentT += 0.045;
        });

        if (_segmentT >= 1) {
          setState(() {
            _visibleCount += 1;
            _segmentT = 0;
            _isAnimatingPath = _visibleCount < withCoordinate.length;
          });
        }

        if (_visibleCount >= withCoordinate.length) {
          timer.cancel();
        }
      });
    });
  }

  void _focusSelectedEventIfNeeded() {
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

    final adjusted = _buildAdjustedPoints(withCoordinate);
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
    final calloutTop =
        selectedOffset.dy -
        _selectedPinStyle.size -
        _selectedCalloutEstimatedHeight;
    final minimumPointY =
        _selectedPinStyle.size +
        _selectedCalloutEstimatedHeight +
        _selectedCalloutTopMargin;
    final needsFocus =
        calloutTop < _selectedCalloutTopMargin ||
        selectedOffset.dy < minimumPointY;
    if (!needsFocus) {
      return;
    }

    final maxPointY = math.max(minimumPointY, size.height - 88);
    final targetY = (size.height * 0.62).clamp(minimumPointY, maxPointY);
    final targetOffset = Offset(size.width / 2, targetY);
    final targetZoom = math.min(camera.zoom, 7.7);
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
    final points = widget.events
        .where((event) => event.hasCoordinate)
        .map((event) => event.latLng)
        .toList(growable: false);
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      final singleZoom = ((widget.initialZoom ?? 5.3) + 0.35).clamp(2.4, 13.0);
      _focusToPoint(points.first, singleZoom, duration: duration);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    // Keep a small safety margin so all pin heads remain visible.
    final zoomAdjust = widget.fitAllZoomAdjust.clamp(-2.0, 2.0);
    final fittedZoom = (_computeRevealZoom(points) + zoomAdjust).clamp(
      2.4,
      13.0,
    );
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
    final offsetFromCenter = _rotateOffset(
      targetOffset - viewportCenter,
      camera.rotationRad,
    );
    final projectedCenter = projectedPoint - offsetFromCenter;
    return camera.unprojectAtZoom(projectedCenter, zoom);
  }

  Offset _rotateOffset(Offset value, double radians) {
    final cosTheta = math.cos(radians);
    final sinTheta = math.sin(radians);
    return Offset(
      value.dx * cosTheta - value.dy * sinTheta,
      value.dx * sinTheta + value.dy * cosTheta,
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
      final eased = _easeInOut(t);

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
    if (all.isEmpty) {
      setState(() {
        _visibleCount = 0;
        _segmentT = 1;
        _isAnimatingPath = false;
      });
      return;
    }

    setState(() {
      _visibleCount = all.length;
      _segmentT = 1;
      _isAnimatingPath = false;
    });
  }

  List<Color> _colorsForEvent(StoryEvent event) {
    if (event.personIds.isNotEmpty) {
      final colors = <Color>[];
      final seen = <Color>{};
      for (final id in event.personIds.where(
        widget.selectedPersonIds.contains,
      )) {
        final color = widget.colorForPerson(id);
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

  Color _markerColorForEvent(StoryEvent event) {
    return _colorsForEvent(event).firstOrNull ?? const Color(0xFF6C5A44);
  }

  double _easeInOut(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  }

  String _signature(List<StoryEvent> events) {
    return events.map((event) => event.id).join('|');
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
    final lonSpan = _normalizedLongitudeDelta(
      bounds.west,
      bounds.east,
    ).clamp(0.000001, 360.0);
    final northY = _mercatorY(bounds.north);
    final southY = _mercatorY(bounds.south);
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

  double _mercatorY(double latitude) {
    final clampedLatitude = latitude.clamp(-85.05112878, 85.05112878);
    final sinValue = math.sin(clampedLatitude * math.pi / 180.0);
    return 0.5 - math.log((1 + sinValue) / (1 - sinValue)) / (4 * math.pi);
  }

  double _normalizedLongitudeDelta(double west, double east) {
    final delta = (east - west).abs();
    if (delta <= 180.0) {
      return delta;
    }
    return 360.0 - delta;
  }

  dynamic _safeCamera() {
    try {
      return _controller.camera;
    } catch (_) {
      return null;
    }
  }
}

class _PinStyle {
  const _PinStyle({
    required this.size,
    required this.avatarDiameter,
    required this.avatarAlignment,
  });

  final double size;
  final double avatarDiameter;
  final Alignment avatarAlignment;
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
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
}
