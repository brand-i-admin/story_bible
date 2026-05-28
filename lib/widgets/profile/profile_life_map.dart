import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../state/story_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/kst_date.dart';
import '../emotion_badge_icon.dart';
import '../parchment_dialog.dart';
import 'profile_event_review_grid.dart';

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
              onOpenHelp: _showLifeMapHelpDialog,
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
    final events = marks
        .map((mark) => eventById[mark.eventId])
        .whereType<StoryEvent>()
        .toList();
    final charactersByCode = <String, Character>{
      for (final character in state.characters) character.code: character,
    };
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
                    child: ProfileEventReviewGrid(
                      events: events,
                      eras: state.eras,
                      charactersByCode: charactersByCode,
                      completedEventIds: state.completedEventIds,
                      eventEmotionMarks: widget.eventEmotionMarks,
                      quizAttemptSummaries: widget.quizAttemptSummaries,
                      emptyText: '이 감정으로 새긴 이야기가 없습니다.',
                      crossAxisCount: 2,
                      mainAxisExtent: 242,
                      onOpenEventDetail: (event) {
                        Navigator.of(dialogContext).pop();
                        widget.onOpenEventDetail(event);
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

  void _showLifeMapHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.58;
        return ParchmentDialog(
          title: '내 삶의 지도 안내',
          subtitle: '성경 이야기 위에 남긴 나의 감정 기록을 한눈에 돌아보는 공간입니다.',
          showCloseButton: true,
          actions: [
            ParchmentDialogActionButton(
              label: '알겠어요',
              style: ParchmentDialogActionStyle.secondary,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.min(maxHeight, 460)),
            child: const SingleChildScrollView(child: _LifeMapHelpContent()),
          ),
        );
      },
    );
  }
}

class _LifeMapAtlas extends StatelessWidget {
  const _LifeMapAtlas({
    required this.marks,
    required this.eventById,
    required this.onOpenRegion,
    required this.onOpenHelp,
  });

  final Map<String, EventEmotionMark> marks;
  final Map<String, StoryEvent> eventById;
  final void Function({
    required _LifeRegionSpec region,
    required List<EventEmotionMark> marks,
    required Map<String, StoryEvent> eventById,
  })
  onOpenRegion;
  final VoidCallback onOpenHelp;

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
                Positioned(
                  left: 15,
                  top: 13,
                  child: _LifeMapTitle(onOpenHelp: onOpenHelp),
                ),
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
  const _LifeMapTitle({required this.onOpenHelp});

  final VoidCallback onOpenHelp;

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
        Tooltip(
          message: '내 삶의 지도 안내',
          child: Semantics(
            button: true,
            label: '내 삶의 지도 안내 열기',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onOpenHelp,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE8D4A8),
                    border: Border.all(
                      color: const Color(0xFFB08A51),
                      width: 0.8,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: AppColors.ink500,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LifeMapHelpContent extends StatelessWidget {
  const _LifeMapHelpContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LifeMapHelpParagraph(
          text:
              '내 삶의 지도는 성경 이야기를 읽고 퀴즈를 푼 뒤, 지도 위에 새긴 나의 감정을 모아 보여주는 감정 지도입니다. 기쁨, 기대, 감사, 놀라움, 안타까움, 위로, 두려움, 기타 감정이 각각 하나의 지역처럼 표시됩니다.',
        ),
        SizedBox(height: 12),
        _LifeMapHelpSection(
          icon: Icons.touch_app_rounded,
          title: '어떻게 쓰나요?',
          body:
              '감정 지역을 누르면 그 감정을 느꼈던 성경 이야기들이 다시 모입니다. 예를 들어 위로 지역을 누르면, 내가 위로를 새겼던 이야기들을 한 번에 복습할 수 있습니다.',
        ),
        SizedBox(height: 10),
        _LifeMapHelpSection(
          icon: Icons.insights_rounded,
          title: '어떤 인사이트를 얻나요?',
          body:
              '어떤 감정이 자주 쌓이는지 보면 요즘 내가 말씀을 어떤 시선으로 만나고 있는지 볼 수 있습니다. 감사가 많다면 은혜를 발견하는 눈이 자라고 있는 것이고, 두려움이나 안타까움이 많다면 하나님 앞에 더 오래 머물러야 할 주제가 보일 수 있습니다.',
        ),
        SizedBox(height: 10),
        _LifeMapHelpSection(
          icon: Icons.auto_stories_rounded,
          title: '더 잘 쓰는 방법',
          body:
              '이야기를 끝낼 때 감정만 고르지 말고 한 줄 메모를 짧게 남겨보세요. 시간이 지난 뒤 같은 감정 지역을 열어보면, 내가 어떤 말씀 앞에서 반복해서 멈춰 섰는지 더 선명하게 보입니다.',
        ),
        SizedBox(height: 10),
        _LifeMapHelpSection(
          icon: Icons.map_rounded,
          title: '개수는 무엇을 말하나요?',
          body:
              '각 지역의 숫자는 그 감정으로 새긴 이야기 수입니다. 숫자의 크고 작음은 점수가 아니라, 지금까지 하나님 말씀과 만난 흔적의 분포입니다. 전체 지도가 넓어질수록 내 삶을 바라보는 시야도 함께 넓어집니다.',
        ),
      ],
    );
  }
}

class _LifeMapHelpParagraph extends StatelessWidget {
  const _LifeMapHelpParagraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.ink700,
        fontSize: 13.2,
        fontWeight: FontWeight.w700,
        height: 1.55,
      ),
    );
  }
}

class _LifeMapHelpSection extends StatelessWidget {
  const _LifeMapHelpSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xEFFFF8E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x99D6BF8D), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.goldLight.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.goldDeep, width: 0.8),
            ),
            child: Icon(icon, color: AppColors.ink500, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink800,
                    fontSize: 13.6,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.ink500,
                    fontSize: 12.3,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
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
