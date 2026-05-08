import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bible_ref.dart';
import '../models/story_event.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../utils/bible_book_meta.dart';
import '../utils/scene_asset_loader.dart';
import 'completion_celebration.dart';
import 'proposal/delete_event_proposal_sheet.dart';
import 'pulse_highlight.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

/// 사건 상세 페이지.
///
/// 1. 제목 + 메타 (장소 · 연도)
/// 2. 4개 장면 이미지 (있으면)
/// 3. 요약 이야기
/// 4. 관련 성경 본문 + 이동 버튼
/// 5. 퀴즈 시작 버튼
///
/// 완료 여부는 [storyControllerProvider]의 `completedEventIds`로 판정한다.
class EventDetailPage extends ConsumerStatefulWidget {
  const EventDetailPage({
    super.key,
    required this.event,
    required this.sceneAssetsFuture,
    required this.onOpenBibleReader,
    required this.onStartQuiz,
    this.prevEvent,
    this.nextEvent,
    this.onNavigateToEvent,
    this.quizWeekKey,
  });

  final StoryEvent event;
  final Future<List<String>> sceneAssetsFuture;

  /// 성경 리더를 열 때 호출되는 콜백. (bookNo, chapterNo, verseNo)
  final void Function(int bookNo, int chapterNo, int verseNo) onOpenBibleReader;

  /// 퀴즈 시작 버튼을 누를 때 호출되는 콜백. (eventId)
  final void Function(String eventId) onStartQuiz;

  /// (선택) 좌측에 작고 연하게 표시될 이전 이야기. null 이면 표시 안 함.
  final StoryEvent? prevEvent;

  /// (선택) 우측에 작고 연하게 표시될 다음 이야기. null 이면 표시 안 함.
  final StoryEvent? nextEvent;

  /// prev/next 카드 클릭 또는 좌우 스와이프 시 호출. 호출 시 부모는 같은
  /// 페이지를 새 사건으로 pushReplacement 하는 식으로 처리한다.
  final void Function(StoryEvent target)? onNavigateToEvent;

  /// 비-null 이면 "퀴즈 모드" — 본문 읽기/퀴즈 완료 진행도가 프로필 진행도와
  /// 독립된 `weekly_quiz_progress` 테이블에 저장된다. 같은 인물이 다음 주에
  /// 또 뽑혀도 week_key 가 달라 자동 reset.
  final String? quizWeekKey;

  @override
  ConsumerState<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends ConsumerState<EventDetailPage> {
  // 본문 읽기 + 퀴즈가 모두 완료되는 전이 시점에 별가루 burst 를 한 번 트리거.
  final GlobalKey<CompletionCelebrationState> _celebrationKey =
      GlobalKey<CompletionCelebrationState>();

  /// 다음 이야기 카드 glow 활성 여부.
  /// - 진입 시 이미 완료된 사건이면 즉시 true (post-frame 으로 setState).
  /// - 페이지 안에서 둘 다 완료해서 축하 애니메이션이 끝났을 때도 true.
  /// - 완료 취소되면 다시 false.
  bool _glowNext = false;

  @override
  void initState() {
    super.initState();
    final weekKey = widget.quizWeekKey;
    if (weekKey != null) {
      // 주간 퀴즈 모드 — 진행도를 미리 로드 (캐시 hit 시 noop).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(storyControllerProvider.notifier)
            .ensureWeeklyQuizProgressLoaded(weekKey);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(storyControllerProvider);
      final eventId = widget.event.id;
      final isCompleted = _isCompletedFor(state, eventId);
      if (isCompleted && widget.nextEvent != null) {
        setState(() => _glowNext = true);
      }
    });
  }

  bool _isCompletedFor(StoryState state, String eventId) {
    if (widget.quizWeekKey != null) {
      return state.weeklyQuizBibleReadEventIds.contains(eventId) &&
          state.weeklyQuizCompletedEventIds.contains(eventId);
    }
    return state.bibleReadEventIds.contains(eventId) &&
        state.quizCompletedEventIds.contains(eventId);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final storyText = (event.summary ?? '').trim();
    final placeText = (event.placeName ?? '').trim();
    final yearText = event.startYear?.toString() ?? '-';
    final metaText = placeText.isEmpty ? yearText : '$placeText · $yearText';
    final refs = event.bibleRefs;
    final moveTarget = parseBibleNavigationTarget(
      event.bibleRefs.firstOrNull?.displayText,
    );

    // 완료 전이(false → true) 감지. 페이지 진입 시 이미 완료라면 발화하지 않음.
    // 반대 전이(true → false, 완료 취소)에는 다음 이야기 glow 도 끔.
    // quiz 모드는 weekly* 필드, 일반 모드는 그대로 bible/quiz* 필드 사용.
    ref.listen<StoryState>(storyControllerProvider, (previous, next) {
      if (previous == null) return;
      final wasCompleted = _isCompletedFor(previous, event.id);
      final isCompleted = _isCompletedFor(next, event.id);
      if (!wasCompleted && isCompleted) {
        _celebrationKey.currentState?.play();
      }
      if (!isCompleted && _glowNext) {
        setState(() => _glowNext = false);
      }
    });

    final currentState = ref.watch(storyControllerProvider);
    final isQuizMode = widget.quizWeekKey != null;
    final isBibleRead = isQuizMode
        ? currentState.weeklyQuizBibleReadEventIds.contains(event.id)
        : currentState.bibleReadEventIds.contains(event.id);
    final isQuizCompleted = isQuizMode
        ? currentState.weeklyQuizCompletedEventIds.contains(event.id)
        : currentState.quizCompletedEventIds.contains(event.id);
    final lastScore = isQuizMode
        ? currentState.weeklyQuizLastScores[event.id]
        : currentState.lastQuizScores[event.id];

    return SubPageScaffold(
      title: event.title,
      compactBackOnly: true,
      child: GestureDetector(
        // 좌우 스와이프로 prev/next 이동 (수평 fling).
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200 && widget.nextEvent != null) {
            widget.onNavigateToEvent?.call(widget.nextEvent!);
          } else if (v > 200 && widget.prevEvent != null) {
            widget.onNavigateToEvent?.call(widget.prevEvent!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 본문 카드.
                    DecoratedBox(
                      decoration: modalSurfaceDecoration(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Color(0xFF3B2A16),
                            height: 1.55,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        height: 1.22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF3A2B15),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      metaText,
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6A522E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              FutureBuilder<List<String>>(
                                future: widget.sceneAssetsFuture,
                                builder: (context, snapshot) {
                                  final sceneAssets =
                                      snapshot.data ?? const <String>[];
                                  if (sceneAssets.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: storySceneRow(sceneAssets),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              if (storyText.isNotEmpty)
                                storySection(
                                  title: '요약 이야기',
                                  content: storyText,
                                )
                              else
                                storySection(
                                  title: '요약 이야기',
                                  content: '요약 정보가 없습니다.',
                                ),
                              const SizedBox(height: 12),
                              CompletionCelebration(
                                key: _celebrationKey,
                                onComplete: () {
                                  if (!mounted) return;
                                  if (widget.nextEvent != null && !_glowNext) {
                                    setState(() => _glowNext = true);
                                  }
                                },
                                child: _ReadAndQuizSection(
                                  eventId: event.id,
                                  refs: refs,
                                  moveTarget: moveTarget,
                                  isBibleRead: isBibleRead,
                                  isQuizCompleted: isQuizCompleted,
                                  lastScore: lastScore,
                                  onOpenBibleReader: widget.onOpenBibleReader,
                                  onStartQuiz: () =>
                                      widget.onStartQuiz(event.id),
                                  onUndoBibleRead: () {
                                    final notifier = ref.read(
                                      storyControllerProvider.notifier,
                                    );
                                    if (isQuizMode) {
                                      notifier.setWeeklyQuizBibleRead(
                                        weekKey: widget.quizWeekKey!,
                                        eventId: event.id,
                                        isRead: false,
                                      );
                                    } else {
                                      notifier.setBibleRead(
                                        eventId: event.id,
                                        isRead: false,
                                      );
                                    }
                                  },
                                  onUndoQuiz: () {
                                    final notifier = ref.read(
                                      storyControllerProvider.notifier,
                                    );
                                    if (isQuizMode) {
                                      notifier.setWeeklyQuizCompleted(
                                        weekKey: widget.quizWeekKey!,
                                        eventId: event.id,
                                        isCompleted: false,
                                      );
                                    } else {
                                      notifier.setQuizCompleted(
                                        eventId: event.id,
                                        isCompleted: false,
                                      );
                                    }
                                  },
                                ),
                              ),
                              _DeleteProposalButton(event: event),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 아래쪽 prev/next 네비 카드 — 한 줄에 좌(이전) + 우(다음).
                    // 각 45% width + 가운데 여백으로 답답하지 않게.
                    if ((widget.prevEvent != null ||
                            widget.nextEvent != null) &&
                        widget.onNavigateToEvent != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: widget.prevEvent != null
                                ? _NavRow(
                                    label: '이전 이야기',
                                    event: widget.prevEvent!,
                                    isPrev: true,
                                    onTap: () => widget.onNavigateToEvent!(
                                      widget.prevEvent!,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: widget.nextEvent != null
                                ? PulseHighlight(
                                    active: _glowNext,
                                    child: _NavRow(
                                      label: '다음 이야기',
                                      event: widget.nextEvent!,
                                      isPrev: false,
                                      onTap: () => widget.onNavigateToEvent!(
                                        widget.nextEvent!,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 이전/다음 이야기 가로 네비 카드. 작은 원형 썸네일 + 라벨 + 사건 제목 + 화살표.
class _NavRow extends StatelessWidget {
  _NavRow({
    required this.label,
    required this.event,
    required this.isPrev,
    required this.onTap,
  });

  final String label;
  final StoryEvent event;
  final bool isPrev;
  final VoidCallback onTap;
  final SceneAssetLoader _loader = SceneAssetLoader();

  @override
  Widget build(BuildContext context) {
    final thumbnail = ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: ColoredBox(
          color: const Color(0xFFF1E4C8),
          child: FutureBuilder<List<String>>(
            future: _loader.loadForEvent(event),
            builder: (_, snap) {
              const placeholder = Icon(
                Icons.menu_book,
                color: Color(0xFF8C6743),
                size: 22,
              );
              if (!snap.hasData || snap.data!.isEmpty) {
                return const Center(child: placeholder);
              }
              final path = snap.data!.first;
              if (path.startsWith('http')) {
                return Image.network(
                  path,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: placeholder),
                );
              }
              return Image.asset(
                path,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: placeholder),
              );
            },
          ),
        ),
      ),
    );

    final textBlock = Column(
      crossAxisAlignment: isPrev
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8C6743),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isPrev ? TextAlign.left : TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF3A2B15),
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x80FFFBEF), // 50% opacity — 시야가 비치는 투명
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x66B89A66), width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 3,
                offset: Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            children: isPrev
                ? [
                    const Icon(
                      Icons.chevron_left,
                      size: 22,
                      color: Color(0xFF8C6743),
                    ),
                    const SizedBox(width: 4),
                    thumbnail,
                    const SizedBox(width: 10),
                    Expanded(child: textBlock),
                  ]
                : [
                    Expanded(child: textBlock),
                    const SizedBox(width: 10),
                    thumbnail,
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: Color(0xFF8C6743),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

/// 본문 읽기 + 퀴즈 풀기 묶음 섹션. 두 버튼 모두 완료해야 사건이 진행률에
/// 추가된다 (StoryController._syncOverallCompletion 이 자동 처리).
class _ReadAndQuizSection extends StatelessWidget {
  const _ReadAndQuizSection({
    required this.eventId,
    required this.refs,
    required this.moveTarget,
    required this.isBibleRead,
    required this.isQuizCompleted,
    required this.lastScore,
    required this.onOpenBibleReader,
    required this.onStartQuiz,
    required this.onUndoBibleRead,
    required this.onUndoQuiz,
  });

  final String eventId;
  final List<BibleRef> refs;
  final BibleNavigationTarget? moveTarget;
  final bool isBibleRead;
  final bool isQuizCompleted;
  final ({int correct, int total})? lastScore;
  final void Function(int bookNo, int chapterNo, int verseNo) onOpenBibleReader;
  final VoidCallback onStartQuiz;
  final VoidCallback onUndoBibleRead;
  final VoidCallback onUndoQuiz;

  @override
  Widget build(BuildContext context) {
    final readLabel = refs.isEmpty
        ? '본문 읽기'
        : '${refs.map((r) => r.displayText).join(', ')} · 읽기';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF1DC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9B785), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '본문 읽고 퀴즈 풀기',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A2B15),
            ),
          ),
          const SizedBox(height: 10),
          _CompletableActionRow(
            label: readLabel,
            completed: isBibleRead,
            onTap: moveTarget == null
                ? null
                : () => onOpenBibleReader(
                    moveTarget!.bookNo,
                    moveTarget!.chapterNo,
                    moveTarget!.verseNo,
                  ),
            onUndo: onUndoBibleRead,
          ),
          const SizedBox(height: 8),
          _CompletableActionRow(
            label: !isQuizCompleted
                ? '퀴즈 시작'
                : (lastScore == null || lastScore!.total == 0)
                ? '퀴즈 (없음)'
                : '퀴즈 (${lastScore!.correct}/${lastScore!.total} 정답)',
            completed: isQuizCompleted,
            onTap: onStartQuiz,
            onUndo: onUndoQuiz,
          ),
        ],
      ),
    );
  }
}

/// 진행 가능한 액션 버튼 한 행 — 미완 시 골드, 완료 시 초록 + 작은 '완료 취소'.
class _CompletableActionRow extends StatelessWidget {
  const _CompletableActionRow({
    required this.label,
    required this.completed,
    required this.onTap,
    required this.onUndo,
  });

  final String label;
  final bool completed;
  final VoidCallback? onTap;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: filledActionButton(
            label: label,
            onTap: onTap ?? () {},
            completed: completed,
          ),
        ),
        if (completed) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: const Color(0xFF8C4A3A),
            ),
            child: const Text(
              '완료 취소',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

/// 사역자/관리자 전용 — 이 이야기에 대한 삭제 제안을 내는 TextButton.
///
/// 일반 사용자에게는 아예 렌더되지 않는다. 권한 프로바이더가 로딩 중이면 빈
/// 공간으로 fallback 해 레이아웃이 흔들리지 않도록 한다.
class _DeleteProposalButton extends ConsumerWidget {
  const _DeleteProposalButton({required this.event});

  final StoryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 삭제 제안은 pastor 또는 admin 누구나 가능. (admin 은 직접 DB 조작도
    // 가능하지만, 제안 채널을 통해 history/댓글이 남도록 일관성 유지)
    final isAdmin = ref.watch(isAdminProvider);
    final isPastorAsync = ref.watch(isPastorProvider);
    final isPastor = isPastorAsync.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    if (!isAdmin && !isPastor) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('이 이야기 삭제 제안'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF8C4A3A)),
          onPressed: () {
            showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => DeleteEventProposalSheet(event: event),
            );
          },
        ),
      ),
    );
  }
}
