import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/services/app_monitoring_service.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  test('Supabase 인증 스트림 오류를 전역 비동기 오류로 유출하지 않는다', () async {
    final authStateController = StreamController<AuthState>();
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);
    when(
      () => auth.onAuthStateChange,
    ).thenAnswer((_) => authStateController.stream);

    final uncaughtErrors = <Object>[];
    await runZonedGuarded(() async {
      await AppMonitoringService.instance.observeAuthState(client);
      authStateController.addError(
        const AuthException(
          'Invalid Refresh Token: Refresh Token Not Found',
          statusCode: '400',
          code: 'refresh_token_not_found',
        ),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => uncaughtErrors.add(error));

    await authStateController.close();
    expect(uncaughtErrors, isEmpty);
  });
}
