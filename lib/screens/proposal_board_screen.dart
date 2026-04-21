import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: proposals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = proposals[index];
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
                        Row(
                          children: [
                            ProposalStatusChip(status: p.status),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(p.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
