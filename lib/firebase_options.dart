// Placeholder — `flutterfire configure` 가 자동으로 이 파일을 덮어쓴다.
//
// 설정 절차 (docs/PUSH_SETUP.md 참조):
//   1. Firebase Console 에서 프로젝트 생성 + iOS/Android/Web 앱 등록
//   2. `dart pub global activate flutterfire_cli`
//   3. `flutterfire configure` → 이 파일 + 플랫폼 구성 파일 자동 생성
//
// 현재 파일이 placeholder 상태면 Firebase.initializeApp() 이 런타임에 실패한다.
// lib/main.dart 에서 try-catch 로 감싸 전체 앱이 멈추지는 않지만,
// 푸시 알림은 활성화되지 않는다.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnimplementedError(
      'Firebase 가 아직 설정되지 않았습니다. '
      '`flutterfire configure` 를 실행해 이 파일을 덮어쓰세요. '
      '자세한 절차는 docs/PUSH_SETUP.md 참조.',
    );
  }
}
