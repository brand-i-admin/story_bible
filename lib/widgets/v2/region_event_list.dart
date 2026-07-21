import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/character_name_fallbacks.dart';
import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/landmark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/scene_asset_loader.dart';
import '../character_avatar.dart';
import '../emotion_badge_icon.dart';
import '../event_timeline_row.dart';

/// 지역 모드 — 선택된 region 의 사건들을 시간순 가로 스크롤 (EventTimelineRow)
/// 으로 보여 준다. 인물 모드 step 3 와 동일한 widget 을 공유 → 두 모드의 UI
/// 동일성 보장. 카드 사이 점선 + ▶ 화살촉 connector.
class RegionEventList extends StatelessWidget {
  const RegionEventList({
    super.key,
    required this.landmark,
    required this.events,
    required this.allEras,
    required this.allCharacters,
    required this.selectedEventId,
    required this.onSelectEvent,
    required this.onClose,
    this.completedEventIds = const <String>{},
    this.eventEmotionMarks = const {},
    this.quizAttemptSummaries = const {},
    this.celebrationEventId,
    this.celebrationStampLabel,
    this.celebrationNonce = 0,
    this.onCelebrationComplete,
    this.quizReviewEventIds = const <String>{},
    this.quizConfusedEventIds = const <String>{},
    this.publicUrlForStoragePath,
  });

  final Landmark landmark;
  final List<StoryEvent> events;
  final List<Era> allEras;
  final List<Character> allCharacters;

  /// "현재 이야기" 강조 + 자동 스크롤할 사건 id. 지도 핀 클릭 시 갱신.
  final String? selectedEventId;
  final ValueChanged<StoryEvent> onSelectEvent;
  final VoidCallback onClose;

  /// 본문 + 퀴즈 모두 완료된 사건 id 셋. 카드 배경을 초록 톤으로 표시.
  final Set<String> completedEventIds;

  /// 사용자가 지도 위에 새긴 감정. 카드 번호 배지 옆의 작은 아이콘으로 표시한다.
  final Map<String, EventEmotionMark> eventEmotionMarks;

  /// 이야기별 최근 퀴즈 결과. 카드 배경색으로 복습 필요 정도를 표시한다.
  final Map<String, QuizAttemptSummary> quizAttemptSummaries;

  /// 지도 화면에서 특정 사건 카드 위에 완료 축하 효과를 1회 재생할 때 사용.
  final String? celebrationEventId;
  final String? celebrationStampLabel;
  final int celebrationNonce;
  final VoidCallback? onCelebrationComplete;

  /// 최근 퀴즈에서 오답이나 "헷갈렸어요"가 있었던 사건 id 셋.
  final Set<String> quizReviewEventIds;

  /// 최근 퀴즈에서 "헷갈렸어요" 선택이 있었던 사건 id 셋.
  final Set<String> quizConfusedEventIds;

  /// `events.scene_image_paths` 의 `bucket/path` 값을 public URL 로 바꾼다.
  /// 홈 화면은 상세 페이지와 같은 Supabase client 변환 함수를 내려준다.
  final String Function(String storagePath)? publicUrlForStoragePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = _sortByEraThenIndex(events, allEras);
    final charsByCode = <String, Character>{
      for (final c in allCharacters) c.code: c,
    };
    final rowHeight = eventTimelineRowHeightFor(context, base: 280);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v3 — landmark 헤더 (📍 가나안 · 6개 사건) 제거. 인물 모드와 동일하게
        // 단계 이동은 우측 상단 stepper, 사건 카드는 즉시 노출.
        if (sorted.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '이 지역에 해당하는 사건이 없습니다.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          // 가로 스크롤 timeline — 카드 자연 높이 232 고정. 부모 panel 이 그보다
          // 작아도 (panel 축소 애니메이션 등) overflow 안 나도록 ClipRect +
          // UnconstrainedBox + 비활성 SingleChildScrollView 로 감쌈. 카드 자체는
          // 232px 로 그려지고 viewport 가 작으면 clip 만 됨.
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: rowHeight,
                  child: EventTimelineRow(
                    events: sorted,
                    allEras: allEras,
                    charactersByCode: charsByCode,
                    selectedEventId: selectedEventId,
                    completedEventIds: completedEventIds,
                    eventEmotionMarks: eventEmotionMarks,
                    quizAttemptSummaries: quizAttemptSummaries,
                    celebrationEventId: celebrationEventId,
                    celebrationStampLabel: celebrationStampLabel,
                    celebrationNonce: celebrationNonce,
                    onCelebrationComplete: onCelebrationComplete,
                    quizReviewEventIds: quizReviewEventIds,
                    quizConfusedEventIds: quizConfusedEventIds,
                    publicUrlForStoragePath: publicUrlForStoragePath,
                    onTapEvent: onSelectEvent,
                    rowHeight: rowHeight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static List<StoryEvent> _sortByEraThenIndex(
    List<StoryEvent> events,
    List<Era> eras,
  ) {
    final orderByEraId = <String, int>{};
    for (final era in eras) {
      orderByEraId[era.id] = era.displayOrder;
    }
    final sorted = [...events];
    sorted.sort((a, b) {
      final ao = orderByEraId[a.eraId] ?? 9999;
      final bo = orderByEraId[b.eraId] ?? 9999;
      final cmp = ao.compareTo(bo);
      if (cmp != 0) return cmp;
      return a.storyIndex.compareTo(b.storyIndex);
    });
    return sorted;
  }
}

/// 사건 썸네일 카드 — 홈의 RegionEventList 와 EventDetailPage 의 prev/next 카드
/// 양쪽에서 재사용. orderNumber 가 null 이면 좌상단 동그라미 배지 미표시.
enum StoryEventCardPresentation {
  mapTimeline,
  missionTimeline,
  todayCurrent,
  todayAdjacent,
  reviewGrid,
}

class StoryEventThumbCard extends StatelessWidget {
  const StoryEventThumbCard({
    super.key,
    required this.event,
    required this.era,
    required this.charactersByCode,
    required this.selected,
    required this.loader,
    required this.onTap,
    this.completed = false,
    this.needsQuizReview = false,
    this.hasConfusedQuiz = false,
    this.emotionKey,
    this.attemptSummary,
    this.orderNumber,
    this.presentation = StoryEventCardPresentation.mapTimeline,
    this.showSummary = true,
    this.showCharacterPills = true,
    bool? forceOpaqueSurface,
    bool? expandSurface,
    this.surfaceColorOverride,
    this.highlightedCharacterCodes = const <String>{},
    this.colorForHighlightedCharacter,
    this.publicUrlForStoragePath,
  }) : forceOpaqueSurface =
           forceOpaqueSurface ??
           (presentation != StoryEventCardPresentation.mapTimeline &&
               presentation != StoryEventCardPresentation.missionTimeline),
       expandSurface =
           expandSurface ??
           (presentation == StoryEventCardPresentation.todayCurrent ||
               presentation == StoryEventCardPresentation.todayAdjacent);
  final StoryEvent event;
  final Era? era;
  final Map<String, Character> charactersByCode;
  final bool selected;
  final bool completed;
  final bool needsQuizReview;
  final bool hasConfusedQuiz;
  final String? emotionKey;
  final QuizAttemptSummary? attemptSummary;
  final int? orderNumber;
  final StoryEventCardPresentation presentation;
  final bool showSummary;
  final bool showCharacterPills;
  final bool forceOpaqueSurface;
  final bool expandSurface;
  final Color? surfaceColorOverride;
  final SceneAssetLoader loader;
  final VoidCallback onTap;
  final String Function(String storagePath)? publicUrlForStoragePath;

  /// 사용자가 명시적으로 고른 인물 코드(예: 인물 모드 step 3 의 선택된 인물).
  /// 이 인물들의 pill 은 [colorForHighlightedCharacter] 색으로 강조되고
  /// pills 가로 스크롤에서 가장 앞쪽에 배치된다. 비어 있으면 모든 pill 이
  /// default 파랑 톤 + 원래 순서.
  final Set<String> highlightedCharacterCodes;

  /// highlighted 인물의 강조 색을 반환. null 이면 인물 코드와 무관하게
  /// 모두 default 파랑. 일반적으로 부모가 지도 path 색과 동일한 함수를 넘겨
  /// "지도 점선 색 = 카드 라벨 색" 시각 일관성을 만든다.
  final Color Function(String characterCode)? colorForHighlightedCharacter;

  /// pill 정렬 순서: highlighted 인물 먼저(원래 순서 유지), 그 다음 나머지
  /// (원래 순서 유지). highlighted set 이 비어 있으면 원래 순서 그대로.
  List<String> _orderedCharacterCodes() {
    if (highlightedCharacterCodes.isEmpty) return event.characterCodes;
    final highlighted = <String>[];
    final rest = <String>[];
    for (final code in event.characterCodes) {
      if (highlightedCharacterCodes.contains(code)) {
        highlighted.add(code);
      } else {
        rest.add(code);
      }
    }
    return [...highlighted, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      fit: expandSurface ? StackFit.expand : StackFit.loose,
      children: [
        _buildCardSurface(context, theme),
        if (orderNumber != null ||
            (emotionKey != null && emotionKey!.isNotEmpty))
          _OrderBadge(orderNumber: orderNumber, emotionKey: emotionKey),
        if (selected &&
            (presentation == StoryEventCardPresentation.mapTimeline ||
                presentation == StoryEventCardPresentation.missionTimeline))
          const _CurrentStoryBadge(),
      ],
    );
  }

  Widget _buildCardSurface(BuildContext context, ThemeData theme) {
    final palette = AppPaletteTheme.of(context);
    final quizTone = _QuizCardTone.fromAttempt(attemptSummary, palette);
    final surfaceColor =
        surfaceColorOverride ??
        quizTone?.background ??
        (completed
            ? Color.alphaBlend(palette.completedSurface, palette.cardSurface)
            : (selected
                  ? Color.alphaBlend(
                      palette.selectedSurface,
                      palette.cardSurface,
                    )
                  : (forceOpaqueSurface
                        ? palette.cardSurface
                        : palette.cardSurface.withValues(alpha: 0.92))));
    final borderColor =
        quizTone?.border ??
        (completed
            ? palette.completedBorder
            : (selected ? palette.selectedBorder : palette.subtleBorder));
    final borderWidth =
        presentation == StoryEventCardPresentation.mapTimeline ||
            presentation == StoryEventCardPresentation.missionTimeline
        ? (selected ? 2.0 : 1.6)
        : 1.0;
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          key: ValueKey('story-card-surface-${presentation.name}-${event.id}'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: expandSurface
              ? const EdgeInsets.fromLTRB(8, 10, 8, 7)
              : const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final body = _buildCardBody(context, theme);
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              if ((!expandSurface && textScale < 1.3) ||
                  !constraints.hasBoundedHeight) {
                return body;
              }
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: body,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardBody(BuildContext context, ThemeData theme) {
    final summary = (event.summary ?? '').trim();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactLargeText = textScale >= 1.3;
    final deckCompact = expandSurface && !showSummary;
    final manualSingleLine =
        presentation == StoryEventCardPresentation.reviewGrid ||
        presentation == StoryEventCardPresentation.missionTimeline;
    final thumbnailSize = deckCompact
        ? (compactLargeText ? 38.0 : 48.0)
        : (compactLargeText ? 44.0 : 64.0);
    final characterPillsHeight = deckCompact
        ? (presentation == StoryEventCardPresentation.todayAdjacent
              ? (compactLargeText ? 19.0 : 17.0)
              : (compactLargeText ? 21.0 : 18.0))
        : (compactLargeText ? 24.0 : 18.0);
    final titleMaxLines = manualSingleLine
        ? 1
        : (deckCompact ? 2 : (compactLargeText ? null : 2));
    final summaryMaxLines = compactLargeText ? null : 2;
    final gapAfterThumbnail = deckCompact
        ? (compactLargeText ? 2.0 : 4.0)
        : (compactLargeText ? 3.0 : 6.0);
    final gapAfterTitle = deckCompact ? 2.0 : (compactLargeText ? 2.0 : 4.0);
    final gapBeforeSummary = compactLargeText ? 3.0 : 6.0;
    final gapBeforePills = deckCompact ? 4.0 : (compactLargeText ? 4.0 : 6.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CardThumbnailFrame(
          event: event,
          loader: loader,
          size: thumbnailSize,
          presentation: presentation,
          publicUrlForStoragePath: publicUrlForStoragePath,
        ),
        SizedBox(height: gapAfterThumbnail),
        _ThumbTitle(
          textKey: ValueKey(
            'story-card-title-${presentation.name}-${event.id}',
          ),
          event: event,
          theme: theme,
          presentation: presentation,
          maxLines: titleMaxLines,
          fontSize: deckCompact
              ? presentation == StoryEventCardPresentation.todayCurrent
                    ? 12.2
                    : 9.6
              : 12,
        ),
        SizedBox(height: gapAfterTitle),
        _ThumbMetaRow(
          eventId: event.id,
          presentation: presentation,
          placeName: event.placeName,
          yearLabel: _yearLabel(),
        ),
        if (showSummary && summary.isNotEmpty) ...[
          SizedBox(height: gapBeforeSummary),
          _ThumbSummary(summary: summary, maxLines: summaryMaxLines),
        ],
        if (showCharacterPills && event.characterCodes.isNotEmpty) ...[
          SizedBox(height: gapBeforePills),
          _buildCharacterPills(context, height: characterPillsHeight),
        ],
      ],
    );
  }

  String? _yearLabel() {
    final startYear = event.startYear;
    if (startYear == null) return null;
    return startYear < 0 ? 'B.C. ${-startYear}' : 'A.D. $startYear';
  }

  Widget _buildCharacterPills(BuildContext context, {required double height}) {
    final ordered = _orderedCharacterCodes();
    return SizedBox(
      height: height,
      child: _RightEdgeScrollFade(
        key: ValueKey(
          'story-card-characters-fade-${presentation.name}-${event.id}',
        ),
        strong: presentation == StoryEventCardPresentation.reviewGrid,
        child: ListView.separated(
          key: ValueKey(
            'story-card-characters-scroll-${presentation.name}-${event.id}',
          ),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: ordered.length,
          separatorBuilder: (_, __) => const SizedBox(width: 3),
          itemBuilder: (_, i) {
            final code = ordered[i];
            final character = charactersByCode[code];
            final isHighlighted = highlightedCharacterCodes.contains(code);
            return _CharPillAvatar(
              code: code,
              character: character,
              name: localizedCharacterName(code: code, name: character?.name),
              compact: presentation == StoryEventCardPresentation.todayAdjacent,
              accentColor: isHighlighted
                  ? colorForHighlightedCharacter?.call(code)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _CardThumbnailFrame extends StatelessWidget {
  const _CardThumbnailFrame({
    required this.event,
    required this.loader,
    required this.size,
    required this.presentation,
    this.publicUrlForStoragePath,
  });

  final StoryEvent event;
  final SceneAssetLoader loader;
  final double size;
  final StoryEventCardPresentation presentation;
  final String Function(String storagePath)? publicUrlForStoragePath;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final thumbnail = ColoredBox(
      color: palette.mutedSurface,
      child: _CardThumbnail(
        event: event,
        loader: loader,
        publicUrlForStoragePath: publicUrlForStoragePath,
      ),
    );
    if (presentation == StoryEventCardPresentation.mapTimeline ||
        presentation == StoryEventCardPresentation.missionTimeline) {
      return ClipOval(
        child: SizedBox(width: size, height: size, child: thumbnail),
      );
    }
    if (presentation == StoryEventCardPresentation.reviewGrid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final diameter = constraints.maxWidth * 0.5;
          return Center(
            child: ClipOval(
              key: ValueKey(
                'story-thumbnail-frame-${presentation.name}-${event.id}',
              ),
              child: SizedBox(
                width: diameter,
                height: diameter,
                child: thumbnail,
              ),
            ),
          );
        },
      );
    }
    final isTodayCard =
        presentation == StoryEventCardPresentation.todayCurrent ||
        presentation == StoryEventCardPresentation.todayAdjacent;
    final isTodayCurrent =
        presentation == StoryEventCardPresentation.todayCurrent;
    final aspectRatio = isTodayCard ? 8 / 5 : 1.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTodayCurrent ? 3 : 0),
      child: ClipRRect(
        key: ValueKey('story-thumbnail-frame-${presentation.name}-${event.id}'),
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(aspectRatio: aspectRatio, child: thumbnail),
      ),
    );
  }
}

class _ThumbTitle extends StatelessWidget {
  const _ThumbTitle({
    required this.textKey,
    required this.event,
    required this.theme,
    required this.presentation,
    required this.maxLines,
    required this.fontSize,
  });

  final Key textKey;
  final StoryEvent event;
  final ThemeData theme;
  final StoryEventCardPresentation presentation;
  final int? maxLines;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final singleLine =
        presentation == StoryEventCardPresentation.todayAdjacent ||
        presentation == StoryEventCardPresentation.reviewGrid ||
        presentation == StoryEventCardPresentation.missionTimeline;
    final effectiveMaxLines = singleLine ? 1 : maxLines;
    final style = theme.textTheme.titleSmall?.copyWith(
      color: palette.text,
      fontWeight: FontWeight.w700,
      fontSize: fontSize,
      height: effectiveMaxLines == null ? 1.14 : 1.08,
    );
    if (presentation == StoryEventCardPresentation.todayCurrent) {
      return _AutoScrollingThumbTitle(
        scrollKey: ValueKey(
          'story-card-title-scroll-${presentation.name}-${event.id}',
        ),
        textKey: textKey,
        text: event.title,
        style: style,
      );
    }
    if (presentation == StoryEventCardPresentation.reviewGrid ||
        presentation == StoryEventCardPresentation.missionTimeline) {
      return _ManualScrollingThumbLine(
        fadeKey: ValueKey(
          'story-card-title-fade-${presentation.name}-${event.id}',
        ),
        scrollKey: ValueKey(
          'story-card-title-scroll-${presentation.name}-${event.id}',
        ),
        textKey: textKey,
        text: event.title,
        style: style,
      );
    }
    return Text(
      key: textKey,
      event.title,
      maxLines: effectiveMaxLines,
      overflow: effectiveMaxLines == null
          ? TextOverflow.visible
          : TextOverflow.ellipsis,
      softWrap: presentation != StoryEventCardPresentation.todayAdjacent,
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

class _ManualScrollingThumbLine extends StatelessWidget {
  const _ManualScrollingThumbLine({
    required this.fadeKey,
    required this.scrollKey,
    required this.textKey,
    required this.text,
    required this.style,
  });

  final Key fadeKey;
  final Key scrollKey;
  final Key textKey;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return _RightEdgeScrollFade(
      key: fadeKey,
      strong: true,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: scrollKey,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                text,
                key: textKey,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RightEdgeScrollFade extends StatelessWidget {
  const _RightEdgeScrollFade({
    super.key,
    required this.child,
    this.strong = false,
  });

  final Widget child;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: strong ? const [0.0, 0.68, 0.88, 1.0] : const [0.0, 0.84, 1.0],
        colors: strong
            ? const [
                Colors.white,
                Colors.white,
                Color(0x88FFFFFF),
                Color(0x00FFFFFF),
              ]
            : const [Colors.white, Colors.white, Color(0x00FFFFFF)],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

class _AutoScrollingThumbTitle extends StatefulWidget {
  const _AutoScrollingThumbTitle({
    required this.scrollKey,
    required this.textKey,
    required this.text,
    required this.style,
  });

  final Key scrollKey;
  final Key textKey;
  final String text;
  final TextStyle? style;

  @override
  State<_AutoScrollingThumbTitle> createState() =>
      _AutoScrollingThumbTitleState();
}

class _AutoScrollingThumbTitleState extends State<_AutoScrollingThumbTitle> {
  static const _initialDelay = Duration(milliseconds: 850);
  static const _endPause = Duration(milliseconds: 2000);
  static const _restartDelay = Duration(milliseconds: 850);
  static const _millisecondsPerPixel = 26;
  static const _minimumScrollMilliseconds = 2400;
  static const _maximumScrollMilliseconds = 7200;

  final ScrollController _controller = ScrollController();
  Timer? _startTimer;
  int _animationRequest = 0;
  double? _textScale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextTextScale = MediaQuery.textScalerOf(context).scale(1);
    if (_textScale == nextTextScale) {
      return;
    }
    _textScale = nextTextScale;
    _scheduleScrollToEnd();
  }

  @override
  void didUpdateWidget(covariant _AutoScrollingThumbTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _scheduleScrollToEnd();
    }
  }

  void _scheduleScrollToEnd() {
    final request = ++_animationRequest;
    _startTimer?.cancel();
    if (_controller.hasClients) {
      // 글자 크기/스타일 변경 중 실행 중이던 animateTo를 취소한다. 이전
      // maxScrollExtent를 향한 애니메이션이 새 레이아웃에 남으면 범위를
      // 넘어선 위치에서 계속 합성되는 프레임과 테스트 불안정이 생긴다.
      _controller.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTimer = Timer(_initialDelay, () {
        if (!mounted ||
            request != _animationRequest ||
            !_controller.hasClients) {
          return;
        }
        _startScrollCycle(request);
      });
    });
  }

  void _startScrollCycle(int request) {
    if (!mounted || request != _animationRequest || !_controller.hasClients) {
      return;
    }
    final distance = _controller.position.maxScrollExtent;
    if (distance <= 0) return;
    final milliseconds = (distance * _millisecondsPerPixel).round().clamp(
      _minimumScrollMilliseconds,
      _maximumScrollMilliseconds,
    );
    unawaited(
      _controller.animateTo(
        distance,
        duration: Duration(milliseconds: milliseconds),
        curve: Curves.linear,
      ),
    );
    // animateTo의 Future 완료는 스크롤 범위가 레이아웃 중 바뀌면 늦어질 수
    // 있다. 절대 시간 타이머로 원위치시킨 뒤 같은 제목의 다음 주기를 시작한다.
    _startTimer = Timer(Duration(milliseconds: milliseconds) + _endPause, () {
      if (!mounted || request != _animationRequest || !_controller.hasClients) {
        return;
      }
      _controller.jumpTo(0);
      _startTimer = Timer(_restartDelay, () {
        if (!mounted || request != _animationRequest) return;
        _startScrollCycle(request);
      });
    });
  }

  @override
  void dispose() {
    _animationRequest++;
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: widget.scrollKey,
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              widget.text,
              key: widget.textKey,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbMetaRow extends StatelessWidget {
  const _ThumbMetaRow({
    required this.eventId,
    required this.presentation,
    required this.placeName,
    required this.yearLabel,
  });

  final String eventId;
  final StoryEventCardPresentation presentation;
  final String? placeName;
  final String? yearLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final hasPlace = placeName != null && placeName!.isNotEmpty;
    if (!hasPlace && yearLabel == null) return const SizedBox.shrink();
    final label = [
      if (hasPlace) placeName!,
      if (yearLabel != null) yearLabel!,
    ].join(' · ');
    if (presentation == StoryEventCardPresentation.todayAdjacent) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            if (hasPlace) ...[
              Icon(Icons.location_on, size: 10, color: palette.primary),
              const SizedBox(width: 1),
            ],
            Expanded(
              child: Text(
                label,
                key: ValueKey(
                  'story-card-meta-ellipsis-${presentation.name}-$eventId',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.mutedText,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasPlace) ...[
          Icon(Icons.location_on, size: 10, color: palette.primary),
          const SizedBox(width: 1),
          Text(
            placeName!,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.mutedText,
              height: 1.1,
            ),
          ),
        ],
        if (hasPlace && yearLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              '·',
              style: TextStyle(fontSize: 10, color: palette.mutedText),
            ),
          ),
        if (yearLabel != null)
          Text(
            yearLabel!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: palette.mutedText,
              height: 1.1,
            ),
          ),
      ],
    );
    if (presentation == StoryEventCardPresentation.todayCurrent ||
        presentation == StoryEventCardPresentation.reviewGrid) {
      final scrollView = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: ValueKey('story-card-meta-scroll-${presentation.name}-$eventId'),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: row,
          ),
        ),
      );
      if (presentation == StoryEventCardPresentation.reviewGrid) {
        return _RightEdgeScrollFade(
          key: ValueKey('story-card-meta-fade-${presentation.name}-$eventId'),
          strong: true,
          child: scrollView,
        );
      }
      return scrollView;
    }
    return SizedBox(
      width: double.infinity,
      child: FittedBox(fit: BoxFit.scaleDown, child: row),
    );
  }
}

class _ThumbSummary extends StatelessWidget {
  const _ThumbSummary({required this.summary, required this.maxLines});

  final String summary;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Text(
      summary,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: true,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, height: 1.3, color: palette.mutedText),
    );
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge({required this.orderNumber, this.emotionKey});

  final int? orderNumber;
  final String? emotionKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final hasEmotion = emotionKey != null && emotionKey!.isNotEmpty;
    return Positioned(
      left: -4,
      top: -4,
      child: SizedBox(
        width: hasEmotion ? 34 : 24,
        height: hasEmotion ? 34 : 24,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (hasEmotion)
              EmotionBadgeIcon(
                emotionKey: emotionKey!,
                size: 30,
                iconSize: 17,
                elevation: true,
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: palette.primaryDeep,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${orderNumber ?? ''}',
                      textScaler: TextScaler.noScaling,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        shadows: [
                          Shadow(color: Color(0xCC000000), blurRadius: 1.8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (hasEmotion && orderNumber != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: _TinyOrderBadge(number: orderNumber!, size: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _TinyOrderBadge extends StatelessWidget {
  const _TinyOrderBadge({required this.number, required this.size});

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2F9462),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.greenRim, width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        textScaler: TextScaler.noScaling,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _QuizCardTone {
  const _QuizCardTone({required this.background, required this.border});

  final Color background;
  final Color border;

  static _QuizCardTone? fromAttempt(
    QuizAttemptSummary? attempt,
    AppColorPalette palette,
  ) {
    if (attempt == null || attempt.totalCount <= 0) {
      return null;
    }
    if (attempt.correctCount <= 0) {
      return _QuizCardTone(
        background: Color.alphaBlend(
          AppColors.dangerBot.withValues(alpha: 0.18),
          palette.cardSurface,
        ),
        border: AppColors.dangerBot,
      );
    }
    if (attempt.correctCount >= attempt.totalCount) {
      return _QuizCardTone(
        background: Color.alphaBlend(
          palette.successBottom.withValues(alpha: 0.18),
          palette.cardSurface,
        ),
        border: palette.successBottom,
      );
    }
    return _QuizCardTone(
      background: Color.alphaBlend(
        palette.currentAccent.withValues(alpha: 0.20),
        palette.cardSurface,
      ),
      border: palette.currentAccentDeep,
    );
  }
}

class _CurrentStoryBadge extends StatelessWidget {
  const _CurrentStoryBadge();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Positioned(
      top: -10,
      left: 28,
      right: 8,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: palette.currentAccent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.currentAccentDeep, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '현재 이야기',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: AppColors.ink900,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardThumbnail extends StatelessWidget {
  const _CardThumbnail({
    required this.event,
    required this.loader,
    this.publicUrlForStoragePath,
  });
  final StoryEvent event;
  final SceneAssetLoader loader;
  final String Function(String storagePath)? publicUrlForStoragePath;
  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return FutureBuilder<List<String>>(
      future: loader.loadForEvent(event, publicUrlFor: publicUrlForStoragePath),
      builder: (_, snap) {
        final placeholder = Center(
          child: Icon(Icons.menu_book, color: palette.primary, size: 28),
        );
        if (!snap.hasData || snap.data!.isEmpty) return placeholder;
        final path = snap.data!.first;
        if (path.startsWith('http')) {
          return Image.network(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );
        }
        return Image.asset(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        );
      },
    );
  }
}

class _CharPillAvatar extends StatelessWidget {
  const _CharPillAvatar({
    required this.code,
    required this.character,
    required this.name,
    this.compact = false,
    this.accentColor,
  });
  final String code;
  final Character? character;
  final String name;
  final bool compact;

  /// 부모가 명시적으로 강조하라고 지정한 색. null 이면 default 파랑 톤
  /// (0xFF3F8FB6) 으로 표시. 사용자가 인물 모드에서 고른 인물의 pill 에
  /// 지도 path 점선 색과 동일한 색을 넘기면 시각적 매칭이 된다.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final defaultColor = palette.primary;
    final defaultText = palette.primaryDeep;
    final color = accentColor ?? defaultColor;
    final darkSurface =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
        Brightness.dark;
    final textColor = darkSurface
        ? palette.text
        : (accentColor != null
              ? Color.alphaBlend(color.withValues(alpha: 0.85), Colors.black)
              : defaultText);
    final backgroundColor = color.withValues(alpha: darkSurface ? 0.34 : 0.20);
    final avatarCharacter =
        character ?? _localAvatarFallbackCharacter(code, name);
    final avatarSize = compact ? 12.0 : 14.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        2,
        compact ? 1 : 2,
        compact ? 5 : 6,
        compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: accentColor != null
            ? Border.all(color: color.withValues(alpha: 0.55), width: 0.8)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (character != null)
            ClipOval(
              child: SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: CharacterAvatar(
                  character: avatarCharacter,
                  size: avatarSize,
                ),
              ),
            )
          else if (avatarCharacter.hasLocalAvatar)
            ClipOval(
              child: SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: CharacterAvatar(
                  character: avatarCharacter,
                  size: avatarSize,
                ),
              ),
            )
          else
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          SizedBox(width: compact ? 2 : 3),
          Text(
            name,
            style: TextStyle(
              fontSize: compact ? 8.5 : 9.5,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Character _localAvatarFallbackCharacter(String code, String name) {
    final normalizedCode = code.trim();
    return Character(
      id: normalizedCode,
      code: normalizedCode,
      name: name,
      tagline: null,
      description: null,
      avatarUrl: normalizedCode.isEmpty
          ? null
          : 'assets/avatars/$normalizedCode.png',
      displayOrder: 0,
    );
  }
}

// _DottedHorizontal / _RowConnector / _SnakeConnectorPainter / _DottedLinePainter
// 폐기 — 가로 단일 row 로 전환되면서 grid wrap connector 가 더 이상 필요 없음.
// EventTimelineRow 안의 _DashedArrowConnector 가 카드 사이 점선 + ▶ 화살촉을
// 그린다.
