import 'package:web/web.dart' as web;

/// Flutter Web 전용 — 브라우저 `Notification` API 로 인앱 토스트 알림 발행.
///
/// FCM 은 탭이 포그라운드(visibilityState=visible)일 때 `onBackgroundMessage`
/// 를 호출하지 않아 Service Worker 가 `showNotification` 을 못 띄운다. 대신
/// `FirebaseMessaging.onMessage` 만 fire 되므로 그 시점에 이 함수를 호출해
/// 직접 알림을 표시한다.
///
/// 권한이 `granted` 가 아니면 조용히 무시. 예외가 나도 삼켜 앱 동작에 영향 없음.
void showWebNotification(String title, {String? body, String? icon}) {
  try {
    if (web.Notification.permission != 'granted') return;
    final options = web.NotificationOptions(body: body ?? '', icon: icon ?? '');
    web.Notification(title, options);
  } catch (_) {
    // Notification API 미지원 브라우저나 사파리 구버전 — 조용히 skip.
  }
}
