import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OAuth deep link platform configuration', () {
    test('iOS delegates OAuth callbacks to the app_links plugin only', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final normalizedInfoPlist = infoPlist.replaceAll(RegExp(r'\s+'), ' ');
      const flutterDeepLinkingDisabled =
          '<key>FlutterDeepLinkingEnabled</key> <false/>';

      expect(
        normalizedInfoPlist,
        contains('<string>com.storybible.app</string>'),
        reason: 'The OAuth callback scheme must remain registered on iOS.',
      );
      expect(
        normalizedInfoPlist,
        contains(flutterDeepLinkingDisabled),
        reason:
            'Flutter navigation must not also consume callbacks handled by '
            'Supabase app_links.',
      );
    });

    test('Android delegates OAuth callbacks to the app_links plugin only', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final normalizedManifest = manifest.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        normalizedManifest,
        contains(
          'android:scheme="com.storybible.app" '
          'android:host="login-callback"',
        ),
        reason: 'The OAuth callback intent filter must remain registered.',
      );
      expect(
        normalizedManifest,
        contains(
          'android:name="flutter_deeplinking_enabled" '
          'android:value="false"',
        ),
        reason:
            'Flutter navigation must not also consume callbacks handled by '
            'Supabase app_links.',
      );
    });
  });
}
