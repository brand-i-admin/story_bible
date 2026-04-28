import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/app_notification.dart';

/// deep_link 문자열 파싱 결과.
///
/// 현재 스키마가 지원하는 target:
///  - `proposal/{id}`  : 제안 상세 — 편집은 웹 전용이라 모바일이면 경고 다이얼로그
///  - `event/{id}`     : 이야기 상세
///  - `weekly`         : 금주 탭
///  - `unknown`        : 처리 불가 (읽음만 남기고 끝)
enum NotificationTarget { proposal, event, weekly, unknown }

class NotificationDeepLink {
  const NotificationDeepLink(this.target, this.id);
  final NotificationTarget target;
  final String? id;

  static NotificationDeepLink parse(String? rawPath) {
    if (rawPath == null) {
      return const NotificationDeepLink(NotificationTarget.unknown, null);
    }
    final normalized = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      return const NotificationDeepLink(NotificationTarget.unknown, null);
    }
    switch (parts.first) {
      case 'proposal':
        return NotificationDeepLink(
          NotificationTarget.proposal,
          parts.length > 1 ? parts[1] : null,
        );
      case 'event':
        return NotificationDeepLink(
          NotificationTarget.event,
          parts.length > 1 ? parts[1] : null,
        );
      case 'weekly':
        return const NotificationDeepLink(NotificationTarget.weekly, null);
      default:
        return const NotificationDeepLink(NotificationTarget.unknown, null);
    }
  }
}

/// 모바일/태블릿 사용자가 제안 알림을 탭하면 뜨는 안내 다이얼로그.
///
/// 배경: 제안 작성/편집 UI 는 웹 전용이다(`story_home_screen.dart` 에서
/// `if (kIsWeb)` 로 "이야기 등록" 버튼도 웹에서만 노출). 모바일/태블릿에서
/// 알림을 눌러 이동해도 할 수 있는 일이 제한적이라 컴퓨터 사용을 안내한다.
Future<void> showUseDesktopDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('컴퓨터로 확인해 주세요'),
      content: const Text(
        '이 알림은 제안 게시판과 관련되어 있어요.\n'
        '제안 확인과 댓글 작성은 PC 웹에서만 지원합니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 모바일/태블릿 판별 — Flutter Web 이 아니면서 short-side 가 900 미만.
/// Desktop 웹 브라우저에서는 항상 false.
bool isMobileOrTabletDevice(BuildContext context) {
  if (kIsWeb) return false;
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  return shortestSide < 900;
}

/// 알림 탭 라우팅 판별. 반환값이 true 면 호출부가 실제 화면 전환을 진행,
/// false 면 이미 다이얼로그를 띄웠거나 처리가 끝났으니 아무것도 안 해도 된다.
///
/// 제안 관련 알림 + 모바일/태블릿 → 경고 다이얼로그만 노출.
Future<bool> shouldProceedWithNavigation(
  BuildContext context,
  AppNotification notification,
) async {
  if (notification.type.isProposalRelated && isMobileOrTabletDevice(context)) {
    await showUseDesktopDialog(context);
    return false;
  }
  return true;
}
