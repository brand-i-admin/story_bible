import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/services/monitoring_privacy_policy.dart';

void main() {
  group('shouldReportNonFatalError', () {
    test('인터넷 단절과 사용자의 취소는 보고하지 않는다', () {
      expect(
        shouldReportNonFatalError(Exception('Failed host lookup: api.test')),
        isFalse,
      );
      expect(
        shouldReportNonFatalError(Exception('The operation was canceled')),
        isFalse,
      );
    });

    test('서버에서 이미 정리된 refresh token은 보고하지 않는다', () {
      expect(
        shouldReportNonFatalError(
          const AuthException(
            'Invalid Refresh Token: Refresh Token Not Found',
            statusCode: '400',
            code: 'refresh_token_not_found',
          ),
        ),
        isFalse,
      );
    });

    test('예상하지 못한 저장 오류는 보고한다', () {
      expect(
        shouldReportNonFatalError(Exception('database constraint mismatch')),
        isTrue,
      );
    });
  });

  group('isLikelyNewAccountSignIn', () {
    test('생성과 최초 로그인 시각이 가까우면 신규 계정이다', () {
      expect(
        isLikelyNewAccountSignIn(
          createdAt: '2026-07-16T01:00:00Z',
          lastSignInAt: '2026-07-16T01:00:10Z',
        ),
        isTrue,
      );
    });

    test('기존 계정 재로그인과 잘못된 시각은 신규 계정이 아니다', () {
      expect(
        isLikelyNewAccountSignIn(
          createdAt: '2026-06-01T01:00:00Z',
          lastSignInAt: '2026-07-16T01:00:00Z',
        ),
        isFalse,
      );
      expect(
        isLikelyNewAccountSignIn(createdAt: 'invalid', lastSignInAt: null),
        isFalse,
      );
    });
  });
}
