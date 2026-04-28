/// 인앱 알림함에 표시되는 알림 한 건.
///
/// DB 측에서는 두 테이블로 분리 저장된다:
/// - `notifications` (개인용 — Fan-out on Write)
/// - `broadcast_notifications` + `broadcast_notification_reads` (공지용)
///
/// `list_my_notifications` RPC 가 두 소스를 UNION 해서 단일 row 시퀀스로
/// 반환하며, [source] 필드로 어느 쪽에서 왔는지를 구분한다.
/// 이 구분은 "읽음 처리" 경로가 달라지기 때문에 필요하다
/// (개인 → `mark_notification_read`, 공지 → `mark_broadcast_read`).
enum NotificationSource { personal, broadcast }

/// 알림 type — DB 의 check 제약과 1:1 매핑.
/// 모르는 값이 들어와도 [AppNotificationType.unknown] 으로 떨어지며,
/// 클라이언트는 이 경우에도 크래시 없이 title/body 만 그대로 노출한다.
enum AppNotificationType {
  proposalComment('proposal_comment'),
  proposalCommentAdmin('proposal_comment_admin'),
  newProposalAdmin('new_proposal_admin'),
  proposalApproved('proposal_approved'),
  proposalRejected('proposal_rejected'),
  quizCompleted('quiz_completed'),
  newEvent('new_event'),
  weeklyCharacter('weekly_character'),
  weeklyProgressCheck('weekly_progress_check'),
  unknown('unknown');

  const AppNotificationType(this.wire);

  /// DB 에 저장되는 문자열 값.
  final String wire;

  static AppNotificationType fromWire(String? raw) {
    if (raw == null) return AppNotificationType.unknown;
    for (final t in AppNotificationType.values) {
      if (t.wire == raw) return t;
    }
    return AppNotificationType.unknown;
  }

  /// 제안 관련(댓글/승인/거절/새 제안) 알림인지.
  /// 모바일/태블릿에서 제안 상세는 편집이 웹 전용이므로, 이 경우에만
  /// "컴퓨터로 확인하세요" 다이얼로그를 띄운다.
  bool get isProposalRelated =>
      this == AppNotificationType.proposalComment ||
      this == AppNotificationType.proposalCommentAdmin ||
      this == AppNotificationType.newProposalAdmin ||
      this == AppNotificationType.proposalApproved ||
      this == AppNotificationType.proposalRejected;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.source,
    required this.type,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.payload,
    required this.isRead,
    required this.createdAt,
  });

  /// 원본 row id — personal 이면 notifications.id, broadcast 면
  /// broadcast_notifications.id.
  final String id;
  final NotificationSource source;
  final AppNotificationType type;
  final String title;
  final String? body;

  /// 클릭 시 이동할 앱 내 경로. 현재 스키마:
  /// - `/proposal/<uuid>` — 제안 상세
  /// - `/event/<uuid>`    — 이야기 상세
  /// - `/weekly`          — 금주 탭
  /// null 이면 클릭해도 이동하지 않고 읽음 처리만.
  final String? deepLink;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id'] as String,
      source: (row['source'] as String?) == 'broadcast'
          ? NotificationSource.broadcast
          : NotificationSource.personal,
      type: AppNotificationType.fromWire(row['type'] as String?),
      title: (row['title'] as String?) ?? '',
      body: row['body'] as String?,
      deepLink: row['deep_link'] as String?,
      payload: _coercePayload(row['payload']),
      isRead: (row['is_read'] as bool?) ?? false,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
    );
  }

  /// 드롭다운/히스토리 리스트에서 비교용 (읽음 상태 토글 시 객체 교체).
  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      source: source,
      type: type,
      title: title,
      body: body,
      deepLink: deepLink,
      payload: payload,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static Map<String, dynamic> _coercePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }
}
