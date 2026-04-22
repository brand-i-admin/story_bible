import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../state/notification_providers.dart';
import '../widgets/notification/notification_list_tile.dart';

/// "전체 보기" 버튼으로 진입하는 알림 히스토리 화면.
/// 읽은 알림 포함, 최근 30일 범위(서버 필터).
class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key, required this.onNavigate});

  /// 항목 탭 시 호출자가 딥링크 라우팅 + 읽음 처리.
  final void Function(AppNotification notification) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(notificationHistoryProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF4EAD2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE6D2A6),
        foregroundColor: const Color(0xFF4D381F),
        title: const Text('알림', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          TextButton(
            onPressed: () async {
              final repo = ref.read(notificationRepositoryProvider);
              await repo.markAllRead();
              ref.invalidate(notificationHistoryProvider);
              ref.invalidate(unreadNotificationsProvider);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B4A22),
            ),
            child: const Text(
              '모두 읽음',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationHistoryProvider);
          await ref.read(notificationHistoryProvider.future);
        },
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '알림을 불러오지 못했어요\n$err',
                style: const TextStyle(color: Color(0xFF8B5A24)),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(28),
                children: const [
                  SizedBox(height: 60),
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 40,
                    color: Color(0xFF8B7354),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '최근 30일 내 알림이 없어요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF7A6244),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: const Color(0xFF8E6F48).withValues(alpha: 0.2),
              ),
              itemBuilder: (_, index) {
                final n = items[index];
                return NotificationListTile(
                  notification: n,
                  onTap: () => onNavigate(n),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
