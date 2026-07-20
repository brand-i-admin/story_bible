import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_analytics_event.dart';
import 'monitoring_policy.dart';
import 'monitoring_privacy_policy.dart';

const _forceFirebaseMonitoring = bool.fromEnvironment(
  'FIREBASE_MONITORING_ENABLED',
  defaultValue: false,
);
const _forceCrashlyticsTestCrash = bool.fromEnvironment(
  'CRASHLYTICS_TEST_CRASH',
  defaultValue: false,
);
const _forceCrashlyticsTestNonFatal = bool.fromEnvironment(
  'CRASHLYTICS_TEST_NON_FATAL',
  defaultValue: false,
);

/// Firebase Analytics와 Crashlytics의 수집 경계를 한곳에서 관리한다.
///
/// 운영(real/prod) 릴리스 빌드에서만 자동 수집한다. 웹은 Analytics만 지원하며,
/// Crashlytics에는 사용자 작성 내용이나 사용자 식별자를 별도로 첨부하지 않는다.
class AppMonitoringService {
  AppMonitoringService._();

  static final AppMonitoringService instance = AppMonitoringService._();

  bool _analyticsEnabled = false;
  bool _crashlyticsEnabled = false;
  bool _globalHandlersInstalled = false;
  StreamSubscription<AuthState>? _authStateSubscription;

  Future<void> initialize({required String runtimeEnvironment}) async {
    final policy = MonitoringPolicy.resolve(
      runtimeEnvironment: runtimeEnvironment,
      isReleaseMode: kReleaseMode,
      isWeb: kIsWeb,
      forceEnabled: _forceFirebaseMonitoring,
    );

    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
        policy.analyticsEnabled,
      );
      _analyticsEnabled = policy.analyticsEnabled;
    } catch (error) {
      _analyticsEnabled = false;
      debugPrint('[monitoring] Analytics 수집 설정 실패: $error');
    }

    if (kIsWeb) {
      debugPrint(
        '[monitoring] Analytics=${policy.analyticsEnabled}, '
        'Crashlytics=false(web 미지원)',
      );
      return;
    }

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        policy.crashlyticsEnabled,
      );
      _crashlyticsEnabled = policy.crashlyticsEnabled;
    } catch (error) {
      _crashlyticsEnabled = false;
      debugPrint('[monitoring] Crashlytics 수집 설정 실패: $error');
      return;
    }

    if (_crashlyticsEnabled) {
      await _setStaticCrashContext(runtimeEnvironment);
      _installGlobalErrorHandlers();
      if (_forceFirebaseMonitoring &&
          _forceCrashlyticsTestNonFatal &&
          !kReleaseMode) {
        await _recordErrorSafely(
          StateError('Crashlytics non-fatal connection test'),
          StackTrace.current,
          reason: 'Crashlytics non-fatal connection test',
          fatal: false,
        );
        debugPrint('[monitoring] Crashlytics non-fatal 테스트를 전송했습니다.');
      }
      if (_forceFirebaseMonitoring &&
          _forceCrashlyticsTestCrash &&
          !kReleaseMode) {
        debugPrint('[monitoring] 요청된 Crashlytics 연결 테스트를 실행합니다.');
        FirebaseCrashlytics.instance.crash();
      }
    }

    debugPrint(
      '[monitoring] Analytics=${policy.analyticsEnabled}, '
      'Crashlytics=$_crashlyticsEnabled',
    );
  }

  /// Supabase 인증 상태를 익명 Analytics 속성과 계정 생성 이벤트로 연결한다.
  ///
  /// Supabase 사용자 ID나 이메일은 Firebase에 전달하지 않는다.
  Future<void> observeAuthState(SupabaseClient client) async {
    await _authStateSubscription?.cancel();
    await setLoginState(client.auth.currentUser != null);
    _authStateSubscription = client.auth.onAuthStateChange.listen(
      (authState) {
        final user = authState.session?.user;
        unawaited(setLoginState(user != null));
        if (authState.event == AuthChangeEvent.signedIn &&
            user != null &&
            isLikelyNewAccountSignIn(
              createdAt: user.createdAt,
              lastSignInAt: user.lastSignInAt,
            )) {
          unawaited(logAnalyticsEvent(AppAnalyticsEvent.accountCreated()));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // GoTrue removes an invalid persisted session before emitting this
        // error. Handle it here so a normal signed-out recovery is not raised
        // to PlatformDispatcher as an uncaught fatal exception.
        recordNonFatal(
          error,
          stackTrace,
          reason: 'Supabase auth state stream error',
        );
      },
    );
  }

  Future<void> setLoginState(bool signedIn) async {
    if (!_analyticsEnabled) {
      return;
    }
    try {
      await FirebaseAnalytics.instance.setUserProperty(
        name: 'login_state',
        value: signedIn ? 'signed_in' : 'signed_out',
      );
    } catch (error) {
      debugPrint('[monitoring] 로그인 상태 속성 전송 실패: $error');
    }
  }

  Future<void> logAnalyticsEvent(AppAnalyticsEvent event) async {
    if (!_analyticsEnabled) {
      return;
    }
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: event.name,
        parameters: event.parameters.isEmpty ? null : event.parameters,
      );
      if (!kReleaseMode) {
        debugPrint(
          '[monitoring] Analytics event=${event.name} '
          'parameters=${event.parameters}',
        );
      }
    } catch (error) {
      debugPrint('[monitoring] Analytics 이벤트 전송 실패(${event.name}): $error');
    }
  }

  void recordNonFatal(
    Object error,
    StackTrace stackTrace, {
    required String reason,
  }) {
    if (!_crashlyticsEnabled || !shouldReportNonFatalError(error)) {
      return;
    }
    unawaited(
      _recordErrorSafely(error, stackTrace, reason: reason, fatal: false),
    );
  }

  Future<void> _setStaticCrashContext(String runtimeEnvironment) async {
    try {
      await FirebaseCrashlytics.instance.setCustomKey(
        'runtime_environment',
        runtimeEnvironment.trim().toLowerCase(),
      );
      await FirebaseCrashlytics.instance.setCustomKey(
        'build_mode',
        kReleaseMode ? 'release' : 'debug',
      );
    } catch (error) {
      debugPrint('[monitoring] Crashlytics 공통 정보 설정 실패: $error');
    }
  }

  void _installGlobalErrorHandlers() {
    if (_globalHandlersInstalled) {
      return;
    }
    _globalHandlersInstalled = true;

    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(_recordFlutterErrorSafely(details));
      if (previousFlutterErrorHandler != null) {
        previousFlutterErrorHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(
        _recordErrorSafely(
          error,
          stackTrace,
          reason: 'Uncaught asynchronous error',
          fatal: true,
        ),
      );
      previousPlatformErrorHandler?.call(error, stackTrace);
      return true;
    };
  }

  Future<void> _recordFlutterErrorSafely(FlutterErrorDetails details) async {
    try {
      await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (error) {
      debugPrint('[monitoring] Flutter 오류 전송 실패: $error');
    }
  }

  Future<void> _recordErrorSafely(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    required bool fatal,
  }) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
      );
    } catch (recordingError) {
      debugPrint('[monitoring] 오류 전송 실패: $recordingError');
    }
  }
}
