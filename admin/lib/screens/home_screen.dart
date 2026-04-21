import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/admin_providers.dart';
import 'login_screen.dart';
import 'submit_event_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider);

    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    final isLoggedIn = user != null;
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Bible Admin'),
        actions: [
          if (isLoggedIn)
            IconButton(
              tooltip: '로그아웃',
              onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
              icon: const Icon(Icons.logout),
            )
          else
            TextButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              icon: const Icon(Icons.login),
              label: const Text('로그인'),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isLoggedIn
                      ? '환영합니다, ${user.email ?? '사용자'} 님'
                      : 'Story Bible 어드민',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLine(isLoggedIn: isLoggedIn, isAdmin: isAdmin),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.add_box_outlined),
                    title: const Text('새 이야기 등록'),
                    subtitle: Text(
                      _submitSubtitle(isLoggedIn: isLoggedIn, isAdmin: isAdmin),
                    ),
                    enabled: !isLoggedIn || isAdmin,
                    onTap: () =>
                        _handleSubmitTap(context, isLoggedIn: isLoggedIn),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLine({required bool isLoggedIn, required bool isAdmin}) {
    if (!isLoggedIn) {
      return '로그인 없이 페이지를 둘러볼 수 있습니다. 이야기 등록은 관리자 로그인이 필요합니다.';
    }
    return isAdmin ? '권한: 관리자' : '권한: 없음 (관리자 계정이 필요합니다)';
  }

  String _submitSubtitle({required bool isLoggedIn, required bool isAdmin}) {
    if (!isLoggedIn) return '먼저 관리자 계정으로 로그인하세요';
    if (!isAdmin) return '관리자 권한이 필요합니다';
    return '폼을 채우면 바로 published 로 등록됩니다';
  }

  void _handleSubmitTap(BuildContext context, {required bool isLoggedIn}) {
    if (!isLoggedIn) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SubmitEventScreen()));
  }
}
