import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

/// `auth.app_metadata.role == 'admin'` 인 사용자만 관리자 화면(검토 리스트,
/// 배포 버튼)을 보여준다. SQL `is_admin()` 함수와 동일한 기준.
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(supabaseClientProvider).auth.currentUser;
  if (user == null) {
    return false;
  }
  final role = user.appMetadata['role'];
  return role == 'admin';
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});
