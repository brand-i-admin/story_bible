import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/proposal_repository.dart';
import '../models/event_proposal.dart';
import '../models/proposal_comment.dart';
import 'auth_providers.dart';

final proposalRepositoryProvider = Provider<ProposalRepository>((ref) {
  return ProposalRepository(Supabase.instance.client);
});

/// 사역자(목회자) 여부. `user_profiles.is_pastor` 컬럼 기준.
/// 로그인 상태가 바뀌면 자동 재계산된다.
final isPastorProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(signedInUserProvider);
  if (user == null) {
    return false;
  }
  return ref.watch(userRepositoryProvider).fetchIsPastor(user.id);
});

/// 관리자 여부. `auth.app_metadata.role == 'admin'` 기준.
/// `is_admin()` SQL 함수와 동일 기준이라 RLS와 일관된다.
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(signedInUserProvider);
  if (user == null) {
    return false;
  }
  return user.appMetadata['role'] == 'admin';
});

/// 게시판 필터 옵션. null = 전체.
class ProposalListFilter {
  const ProposalListFilter({this.status, this.onlyMine = false});
  final String? status; // 'pending' | 'approved' | 'rejected' | null
  final bool onlyMine;

  ProposalListFilter copyWith({
    String? status,
    bool? onlyMine,
    bool clearStatus = false,
  }) {
    return ProposalListFilter(
      status: clearStatus ? null : (status ?? this.status),
      onlyMine: onlyMine ?? this.onlyMine,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProposalListFilter &&
          status == other.status &&
          onlyMine == other.onlyMine);

  @override
  int get hashCode => Object.hash(status, onlyMine);
}

final proposalListFilterProvider = StateProvider<ProposalListFilter>(
  (ref) => const ProposalListFilter(),
);

/// 필터에 맞는 제안 목록. 탭 전환/새로고침 시 재요청.
final proposalListProvider = FutureProvider.autoDispose<List<EventProposal>>((
  ref,
) async {
  final filter = ref.watch(proposalListFilterProvider);
  final user = ref.watch(signedInUserProvider);
  final repo = ref.watch(proposalRepositoryProvider);
  return repo.fetchProposals(
    status: filter.status,
    proposerUserId: filter.onlyMine ? user?.id : null,
  );
});

/// 특정 제안 단건 — 상세 화면용.
final proposalDetailProvider = FutureProvider.autoDispose
    .family<EventProposal, String>((ref, id) async {
      return ref.watch(proposalRepositoryProvider).fetchProposal(id);
    });

/// 제안에 달린 댓글 목록.
final proposalCommentsProvider = FutureProvider.autoDispose
    .family<List<ProposalComment>, String>((ref, id) async {
      return ref.watch(proposalRepositoryProvider).fetchComments(id);
    });
