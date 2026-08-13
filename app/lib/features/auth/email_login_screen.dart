import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import 'auth_service.dart';

/// S-02 이메일 로그인 — 자체가입 계정의 이메일·비밀번호 로그인.
/// 로그인 성공 후 appSession을 갱신하면 라우터 redirect가 방 게이트/홈으로 이동시킨다.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  late final AuthService _authService;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _errorText;

  // 이메일·비밀번호가 모두 채워져야 로그인 버튼이 활성 — 빈 필수값은 에러 문구 대신
  // 비활성 버튼으로 알린다(빈 필드에 "입력해 주세요" 문구를 띄우지 않는다).
  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorText = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await _authService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await appSession.refreshMembership();
    } catch (e) {
      debugPrint('이메일 로그인 실패: $e');
      if (mounted) setState(() => _errorText = _mapError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => '이메일 형식이 올바르지 않아요',
        'user-disabled' => '사용할 수 없는 계정이에요',
        'too-many-requests' => '잠시 후 다시 시도해 주세요',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => '이메일 또는 비밀번호가 올바르지 않아요',
        _ => '로그인에 실패했어요. 다시 시도해 주세요',
      };
    }
    return '로그인에 실패했어요. 다시 시도해 주세요';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('이메일로 로그인')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.content),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('email-login-email-field'),
                  controller: _emailController,
                  enabled: !_loading,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    hintText: 'example@modi.app',
                  ),
                  validator: (value) {
                    // 빈 값은 에러로 띄우지 않는다(로그인 버튼이 비활성) — 형식 오류만 안내.
                    final email = value?.trim() ?? '';
                    if (email.isNotEmpty &&
                        (!email.contains('@') || !email.contains('.'))) {
                      return '이메일 형식이 올바르지 않아요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.cardGap),
                TextFormField(
                  key: const ValueKey('email-login-password-field'),
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: '비밀번호'),
                  onFieldSubmitted: (_) =>
                      (_loading || !_canSubmit) ? null : _submit(),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: AppSpacing.cardGap),
                  Text(
                    _errorText!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.accentDanger,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.content),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_loading || !_canSubmit) ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('로그인'),
                  ),
                ),
                const SizedBox(height: AppSpacing.content),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('계정이 없으신가요?', style: AppTypography.bodySmall),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => context.push('/onboarding/signup'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.foreground,
                        textStyle: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
