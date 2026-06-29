import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';

class AuthRepository {
  const AuthRepository(this._client);

  /// 모바일 앱의 deep link URL.
  /// iOS Info.plist / Android intent-filter 에 등록되어 있어야 Supabase 가
  /// OAuth 완료 후 앱으로 돌려보낸다.
  static const String oauthRedirectUrl = 'com.storybible.app://login-callback';

  /// 플랫폼별 OAuth redirectTo 값.
  ///
  /// - 모바일: [oauthRedirectUrl] deep link (앱으로 복귀)
  /// - 웹: 현재 페이지 origin (예: http://localhost:5050)
  ///   브라우저가 처리 가능한 http(s) URL 이어야 한다. Supabase 대시보드
  ///   Authentication → URL Configuration 의 Redirect URLs 에 해당 origin
  ///   (또는 와일드카드)이 등록되어 있어야 한다.
  static String get _oauthRedirectForPlatform {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return oauthRedirectUrl;
  }

  final SupabaseClient _client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<String?> signInWithApple() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      throw const AuthException('애플 로그인은 Apple 기기 앱에서만 사용할 수 있습니다.');
    }

    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('애플 로그인 토큰을 가져오지 못했습니다.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    final givenName = credential.givenName?.trim();
    final familyName = credential.familyName?.trim();
    final fullName = [
      familyName,
      givenName,
    ].whereType<String>().where((value) => value.isNotEmpty).join();
    return fullName.isEmpty ? null : fullName;
  }

  Future<void> signInWithGoogle() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _signInWithNativeGoogleOnAndroid();
      return;
    }
    await _signInWithOAuth(
      OAuthProvider.google,
      failureLabel: '구글',
      queryParams: googleAccountChooserQueryParams(),
    );
  }

  Future<void> _signInWithNativeGoogleOnAndroid() async {
    final googleSignIn = GoogleSignIn(scopes: const ['email', 'profile']);

    try {
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) {
        return;
      }

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('구글 로그인 토큰을 가져오지 못했습니다.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authentication.accessToken,
      );
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) {
        return;
      }
      if (_isGoogleDeveloperError(error)) {
        throw const AuthException(
          '구글 로그인 설정을 확인해야 합니다. Firebase/Google Cloud의 Android OAuth '
          'client에 com.storybible.app 패키지와 현재 서명 인증서 SHA-1/SHA-256을 '
          '등록한 뒤 google-services.json을 다시 내려받아 주세요.',
        );
      }
      throw AuthException(error.message ?? '구글 로그인에 실패했습니다.');
    }
  }

  Future<void> signInWithKakao() async {
    await _signInWithOAuth(OAuthProvider.kakao, failureLabel: '카카오');
  }

  Future<void> _signInWithOAuth(
    OAuthProvider provider, {
    required String failureLabel,
    Map<String, String>? queryParams,
  }) async {
    final launched = await _client.auth.signInWithOAuth(
      provider,
      redirectTo: _oauthRedirectForPlatform,
      queryParams: queryParams,
      // authScreenLaunchMode 는 모바일 전용. 웹에서는 current tab 리다이렉트를
      // 써야 SetSID → Supabase callback 체인이 정상 동작한다.
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.inAppBrowserView,
    );

    if (!launched) {
      throw AuthException('$failureLabel 로그인 화면을 열지 못했습니다.');
    }
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  Future<void> deleteCurrentAccount({required String confirmationId}) async {
    final response = await _client.functions.invoke(
      'delete-account',
      body: {'confirmationId': confirmationId.trim()},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'HTTP ${response.status}';
      throw AuthException('계정 삭제에 실패했습니다: $msg');
    }

    try {
      await _client.auth.signOut();
    } catch (_) {
      // Auth row has already been deleted; local session cleanup failure should
      // not surface as a failed deletion.
    }
  }
}

@visibleForTesting
Map<String, String> googleAccountChooserQueryParams() {
  return const {'prompt': 'select_account'};
}

bool _isGoogleDeveloperError(PlatformException error) {
  final detailText = [
    error.code,
    error.message,
    error.details,
  ].whereType<Object>().join(' ');
  return detailText.contains('ApiException: 10') ||
      detailText.contains('DEVELOPER_ERROR') ||
      detailText.contains('developer_error');
}

String accountDeletionConfirmationId({
  required User user,
  AppUserProfile? profile,
}) {
  final email = _cleanNullableText(user.email);
  if (email != null) {
    return email;
  }
  final shareId = _cleanNullableText(profile?.shareId);
  if (shareId != null) {
    return shareId;
  }
  return user.id;
}

bool accountDeletionConfirmationMatches({
  required String input,
  required String expected,
}) {
  return _normalizeConfirmation(input) == _normalizeConfirmation(expected);
}

String _normalizeConfirmation(String value) => value.trim().toLowerCase();

String? _cleanNullableText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
