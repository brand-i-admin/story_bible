import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/notification_repository.dart';
import '../models/app_notification.dart';
import 'auth_providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

/// bell 드롭다운(최대 5개 읽지 않은 알림).
/// autoDispose — 드롭다운 닫히면 해제.
final unreadNotificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
      final user = ref.watch(signedInUserProvider);
      if (user == null) return const [];
      return ref
          .watch(notificationRepositoryProvider)
          .fetchNotifications(limit: 5, onlyUnread: true);
    });

/// 전체보기 히스토리 화면 (최근 30일 — 읽은 것 포함).
final notificationHistoryProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
      final user = ref.watch(signedInUserProvider);
      if (user == null) return const [];
      return ref
          .watch(notificationRepositoryProvider)
          .fetchNotifications(limit: 100, onlyUnread: false);
    });

/// bell 아이콘 배지용 읽지 않은 개수 polling 스트림.
/// 로그인 상태에서만 active. 로그아웃 시 0 고정.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(signedInUserProvider);
  if (user == null) return Stream<int>.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCount();
});
