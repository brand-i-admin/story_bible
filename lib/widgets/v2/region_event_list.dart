import 'package:flutter/material.dart';

import '../../data/character_name_fallbacks.dart';
import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/event_emotion_mark.dart';
import '../../models/landmark.dart';
import '../../models/quiz_attempt_summary.dart';
import '../../models/story_event.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = _sortByEraThenIndex(events, allEras);
    final charsByCode = <String, Character>{
      for (final c in allCharacters) c.code: c,
    };

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
                  height: 280,
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
                    onTapEvent: onSelectEvent,
                    rowHeight: 280,
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
    this.showSummary = true,
    this.highlightedCharacterCodes = const <String>{},
    this.colorForHighlightedCharacter,
  });
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
  final bool showSummary;
  final SceneAssetLoader loader;
  final VoidCallback onTap;

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
      children: [
        _buildCardSurface(theme),
        if (orderNumber != null ||
            (emotionKey != null && emotionKey!.isNotEmpty))
          _OrderBadge(orderNumber: orderNumber, emotionKey: emotionKey),
        if (selected) const _CurrentStoryBadge(),
      ],
    );
  }

  Widget _buildCardSurface(ThemeData theme) {
    final quizTone = _QuizCardTone.fromAttempt(attemptSummary);
    final surfaceColor =
        quizTone?.background ??
        (completed
            ? AppColors.greenTint1
            : (selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.85)));
    final borderColor =
        quizTone?.border ??
        (completed
            ? AppColors.greenBorder
            : (selected ? theme.colorScheme.primary : const Color(0xFFD9C9A2)));
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1.6),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: _buildCardBody(theme),
        ),
      ),
    );
  }

  Widget _buildCardBody(ThemeData theme) {
    final summary = (event.summary ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CardThumbnailFrame(event: event, loader: loader),
        const SizedBox(height: 6),
        _ThumbTitle(event: event, theme: theme),
        const SizedBox(height: 4),
        _ThumbMetaRow(placeName: event.placeName, yearLabel: _yearLabel()),
        if (showSummary && summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ThumbSummary(summary: summary),
        ],
        const SizedBox(height: 6),
        if (event.characterCodes.isNotEmpty) _buildCharacterPills(),
      ],
    );
  }

  String? _yearLabel() {
    final startYear = event.startYear;
    if (startYear == null) return null;
    return startYear < 0 ? 'B.C. ${-startYear}' : 'A.D. $startYear';
  }

  Widget _buildCharacterPills() {
    final ordered = _orderedCharacterCodes();
    return SizedBox(
      height: 18,
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, 0.85, 1.0],
          colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
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
  const _CardThumbnailFrame({required this.event, required this.loader});

  final StoryEvent event;
  final SceneAssetLoader loader;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 64,
        height: 64,
        child: ColoredBox(
          color: const Color(0xFFF1E4C8),
          child: _CardThumbnail(event: event, loader: loader),
        ),
      ),
    );
  }
}

class _ThumbTitle extends StatelessWidget {
  const _ThumbTitle({required this.event, required this.theme});

  final StoryEvent event;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      event.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }
}

class _ThumbMetaRow extends StatelessWidget {
  const _ThumbMetaRow({required this.placeName, required this.yearLabel});

  final String? placeName;
  final String? yearLabel;

  @override
  Widget build(BuildContext context) {
    final hasPlace = placeName != null && placeName!.isNotEmpty;
    if (!hasPlace && yearLabel == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasPlace) ...[
          const Icon(Icons.location_on, size: 10, color: Color(0xFF8C6743)),
          const SizedBox(width: 1),
          Flexible(
            child: Text(
              placeName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8C6743),
              ),
            ),
          ),
        ],
        if (hasPlace && yearLabel != null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              '·',
              style: TextStyle(fontSize: 10, color: Color(0xFF8C6743)),
            ),
          ),
        if (yearLabel != null)
          Text(
            yearLabel!,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8C6743),
            ),
          ),
      ],
    );
  }
}

class _ThumbSummary extends StatelessWidget {
  const _ThumbSummary({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return Text(
      summary,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 10,
        height: 1.3,
        color: Color(0xFF6B5430),
      ),
    );
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge({required this.orderNumber, this.emotionKey});

  final int? orderNumber;
  final String? emotionKey;

  @override
  Widget build(BuildContext context) {
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
                  color: const Color(0xFF6B4A2A),
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
                child: Text(
                  '${orderNumber ?? ''}',
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

  static _QuizCardTone? fromAttempt(QuizAttemptSummary? attempt) {
    if (attempt == null || attempt.totalCount <= 0) {
      return null;
    }
    if (attempt.correctCount <= 0) {
      return const _QuizCardTone(
        background: Color(0xFFF7DAD2),
        border: AppColors.dangerBot,
      );
    }
    if (attempt.correctCount >= attempt.totalCount) {
      return const _QuizCardTone(
        background: AppColors.greenTint1,
        border: AppColors.greenBorder,
      );
    }
    return const _QuizCardTone(
      background: Color(0xFFF6E7B8),
      border: AppColors.goldDeep,
    );
  }
}

class _CurrentStoryBadge extends StatelessWidget {
  const _CurrentStoryBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -10,
      left: 28,
      right: 8,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE8A33D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF8C5A2E), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Text(
            '현재 이야기',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF3D2A14),
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardThumbnail extends StatelessWidget {
  const _CardThumbnail({required this.event, required this.loader});
  final StoryEvent event;
  final SceneAssetLoader loader;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: loader.loadForEvent(event),
      builder: (_, snap) {
        const placeholder = Center(
          child: Icon(Icons.menu_book, color: Color(0xFF8C6743), size: 28),
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
    this.accentColor,
  });
  final String code;
  final Character? character;
  final String name;

  /// 부모가 명시적으로 강조하라고 지정한 색. null 이면 default 파랑 톤
  /// (0xFF3F8FB6) 으로 표시. 사용자가 인물 모드에서 고른 인물의 pill 에
  /// 지도 path 점선 색과 동일한 색을 넘기면 시각적 매칭이 된다.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    const defaultColor = Color(0xFF3F8FB6);
    const defaultText = Color(0xFF2A6F92);
    final color = accentColor ?? defaultColor;
    final textColor = accentColor != null
        ? Color.alphaBlend(color.withValues(alpha: 0.85), Colors.black)
        : defaultText;
    final avatarCharacter =
        character ?? _localAvatarFallbackCharacter(code, name);
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
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
                width: 14,
                height: 14,
                child: CharacterAvatar(character: avatarCharacter, size: 14),
              ),
            )
          else if (avatarCharacter.hasLocalAvatar)
            ClipOval(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CharacterAvatar(character: avatarCharacter, size: 14),
              ),
            )
          else
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          const SizedBox(width: 3),
          Text(
            name,
            style: TextStyle(
              fontSize: 9.5,
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
