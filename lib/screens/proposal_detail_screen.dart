import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event_proposal.dart';
import '../models/proposal_comment.dart';
import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';
import '../utils/bible_book_meta.dart';
import '../widgets/bible_reader_page.dart';
import '../widgets/proposal/approve_proposal_dialog.dart';
import '../widgets/proposal/proposal_status_chip.dart';
import '../widgets/proposal/revise_position_dialog.dart';
import 'proposal_submit_screen.dart';

part 'proposal_detail_screen_state.dart';

/// 제안 상세 화면.
///
/// - 공통: 제안 본문 + 상태 + 댓글 목록 + 댓글 작성
/// - 본인 pending: "수정" 버튼
/// - admin: "승인" / "거절" 버튼
class ProposalDetailScreen extends ConsumerStatefulWidget {
  const ProposalDetailScreen({super.key, required this.proposalId});

  final String proposalId;

  @override
  ConsumerState<ProposalDetailScreen> createState() =>
      _ProposalDetailScreenState();
}

class _CommentList extends StatelessWidget {
  const _CommentList({required this.comments, required this.currentUserId});
  final List<ProposalComment> comments;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '아직 댓글이 없습니다',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final c in comments)
          _CommentBubble(
            comment: c,
            isOwn: currentUserId != null && c.authorUserId == currentUserId,
          ),
      ],
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment, required this.isOwn});
  final ProposalComment comment;
  final bool isOwn;

  static const _avatarPalette = <Color>[
    Color(0xFF6E4A2B),
    Color(0xFF8B5A2B),
    Color(0xFF6F5D3E),
    Color(0xFF3D6E6E),
    Color(0xFF5C6B9F),
    Color(0xFF8A4E5D),
    Color(0xFF557C3E),
    Color(0xFFB6673C),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleBg = isOwn
        ? theme.colorScheme.primary.withValues(alpha: 0.10)
        : theme.colorScheme.surfaceContainerHighest;
    final bubbleBorder = isOwn
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;
    final avatarColor =
        _avatarPalette[comment.authorUserId.hashCode.abs() %
            _avatarPalette.length];
    final initial = _initialFromId(comment.authorUserId, isOwn);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: avatarColor,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleBg,
                border: Border.all(color: bubbleBorder),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isOwn ? '나' : '사용자 ${_shortId(comment.authorUserId)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isOwn
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(comment.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initialFromId(String id, bool isOwn) {
    if (isOwn) return '나';
    if (id.isEmpty) return '?';
    return id.substring(0, 1).toUpperCase();
  }

  static String _shortId(String id) {
    if (id.length <= 6) return id;
    return id.substring(0, 6);
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '댓글을 입력하세요',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: IconButton.filled(
              tooltip: '댓글 등록',
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Proposal detail — EventDetailPage 에 맞춘 신규 레이아웃 블록들
// ============================================================================

/// 제목 + 장소·연도 메타 한 줄.
class _ProposalHeaderRow extends StatelessWidget {
  const _ProposalHeaderRow({required this.proposal});
  final EventProposal proposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = (proposal.placeName ?? '').trim();
    final year = _formatYearRange(proposal.startYear, proposal.endYear);
    final meta = [
      if (place.isNotEmpty) place,
      if (year.isNotEmpty) year,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            proposal.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              meta,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatYearRange(int? start, int? end) {
    if (start == null && end == null) return '';
    String fmt(int y) => y < 0 ? 'B.C. ${-y}' : 'A.D. $y';
    if (start == null) return fmt(end!);
    if (end == null || start == end) return fmt(start);
    return '${fmt(start)} ~ ${fmt(end)}';
  }
}

/// 4장면 이미지 그리드 (Storage public URL).
///
/// 빈 path 는 placeholder 로 대체. 이벤트 상세 페이지의 `storySceneRow` 와
/// 비슷한 느낌을 Image.network 기반으로 재현.
class _ProposalSceneGrid extends ConsumerWidget {
  const _ProposalSceneGrid({required this.paths, required this.captions});
  final List<String> paths;
  final List<String> captions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(proposalRepositoryProvider);
    final visible = paths.take(4).toList(growable: false);
    const gap = 8.0;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xF4EFE3CC),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileW = (constraints.maxWidth - (gap * 3)) / 4;
          final viewportH = MediaQuery.sizeOf(context).height;
          final maxTileH = math.max(180.0, viewportH * 0.48);
          final tileH = math.min(tileW * 1.62, maxTileH);
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(visible.length, (i) {
              final path = visible[i];
              final url = path.isEmpty
                  ? null
                  : repo.publicUrlForProposalScene(path);
              return Padding(
                padding: EdgeInsets.only(
                  right: i == visible.length - 1 ? 0 : gap,
                ),
                child: SizedBox(
                  width: tileW,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0x9C7C5C39),
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SizedBox(
                        height: tileH,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (url == null)
                              const ColoredBox(
                                color: Color(0xFFE7D2B2),
                                child: Center(
                                  child: Icon(Icons.image_outlined),
                                ),
                              )
                            else
                              Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Color(0xFFE7D2B2),
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            if (i < captions.length &&
                                captions[i].trim().isNotEmpty)
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      captions[i],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _SceneTextSection extends StatelessWidget {
  const _SceneTextSection({required this.scenes, required this.captions});
  final List<String> scenes;
  final List<String> captions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '장면 원고와 캡션',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < scenes.length; i++) ...[
            if (i > 0) Divider(color: theme.colorScheme.outlineVariant),
            Text(
              '장면 ${i + 1}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(scenes[i], style: theme.textTheme.bodyMedium),
            if (i < captions.length && captions[i].trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '캡션: ${captions[i]}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 일반 제안의 첨부 이미지 그리드 (최대 5장). 가로로 스크롤되는 카드.
class _GeneralImageGrid extends ConsumerWidget {
  const _GeneralImageGrid({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(proposalRepositoryProvider);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, idx) {
            final path = paths[idx];
            final url = path.isEmpty
                ? null
                : repo.publicUrlForStoragePath(path);
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 160,
                height: 160,
                child: url == null
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.image_outlined)),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// EventDetailPage 의 `storySection` 을 미니 포팅. 테두리 카드 + 제목 + 본문 +
/// 우상단 액션 버튼.
class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.content,
    this.action,
  });

  final String title;
  final String content;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

/// "미리보기" 섹션 — 제목 라벨이 붙은 카드 안에 자식 (장면 이미지 등) 을 감싼다.
/// 승인 후 events 페이지에서 어떻게 보일지 작성자/관리자가 미리 볼 수 있게 함.
class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '미리보기',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '— 승인되면 사용자에게 이렇게 보여요',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 퀴즈 섹션 — 목회자 입력 3개 보기 + 자동 4번 "헷갈렸어요" 표시.
/// 정답은 초록 ✓ 로 강조.
class _QuizSection extends StatelessWidget {
  const _QuizSection({required this.quizzes});
  final List<QuizDraft> quizzes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '퀴즈 (${quizzes.length}문항)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var qi = 0; qi < quizzes.length; qi++) ...[
            if (qi > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: theme.colorScheme.outlineVariant,
                  height: 1,
                ),
              ),
            _QuizCard(index: qi, quiz: quizzes[qi]),
          ],
        ],
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({required this.index, required this.quiz});
  final int index;
  final QuizDraft quiz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayChoices = [...quiz.choices, QuizDraft.confusedChoiceLabel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Q${index + 1}. ${quiz.question}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (var ci = 0; ci < displayChoices.length; ci++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ci == quiz.answerIndex
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: ci == quiz.answerIndex
                      ? const Color(0xFF2D7B4D)
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayChoices[ci],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ci == quiz.answerIndex
                          ? const Color(0xFF2D7B4D)
                          : theme.colorScheme.onSurface,
                      fontWeight: ci == quiz.answerIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (quiz.explanation.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quiz.explanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 상세 페이지 하단 보조 메타 — 좌표 + 등장 인물 코드 리스트 등.
/// 사건 상세 페이지에는 없는 "제안 고유" 정보 (pastor 가 입력한 정밀도 등).
class _MetaKvBlock extends StatelessWidget {
  const _MetaKvBlock({required this.proposal});
  final EventProposal proposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <List<String>>[
      [
        '구간',
        '${proposal.unitTitle} (${proposal.unitCode}, ${proposal.unitOrder})',
      ],
      [
        '좌표',
        proposal.lat == null || proposal.lng == null
            ? '—'
            : '${proposal.lat!.toStringAsFixed(3)}, '
                  '${proposal.lng!.toStringAsFixed(3)}',
      ],
      [
        '등장 인물',
        proposal.characterCodes.isEmpty
            ? '—'
            : proposal.characterCodes.join(', '),
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      row[0],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(row[1], style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
