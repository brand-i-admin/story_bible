import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  const AuthRepository(this._client);

  static const String oauthRedirectUrl = 'com.storybible.app://login-callback';

  final SupabaseClient _client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<String?> signInWithApple() async {
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
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );

    if (!launched) {
      throw const AuthException('구글 로그인 화면을 열지 못했습니다.');
    }
  }

  Future<void> signInWithKakao() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.kakao,
      redirectTo: oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );

    if (!launched) {
      throw const AuthException('카카오 로그인 화면을 열지 못했습니다.');
    }
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
