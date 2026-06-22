import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class AuthRepository {
  const AuthRepository(this._client);

  static const String _googleWebClientId =
      '196457947669-f2hcqoqmc9v4bdtchuvee5l9fiqt26ka.apps.googleusercontent.com';

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
      final googleSignIn = GoogleSignIn(
        serverClientId: _googleWebClientId,
        scopes: const ['email', 'profile', 'openid'],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('구글 로그인이 취소되었습니다.');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('구글 ID 토큰을 가져오지 못했습니다.');
      }
      if (accessToken == null || accessToken.isEmpty) {
        throw const AuthException('구글 액세스 토큰을 가져오지 못했습니다.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return;
    }

    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectForPlatform,
      // authScreenLaunchMode 는 모바일 전용. 웹에서는 current tab 리다이렉트를
      // 써야 SetSID → Supabase callback 체인이 정상 동작한다.
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );

    if (!launched) {
      throw const AuthException('구글 로그인 화면을 열지 못했습니다.');
    }
  }

  Future<void> signInWithKakao() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.kakao,
      redirectTo: _oauthRedirectForPlatform,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );

    if (!launched) {
      throw const AuthException('카카오 로그인 화면을 열지 못했습니다.');
    }
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
