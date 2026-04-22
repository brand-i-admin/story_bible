import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_event.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../utils/bible_book_meta.dart';
import 'proposal/delete_event_proposal_sheet.dart';
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
class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({
    super.key,
    required this.event,
    required this.sceneAssetsFuture,
    required this.onOpenBibleReader,
    required this.onStartQuiz,
  });

  final StoryEvent event;
  final Future<List<String>> sceneAssetsFuture;

  /// 성경 리더를 열 때 호출되는 콜백. (bookNo, chapterNo, verseNo)
  final void Function(int bookNo, int chapterNo, int verseNo) onOpenBibleReader;

  /// 퀴즈 시작 버튼을 누를 때 호출되는 콜백. (eventId)
  final void Function(String eventId) onStartQuiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storyText = (event.summary ?? '').trim();
    final placeText = (event.placeName ?? '').trim();
    final yearText = event.startYear?.toString() ?? '-';
    final metaText = placeText.isEmpty ? yearText : '$placeText · $yearText';
    final refs = event.bibleRefs;
    final moveTarget = parseBibleNavigationTarget(
      event.bibleRefs.firstOrNull?.displayText,
    );

    final currentState = ref.watch(storyControllerProvider);
    final isCompleted = currentState.completedEventIds.contains(event.id);

    return SubPageScaffold(
      title: event.title,
      compactBackOnly: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: DecoratedBox(
              decoration: modalSurfaceDecoration(),
              child: SingleChildScrollView(
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
                        future: sceneAssetsFuture,
                        builder: (context, snapshot) {
                          final sceneAssets = snapshot.data ?? const <String>[];
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
                        storySection(title: '요약 이야기', content: storyText)
                      else
                        storySection(title: '요약 이야기', content: '요약 정보가 없습니다.'),
                      if (refs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        storySection(
                          title: '관련 본문',
                          content: refs
                              .map((ref) => '• ${ref.displayText}')
                              .join('\n'),
                          action: moveTarget == null
                              ? null
                              : bibleMoveButton(
                                  onTap: () {
                                    Future.microtask(() {
                                      onOpenBibleReader(
                                        moveTarget.bookNo,
                                        moveTarget.chapterNo,
                                        moveTarget.verseNo,
                                      );
                                    });
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: filledActionButton(
                          label: '퀴즈 시작',
                          onTap: () => onStartQuiz(event.id),
                          completed: isCompleted,
                        ),
                      ),
                      _DeleteProposalButton(event: event),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
