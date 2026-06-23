import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/notification/notification_deep_link.dart';

void main() {
  group('NotificationDeepLink.parse', () {
    test('/proposal/<id> 는 proposal target + id 추출', () {
      final link = NotificationDeepLink.parse('/proposal/abc-123');
      expect(link.target, NotificationTarget.proposal);
      expect(link.id, 'abc-123');
    });

    test('/event/<id> 는 event target + id 추출', () {
      final link = NotificationDeepLink.parse('/event/xyz');
      expect(link.target, NotificationTarget.event);
      expect(link.id, 'xyz');
    });

    test('/daily-exploration 는 dailyExploration target, id 없음', () {
      final link = NotificationDeepLink.parse('/daily-exploration');
      expect(link.target, NotificationTarget.dailyExploration);
      expect(link.id, isNull);
    });

    test('/daily-quiz 는 호환 dailyExploration target, id 없음', () {
      final link = NotificationDeepLink.parse('/daily-quiz');
      expect(link.target, NotificationTarget.dailyExploration);
      expect(link.id, isNull);
    });

    test('/weekly 는 weekly target, id 없음', () {
      final link = NotificationDeepLink.parse('/weekly');
      expect(link.target, NotificationTarget.weekly);
      expect(link.id, isNull);
    });

    test('/profile 는 profile target, id 없음', () {
      final link = NotificationDeepLink.parse('/profile');
      expect(link.target, NotificationTarget.profile);
      expect(link.id, isNull);
    });

    test('/weekly/extra 도 weekly target (하위 세그먼트 무시)', () {
      final link = NotificationDeepLink.parse('/weekly/foo');
      expect(link.target, NotificationTarget.weekly);
    });

    test('null 은 unknown', () {
      final link = NotificationDeepLink.parse(null);
      expect(link.target, NotificationTarget.unknown);
      expect(link.id, isNull);
    });

    test('빈 문자열은 unknown', () {
      final link = NotificationDeepLink.parse('');
      expect(link.target, NotificationTarget.unknown);
    });

    test('알 수 없는 prefix 는 unknown', () {
      final link = NotificationDeepLink.parse('/account/me');
      expect(link.target, NotificationTarget.unknown);
    });

    test('선두 / 없어도 파싱', () {
      final link = NotificationDeepLink.parse('proposal/abc');
      expect(link.target, NotificationTarget.proposal);
      expect(link.id, 'abc');
    });

    test('id 누락된 proposal 는 target 만 잡히고 id 는 null', () {
      final link = NotificationDeepLink.parse('/proposal');
      expect(link.target, NotificationTarget.proposal);
      expect(link.id, isNull);
    });
  });
}
