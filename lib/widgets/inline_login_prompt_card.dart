import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_providers.dart';
import '../theme/tokens.dart';
import 'story_home_styles.dart';

/// 로그인이 필요한 영역에 인라인으로 표시되는 소셜 로그인 카드.
///
/// 로그인이 성공하면 [onSignedIn] 콜백이 호출된다.
class InlineLoginPromptCard extends ConsumerStatefulWidget {
  const InlineLoginPromptCard({
    super.key,
    required this.title,
    required this.description,
    required this.onSignedIn,
  });

  final String title;
  final String description;
  final Future<void> Function() onSignedIn;

  @override
  ConsumerState<InlineLoginPromptCard> createState() =>
      _InlineLoginPromptCardState();
}

class _InlineLoginPromptCardState extends ConsumerState<InlineLoginPromptCard> {
  bool _submitting = false;
  String? _error;

  bool get _showAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _finishSignedIn({String? nicknameHint}) async {
    final authRepo = ref.read(authRepositoryProvider);
    final user = authRepo.currentUser ?? ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }
    await ref
        .read(userRepositoryProvider)
        .ensureSignedInUser(user, nicknameHint: nicknameHint);
    await widget.onSignedIn();
  }

  Future<void> _handleAppleSignIn() async {
    await _runSocialAuthAction(() async {
      return ref.read(authRepositoryProvider).signInWithApple();
    }, failureLabel: '애플 로그인');
  }

  Future<void> _handleKakaoSignIn() async {
    await _runSocialAuthAction(() async {
      await ref.read(authRepositoryProvider).signInWithKakao();
      return null;
    }, failureLabel: '카카오 로그인');
  }

  Future<void> _handleGoogleSignIn() async {
    await _runSocialAuthAction(() async {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      return null;
    }, failureLabel: '구글 로그인');
  }

  Future<void> _runSocialAuthAction(
    Future<String?> Function() action, {
    required String failureLabel,
  }) async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final nicknameHint = await action();
      await _finishSignedIn(nicknameHint: nicknameHint);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$failureLabel에 실패했습니다.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        decoration: modalSurfaceDecoration(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Opacity(
          opacity: _submitting ? 0.78 : 1,
          child: IgnorePointer(
            ignoring: _submitting,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink500,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6D5231),
                    fontSize: 11.8,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF2A1B00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    onPressed: _handleKakaoSignIn,
                    child: const Text('카카오로 로그인'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2E2A24),
                      side: const BorderSide(
                        color: Color(0xFFCCB79D),
                        width: 1.1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    onPressed: _handleGoogleSignIn,
                    child: const Text('Google로 로그인'),
                  ),
                ),
                if (_showAppleSignIn) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF161616),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      onPressed: _handleAppleSignIn,
                      child: const Text('Apple로 로그인'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFA63F2D),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.38,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
