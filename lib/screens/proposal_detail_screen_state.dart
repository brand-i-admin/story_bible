part of 'proposal_detail_screen.dart';

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
    // 새 이야기 제안은 승인 전 등장 인물 is_active 결정 다이얼로그.
    // 삭제/일반 제안은 단순 yes/no.
    ApproveProposalReviewResult? reviewResult;
    if (p.isNewProposal) {
      reviewResult = await ApproveProposalDialog.show(context, p);
      if (reviewResult == null) return; // 취소
    } else {
      final (title, body) = p.isDeleteProposal
          ? ('삭제 제안 승인', '"${p.title}" 이(가) 앱에서 숨겨집니다. 진행할까요?')
          : ('일반 제안 승인', '"${p.title}" 제안을 승인 처리할까요?');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('승인'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _reviewing = true);
    try {
      final repo = ref.read(proposalRepositoryProvider);
      final String successMessage;
      if (p.isDeleteProposal) {
        await repo.approveDelete(p.id);
        successMessage = '삭제 제안이 승인되어 이야기가 숨겨졌습니다';
      } else if (p.isGeneralProposal) {
        await repo.approveGeneral(p.id);
        successMessage = '일반 제안이 승인되었습니다';
      } else {
        final newReviewResult = reviewResult;
        if (newReviewResult == null) {
          throw StateError('새 이야기 승인 검토 결과가 없습니다.');
        }
        await repo.approve(
          p.id,
          afterStoryIndexOverride: newReviewResult.afterStoryIndexOverride,
          characterActiveOverrides: newReviewResult.characterActiveOverrides,
        );
        successMessage = '제안이 승인되어 events 에 반영되었습니다';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
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
      final repo = ref.read(proposalRepositoryProvider);
      if (p.isGeneralProposal) {
        await repo.rejectGeneral(p.id, note: note);
      } else {
        await repo.reject(p.id, note: note);
      }
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

  /// 위치 재선택 다이얼로그 — 제안자 본인이 invalidate 된 자기 제안의 위치/연도를
  /// 새로 고른다. 내부 RPC `revise_proposal_position` 가 prev/next 이벤트 연도와
  /// 정합 검증해 부적합하면 예외. 성공 시 invalidated 가 풀려 admin 이 다시
  /// approve/reject 가능.
  Future<void> _openRevisePositionDialog(EventProposal p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RevisePositionDialog(proposal: p),
    );
    if (ok == true) {
      ref.invalidate(proposalDetailProvider(p.id));
      ref.invalidate(proposalListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치/연도가 갱신되었습니다 (관리자 검토 대기)')),
      );
    }
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

  /// 본인 제안 삭제 — approved 는 UI 에서 이미 버튼 비활성화로 막지만,
  /// 서버 RLS `event_proposals_delete_own_unapproved` 가 최종 방어.
  /// 실제 삭제 전 확인 다이얼로그 노출.
  Future<void> _delete(EventProposal p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제안 삭제'),
        content: Text(
          '"${p.title}" 제안을 삭제하시겠어요?\n'
          '${p.isRejected ? "거절 이력 및 댓글" : "작성 중인 내용과 댓글"}이 모두 함께 사라집니다. '
          '되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _reviewing = true);
    try {
      await ref.read(proposalRepositoryProvider).deleteProposal(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제안이 삭제되었습니다')));
      ref.invalidate(proposalListProvider);
      Navigator.of(context).pop(true); // 제안 게시판으로 복귀
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    } finally {
      if (mounted) setState(() => _reviewing = false);
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
              // ───── 삭제 제안 안내 배너 ─────
              if (p.isDeleteProposal) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBE9E7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '이 제안은 기존 이야기의 삭제를 요청합니다. 승인하면 대상 '
                          '이야기가 앱과 프로필 진행률에서 제외됩니다. 과거 기록은 '
                          'DB에만 남습니다.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ───── 일반 제안 안내 배너 ─────
              if (p.isGeneralProposal) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '앱 전반에 대한 일반 제안입니다. 승인/거절은 status 만 갱신합니다.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ───── 제목 + 장소·연도 (EventDetailPage 스타일) ─────
              // 일반 제안은 장소·연도가 없으므로 제목만 표시.
              _ProposalHeaderRow(proposal: p),
              // ───── 일반 제안 본문 + 첨부 이미지 ─────
              if (p.isGeneralProposal) ...[
                const SizedBox(height: 12),
                _DetailSection(
                  title: '내용',
                  content: (p.summary ?? '').trim().isEmpty
                      ? '내용이 없습니다.'
                      : p.summary!,
                ),
                if (p.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _GeneralImageGrid(paths: p.imagePaths),
                ],
              ] else ...[
                // ───── 미리보기 섹션 (4장면 이미지) ─────
                if (p.sceneImagePaths.any((s) => s.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  _PreviewSection(
                    child: _ProposalSceneGrid(
                      paths: p.sceneImagePaths,
                      captions: p.sceneCaptions,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // ───── 배경 지식 ─────
                _DetailSection(
                  title: '배경 지식',
                  content: (p.backgroundContext ?? '').trim().isEmpty
                      ? '배경 지식이 없습니다.'
                      : p.backgroundContext!,
                ),
                const SizedBox(height: 12),
                // ───── 요약 이야기 ─────
                _DetailSection(
                  title: '요약 이야기',
                  content: (p.summary ?? '').trim().isEmpty
                      ? '요약 정보가 없습니다.'
                      : p.summary!,
                ),
                if (p.storyScenes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SceneTextSection(
                    scenes: p.storyScenes,
                    captions: p.sceneCaptions,
                  ),
                ],
                // ───── 관련 본문 + 이동 버튼 ─────
                if (p.bibleRefs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DetailSection(
                    title: '관련 본문',
                    content: p.bibleRefs
                        .map(
                          (r) =>
                              '• ${r['book'] ?? ''} ${r['from'] ?? ''}${(r['to'] != null && r['to'] != r['from']) ? '-${r['to']}' : ''}',
                        )
                        .join('\n'),
                    action: _bibleMoveButtonFor(p),
                  ),
                ],
                // ───── 추가 메타 (장소 좌표, 등장 인물 코드) ─────
                const SizedBox(height: 12),
                _MetaKvBlock(proposal: p),
                // ───── 퀴즈 (작성 선택지 3개 + 자동 헷갈림 보기) ─────
                if (p.quizQuestions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _QuizSection(quizzes: p.quizQuestions),
                ],
              ],
              // ───── 상태 chip + 거절 사유 ─────
              const SizedBox(height: 12),
              Row(
                children: [
                  ProposalStatusChip(status: p.status),
                  if (p.isApproved && p.approvedEventId != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '→ events.id: ${p.approvedEventId!.substring(0, 8)}...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              if (p.isRejected && (p.reviewNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
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
              ],
              // ───── 위치 재선택 안내 배너 (invalidate 된 경우) ─────
              if (p.needsPositionRevision) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE53935)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.report_problem_outlined,
                        color: Color(0xFFE53935),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '위치 재선택이 필요해요',
                              style: TextStyle(
                                color: Color(0xFFB71C1C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.positionInvalidationReason ??
                                  '같은 위치에 다른 이야기가 먼저 승인되었어요. 새 위치와 연도를 골라주세요.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ───── 액션 버튼 ─────
              const SizedBox(height: 16),
              Builder(
                builder: (_) {
                  // 작성자 삭제 허용 조건:
                  //   1) 로그인 + 2) 본인 제안 + 3) 승인되지 않은 상태.
                  //   (pending / rejected 모두 본인 삭제 가능)
                  // admin 은 승인 여부 무관하게 삭제 가능 (서버 RLS 가 최종 판정).
                  final isOwner =
                      currentUser != null && p.proposerUserId == currentUser.id;
                  final canOwnerDelete = isOwner && !p.isApproved;
                  final canAdminDelete = isAdmin;
                  // invalidate 된 동안에도 admin 은 승인 다이얼로그에서 새 위치를
                  // 명시하면 바로 승인 가능하다. 거절은 위치 의미가 모호한 동안
                  // RPC 에서 거부하므로 UI 에서도 잠근다.
                  final reviewLocked = p.needsPositionRevision;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 삭제 제안은 사유만 담긴 단순 구조라 수정 UX 가 의미 없음.
                      // 본인이 철회하고 싶으면 아래 "삭제" 버튼으로 제안 자체를 지우고
                      // 다시 낸다.
                      if (isOwnerPending &&
                          !p.isDeleteProposal &&
                          !p.isGeneralProposal)
                        OutlinedButton.icon(
                          onPressed: _reviewing ? null : () => _edit(p),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('수정'),
                        ),
                      // 작성자 본인이 invalidate 된 자기 제안의 위치/연도를 다시 결정.
                      if (isOwner && p.needsPositionRevision)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _reviewing
                              ? null
                              : () => _openRevisePositionDialog(p),
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('위치 재선택'),
                        ),
                      if (isAdmin && p.isPending) ...[
                        FilledButton.icon(
                          onPressed: _reviewing ? null : () => _approve(p),
                          icon: const Icon(Icons.check),
                          label: Text(reviewLocked ? '위치 조정 후 승인' : '승인'),
                        ),
                        Tooltip(
                          message: reviewLocked
                              ? '제안자가 위치를 다시 결정한 뒤에 거절할 수 있어요'
                              : '',
                          child: OutlinedButton.icon(
                            onPressed: (_reviewing || reviewLocked)
                                ? null
                                : () => _reject(p),
                            icon: const Icon(Icons.close),
                            label: const Text('거절'),
                          ),
                        ),
                      ],
                      if (canOwnerDelete || canAdminDelete)
                        Tooltip(
                          message: p.isApproved
                              ? '승인된 제안은 삭제할 수 없습니다'
                              : '이 제안을 삭제합니다',
                          child: OutlinedButton.icon(
                            onPressed: (_reviewing || p.isApproved)
                                ? null
                                : () => _delete(p),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.isApproved
                                  ? theme.disabledColor
                                  : theme.colorScheme.error,
                              side: BorderSide(
                                color: p.isApproved
                                    ? theme.colorScheme.outlineVariant
                                    : theme.colorScheme.error.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('삭제'),
                          ),
                        ),
                    ],
                  );
                },
              ),
              // ───── 댓글 ─────
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

  /// 관련 본문 카드 우측의 "이동" 버튼 — 첫 ref 로 BibleReaderPage 이동.
  Widget? _bibleMoveButtonFor(EventProposal p) {
    if (p.bibleRefs.isEmpty) return null;
    final first = p.bibleRefs.first;
    final book = (first['book'] as String?)?.trim() ?? '';
    final from = (first['from'] as String?)?.trim() ?? '';
    if (book.isEmpty || from.isEmpty) return null;
    final target = parseBibleNavigationTarget('$book $from');
    if (target == null) return null;
    return FilledButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BibleReaderPage(
              initialBookNo: target.bookNo,
              initialChapterNo: target.chapterNo,
              initialVerseNo: target.verseNo,
            ),
          ),
        );
      },
      child: const Text('이동'),
    );
  }
}
