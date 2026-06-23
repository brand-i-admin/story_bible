import 'package:flutter/material.dart';

import '../../models/app_notification.dart';

/// 알림 드롭다운 / 전체보기 히스토리 모두에서 공통으로 쓰는 행 위젯.
/// 타입별 아이콘 + 제목(굵게) + 본문(1줄 생략) + 상대시간 + 미독 점.
class NotificationListTile extends StatelessWidget {
  const NotificationListTile({
    super.key,
    required this.notification,
    required this.onTap,
    this.compact = false,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  /// 드롭다운(소형) vs 전체보기(표준) 레이아웃.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconData = _iconFor(notification.type);
    final iconColor = _iconColorFor(notification.type);
    final titleStyle = TextStyle(
      fontSize: compact ? 13 : 14,
      fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w800,
      color: const Color(0xFF3B2A17),
      height: 1.25,
    );
    final bodyStyle = TextStyle(
      fontSize: compact ? 11.5 : 12.5,
      color: notification.isRead
          ? const Color(0xFF7C6847)
          : const Color(0xFF4D381F),
      height: 1.35,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 32 : 36,
                height: compact ? 32 : 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  iconData,
                  size: compact ? 18 : 20,
                  color: iconColor,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: TextStyle(
                            fontSize: compact ? 10.5 : 11,
                            color: const Color(0xFF8B7354),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((notification.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body!,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.proposalComment:
      case AppNotificationType.proposalCommentAdmin:
        return Icons.mode_comment_outlined;
      case AppNotificationType.newProposalAdmin:
        return Icons.note_add_outlined;
      case AppNotificationType.proposalApproved:
        return Icons.check_circle_outline;
      case AppNotificationType.proposalRejected:
        return Icons.cancel_outlined;
      case AppNotificationType.proposalPositionInvalidated:
        return Icons.edit_location_alt_outlined;
      case AppNotificationType.quizCompleted:
        return Icons.emoji_events_outlined;
      case AppNotificationType.newEvent:
        return Icons.menu_book_outlined;
      case AppNotificationType.weeklyCharacter:
        return Icons.person_outline;
      case AppNotificationType.weeklyQuiz:
        return Icons.calendar_month_outlined;
      case AppNotificationType.dailyQuiz:
        return Icons.quiz_outlined;
      case AppNotificationType.weeklyProgressCheck:
        return Icons.track_changes;
      case AppNotificationType.weeklyDiaryReflection:
        return Icons.edit_note_outlined;
      case AppNotificationType.unknown:
        return Icons.notifications_outlined;
    }
  }

  static Color _iconColorFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.proposalApproved:
      case AppNotificationType.quizCompleted:
        return const Color(0xFF2D7B4D);
      case AppNotificationType.proposalRejected:
        return const Color(0xFFB00020);
      case AppNotificationType.newEvent:
      case AppNotificationType.weeklyCharacter:
      case AppNotificationType.weeklyQuiz:
      case AppNotificationType.dailyQuiz:
      case AppNotificationType.weeklyProgressCheck:
      case AppNotificationType.weeklyDiaryReflection:
        return const Color(0xFF7A4B21);
      default:
        return const Color(0xFFA85B25);
    }
  }

  /// '지금' / '3분' / '2시간' / '5일' / 'M월 D일' 형태의 상대시간.
  static String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return '지금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    if (diff.inDays < 7) return '${diff.inDays}일';
    return '${when.month}월 ${when.day}일';
  }
}
