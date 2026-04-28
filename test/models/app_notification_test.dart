import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/app_notification.dart';

void main() {
  group('AppNotificationType.fromWire', () {
    test('알려진 type 문자열은 해당 enum 으로 매핑된다', () {
      expect(
        AppNotificationType.fromWire('proposal_comment'),
        AppNotificationType.proposalComment,
      );
      expect(
        AppNotificationType.fromWire('weekly_character'),
        AppNotificationType.weeklyCharacter,
      );
      expect(
        AppNotificationType.fromWire('quiz_completed'),
        AppNotificationType.quizCompleted,
      );
    });

    test('알 수 없는 값은 unknown 으로 떨어진다', () {
      expect(
        AppNotificationType.fromWire('some_new_event'),
        AppNotificationType.unknown,
      );
      expect(AppNotificationType.fromWire(null), AppNotificationType.unknown);
    });
  });

  group('AppNotificationType.isProposalRelated', () {
    test('제안 관련 5종은 true — 모바일/태블릿 다이얼로그 분기용', () {
      expect(AppNotificationType.proposalComment.isProposalRelated, isTrue);
      expect(
        AppNotificationType.proposalCommentAdmin.isProposalRelated,
        isTrue,
      );
      expect(AppNotificationType.newProposalAdmin.isProposalRelated, isTrue);
      expect(AppNotificationType.proposalApproved.isProposalRelated, isTrue);
      expect(AppNotificationType.proposalRejected.isProposalRelated, isTrue);
    });

    test('제안 무관 타입은 false', () {
      expect(AppNotificationType.quizCompleted.isProposalRelated, isFalse);
      expect(AppNotificationType.newEvent.isProposalRelated, isFalse);
      expect(AppNotificationType.weeklyCharacter.isProposalRelated, isFalse);
    });
  });

  group('AppNotification.fromMap', () {
    test('personal source + 전체 필드', () {
      final n = AppNotification.fromMap({
        'id': '11111111-1111-1111-1111-111111111111',
        'source': 'personal',
        'type': 'proposal_approved',
        'title': '제안이 승인되었어요',
        'body': '"가인과 아벨" 이(가) 등록되었어요.',
        'deep_link': '/event/abc',
        'payload': {'event_id': 'abc', 'proposal_title': '가인과 아벨'},
        'is_read': false,
        'created_at': '2026-04-22T10:00:00Z',
      });
      expect(n.id, '11111111-1111-1111-1111-111111111111');
      expect(n.source, NotificationSource.personal);
      expect(n.type, AppNotificationType.proposalApproved);
      expect(n.title, '제안이 승인되었어요');
      expect(n.deepLink, '/event/abc');
      expect(n.payload['event_id'], 'abc');
      expect(n.isRead, false);
      expect(n.createdAt.year, 2026);
    });

    test('broadcast source + is_read 기본값 false', () {
      final n = AppNotification.fromMap({
        'id': 'bbb',
        'source': 'broadcast',
        'type': 'new_event',
        'title': '새 이야기',
        'created_at': '2026-04-22T10:00:00Z',
      });
      expect(n.source, NotificationSource.broadcast);
      expect(n.isRead, false);
      expect(n.body, isNull);
      expect(n.payload, isEmpty);
    });

    test('source 누락 시 personal 로 폴백', () {
      final n = AppNotification.fromMap({
        'id': 'x',
        'type': 'unknown',
        'title': 't',
        'created_at': '2026-04-22T10:00:00Z',
      });
      expect(n.source, NotificationSource.personal);
    });

    test('payload 가 Map<dynamic,dynamic> 이어도 Map<String,dynamic> 으로 정규화', () {
      final n = AppNotification.fromMap({
        'id': 'x',
        'source': 'personal',
        'type': 'quiz_completed',
        'title': 't',
        'payload': <dynamic, dynamic>{'key': 'value'},
        'created_at': '2026-04-22T10:00:00Z',
      });
      expect(n.payload['key'], 'value');
    });
  });

  group('AppNotification.copyWith', () {
    test('isRead 만 바꿔 새 객체 반환', () {
      final n = AppNotification.fromMap({
        'id': 'x',
        'source': 'personal',
        'type': 'quiz_completed',
        'title': 't',
        'is_read': false,
        'created_at': '2026-04-22T10:00:00Z',
      });
      final updated = n.copyWith(isRead: true);
      expect(updated.isRead, isTrue);
      expect(updated.id, n.id);
      expect(updated.title, n.title);
    });
  });
}
