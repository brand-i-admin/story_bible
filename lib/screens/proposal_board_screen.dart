import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event_proposal.dart';
import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';
import '../widgets/proposal/proposal_status_chip.dart';
import 'proposal_detail_screen.dart';
import 'proposal_submit_screen.dart';

/// 사역자/관리자 전용 "이야기 제안" 게시판.
/// 전체 / 내 제안 / 대기중 / 승인 / 거절 탭으로 필터링한다.
class ProposalBoardScreen extends ConsumerStatefulWidget {
  const ProposalBoardScreen({super.key});

  @override
  ConsumerState<ProposalBoardScreen> createState() =>
      _ProposalBoardScreenState();
}

class _ProposalBoardScreenState extends ConsumerState<ProposalBoardScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_TabDef>[
    _TabDef(label: '전체', filter: ProposalListFilter()),
    _TabDef(label: '내 제안', filter: ProposalListFilter(onlyMine: true)),
    _TabDef(
      label: '대기중',
      filter: ProposalListFilter(status: 'pending'),
    ),
    _TabDef(
      label: '승인됨',
      filter: ProposalListFilter(status: 'approved'),
    ),
    _TabDef(
      label: '거절됨',
      filter: ProposalListFilter(status: 'rejected'),
    ),
  ];

  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _tabs.length, vsync: this);
    _controller.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_controller.indexIsChanging) {
      ref.read(proposalListFilterProvider.notifier).state =
          _tabs[_controller.index].filter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listAsync = ref.watch(proposalListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('이야기 제안 게시판'),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabs: [for (final t in _tabs) Tab(text: t.label)],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goSubmit(context),
        icon: const Icon(Icons.add),
        label: const Text('새 제안'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(proposalListProvider),
        child: listAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text(
                  '제안 목록을 불러오지 못했습니다\n$err',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          data: (proposals) {
            if (proposals.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('등록된 제안이 없습니다')),
                ],
              );
            }
            final myUserId = ref.watch(signedInUserProvider)?.id;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: proposals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = proposals[index];
                // 본인 제안 + status='pending' 일 때만 취소 가능 (RLS 와 일치).
                final isMine = myUserId != null && p.proposerUserId == myUserId;
                final canCancel = isMine && p.status == 'pending';
                return Card(
                  child: ListTile(
                    title: Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          p.summary ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ProposalStatusChip(status: p.status),
                            // 같은 위치에 다른 제안이 먼저 승인되어 위치가 모호해진
                            // 상태 → 빨간 "수정 필요" 라벨로 강조 (작성자가 한눈에).
                            if (p.needsPositionRevision)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE53935),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  '수정 필요',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            Text(
                              _formatDate(p.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (isMine)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '내 제안',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    trailing: canCancel
                        ? IconButton(
                            tooltip: '제안 취소 (관리자 검토 전까지만 가능)',
                            icon: const Icon(Icons.delete_outline),
                            color: theme.colorScheme.error,
                            onPressed: () => _confirmCancel(context, p),
                          )
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProposalDetailScreen(proposalId: p.id),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _goSubmit(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProposalSubmitScreen()));
    // 돌아오면 목록 새로고침
    ref.invalidate(proposalListProvider);
  }

  /// 본인 pending 제안 취소 확인 → Storage(장면 + 신규 캐릭터) + DB row 일괄 삭제.
  Future<void> _confirmCancel(BuildContext context, EventProposal p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('제안을 취소할까요?'),
        content: Text(
          '"${p.title}" 제안을 삭제합니다.\n'
          '생성한 장면 이미지와, 이 제안에서 새로 만든 캐릭터 아바타도 같이 정리됩니다. '
          '되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('아니오'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(proposalRepositoryProvider).deleteProposalWithAssets(p);
      if (!mounted) return;
      ref.invalidate(proposalListProvider);
      messenger.showSnackBar(const SnackBar(content: Text('제안이 취소되었어요.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('취소 실패: $e')));
    }
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _TabDef {
  const _TabDef({required this.label, required this.filter});
  final String label;
  final ProposalListFilter filter;
}
