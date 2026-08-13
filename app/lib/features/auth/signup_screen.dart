import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import 'auth_service.dart';

/// 회원가입 4단계. 스텝 인디케이터(3바)는 이메일인증(email+code)=1 / 비밀번호=2 / 프로필=3으로 묶는다.
enum _SignupStep { email, code, password, profile }

/// 프로필 이미지 피커 — 테스트에서 가짜를 주입할 수 있게 분리(기본은 image_picker).
typedef SignupImagePick = Future<XFile?> Function(ImageSource source);

/// 비밀번호 규칙 — 영문+숫자+특수문자 조합 8자 이상. 버튼 활성 게터와 폼 validator가 공유한다.
bool _isValidPassword(String p) =>
    p.length >= 8 &&
    RegExp(r'[A-Za-z]').hasMatch(p) &&
    RegExp(r'[0-9]').hasMatch(p) &&
    RegExp(r'[^A-Za-z0-9]').hasMatch(p);

/// 닉네임 규칙 — 한글/영문/숫자 2~8자. 게터와 validator 공유.
bool _isValidNickname(String n) => RegExp(r'^[가-힣a-zA-Z0-9]{2,8}$').hasMatch(n);

/// 이메일 규칙 — TLD(마지막 점 뒤)는 2글자 이상이라야 한다(`gmail.c`는 무효, `gmail.com`은 유효).
bool _isValidEmail(String e) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(e);

/// S-02-A 자체가입 폼 — 이메일 → 인증코드 → 비밀번호 → 프로필.
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.authService,
    this.onCompleted,
    this.pickImage,
  });

  final AuthService? authService;

  /// 위젯 테스트에서 가입 완료 후 라우팅을 대체하기 위한 선택적 훅.
  final Future<void> Function()? onCompleted;

  /// 프로필 이미지 피커(테스트 주입용). null이면 image_picker 실사용.
  final SignupImagePick? pickImage;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final AuthService _authService;

  _SignupStep _step = _SignupStep.email;
  bool _loading = false;
  String? _error;

  // Step 1 — 이메일
  final _emailController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();

  // Step 2 — 인증코드
  final _codeController = TextEditingController();
  Timer? _codeTimer;
  int _codeTimerRemaining = 60; // 재전송 쿨다운 60초(서버 쿨다운과 동일)

  // Step 3 — 비밀번호
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  // Step 4 — 프로필
  final _nicknameController = TextEditingController();
  final _profileFormKey = GlobalKey<FormState>();
  XFile? _profileImage;
  bool _agreedToTerms = false;
  bool _agreedToPrivacy = false;

  static Future<XFile?> _defaultPick(ImageSource source) =>
      ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 800);

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _codeTimer?.cancel();
    super.dispose();
  }

  void _startCodeTimer() {
    _codeTimer?.cancel();
    // 재전송 쿨다운 60초 — 카운트다운이 끝나면 재전송 버튼이 활성된다(서버 쿨다운 60초와 동일).
    _codeTimerRemaining = 60;
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_codeTimerRemaining <= 0) {
        _codeTimer?.cancel();
        return;
      }
      setState(() => _codeTimerRemaining--);
    });
  }

  bool get _emailValid => _isValidEmail(_emailController.text.trim());

  bool get _passwordStepValid =>
      _isValidPassword(_passwordController.text) &&
      _passwordConfirmController.text == _passwordController.text;

  bool get _nicknameValid => _isValidNickname(_nicknameController.text.trim());

  /// 스텝 인디케이터(3바) 매핑 — 이메일인증(email+code)=0, 비밀번호=1, 프로필=2.
  int get _indicatorStep => switch (_step) {
    _SignupStep.email => 0,
    _SignupStep.code => 0,
    _SignupStep.password => 1,
    _SignupStep.profile => 2,
  };

  void _back() {
    setState(() => _error = null);
    switch (_step) {
      case _SignupStep.email:
        if (mounted) context.pop();
      case _SignupStep.code:
        setState(() => _step = _SignupStep.email);
      case _SignupStep.password:
        setState(() => _step = _SignupStep.code);
      case _SignupStep.profile:
        setState(() => _step = _SignupStep.password);
    }
  }

  void _goToProfile() {
    FocusScope.of(context).unfocus();
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _step = _SignupStep.profile;
      _error = null;
    });
  }

  Future<void> _pickProfileImage() async {
    final pick = widget.pickImage ?? _defaultPick;
    try {
      final picked = await pick(ImageSource.gallery);
      if (picked != null && mounted) {
        setState(() => _profileImage = picked);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미지를 불러오지 못했어요')));
      }
    }
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      await _authService.sendEmailVerificationCode(
        _emailController.text.trim(),
      );
    } catch (e) {
      error = _extractMessage(e);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _step = _SignupStep.code;
      }
    });
    if (error == null) _startCodeTimer();
  }

  Future<void> _resendCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      await _authService.sendEmailVerificationCode(
        _emailController.text.trim(),
      );
    } catch (e) {
      error = _extractMessage(e);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (error != null) _error = error;
    });
    if (error == null) _startCodeTimer();
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '인증코드를 입력해 주세요');
      return;
    }
    if (code.length < 6) {
      setState(() => _error = '6자리를 모두 입력해 주세요');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      await _authService.verifyEmailCode(_emailController.text.trim(), code);
    } catch (e) {
      error = _extractMessage(e);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _step = _SignupStep.password;
      }
    });
  }

  /// 약관 보기 — 별도 약관·정책 페이지(/legal)로 이동한다.
  /// 개인정보 관련 항목이면 개인정보 처리방침 탭으로 연다.
  void _openLegal(String title) {
    final isPrivacy = title.contains('개인정보');
    context.push(isPrivacy ? '/legal?doc=privacy' : '/legal');
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        nickname: _nicknameController.text.trim(),
        password: _passwordController.text,
      );
      if (widget.onCompleted != null) {
        await widget.onCompleted!();
        return;
      }
      await appSession.refreshMembership();
      if (mounted) context.go('/onboarding/room-setup');
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractMessage(Object e) {
    if (e is StateError) return e.message;
    return '잠시 후 다시 시도해 주세요';
  }

  String _messageFor(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'email-already-in-use' => '이미 가입된 이메일이에요. 다른 이메일을 사용해 주세요',
        'invalid-email' => '이메일 형식이 올바르지 않아요',
        'weak-password' => '비밀번호가 보안 기준에 맞지 않아요',
        'network-request-failed' => '네트워크를 확인하고 다시 시도해 주세요',
        _ => '회원가입에 실패했어요. 다시 시도해 주세요',
      };
    }
    return _extractMessage(e);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _SignupStep.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: '뒤로 가기',
            onPressed: _loading ? null : _back,
            // 뒤로가기는 앱 전역 `<`(chevron) — theme.dart actionIconTheme와 같은 모양.
            icon: const Icon(
              Icons.chevron_left,
              size: 28,
              color: AppColors.foreground,
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.content,
              ),
              child: _StepIndicator(totalSteps: 3, currentStep: _indicatorStep),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: IndexedStack(
                  index: _step.index,
                  children: [
                    _EmailStep(
                      key: const ValueKey('step-email'),
                      controller: _emailController,
                      formKey: _emailFormKey,
                      loading: _loading,
                      error: _error,
                      emailValid: _emailValid,
                      onEmailChanged: () => setState(() {}),
                      onSendCode: _sendCode,
                      agreedToTerms: _agreedToTerms,
                      agreedToPrivacy: _agreedToPrivacy,
                      onTermsChanged: (v) => setState(() => _agreedToTerms = v),
                      onPrivacyChanged: (v) =>
                          setState(() => _agreedToPrivacy = v),
                      onViewTerms: _openLegal,
                    ),
                    _CodeStep(
                      key: const ValueKey('step-code'),
                      email: _emailController.text.trim(),
                      controller: _codeController,
                      loading: _loading,
                      error: _error,
                      timerRemaining: _codeTimerRemaining,
                      onVerify: _verifyCode,
                      onResend: _resendCode,
                    ),
                    _PasswordStep(
                      key: const ValueKey('step-password'),
                      passwordController: _passwordController,
                      passwordConfirmController: _passwordConfirmController,
                      formKey: _passwordFormKey,
                      loading: _loading,
                      onChanged: () => setState(() {}),
                      onNext: (_passwordStepValid && !_loading)
                          ? _goToProfile
                          : null,
                    ),
                    _ProfileStep(
                      key: const ValueKey('step-profile'),
                      nicknameController: _nicknameController,
                      formKey: _profileFormKey,
                      loading: _loading,
                      error: _error,
                      profileImage: _profileImage,
                      onPickImage: _loading ? null : _pickProfileImage,
                      onNicknameChanged: () => setState(() {}),
                      // 약관은 이메일 단계에서 이미 동의받았다 — 최종 게이트는 닉네임만.
                      onSubmit: (_nicknameValid && !_loading) ? _submit : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 위젯들 ──────────────────────────────────────────────────────────────

/// 회원가입 단계 세그먼트 바 — specs/design.md §6. 3등분 균등폭(브리핑 고정 114px은
/// 좁은 화면에서 넘쳐 반응형으로), 높이 6·라운드 5·간격 3. 현재 단계까지 primary로 채움.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.totalSteps, required this.currentStep});

  final int totalSteps;

  /// 0-based 현재 단계 인덱스. 0..currentStep 세그먼트가 활성.
  final int currentStep;

  static const double _height = 6;
  static const double _radius = 5;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '회원가입 진행 단계',
      value: '총 $totalSteps단계 중 ${currentStep + 1}단계',
      child: Row(
        children: [
          for (var i = 0; i < totalSteps; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(
              child: Container(
                height: _height,
                decoration: BoxDecoration(
                  color: i <= currentStep
                      ? AppColors.primary
                      : AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(_radius),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    super.key,
    required this.controller,
    required this.formKey,
    required this.loading,
    required this.error,
    required this.emailValid,
    required this.onEmailChanged,
    required this.onSendCode,
    required this.agreedToTerms,
    required this.agreedToPrivacy,
    required this.onTermsChanged,
    required this.onPrivacyChanged,
    required this.onViewTerms,
  });

  final TextEditingController controller;
  final GlobalKey<FormState> formKey;
  final bool loading;
  final String? error;
  final bool emailValid;
  final VoidCallback onEmailChanged;
  final VoidCallback onSendCode;
  final bool agreedToTerms;
  final bool agreedToPrivacy;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onPrivacyChanged;
  final void Function(String title) onViewTerms;

  bool get _canSend => emailValid && agreedToTerms && agreedToPrivacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  const Text('반가워요!', style: AppTypography.display),
                  const SizedBox(height: AppSpacing.sm),
                  // "반가워요!"와 동일 크기·굵기(display)의 두 번째 헤더 줄.
                  const Text('어떤 이메일로 시작할까요?', style: AppTypography.display),
                  // 제목과 이메일 입력칸 간격 = xl(32) + 20px(사용자 요청).
                  const SizedBox(height: AppSpacing.xl + 20),
                  TextFormField(
                    key: const ValueKey('signup-email'),
                    controller: controller,
                    enabled: !loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => onEmailChanged(),
                    onFieldSubmitted: (_) {
                      if (_canSend) onSendCode();
                    },
                    // 상태별 테두리 색을 두지 않는다 — 테마(기본/포커스 회색)만 쓰고,
                    // 상태는 아래 안내 텍스트로만 표현한다(입력창 소음 최소화).
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      hintText: 'modi@example.com',
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      // 빈 값은 에러로 띄우지 않는다(기본 상태) — CTA가 어차피 비활성.
                      // 형식이 틀렸을 때만 빨간 안내를 보여준다.
                      if (email.isNotEmpty && !_isValidEmail(email)) {
                        return '이메일 형식이 올바르지 않아요';
                      }
                      return null;
                    },
                  ),
                  // 유효 시 성공 문구는 띄우지 않는다(색 개입 최소화). 에러만 빨강 안내.
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accentDanger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // 필수 약관 동의 — "인증번호 보내기" 버튼 바로 위에 고정. 두 항목 사이 간격 8px.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TermsCheckbox(
                key: const ValueKey('terms-checkbox'),
                label: '[필수] 이용약관 동의',
                value: agreedToTerms,
                onChanged: onTermsChanged,
                onViewTerms: () => onViewTerms('이용약관'),
              ),
              const SizedBox(height: AppSpacing.xxs), // 약관 두 항목 사이 간격 2px
              _TermsCheckbox(
                key: const ValueKey('privacy-checkbox'),
                label: '[필수] 개인정보 수집·이용 동의',
                value: agreedToPrivacy,
                onChanged: onPrivacyChanged,
                onViewTerms: () => onViewTerms('개인정보 수집·이용'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            AppSpacing.md,
            AppSpacing.content,
            AppSpacing.lg,
          ),
          child: ElevatedButton(
            onPressed: (!_canSend || loading) ? null : onSendCode,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('인증번호 보내기'),
          ),
        ),
      ],
    );
  }
}

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    super.key,
    required this.email,
    required this.controller,
    required this.loading,
    required this.error,
    required this.timerRemaining,
    required this.onVerify,
    required this.onResend,
  });

  final String email;
  final TextEditingController controller;
  final bool loading;
  final String? error;
  final int timerRemaining;
  final VoidCallback onVerify;
  final VoidCallback onResend;

  bool get _timerExpired => timerRemaining <= 0;

  String get _timerText {
    final m = timerRemaining ~/ 60;
    final s = timerRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        AppSpacing.xl,
        AppSpacing.content,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('반가워요!', style: AppTypography.display),
          const SizedBox(height: AppSpacing.sm),
          const Text('어떤 이메일로 시작할까요?', style: AppTypography.display),
          const SizedBox(height: AppSpacing.xl),
          // 읽기 전용 이메일 표시(발송 완료 상태) — build()마다 컨트롤러를 새로 생성하면
          // 레이아웃 중 markNeedsLayout이 호출되므로 Text 위젯으로 대체한다.
          // 테두리는 상태색 없이 테마 기본(회색)만 쓴다.
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '이메일',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Text(
              email,
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 발송 안내는 성공색이 아니라 중립(muted) 정보 텍스트로 남긴다.
          Text(
            '인증코드를 보냈어요',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('signup-code'),
                  controller: controller,
                  enabled: !loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: (_) => onVerify(),
                  decoration: const InputDecoration(
                    labelText: '인증코드',
                    hintText: '6자리 코드 입력',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ResendButton(
                onPressed: (loading || !_timerExpired) ? null : onResend,
              ),
            ],
          ),
          // 쿨다운 동안은 "언제 재전송할 수 있는지"를 문구로 명확히 안내한다.
          // (초 숫자만 붙어 있으면 코드 유효시간과 헷갈린다는 피드백 반영, 2026-08-05)
          if (!_timerExpired) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$_timerText 후 재전송할 수 있어요',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          ElevatedButton(
            onPressed: loading ? null : onVerify,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('다음'),
          ),
        ],
      ),
    );
  }
}

class _ResendButton extends StatelessWidget {
  const _ResendButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.muted,
        // 앱 전역 OutlinedButtonTheme(theme.dart)는 전체 폭 버튼 기준으로
        // minimumSize: Size.fromHeight(48) = Size(double.infinity, 48)을 쓴다.
        // 이 버튼은 Row 안에서 옆 TextField와 나란히 쓰이므로 무한 너비를
        // 받으면 안 된다 — 높이만 48로 고정하고 너비는 내용에 맞춘다.
        minimumSize: const Size(0, 48),
        side: BorderSide(
          color: onPressed == null ? AppColors.borderSoft : AppColors.border,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.base,
        ),
      ),
      // 카운트다운은 버튼 밖(아래 안내 문구)으로 옮겼다 — 버튼은 항상 "재전송"만.
      // 쿨다운 중에는 onPressed=null로 비활성(muted)되고, 끝나면 primary로 활성.
      child: Text(
        '재전송',
        style: AppTypography.bodySmall.copyWith(
          color: onPressed == null ? AppColors.muted : AppColors.primary,
        ),
      ),
    );
  }
}

/// Step 3 — 비밀번호 설정. 영문+숫자+특수문자 8자 이상 + 확인 일치.
class _PasswordStep extends StatefulWidget {
  const _PasswordStep({
    super.key,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.formKey,
    required this.loading,
    required this.onChanged,
    this.onNext,
  });

  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;
  final GlobalKey<FormState> formKey;
  final bool loading;
  final VoidCallback onChanged;
  final VoidCallback? onNext;

  @override
  State<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<_PasswordStep> {
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// 비밀번호 표시/숨김 눈 아이콘. 숨김이면 뜬 눈(표시 유도), 표시면 감은 눈(숨김 유도).
  Widget _visibilityToggle({
    required Key key,
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    return IconButton(
      key: key,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppColors.muted,
      ),
      tooltip: obscured ? '비밀번호 표시' : '비밀번호 숨기기',
      onPressed: widget.loading ? null : onToggle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
            child: Form(
              key: widget.formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  const Text('사용할 비밀번호를 입력해 주세요', style: AppTypography.display),
                  const SizedBox(height: AppSpacing.xl),
                  TextFormField(
                    key: const ValueKey('signup-password'),
                    controller: widget.passwordController,
                    enabled: !widget.loading,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => widget.onChanged(),
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      hintText: '영문, 숫자, 특수문자 조합 8자 이상',
                      suffixIcon: _visibilityToggle(
                        key: const ValueKey('signup-password-visibility'),
                        obscured: _obscurePassword,
                        onToggle: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      // 빈 값은 에러로 띄우지 않는다(기본 상태, CTA 비활성) — 규칙 위반만 안내.
                      final p = value ?? '';
                      if (p.isNotEmpty && !_isValidPassword(p)) {
                        return '영문, 숫자, 특수문자를 조합해 8자 이상 입력해 주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const ValueKey('signup-password-confirmation'),
                    controller: widget.passwordConfirmController,
                    enabled: !widget.loading,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => widget.onChanged(),
                    onFieldSubmitted: (_) => widget.onNext?.call(),
                    decoration: InputDecoration(
                      labelText: '비밀번호 확인',
                      hintText: '비밀번호를 한번 더 입력해 주세요',
                      suffixIcon: _visibilityToggle(
                        key: const ValueKey(
                          'signup-password-confirm-visibility',
                        ),
                        obscured: _obscureConfirm,
                        onToggle: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (value) {
                      // 빈 값은 에러로 띄우지 않는다 — 입력했는데 다를 때만 불일치 안내.
                      final v = value ?? '';
                      if (v.isNotEmpty && v != widget.passwordController.text) {
                        return '비밀번호가 일치하지 않아요';
                      }
                      return null;
                    },
                  ),
                  // 일치 시 성공 문구는 띄우지 않는다(색 개입 최소화) — 불일치 에러만 빨강.
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            AppSpacing.base,
            AppSpacing.content,
            AppSpacing.lg,
          ),
          child: ElevatedButton(
            onPressed: widget.onNext,
            child: const Text('다음'),
          ),
        ),
      ],
    );
  }
}

/// Step 4 — 프로필(이미지·닉네임·약관). CTA "MODI 시작하기".
class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    super.key,
    required this.nicknameController,
    required this.formKey,
    required this.loading,
    required this.error,
    required this.profileImage,
    required this.onPickImage,
    required this.onNicknameChanged,
    this.onSubmit,
  });

  final TextEditingController nicknameController;
  final GlobalKey<FormState> formKey;
  final bool loading;
  final String? error;
  final XFile? profileImage;
  final VoidCallback? onPickImage;
  final VoidCallback onNicknameChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'MODI에서 보여질\n나만의 프로필을 만들어 보세요',
                    style: AppTypography.display,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: GestureDetector(
                      key: const ValueKey('profile-image-picker'),
                      onTap: onPickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: AppColors.surfaceStrong,
                            backgroundImage: profileImage != null
                                ? FileImage(File(profileImage!.path))
                                : null,
                            child: profileImage == null
                                ? const Icon(
                                    Icons.person,
                                    size: 52,
                                    color: AppColors.mutedSoft,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: AppColors.foregroundSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextFormField(
                    key: const ValueKey('signup-nickname'),
                    controller: nicknameController,
                    enabled: !loading,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => onNicknameChanged(),
                    onFieldSubmitted: (_) => onSubmit?.call(),
                    decoration: const InputDecoration(
                      labelText: '닉네임',
                      hintText: '2~8자 내외로 입력해 주세요',
                    ),
                    validator: (value) {
                      // 빈 값은 에러로 띄우지 않는다(기본 상태, CTA 비활성) — 규칙 위반만 안내.
                      final v = value?.trim() ?? '';
                      if (v.isNotEmpty && !_isValidNickname(v)) {
                        return '한글, 영문, 숫자 2~8자로 입력해 주세요';
                      }
                      return null;
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accentDanger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            AppSpacing.base,
            AppSpacing.content,
            AppSpacing.lg,
          ),
          child: ElevatedButton(
            onPressed: onSubmit,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('MODI 시작하기'),
          ),
        ),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onViewTerms,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 우측 ">"(약관 보기) 탭 콜백. null이면 화살표를 표시하지 않는다.
  final VoidCallback? onViewTerms;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          // 체크박스+라벨 영역 탭 = 동의 토글. ">"(약관 보기)와 분리한다.
          child: GestureDetector(
            onTap: () => onChanged(!value),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    shape: const CircleBorder(),
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                    // 기본 48 탭영역 예약을 줄여 행 높이를 낮춘다.
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(label, style: AppTypography.body)),
              ],
            ),
          ),
        ),
        if (onViewTerms != null)
          IconButton(
            tooltip: '약관 보기',
            onPressed: onViewTerms,
            // 기본 48px 탭영역이 행을 키워 항목 간격이 넓어 보인다 — 타이트하게 축소.
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
            icon: const Icon(
              Icons.chevron_right,
              color: AppColors.muted,
              size: 20,
            ),
          ),
      ],
    );
  }
}
