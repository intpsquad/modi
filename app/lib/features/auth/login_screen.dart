import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design/modi_wordmark.dart';
import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import 'auth_service.dart';

const _socialLoginButtonHeight = 52.0;
const _socialLoginIconSize = 20.0;
const _socialLoginLabelFontSize = 16.0;
const _socialLoginLabelFontWeight = FontWeight.w600;

/// S-02 로그인 — 소셜 로그인 선택 화면.
/// 로그인 성공 후 방 소속 상태(appSession)를 갱신하면 라우터 redirect가 S-03(게이트) 또는
/// 홈으로 자동 이동시킨다(app_router.dart). Kakao·Google·Apple은 실제 인증을 제공한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthService _authService;

  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await _authService.signInWithGoogle();
      await appSession.refreshMembership();
    } catch (e) {
      debugPrint('로그인 실패: $e');
      if (mounted) {
        setState(() => _errorText = '로그인에 실패했어요. 다시 시도해 주세요');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleKakaoSignIn() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await _authService.signInWithKakao();
      await appSession.refreshMembership();
    } catch (e) {
      debugPrint('카카오 로그인 실패: $e');
      if (mounted) {
        setState(() => _errorText = '카카오 로그인에 실패했어요. 다시 시도해 주세요');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await _authService.signInWithApple();
      await appSession.refreshMembership();
    } catch (e) {
      // 🔴 예외를 삼키지 않는다. 여기가 `catch (_)` 였던 탓에 배포 빌드의 Apple 로그인이
      // 왜 죽는지 알 수 없었고(2026-08-15), 서버 로그와 IPA 서명까지 해부하고서야
      // entitlements 누락이라는 것을 찾았다. 구글·카카오와 같은 모양으로 맞춘다.
      debugPrint('Apple 로그인 실패: $e');
      if (mounted) {
        setState(() => _errorText = 'Apple 로그인에 실패했어요. 다시 시도해 주세요');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEmailLogin() {
    context.push('/onboarding/login/email');
  }

  void _openSignUp() {
    context.push('/onboarding/signup');
  }

  @override
  Widget build(BuildContext context) {
    // 두 번째 소셜 버튼은 플랫폼별 — iOS는 애플, 그 외(안드로이드)는 구글.
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: (constraints.maxHeight * 0.25)
                              .clamp(96.0, 220.0)
                              .toDouble(),
                        ),
                        Semantics(
                          label: 'MODI 로고',
                          container: true,
                          child: _ModiLogo(),
                        ),
                        const SizedBox(height: 44),
                        _SocialLoginButton(
                          label: '카카오로 계속하기',
                          backgroundColor: AppColors.kakao,
                          foregroundColor: AppColors.kakaoText,
                          labelColor: AppColors.kakaoLabel,
                          icon: SvgPicture.asset(
                            'assets/icons/kakao_login_symbol.svg',
                            key: const ValueKey('kakao-login-symbol'),
                            width: _socialLoginIconSize,
                            height: _socialLoginIconSize,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                          onPressed: _loading ? null : _handleKakaoSignIn,
                        ),
                        const SizedBox(height: 8),
                        if (isIOS)
                          _SocialLoginButton(
                            label: 'Apple로 계속하기',
                            backgroundColor: AppColors.apple,
                            foregroundColor: AppColors.appleText,
                            icon: SvgPicture.asset(
                              'assets/icons/apple_login_symbol.svg',
                              key: const ValueKey('apple-login-symbol'),
                              height: _socialLoginIconSize,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                            ),
                            onPressed: _loading ? null : _handleAppleSignIn,
                          )
                        else
                          _SocialLoginButton(
                            label: 'Google로 계속하기',
                            backgroundColor: AppColors.surfaceStrong,
                            foregroundColor: AppColors.foreground,
                            icon: SvgPicture.asset(
                              'assets/icons/google_login_symbol.svg',
                              key: const ValueKey('google-login-symbol'),
                              width: _socialLoginIconSize,
                              height: _socialLoginIconSize,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                            ),
                            onPressed: _loading ? null : _handleGoogleSignIn,
                          ),
                        const SizedBox(height: 62),
                        Semantics(
                          label: '또는',
                          container: true,
                          child: _SectionDivider(label: '또는'),
                        ),
                        const SizedBox(height: 16),
                        _SocialLoginButton(
                          label: '이메일로 로그인',
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.foreground,
                          borderColor: AppColors.border,
                          icon: const Icon(
                            Icons.mail_outline,
                            key: ValueKey('email-login-symbol'),
                            size: _socialLoginIconSize,
                          ),
                          onPressed: _loading ? null : _openEmailLogin,
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.accentDanger,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 40),
                        _SignUpPrompt(onPressed: _openSignUp),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_loading)
            Positioned.fill(
              child: Stack(
                key: const ValueKey('login-loading-overlay'),
                children: [
                  ModalBarrier(
                    dismissible: false,
                    color: AppColors.foreground.withValues(alpha: 0.18),
                  ),
                  Center(
                    child: Semantics(
                      label: '로그인 중',
                      liveRegion: true,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModiLogo extends StatelessWidget {
  const _ModiLogo();

  @override
  Widget build(BuildContext context) {
    return const ModiWordmark(height: 30);
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.icon,
    this.labelColor,
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget? icon;
  final Color? labelColor;
  final Color? borderColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final resolvedLabelColor = labelColor ?? foregroundColor;
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size.fromHeight(_socialLoginButtonHeight),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return backgroundColor.withValues(alpha: 0.55);
        }
        return backgroundColor;
      }),
      foregroundColor: WidgetStatePropertyAll(foregroundColor),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          inherit: false,
          fontSize: _socialLoginLabelFontSize,
          fontWeight: _socialLoginLabelFontWeight,
          height: 1,
          color: resolvedLabelColor,
        ),
      ),
    );

    // 아이콘과 텍스트를 한 묶음으로 가운데 정렬(레퍼런스). 아이콘 시각 크기는 24로
    // 정규화되어 들어온다(구글은 OverflowBox로 배치 폭 24).
    return SizedBox(
      width: double.infinity,
      height: _socialLoginButtonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: foregroundColor,
                  size: _socialLoginIconSize,
                ),
                child: icon!,
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  inherit: false,
                  fontSize: _socialLoginLabelFontSize,
                  fontWeight: _socialLoginLabelFontWeight,
                  height: 1,
                  color: resolvedLabelColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignUpPrompt extends StatelessWidget {
  const _SignUpPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('계정이 없으신가요?', style: AppTypography.bodySmall),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.foreground,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
          ),
          child: const Text('회원가입'),
        ),
      ],
    );
  }
}
