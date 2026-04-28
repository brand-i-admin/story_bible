/// 비-웹 플랫폼용 stub — conditional import 경로.
///
/// `push_service.dart` 가
/// ```
/// import 'web_notification_stub.dart'
///   if (dart.library.js_interop) 'web_notification_web.dart';
/// ```
/// 형태로 import 하면, 모바일/데스크탑 빌드 시 이 파일이 선택돼 no-op 로 동작.
/// Web 빌드에서는 `web_notification_web.dart` 가 선택돼 실제 브라우저
/// `Notification` API 를 호출한다.
void showWebNotification(String title, {String? body, String? icon}) {
  // 웹이 아닌 플랫폼에서는 아무것도 하지 않음 — flutter_local_notifications 가
  // 대신 처리한다 (push_service 에서 kIsWeb 분기로 호출 방지).
}
