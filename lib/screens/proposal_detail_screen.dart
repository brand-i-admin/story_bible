import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event_proposal.dart';
import '../models/proposal_comment.dart';
import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';
import '../widgets/proposal/proposal_status_chip.dart';
import 'proposal_submit_screen.dart';

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

class _ProposalDetailScreenState extends ConsumerState<ProposalDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _commentSubmitting = false;
  bool _reviewing = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _commentSubmitting = true);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .addComment(widget.proposalId, body);
      _commentCtrl.clear();
      ref.invalidate(proposalCommentsProvider(widget.proposalId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('댓글 실패: $e')));
    } finally {
      if (mounted) setState(() => _commentSubmitting = false);
    }
  }

  Future<void> _approve(EventProposal p) async {
    setState(() => _reviewing = true);
    try {
      await ref.read(proposalRepositoryProvider).approve(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제안이 승인되어 events 에 반영되었습니다')),
      );
      ref.invalidate(proposalDetailProvider(p.id));
      ref.invalidate(proposalListProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('승인 실패: $e')));
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _reject(EventProposal p) async {
    final note = await _promptForNote();
    if (note == null) return;
    setState(() => _reviewing = true);
    try {
      await ref.read(proposalRepositoryProvider).reject(p.id, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제안이 거절되었습니다')));
      ref.invalidate(proposalDetailProvider(p.id));
      ref.invalidate(proposalListProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('거절 실패: $e')));
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<String?> _promptForNote() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '제안자에게 전달될 거절 사유'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('거절'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(EventProposal p) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProposalSubmitScreen(existing: p)),
    );
    if (result == true) {
      ref.invalidate(proposalDetailProvider(p.id));
      ref.invalidate(proposalListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposalAsync = ref.watch(proposalDetailProvider(widget.proposalId));
    final commentsAsync = ref.watch(
      proposalCommentsProvider(widget.proposalId),
    );
    final currentUser = ref.watch(signedInUserProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('제안 상세')),
      body: proposalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오기 실패: $e')),
        data: (p) {
          final isOwnerPending =
              currentUser != null &&
              p.proposerUserId == currentUser.id &&
              p.isPending;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p.title, style: theme.textTheme.headlineSmall),
                  ),
                  ProposalStatusChip(status: p.status),
                ],
              ),
              const SizedBox(height: 12),
              if (p.summary != null && p.summary!.isNotEmpty) ...[
                Text(p.summary!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              _kv('장소', p.placeName ?? '—'),
              _kv(
                '좌표',
                p.lat == null || p.lng == null
                    ? '—'
                    : '${p.lat!.toStringAsFixed(3)}, ${p.lng!.toStringAsFixed(3)}',
              ),
              _kv(
                '연도',
                p.startYear == null && p.endYear == null
                    ? '—'
                    : '${p.startYear ?? '?'} ~ ${p.endYear ?? '?'} (${p.timePrecision})',
              ),
              _kv(
                '등장 인물',
                p.personCodes.isEmpty ? '—' : p.personCodes.join(', '),
              ),
              _kv(
                '성경 본문',
                p.bibleRefs.isEmpty
                    ? '—'
                    : p.bibleRefs
                          .map(
                            (r) =>
                                '${r['book'] ?? ''} ${r['from'] ?? ''}${(r['to'] != null && r['to'] != r['from']) ? '-${r['to']}' : ''}',
                          )
                          .join(' / '),
              ),
              const SizedBox(height: 16),
              if (p.storyScenes.isNotEmpty) ...[
                Text('4장면', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (var i = 0; i < p.storyScenes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${i + 1}. ${p.storyScenes[i]}'),
                  ),
                const SizedBox(height: 16),
              ],
              if (p.isRejected && (p.reviewNote ?? '').isNotEmpty) ...[
                Card(
                  color: const Color(0xFFFBE9E7),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '거절 사유',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(p.reviewNote!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // 액션 버튼
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isOwnerPending)
                    OutlinedButton.icon(
                      onPressed: _reviewing ? null : () => _edit(p),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('수정'),
                    ),
                  if (isAdmin && p.isPending) ...[
                    FilledButton.icon(
                      onPressed: _reviewing ? null : () => _approve(p),
                      icon: const Icon(Icons.check),
                      label: const Text('승인'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reviewing ? null : () => _reject(p),
                      icon: const Icon(Icons.close),
                      label: const Text('거절'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 8),
              Text('댓글', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              commentsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('댓글 불러오기 실패: $e'),
                data: (comments) => _CommentList(
                  comments: comments,
                  currentUserId: currentUser?.id,
                ),
              ),
              const SizedBox(height: 12),
              _CommentComposer(
                controller: _commentCtrl,
                submitting: _commentSubmitting,
                onSubmit: _sendComment,
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
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
