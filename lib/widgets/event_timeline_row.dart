import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/quiz_attempt_summary.dart';
import '../models/story_event.dart';
import '../utils/scene_asset_loader.dart';
import 'completion_celebration.dart';
import 'v2/region_event_list.dart' show StoryEventThumbCard;

double eventTimelineRowHeightFor(BuildContext context, {required double base}) {
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  final extra = ((textScale - 1) * 90).clamp(0.0, 40.0).toDouble();
  return base + extra;
}

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
    this.quizReviewEventIds = const <String>{},
    this.quizConfusedEventIds = const <String>{},
    this.eventEmotionMarks = const {},
    this.quizAttemptSummaries = const {},
    this.cardWidth = 148,
    this.connectorWidth = 22,
    this.rowHeight,
    this.padding = const EdgeInsets.fromLTRB(14, 18, 14, 14),
    this.highlightedCharacterCodes = const <String>{},
    this.colorForHighlightedCharacter,
    this.orderNumberBuilder,
    this.celebrationEventId,
    this.celebrationStampLabel,
    this.celebrationNonce = 0,
    this.onCelebrationComplete,
    this.publicUrlForStoragePath,
  });

  final List<StoryEvent> events;
  final List<Era> allEras;
  final Map<String, Character> charactersByCode;

  /// 카드 안 인물 pill 중 강조해 앞쪽에 배치할 인물 코드. 인물 모드 step 3
  /// 에서 사용자가 고른 인물 set 을 부모가 넘긴다. 비어 있으면 모든 pill
  /// default 톤 + 원래 순서.
  final Set<String> highlightedCharacterCodes;

  /// highlighted 인물의 강조 색을 반환. 일반적으로 부모의 `colorForCharacter`
  /// (지도 path 색) 을 그대로 넘긴다.
  final Color Function(String characterCode)? colorForHighlightedCharacter;

  /// 카드 좌상단 순서 번호를 외부 정렬 기준으로 맞춰야 할 때 사용한다.
  /// null 이면 현재 row 안의 1-based index 를 쓴다.
  final int Function(StoryEvent event, int index)? orderNumberBuilder;

  /// 현재 "현재 이야기" 라벨이 붙어야 하는 사건 id. null 이면 미강조.
  /// set 변경 시 자동 스크롤로 그 카드를 viewport 중앙에 배치.
  final String? selectedEventId;

  /// 본문 + 퀴즈 모두 완료된 사건 id 셋 — 카드 배경을 초록 톤으로 표시.
  final Set<String> completedEventIds;

  /// 최근 퀴즈에서 오답이나 "헷갈렸어요"가 있었던 사건 id 셋.
  final Set<String> quizReviewEventIds;

  /// 최근 퀴즈에서 "헷갈렸어요" 선택이 있었던 사건 id 셋.
  final Set<String> quizConfusedEventIds;

  /// 사용자가 지도 위에 새긴 감정. 카드 번호 배지 옆의 작은 아이콘으로 표시한다.
  final Map<String, EventEmotionMark> eventEmotionMarks;

  /// 이야기별 최근 퀴즈 결과. 카드 배경색으로 복습 필요 정도를 표시한다.
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;

  /// 지도 화면에서 특정 사건 카드 위에 완료 축하 효과를 1회 재생할 때 사용.
  final String? celebrationEventId;
  final String? celebrationStampLabel;
  final int celebrationNonce;
  final VoidCallback? onCelebrationComplete;
  final String Function(String storagePath)? publicUrlForStoragePath;

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
  final GlobalKey<CompletionCelebrationState> _celebrationKey =
      GlobalKey<CompletionCelebrationState>();
  String? _lastScrolledTo;
  bool _didInitialNudge = false;
  int _lastCelebrationNonce = 0;
  int? _playedCelebrationNonce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRunInitialNudge();
    });
    _maybeTriggerCelebration();
  }

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
    // events 가 바뀌면 (region 재선택) shimmy 한 번 더.
    if (!_eventsIdentical(old.events, widget.events)) {
      _didInitialNudge = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRunInitialNudge();
      });
    }
    _maybeTriggerCelebration();
  }

  void _maybeTriggerCelebration() {
    if (widget.celebrationEventId == null || widget.celebrationNonce <= 0) {
      return;
    }
    if (widget.celebrationNonce == _lastCelebrationNonce) {
      return;
    }
    final nonce = widget.celebrationNonce;
    _lastCelebrationNonce = nonce;
    _playedCelebrationNonce = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryPlayCelebration(nonce);
    });
    Future<void>.delayed(const Duration(milliseconds: 430), () {
      if (mounted) _tryPlayCelebration(nonce);
    });
  }

  void _tryPlayCelebration(int nonce) {
    if (_playedCelebrationNonce == nonce || widget.celebrationNonce != nonce) {
      return;
    }
    final celebrationState = _celebrationKey.currentState;
    if (celebrationState == null) {
      return;
    }
    _playedCelebrationNonce = nonce;
    celebrationState.play(stampLabel: widget.celebrationStampLabel);
  }

  bool _eventsIdentical(List<StoryEvent> a, List<StoryEvent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// 카드가 viewport 보다 길고 selectedEventId 가 없을 때, 등장 시
  /// 0 → 60 → 0 으로 한 번 들썩여 "오른쪽에 더 있음" affordance.
  Future<void> _maybeRunInitialNudge() async {
    if (_didInitialNudge) return;
    if (!_ctl.hasClients) return;
    if (_ctl.position.maxScrollExtent <= 0) return;
    if (widget.selectedEventId != null) {
      // _scrollToSelected 가 따로 돌므로 nudge 는 skip.
      _didInitialNudge = true;
      return;
    }
    _didInitialNudge = true;
    const peak = 60.0;
    try {
      await _ctl.animateTo(
        peak,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || !_ctl.hasClients) return;
      await _ctl.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // dispose 등으로 controller 가 detach 되면 무시.
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
        final card = StoryEventThumbCard(
          event: event,
          era: era,
          charactersByCode: widget.charactersByCode,
          selected: event.id == widget.selectedEventId,
          completed: widget.completedEventIds.contains(event.id),
          needsQuizReview: widget.quizReviewEventIds.contains(event.id),
          hasConfusedQuiz: widget.quizConfusedEventIds.contains(event.id),
          emotionKey: widget.eventEmotionMarks[event.id]?.emotionKey,
          attemptSummary: widget.quizAttemptSummaries[event.id],
          orderNumber: widget.orderNumberBuilder?.call(event, idx) ?? idx + 1,
          loader: _loader,
          publicUrlForStoragePath: widget.publicUrlForStoragePath,
          onTap: () => widget.onTapEvent(event),
          highlightedCharacterCodes: widget.highlightedCharacterCodes,
          colorForHighlightedCharacter: widget.colorForHighlightedCharacter,
        );
        return SizedBox(
          width: widget.cardWidth,
          child: event.id == widget.celebrationEventId
              ? CompletionCelebration(
                  key: _celebrationKey,
                  stampLabel: widget.celebrationStampLabel ?? '완료',
                  onComplete: widget.onCelebrationComplete,
                  child: card,
                )
              : card,
        );
      },
    );
    // 우측 페이드 — overflow 가 있고 끝까지 안 갔을 때만 fade. ShaderMask 는
    // 항상 배치하고 색만 토글해서 setState 없이 _ctl 알림만으로 동기.
    final faded = AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        final hasOverflow =
            _ctl.hasClients && _ctl.position.maxScrollExtent > 0;
        final atEnd =
            !hasOverflow ||
            _ctl.position.pixels >= _ctl.position.maxScrollExtent - 4;
        final fadeOn = hasOverflow && !atEnd;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.92, 1.0],
            colors: [
              Colors.white,
              Colors.white,
              fadeOn ? const Color(0x00FFFFFF) : Colors.white,
            ],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: child!,
        );
      },
      child: list,
    );
    return widget.rowHeight != null
        ? SizedBox(height: widget.rowHeight, child: faded)
        : faded;
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
