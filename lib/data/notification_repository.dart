import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// 인앱 알림함 + FCM 토큰 등록 데이터 계층.
///
/// DB 는 `notifications` (개인) + `broadcast_notifications` (공지) 두 테이블을
/// [`list_my_notifications`](db_init.sql) RPC 로 UNION 하여 반환한다. 이 레이어는
/// 그 결과를 [AppNotification] 으로 파싱하고, 읽음 처리 등 RPC wrapper 를 제공.
///
/// Realtime 구독은 개인 알림만 직접 스트리밍 할 수 있다(`notifications` 테이블에
/// row INSERT 가 오면 옴). 브로드캐스트는 테이블이 공용이므로 별도 구독이 가능
/// 하되 전체 유저 수 × 이벤트 수만큼 payload 가 흐를 수 있어 비효율적이다.
/// 대신 bell 아이콘이 표시될 때마다 [unreadCount] 를 polling 하는 방식으로
/// 설계했다(기본 30초 간격, [watchUnreadCount] 제공).
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// 최근 30일 내 알림 조회 (UNION of personal + broadcast).
  /// [onlyUnread] = true 이면 읽지 않은 것만. bell 드롭다운에서 활용.
  Future<List<AppNotification>> fetchNotifications({
    int limit = 30,
    bool onlyUnread = false,
  }) async {
    final rows = await _client.rpc(
      'list_my_notifications',
      params: {'p_limit': limit, 'p_only_unread': onlyUnread},
    );
    return (rows as List)
        .map<AppNotification>(
          (row) => AppNotification.fromMap(row as Map<String, dynamic>),
        )
        .toList();
  }

  /// 배지용 읽지 않은 개수 (개인 + 공지 합산).
  Future<int> fetchUnreadCount() async {
    final result = await _client.rpc('unread_notification_count');
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.tryParse(result) ?? 0;
    return 0;
  }

  /// [AppNotification] 의 source 에 따라 올바른 read RPC 를 호출.
  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    final rpcName = notification.source == NotificationSource.personal
        ? 'mark_notification_read'
        : 'mark_broadcast_read';
    final param = notification.source == NotificationSource.personal
        ? 'p_id'
        : 'p_broadcast_id';
    await _client.rpc(rpcName, params: {param: notification.id});
  }

  /// 전부 읽음 — 개인 + 공지 모두 한번에.
  Future<void> markAllRead() async {
    // 두 RPC 를 연속 호출. 실패 시에도 부분 성공 가능성이 있어 try-catch 로
    // 서로 영향 주지 않게 분리.
    try {
      await _client.rpc('mark_all_notifications_read');
    } catch (_) {}
    try {
      await _client.rpc('mark_all_broadcasts_read');
    } catch (_) {}
  }

  /// 읽지 않은 개수 polling 스트림. [interval] 간격으로 [fetchUnreadCount].
  /// 구독자가 없으면 Timer 해제됨.
  Stream<int> watchUnreadCount({
    Duration interval = const Duration(seconds: 30),
  }) {
    late final StreamController<int> controller;
    Timer? timer;

    Future<void> tick() async {
      try {
        final count = await fetchUnreadCount();
        if (!controller.isClosed) {
          controller.add(count);
        }
      } catch (_) {
        // polling 에러는 무시 — 다음 tick 에 재시도.
      }
    }

    controller = StreamController<int>(
      onListen: () {
        tick();
        timer = Timer.periodic(interval, (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        controller.close();
      },
    );

    return controller.stream;
  }

  /// FCM 디바이스 토큰 등록(upsert).
  /// [platform] 은 'web' | 'ios' | 'android'.
  Future<void> registerPushToken({
    required String token,
    required String platform,
    String? deviceLabel,
  }) async {
    await _client.rpc(
      'register_push_token',
      params: {
        'p_token': token,
        'p_platform': platform,
        'p_device_label': deviceLabel,
      },
    );
  }

  /// FCM 디바이스 토큰 해제 (로그아웃/토큰 갱신 시).
  Future<void> unregisterPushToken(String token) async {
    await _client.rpc('unregister_push_token', params: {'p_token': token});
  }

  /// 퀴즈 완료 알림 트리거 — 클라이언트가 퀴즈 완주 직후 호출.
  /// DB 측에서 본인에게 notifications row 를 INSERT 한다 (SECURITY DEFINER).
  Future<void> notifyQuizCompleted(String eventId) async {
    await _client.rpc('notify_quiz_completed', params: {'p_event_id': eventId});
  }
}
