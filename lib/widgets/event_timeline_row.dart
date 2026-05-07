import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/story_event.dart';
import '../utils/scene_asset_loader.dart';
import 'v2/region_event_list.dart' show StoryEventThumbCard;

/// 가로 스크롤 사건 타임라인 — 인물 모드 step 3 와 장소 모드(region 선택 후)
/// 가 공유한다. 카드 사이마다 점선 + ▶ 화살촉 connector 로 시간 흐름 시각화.
///
/// `selectedEventId` 가 set 되면 자동으로 그 카드가 viewport 가운데 오도록
/// 스크롤 (사용자가 지도 핀을 누르면 트리거).
class EventTimelineRow extends StatefulWidget {
  const EventTimelineRow({
    super.key,
    required this.events,
    required this.allEras,
    required this.charactersByCode,
    required this.selectedEventId,
    required this.onTapEvent,
    this.completedEventIds = const <String>{},
    this.cardWidth = 148,
    this.connectorWidth = 22,
    this.rowHeight,
    this.padding = const EdgeInsets.fromLTRB(14, 18, 14, 14),
  });

  final List<StoryEvent> events;
  final List<Era> allEras;
  final Map<String, Character> charactersByCode;

  /// 현재 "현재 이야기" 라벨이 붙어야 하는 사건 id. null 이면 미강조.
  /// set 변경 시 자동 스크롤로 그 카드를 viewport 중앙에 배치.
  final String? selectedEventId;

  /// 본문 + 퀴즈 모두 완료된 사건 id 셋 — 카드 배경을 초록 톤으로 표시.
  final Set<String> completedEventIds;

  final ValueChanged<StoryEvent> onTapEvent;

  final double cardWidth;
  final double connectorWidth;

  /// 명시적으로 height 를 잡고 싶을 때만 set. null 이면 부모(Expanded 등)가
  /// 잡아주는 height 를 그대로 사용. SliverToBoxAdapter 같이 height 가 필요한
  /// 곳에선 232 등 명시; Column+Expanded 안에선 null.
  final double? rowHeight;
  final EdgeInsets padding;

  @override
  State<EventTimelineRow> createState() => _EventTimelineRowState();
}

class _EventTimelineRowState extends State<EventTimelineRow> {
  final ScrollController _ctl = ScrollController();
  final SceneAssetLoader _loader = SceneAssetLoader();
  String? _lastScrolledTo;

  @override
  void didUpdateWidget(covariant EventTimelineRow old) {
    super.didUpdateWidget(old);
    final id = widget.selectedEventId;
    if (id != null && id != _lastScrolledTo) {
      _lastScrolledTo = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSelected();
      });
    } else if (id == null) {
      _lastScrolledTo = null;
    }
  }

  void _scrollToSelected() {
    final id = widget.selectedEventId;
    if (id == null) return;
    final idx = widget.events.indexWhere((e) => e.id == id);
    if (idx < 0 || !_ctl.hasClients) return;
    // 한 카드(card+connector) 의 width.
    final unit = widget.cardWidth + widget.connectorWidth;
    // 카드 좌측 좌표 — listView padding.left + idx*unit.
    final cardLeft = widget.padding.left + idx * unit;
    final viewport = _ctl.position.viewportDimension;
    // viewport 가운데에 카드 중심이 오도록.
    final target = cardLeft + widget.cardWidth / 2 - viewport / 2;
    final clamped = target.clamp(
      _ctl.position.minScrollExtent,
      _ctl.position.maxScrollExtent,
    );
    _ctl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      const empty = Center(child: Text('표시할 사건이 없습니다.'));
      return widget.rowHeight != null
          ? SizedBox(height: widget.rowHeight, child: empty)
          : empty;
    }
    final list = ListView.builder(
      controller: _ctl,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      itemCount: widget.events.length * 2 - 1,
      itemBuilder: (context, i) {
        if (i.isOdd) {
          return _DashedArrowConnector(width: widget.connectorWidth);
        }
        final idx = i ~/ 2;
        final event = widget.events[idx];
        final era = widget.allEras
            .where((e) => e.id == event.eraId)
            .firstOrNull;
        return SizedBox(
          width: widget.cardWidth,
          child: StoryEventThumbCard(
            event: event,
            era: era,
            charactersByCode: widget.charactersByCode,
            selected: event.id == widget.selectedEventId,
            completed: widget.completedEventIds.contains(event.id),
            orderNumber: idx + 1,
            loader: _loader,
            onTap: () => widget.onTapEvent(event),
          ),
        );
      },
    );
    return widget.rowHeight != null
        ? SizedBox(height: widget.rowHeight, child: list)
        : list;
  }
}

/// 사건 카드 사이 가로 점선 + ▶ 화살촉. 지도 위 dashed path 와 같은 시각 언어.
class _DashedArrowConnector extends StatelessWidget {
  const _DashedArrowConnector({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: SizedBox(
          height: 18,
          child: CustomPaint(
            painter: const _ConnectorPainter(
              color: Color(0xFF8C6743),
              strokeWidth: 1.6,
              dashLength: 4,
              gapLength: 3,
            ),
            size: Size(width, 18),
          ),
        ),
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const arrowReserve = 6.0;
    final lineEnd = size.width - arrowReserve;
    final y = size.height / 2;
    var x = 0.0;
    while (x < lineEnd) {
      final segEnd = math.min(x + dashLength, lineEnd);
      canvas.drawLine(Offset(x, y), Offset(segEnd, y), paint);
      x = segEnd + gapLength;
    }
    final arrowPath = Path()
      ..moveTo(lineEnd, y - 3)
      ..lineTo(size.width, y)
      ..lineTo(lineEnd, y + 3);
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}
