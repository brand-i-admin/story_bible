import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event_proposal.dart';
import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';
import '../widgets/proposal/proposal_status_chip.dart';
import 'general_proposal_submit_screen.dart';
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
                    leading: _ProposalTypeIcon(type: p.proposalType),
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
                            _ProposalTypeChip(type: p.proposalType),
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
    final navigator = Navigator.of(context);
    final picked = await _showProposalTypeSheet(context);
    if (picked == null || !mounted) return;
    final route = picked == _ProposalKind.story
        ? MaterialPageRoute<void>(builder: (_) => const ProposalSubmitScreen())
        : MaterialPageRoute<void>(
            builder: (_) => const GeneralProposalSubmitScreen(),
          );
    await navigator.push(route);
    // 돌아오면 목록 새로고침
    ref.invalidate(proposalListProvider);
  }

  /// 새 제안 시작 시 어떤 종류인지 먼저 묻는 시트.
  Future<_ProposalKind?> _showProposalTypeSheet(BuildContext context) {
    return showModalBottomSheet<_ProposalKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '어떤 제안을 등록할까요?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '이야기 제안은 새 성경 이야기 후보를, 일반 제안은 앱 전반에 대한 의견·문의를 등록합니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _ProposalKindCard(
                  icon: Icons.menu_book_outlined,
                  title: '이야기 제안',
                  subtitle: '새 성경 이야기를 시대·인물·장면·퀴즈와 함께 등록합니다.',
                  onTap: () => Navigator.of(ctx).pop(_ProposalKind.story),
                ),
                const SizedBox(height: 10),
                _ProposalKindCard(
                  icon: Icons.lightbulb_outline,
                  title: '일반 제안',
                  subtitle: '앱 사용 중 떠오른 의견을 텍스트와 이미지(최대 5장) 로 자유롭게 남깁니다.',
                  onTap: () => Navigator.of(ctx).pop(_ProposalKind.general),
                ),
              ],
            ),
          ),
        );
      },
    );
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

enum _ProposalKind { story, general }

/// 리스트 카드 좌측 leading 아이콘 — 제안 종류 한눈 구분.
class _ProposalTypeIcon extends StatelessWidget {
  const _ProposalTypeIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (type) {
      'delete' => (Icons.delete_outline, theme.colorScheme.error),
      'general' => (Icons.lightbulb_outline, theme.colorScheme.primary),
      _ => (Icons.menu_book_outlined, theme.colorScheme.primary),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

/// 상태 chip 옆에 함께 노출되는 종류 chip.
class _ProposalTypeChip extends StatelessWidget {
  const _ProposalTypeChip({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (type) {
      'delete' => ('삭제 제안', theme.colorScheme.error),
      'general' => ('일반 제안', theme.colorScheme.primary),
      _ => ('이야기 제안', theme.colorScheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProposalKindCard extends StatelessWidget {
  const _ProposalKindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
