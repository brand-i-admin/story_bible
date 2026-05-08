import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/landmark.dart';
import '../../models/story_event.dart';
import '../../utils/scene_asset_loader.dart';
import '../character_avatar.dart';
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
    this.orderNumber,
  });
  final StoryEvent event;
  final Era? era;
  final Map<String, Character> charactersByCode;
  final bool selected;
  final bool completed;
  final int? orderNumber;
  final SceneAssetLoader loader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeName = event.placeName;
    final startYear = event.startYear;
    final yearLabel = startYear == null
        ? null
        : (startYear < 0 ? 'B.C. ${-startYear}' : 'A.D. $startYear');

    // 완료 사건 → 초록 배경 + 초록 보더. 완료가 색을 결정하고, 선택은
    // "현재 이야기" 라벨과 보더 두께(2)로 표시 — 둘이 동시에 보이도록.
    const completedBg = Color(0xFFDDEFD0); // 연한 초록
    const completedBorder = Color(0xFF7AAC4C);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: completed
              ? completedBg
              : (selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: completed
                      ? completedBorder
                      : (selected
                            ? theme.colorScheme.primary
                            : const Color(0xFFD9C9A2)),
                  width: selected ? 2 : (completed ? 1.6 : 1.2),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: ColoredBox(
                        color: const Color(0xFFF1E4C8),
                        child: _CardThumbnail(event: event, loader: loader),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if ((placeName != null && placeName.isNotEmpty) ||
                      yearLabel != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (placeName != null && placeName.isNotEmpty) ...[
                          const Icon(
                            Icons.location_on,
                            size: 10,
                            color: Color(0xFF8C6743),
                          ),
                          const SizedBox(width: 1),
                          Flexible(
                            child: Text(
                              placeName,
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
                        if (placeName != null &&
                            placeName.isNotEmpty &&
                            yearLabel != null)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              '·',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF8C6743),
                              ),
                            ),
                          ),
                        if (yearLabel != null)
                          Text(
                            yearLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8C6743),
                            ),
                          ),
                      ],
                    ),
                  // 요약 (2줄). 위치/연도 와 인물 라벨 사이에 표시.
                  if ((event.summary ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.summary!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: Color(0xFF6B5430),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // 인물 pill — 한 줄에 가로 스크롤. 인물 라벨이 2줄로 wrap
                  // 되어 카드가 overflow 되는 것을 방지. ShaderMask 우측
                  // 페이드로 "더 있음" 힌트.
                  if (event.characterCodes.isNotEmpty)
                    SizedBox(
                      height: 18,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: [0.0, 0.85, 1.0],
                          colors: [
                            Colors.white,
                            Colors.white,
                            Color(0x00FFFFFF),
                          ],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          itemCount: event.characterCodes.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 3),
                          itemBuilder: (_, i) {
                            final code = event.characterCodes[i];
                            return _CharPillAvatar(
                              character: charactersByCode[code],
                              name: charactersByCode[code]?.name ?? code,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 좌상단 동그라미 숫자 배지 — 지도 핀과 같은 번호. orderNumber 가 null
        // 이면 (예: EventDetailPage prev/next 카드) 미표시.
        if (orderNumber != null)
          Positioned(
            left: -4,
            top: -4,
            child: Container(
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
                '$orderNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ),
        // "현재 이야기" 라벨 — 카드 상단 가장자리에 걸쳐 표시.
        // 좌상단 숫자 배지(24px) 와 같은 row, 카드 가운데로 정렬.
        if (selected)
          Positioned(
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
          ),
      ],
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
  const _CharPillAvatar({required this.character, required this.name});
  final Character? character;
  final String name;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF3F8FB6).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (character != null)
            ClipOval(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CharacterAvatar(character: character!, size: 14),
              ),
            )
          else
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF3F8FB6),
              ),
            ),
          const SizedBox(width: 3),
          Text(
            name,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2A6F92),
            ),
          ),
        ],
      ),
    );
  }
}

// _DottedHorizontal / _RowConnector / _SnakeConnectorPainter / _DottedLinePainter
// 폐기 — 가로 단일 row 로 전환되면서 grid wrap connector 가 더 이상 필요 없음.
// EventTimelineRow 안의 _DashedArrowConnector 가 카드 사이 점선 + ▶ 화살촉을
// 그린다.
