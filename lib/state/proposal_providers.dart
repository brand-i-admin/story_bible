import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/proposal_repository.dart';
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
