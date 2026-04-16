import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../data/auth_repository.dart';
import '../state/auth_providers.dart';
import '../widgets/parchment_page_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    });
  }

  Future<void> _handleAppleSignIn() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final nicknameHint = await ref
          .read(authRepositoryProvider)
          .signInWithApple();
      final user = ref.read(signedInUserProvider);
      if (user != null) {
        await ref
            .read(userRepositoryProvider)
            .ensureSignedInUser(user, nicknameHint: nicknameHint);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildAppleSignInErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _handleKakaoSignIn() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithKakao();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildKakaoSignInErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildGoogleSignInErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _buildAppleSignInErrorMessage(Object error) {
    if (error is SignInWithAppleAuthorizationException &&
        error.code == AuthorizationErrorCode.canceled) {
      return '애플 로그인 창이 시스템에서 취소되었습니다.\n'
          '지금처럼 비밀번호를 넣은 뒤 바로 이 메시지가 뜨면, 보통 시뮬레이터 Apple ID 세션이 불안정하거나 '
          '앱의 iOS 번들 ID와 Apple/Supabase 설정이 아직 맞지 않은 경우입니다.\n'
          '현재 프로젝트 번들 ID가 placeholder 상태라면 실제 App ID로 바꾸고, '
          'Apple Developer의 Sign in with Apple과 Supabase Apple provider를 같은 값으로 맞춰야 합니다.\n'
          '가능하면 실기기에서 먼저 확인해 주세요.';
    }

    return '애플 로그인에 실패했습니다.\n$error';
  }

  String _buildKakaoSignInErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('Unable to exchange external code')) {
      return '카카오 인증창까지는 정상적으로 다녀왔지만, '
          'Supabase가 카카오 인가 코드를 세션으로 바꾸는 단계에서 실패했습니다.\n'
          '보통 아래 설정 중 하나가 맞지 않을 때 발생합니다.\n'
          '1. Supabase Kakao Client ID에 REST API 키가 아닌 다른 키를 넣은 경우\n'
          '2. Kakao Client Secret이 켜져 있는데 Supabase에 같은 secret을 넣지 않은 경우\n'
          '3. Kakao Redirect URI가 https://cvnutbizsgeycdjcbled.supabase.co/auth/v1/callback 와 다를 경우\n'
          '4. account_email 동의를 쓰지 않는데 Supabase에서 Allow users without an email 이 꺼져 있는 경우';
    }

    return '카카오 로그인에 실패했습니다.\n'
        '$message\n'
        'Supabase Authentication 설정의 Additional Redirect URLs에 '
        '${AuthRepository.oauthRedirectUrl} 를 추가했는지도 확인해 주세요.';
  }

  String _buildGoogleSignInErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('Unable to exchange external code')) {
      return '구글 로그인 화면까지는 정상적으로 다녀왔지만, '
          'Supabase가 Google 인가 코드를 세션으로 바꾸는 단계에서 실패했습니다.\n'
          '보통 아래 설정 중 하나가 맞지 않을 때 발생합니다.\n'
          '1. Google Auth Platform에서 Web application OAuth client를 만들지 않은 경우\n'
          '2. Authorized redirect URIs에 Supabase Google callback URL을 넣지 않은 경우\n'
          '3. Supabase Authentication > Providers > Google에 Client ID/Secret을 넣지 않은 경우\n'
          '4. Supabase URL Configuration의 Additional Redirect URLs에 '
          '${AuthRepository.oauthRedirectUrl} 를 넣지 않은 경우';
    }

    return '구글 로그인에 실패했습니다.\n'
        '$message\n'
        'Supabase URL Configuration의 Additional Redirect URLs에 '
        '${AuthRepository.oauthRedirectUrl} 를 넣었는지도 확인해 주세요.';
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentPageScaffold(
      title: 'Story Bible',
      showBackButton: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ParchmentCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '로그인',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF4A331D),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '프로필, 노트, 저장한 말씀, 공부 기록을\n내 계정에 안전하게 저장하려면 로그인이 필요합니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6D5231),
                            fontSize: 14,
                            height: 1.55,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Opacity(
                          opacity: _submitting ? 0.72 : 1,
                          child: IgnorePointer(
                            ignoring: _submitting,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 50,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFFEE500),
                                      foregroundColor: const Color(0xFF2A1B00),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    onPressed: _handleKakaoSignIn,
                                    child: const Text('카카오로 계속하기'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 50,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF2E2A24),
                                      side: const BorderSide(
                                        color: Color(0xFFCCB79D),
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    onPressed: _handleGoogleSignIn,
                                    child: const Text('Google로 계속하기'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FutureBuilder<bool>(
                                  future: SignInWithApple.isAvailable(),
                                  builder: (context, snapshot) {
                                    final isAvailable = snapshot.data ?? false;
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                          ),
                                        ),
                                      );
                                    }
                                    if (!isAvailable) {
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0x19A63F2D),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: const Color(0x44A63F2D),
                                            width: 1.1,
                                          ),
                                        ),
                                        child: const Text(
                                          '이 기기에서는 애플 로그인을 사용할 수 없습니다.\nApple ID가 설정된 iPhone/iPad 또는 macOS에서 다시 시도해 주세요.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Color(0xFFA63F2D),
                                            fontWeight: FontWeight.w800,
                                            height: 1.5,
                                          ),
                                        ),
                                      );
                                    }
                                    return SizedBox(
                                      height: 48,
                                      child: SignInWithAppleButton(
                                        onPressed: _handleAppleSignIn,
                                        style: SignInWithAppleButtonStyle.black,
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(14),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_submitting) ...[
                          const SizedBox(height: 14),
                          const Center(
                            child: Text(
                              '로그인 중...',
                              style: TextStyle(
                                color: Color(0xFF6D5231),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFA63F2D),
                              fontWeight: FontWeight.w800,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
