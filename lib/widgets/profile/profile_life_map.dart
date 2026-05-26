import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../state/story_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/kst_date.dart';
import '../../utils/scene_asset_loader.dart';
import '../emotion_badge_icon.dart';
import '../v2/region_event_list.dart' show StoryEventThumbCard;

class ProfileLifeMap extends ConsumerStatefulWidget {
  const ProfileLifeMap({
    super.key,
    required this.eventEmotionMarks,
    required this.quizAttemptSummaries,
    required this.onOpenEventDetail,
  });

  final Map<String, EventEmotionMark> eventEmotionMarks;
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;
  final ValueChanged<StoryEvent> onOpenEventDetail;

  @override
  ConsumerState<ProfileLifeMap> createState() => _ProfileLifeMapState();
}

class _ProfileLifeMapState extends ConsumerState<ProfileLifeMap> {
  late Future<List<StoryEvent>> _eventsFuture;
  String _eventIdFingerprint = '';

  @override
  void initState() {
    super.initState();
    _eventIdFingerprint = _fingerprint(widget.eventEmotionMarks.keys);
    _eventsFuture = _loadMarkedEvents();
  }

  @override
  void didUpdateWidget(covariant ProfileLifeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFingerprint = _fingerprint(widget.eventEmotionMarks.keys);
    if (nextFingerprint != _eventIdFingerprint) {
      _eventIdFingerprint = nextFingerprint;
      _eventsFuture = _loadMarkedEvents();
    }
  }

  Future<List<StoryEvent>> _loadMarkedEvents() {
    return ref
        .read(storyRepositoryProvider)
        .fetchEventsByIds(widget.eventEmotionMarks.keys.toSet());
  }

  String _fingerprint(Iterable<String> ids) {
    final sorted = ids.toList()..sort();
    return sorted.join('|');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoryEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <StoryEvent>[];
        final eventById = {for (final event in events) event.id: event};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LifeMapAtlas(
              marks: widget.eventEmotionMarks,
              eventById: eventById,
              onOpenRegion: _showEmotionRegionSheet,
            ),
            const SizedBox(height: 12),
            _RecentEmotionNotes(
              marks: widget.eventEmotionMarks.values.toList(),
              eventById: eventById,
              onOpenEventDetail: widget.onOpenEventDetail,
              loading: snapshot.connectionState == ConnectionState.waiting,
              hasError: snapshot.hasError,
            ),
          ],
        );
      },
    );
  }

  void _showEmotionRegionSheet({
    required _LifeRegionSpec region,
    required List<EventEmotionMark> marks,
    required Map<String, StoryEvent> eventById,
  }) {
    final state = ref.read(storyControllerProvider);
    final sortedEvents = _sortEventsByEraThenIndex(
      marks
          .map((mark) => eventById[mark.eventId])
          .whereType<StoryEvent>()
          .toList(),
      state.eras,
    );
    final charactersByCode = <String, Character>{
      for (final character in state.characters) character.code: character,
    };
    final eraById = {for (final era in state.eras) era.id: era};
    final loader = SceneAssetLoader();
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
              maxHeight: size.height * 0.76,
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
                      EmotionBadgeIcon(
                        emotionKey: region.emotionKey,
                        size: 32,
                        iconSize: 18,
                        backgroundColor: region.fillColor,
                        borderColor: region.strokeColor,
                        iconColor: AppColors.ink700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              region.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink800,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${region.label} ${marks.length}개 새김',
                              style: const TextStyle(
                                color: AppColors.ink200,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
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
                  const SizedBox(height: 12),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 228,
                          ),
                      itemCount: sortedEvents.length,
                      itemBuilder: (_, index) {
                        final event = sortedEvents[index];
                        return StoryEventThumbCard(
                          event: event,
                          era: eraById[event.eraId],
                          charactersByCode: charactersByCode,
                          selected: false,
                          completed: false,
                          emotionKey:
                              widget.eventEmotionMarks[event.id]?.emotionKey,
                          attemptSummary: widget.quizAttemptSummaries[event.id],
                          loader: loader,
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            widget.onOpenEventDetail(event);
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

  List<StoryEvent> _sortEventsByEraThenIndex(
    List<StoryEvent> events,
    List<Era> eras,
  ) {
    final orderByEraId = <String, int>{
      for (final era in eras) era.id: era.displayOrder,
    };
    final sorted = [...events];
    sorted.sort((a, b) {
      final eraOrder = (orderByEraId[a.eraId] ?? 1 << 30).compareTo(
        orderByEraId[b.eraId] ?? 1 << 30,
      );
      if (eraOrder != 0) {
        return eraOrder;
      }
      final storyOrder = a.storyIndex.compareTo(b.storyIndex);
      if (storyOrder != 0) {
        return storyOrder;
      }
      return a.globalRank.compareTo(b.globalRank);
    });
    return sorted;
  }
}

class _LifeMapAtlas extends StatelessWidget {
  const _LifeMapAtlas({
    required this.marks,
    required this.eventById,
    required this.onOpenRegion,
  });

  final Map<String, EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final void Function({
    required _LifeRegionSpec region,
    required List<EventEmotionMark> marks,
    required Map<String, StoryEvent> eventById,
  })
  onOpenRegion;

  @override
  Widget build(BuildContext context) {
    final marksByEmotion = <String, List<EventEmotionMark>>{};
    for (final mark in marks.values) {
      (marksByEmotion[mark.emotionKey] ??= <EventEmotionMark>[]).add(mark);
    }

    return Container(
      height: 292,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xAA8E6F48), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2F1D0B),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaleX = constraints.maxWidth / _lifeMapBaseWidth;
            const scaleY = 1.0;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LifeMapPainter(
                      regions: _lifeRegions,
                      counts: {
                        for (final region in _lifeRegions)
                          region.emotionKey:
                              marksByEmotion[region.emotionKey]?.length ?? 0,
                      },
                    ),
                  ),
                ),
                const Positioned(left: 15, top: 13, child: _LifeMapTitle()),
                for (final region in _lifeRegions)
                  Positioned.fromRect(
                    rect: _scaleRect(region.labelRect, scaleX, scaleY),
                    child: _LifeRegionButton(
                      region: region,
                      count: marksByEmotion[region.emotionKey]?.length ?? 0,
                      onTap: () {
                        final regionMarks =
                            marksByEmotion[region.emotionKey] ??
                            const <EventEmotionMark>[];
                        if (regionMarks.isEmpty) {
                          return;
                        }
                        onOpenRegion(
                          region: region,
                          marks: regionMarks,
                          eventById: eventById,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LifeMapTitle extends StatelessWidget {
  const _LifeMapTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '내 삶의 지도',
          style: TextStyle(
            color: AppColors.ink800,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE8D4A8),
            border: Border.all(color: const Color(0xFFB08A51), width: 0.8),
          ),
          alignment: Alignment.center,
          child: const Text(
            '?',
            style: TextStyle(
              color: AppColors.ink500,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _LifeRegionButton extends StatelessWidget {
  const _LifeRegionButton({
    required this.region,
    required this.count,
    required this.onTap,
  });

  final _LifeRegionSpec region;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : 0.58,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  region.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink700,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: const Color(0xF7FFF7E3),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: region.strokeColor, width: 1.1),
                    boxShadow: enabled
                        ? const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmotionBadgeIcon(
                        emotionKey: region.emotionKey,
                        size: 22,
                        iconSize: 13,
                        backgroundColor: const Color(0xFFFFF7E3),
                        borderColor: Colors.transparent,
                        elevation: false,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: const TextStyle(
                          color: Color(0xFF6B4A2A),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentEmotionNotes extends StatelessWidget {
  const _RecentEmotionNotes({
    required this.marks,
    required this.eventById,
    required this.onOpenEventDetail,
    required this.loading,
    required this.hasError,
  });

  final List<EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final ValueChanged<StoryEvent> onOpenEventDetail;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final sorted = [...marks]..sort(_compareMarksNewestFirst);
    final recent = sorted.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x99D6BF8D), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '최근 남긴 한 줄',
            style: TextStyle(
              color: AppColors.ink800,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          if (loading && recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
            )
          else if (recent.isEmpty)
            const _LifeMapEmptyMessage(
              message: '아직 지도에 새긴 한 줄이 없습니다.\n이야기 상세에서 감정과 메모를 남겨보세요.',
            )
          else ...[
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) const Divider(height: 16, color: Color(0x55BCA47A)),
              _RecentEmotionNoteRow(
                mark: recent[i],
                event: eventById[recent[i].eventId],
                onOpenEventDetail: onOpenEventDetail,
              ),
            ],
            if (hasError)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '일부 이야기 정보를 불러오지 못했습니다.',
                  style: TextStyle(
                    color: AppColors.dangerBot,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecentEmotionNoteRow extends StatelessWidget {
  const _RecentEmotionNoteRow({
    required this.mark,
    required this.event,
    required this.onOpenEventDetail,
  });

  final EventEmotionMark mark;
  final StoryEvent? event;
  final ValueChanged<StoryEvent> onOpenEventDetail;

  @override
  Widget build(BuildContext context) {
    final note = mark.note.trim().isEmpty
        ? '${mark.emotionLabel}으로 새겼어요.'
        : mark.note.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: event == null ? null : () => onOpenEventDetail(event!),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              EmotionBadgeIcon(
                emotionKey: mark.emotionKey,
                size: 24,
                iconSize: 14,
                elevation: false,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event?.title ?? '이야기 정보를 불러오는 중',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink200,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink700,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatMonthDay(mark.updatedAt),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink300,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LifeMapEmptyMessage extends StatelessWidget {
  const _LifeMapEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.ink300,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

class _LifeMapPainter extends CustomPainter {
  const _LifeMapPainter({required this.regions, required this.counts});

  final List<_LifeRegionSpec> regions;
  final Map<String, int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    final parchment = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.35),
        radius: 1.1,
        colors: [Color(0xFFFFF8E8), Color(0xFFF1DEB7)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, parchment);

    _drawTexture(canvas, size);

    for (final region in regions) {
      final count = counts[region.emotionKey] ?? 0;
      final path = _scaledPath(region.path, size);
      final fill = Paint()
        ..color = region.fillColor.withValues(alpha: count > 0 ? 0.78 : 0.34)
        ..style = PaintingStyle.fill;
      final shadow = Paint()
        ..color = const Color(0x1F2F1D0B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawPath(path.shift(const Offset(0, 2)), shadow);
      canvas.drawPath(path, fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = region.strokeColor.withValues(
            alpha: count > 0 ? 0.74 : 0.38,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = count > 0 ? 1.5 : 1.0,
      );
    }

    _drawCompass(canvas, size);
  }

  void _drawTexture(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x10A27D45)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 18; i++) {
      final y = 20.0 + i * 15.0;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 40) {
        path.quadraticBezierTo(
          x + 18,
          y + math.sin(i + x / 40) * 3,
          x + 40,
          y + math.cos(i + x / 30) * 2,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawCompass(Canvas canvas, Size size) {
    final center = Offset(size.width - 38, size.height - 34);
    final paint = Paint()
      ..color = const Color(0x66896A3E)
      ..strokeWidth = 1;
    canvas.drawCircle(center, 16, paint..style = PaintingStyle.stroke);
    for (var i = 0; i < 8; i++) {
      final angle = math.pi * 2 * i / 8;
      final long = i.isEven ? 16.0 : 10.0;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * long,
        paint,
      );
    }
  }

  Path _scaledPath(Path Function(Size size) builder, Size size) =>
      builder(size);

  @override
  bool shouldRepaint(covariant _LifeMapPainter oldDelegate) {
    return oldDelegate.counts != counts;
  }
}

class _LifeRegionSpec {
  const _LifeRegionSpec({
    required this.emotionKey,
    required this.label,
    required this.name,
    required this.fillColor,
    required this.strokeColor,
    required this.labelRect,
    required this.path,
  });

  final String emotionKey;
  final String label;
  final String name;
  final Color fillColor;
  final Color strokeColor;
  final Rect labelRect;
  final Path Function(Size size) path;
}

int _compareMarksNewestFirst(EventEmotionMark a, EventEmotionMark b) {
  final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final timeCompare = bTime.compareTo(aTime);
  if (timeCompare != 0) return timeCompare;
  return a.eventId.compareTo(b.eventId);
}

String _formatMonthDay(DateTime? dateTime) {
  return formatKoreanMonthDayKst(dateTime);
}

Path _blob(Size size, List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx * size.width, points.first.dy * size.height);
  for (var i = 0; i < points.length; i++) {
    final current = points[i];
    final next = points[(i + 1) % points.length];
    final control = Offset(
      (current.dx + next.dx) * size.width / 2,
      (current.dy + next.dy) * size.height / 2,
    );
    path.quadraticBezierTo(
      control.dx,
      control.dy,
      next.dx * size.width,
      next.dy * size.height,
    );
  }
  path.close();
  return path;
}

final _lifeRegions = <_LifeRegionSpec>[
  _LifeRegionSpec(
    emotionKey: 'anticipation',
    label: '기대',
    name: '기대의 들판',
    fillColor: const Color(0xFFE7C26D),
    strokeColor: const Color(0xFF9C7337),
    labelRect: const Rect.fromLTWH(18, 55, 118, 58),
    path: (size) => _blob(size, const [
      Offset(0.02, 0.17),
      Offset(0.32, 0.11),
      Offset(0.39, 0.28),
      Offset(0.24, 0.44),
      Offset(0.03, 0.38),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'wonder',
    label: '놀라움',
    name: '놀라움의 언덕',
    fillColor: const Color(0xFFDCCBA6),
    strokeColor: const Color(0xFF8C7B58),
    labelRect: const Rect.fromLTWH(147, 41, 110, 58),
    path: (size) => _blob(size, const [
      Offset(0.31, 0.09),
      Offset(0.64, 0.04),
      Offset(0.72, 0.23),
      Offset(0.56, 0.35),
      Offset(0.37, 0.29),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'comfort',
    label: '위로',
    name: '위로의 숲',
    fillColor: const Color(0xFFB9C9A0),
    strokeColor: const Color(0xFF5D7A4B),
    labelRect: const Rect.fromLTWH(267, 75, 96, 58),
    path: (size) => _blob(size, const [
      Offset(0.66, 0.18),
      Offset(0.98, 0.12),
      Offset(0.98, 0.43),
      Offset(0.80, 0.50),
      Offset(0.63, 0.36),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'other',
    label: '기타',
    name: '기타의 마을',
    fillColor: const Color(0xFFD8B989),
    strokeColor: const Color(0xFF8A6842),
    labelRect: const Rect.fromLTWH(197, 128, 107, 58),
    path: (size) => _blob(size, const [
      Offset(0.50, 0.37),
      Offset(0.77, 0.37),
      Offset(0.81, 0.59),
      Offset(0.62, 0.70),
      Offset(0.46, 0.57),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'joy',
    label: '기쁨',
    name: '기쁨의 정원',
    fillColor: const Color(0xFFE9D58A),
    strokeColor: const Color(0xFFA38335),
    labelRect: const Rect.fromLTWH(90, 128, 104, 58),
    path: (size) => _blob(size, const [
      Offset(0.25, 0.35),
      Offset(0.51, 0.31),
      Offset(0.53, 0.58),
      Offset(0.38, 0.72),
      Offset(0.18, 0.59),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'fear',
    label: '두려움',
    name: '두려움의 끝자락',
    fillColor: const Color(0xFFC8C6B7),
    strokeColor: const Color(0xFF75715E),
    labelRect: const Rect.fromLTWH(21, 193, 126, 58),
    path: (size) => _blob(size, const [
      Offset(0.01, 0.57),
      Offset(0.26, 0.56),
      Offset(0.35, 0.78),
      Offset(0.16, 0.94),
      Offset(0.00, 0.86),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'gratitude',
    label: '감사',
    name: '감사의 샘',
    fillColor: const Color(0xFFA9C0B2),
    strokeColor: const Color(0xFF577B66),
    labelRect: const Rect.fromLTWH(209, 212, 100, 58),
    path: (size) => _blob(size, const [
      Offset(0.49, 0.62),
      Offset(0.78, 0.59),
      Offset(0.88, 0.87),
      Offset(0.62, 0.95),
      Offset(0.43, 0.82),
    ]),
  ),
  _LifeRegionSpec(
    emotionKey: 'sadness',
    label: '안타까움',
    name: '안타까움의 골짜기',
    fillColor: const Color(0xFFB8C5CA),
    strokeColor: const Color(0xFF607680),
    labelRect: const Rect.fromLTWH(307, 181, 108, 58),
    path: (size) => _blob(size, const [
      Offset(0.75, 0.52),
      Offset(0.99, 0.49),
      Offset(0.99, 0.83),
      Offset(0.86, 0.94),
      Offset(0.72, 0.78),
    ]),
  ),
];

const double _lifeMapBaseWidth = 430;

Rect _scaleRect(Rect rect, double scaleX, double scaleY) {
  return Rect.fromLTWH(
    rect.left * scaleX,
    rect.top * scaleY,
    rect.width * scaleX,
    rect.height * scaleY,
  );
}
