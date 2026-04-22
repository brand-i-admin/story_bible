import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM + 인앱 포그라운드 알림을 관리하는 싱글톤 서비스.
///
/// 호출 절차 (main.dart):
///   ```dart
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await PushService.instance.initialize();  // 권한 요청 + 토큰 구독
///   ```
///
/// 전제:
///  - `flutterfire configure` 로 `lib/firebase_options.dart` 가 생성되어 있어야
///    `DefaultFirebaseOptions.currentPlatform` 을 쓸 수 있다.
///  - Supabase 에 로그인된 뒤에 [registerCurrentTokenIfAuthenticated] 를 호출하면
///    서버 `user_push_tokens` 테이블에 upsert 된다.
///  - 로그아웃 시 [unregisterCurrentToken] 호출.
///
/// 세부 동작:
///  - iOS/Web: `requestPermission` 으로 권한 요청.
///  - Android 13+: Flutter 플러그인이 내부적으로 POST_NOTIFICATIONS 권한 요청.
///  - 포그라운드 메시지: flutter_local_notifications 로 시스템 토스트 재발행.
///  - 토큰 갱신: `onTokenRefresh` 스트림 구독 → Supabase 에 재등록.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  String? _currentToken;
  bool _initialized = false;

  /// 웹 전용 VAPID 공개키. `flutterfire configure` 는 이 값을 자동 설정하지
  /// 않으므로 수동으로 주입해야 한다. Firebase Console → 프로젝트 설정 →
  /// Cloud Messaging → "Web configuration" 에서 생성한 Key pair.
  /// 비어 있으면 Flutter Web 에서 토큰 발급이 실패하므로 PUSH 가 비활성화된다.
  static const String webVapidKey = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: '',
  );

  /// 한 번만 초기화. 이미 초기화되어 있으면 no-op.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 권한 요청 — iOS 는 반드시 필요, Android 13+ 도 필요, Web 도 브라우저 권한.
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[push] permission denied');
      return;
    }

    // Android 포그라운드 채널 + 로컬 알림 초기화 (모바일 한정).
    if (!kIsWeb) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      // Android 채널.
      if (Platform.isAndroid) {
        const channel = AndroidNotificationChannel(
          'default_channel',
          '일반 알림',
          description: '제안/댓글/이야기 등록 등 앱 알림',
          importance: Importance.high,
        );
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
      }
    }

    // 토큰 발급.
    try {
      _currentToken = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && webVapidKey.isNotEmpty ? webVapidKey : null,
      );
      debugPrint('[push] token: $_currentToken');
    } catch (e) {
      debugPrint('[push] token fetch failed: $e');
    }

    // 토큰 갱신 이벤트.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      _currentToken = newToken;
      await registerCurrentTokenIfAuthenticated();
    });

    // 포그라운드 메시지 수신 → 로컬 알림으로 재발행 (모바일만).
    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      if (notification == null) return;
      if (kIsWeb) return; // 웹은 브라우저가 자체 처리.
      await _localNotifications.show(
        message.hashCode,
        notification.title ?? '알림',
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            '일반 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: message.data['deep_link'] as String?,
      );
    });
  }

  /// 현재 유저에 연결된 디바이스로 FCM 토큰을 upsert. 로그인 상태에서만 유효.
  Future<void> registerCurrentTokenIfAuthenticated() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final token = _currentToken;
    if (token == null || token.isEmpty) return;

    await client.rpc(
      'register_push_token',
      params: {
        'p_token': token,
        'p_platform': _platformWire(),
        'p_device_label': null,
      },
    );
  }

  /// 로그아웃 시 호출 — 현재 디바이스 토큰을 서버에서 삭제.
  Future<void> unregisterCurrentToken() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    final client = Supabase.instance.client;
    try {
      await client.rpc('unregister_push_token', params: {'p_token': token});
    } catch (_) {
      // 네트워크 오류는 무시 (로그아웃 UX 저해 방지)
    }
  }

  String _platformWire() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'web'; // 데스크탑 등은 웹으로 fallback
  }
}
