import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/auth/signup_screen.dart';
import 'package:app/features/legal/legal_content.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class _FakeAuthService extends AuthService {
  String? lastEmail;
  String? lastCode;
  String? nickname;
  String? password;
  int sendCodeCalls = 0;
  int verifyCodeCalls = 0;
  int signUpCalls = 0;

  @override
  Future<void> sendEmailVerificationCode(String email) async {
    sendCodeCalls++;
    lastEmail = email;
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    verifyCodeCalls++;
    lastEmail = email;
    lastCode = code;
  }

  @override
  Future<void> signUpWithEmail({
    required String email,
    required String nickname,
    required String password,
    String? profileImage,
  }) async {
    signUpCalls++;
    lastEmail = email;
    this.nickname = nickname;
    this.password = password;
  }
}

/// 이메일 단계의 필수 약관 2종에 동의(이제 첫 화면에 있음).
Future<void> _agreeTerms(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('terms-checkbox')));
  await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('privacy-checkbox')));
  await tester.tap(find.byKey(const ValueKey('privacy-checkbox')));
  await tester.pump();
}

/// email → code → 비밀번호 스텝까지 이동.
Future<void> _goToPasswordStep(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('signup-email')),
    'modi@example.com',
  );
  await tester.pump();
  await _agreeTerms(tester);
  await tester.tap(find.text('인증번호 보내기'));
  await tester.pump();

  await tester.enterText(find.byKey(const ValueKey('signup-code')), '123456');
  await tester.pump();
  await tester.tap(find.text('다음'));
  await tester.pump();
}

/// email → code → 비밀번호(유효 입력) → 프로필 스텝까지 이동.
Future<void> _goToProfileStep(WidgetTester tester) async {
  await _goToPasswordStep(tester);
  await tester.enterText(
    find.byKey(const ValueKey('signup-password')),
    'Modi1234!',
  );
  await tester.enterText(
    find.byKey(const ValueKey('signup-password-confirmation')),
    'Modi1234!',
  );
  await tester.pump();
  await tester.tap(find.text('다음'));
  await tester.pump();
}

void main() {
  testWidgets('이메일 미입력 상태에서 인증번호 보내기 버튼이 비활성화된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '인증번호 보내기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('잘못된 이메일 입력 시 에러 메시지가 표시된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'invalid',
    );
    await tester.pump();

    expect(find.text('이메일 형식이 올바르지 않아요'), findsOneWidget);
  });

  testWidgets('유효한 이메일 입력 시 성공 문구 없이 형식 오류만 사라진다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'modi@example.com',
    );
    await tester.pump();

    // 성공 상태에는 안내 문구를 띄우지 않는다(색 개입 최소화).
    expect(find.text('사용할 수 있는 이메일이에요'), findsNothing);
    expect(find.text('이메일 형식이 올바르지 않아요'), findsNothing);
  });

  testWidgets('유효한 이메일 입력 후 인증번호 보내기를 누르면 코드 입력 화면으로 이동한다', (tester) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: authService)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'modi@example.com',
    );
    await tester.pump();
    await _agreeTerms(tester); // 필수 약관은 이메일 단계에 있다

    await tester.tap(find.text('인증번호 보내기'));
    await tester.pump();

    expect(authService.sendCodeCalls, 1);
    // 코드 스텝 진입 — 헤더는 이메일 스텝과 동일("반가워요!")이라, 코드 스텝
    // 고유의 "인증코드를 보냈어요"(발송 완료 안내)로 진입을 확인한다.
    expect(find.text('인증코드를 보냈어요'), findsOneWidget);
  });

  testWidgets('코드 스텝 진입 직후엔 재전송이 비활성이고 언제 가능한지 안내한다', (tester) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: authService)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'modi@example.com',
    );
    await tester.pump();
    await _agreeTerms(tester);
    await tester.tap(find.text('인증번호 보내기'));
    await tester.pump();

    // 쿨다운 동안: 초 숫자만 있지 않고 "..후 재전송할 수 있어요" 문구로 안내한다.
    expect(find.textContaining('후 재전송할 수 있어요'), findsOneWidget);
    // 재전송 버튼은 있지만 쿨다운이라 비활성(onPressed == null).
    final resend = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '재전송'),
    );
    expect(resend.onPressed, isNull);

    // 위젯을 정리해 진행 중인 재전송 타이머를 취소한다.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('인증코드 입력 후 다음을 누르면 비밀번호 화면으로 이동한다', (tester) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: authService)),
    );

    await _goToPasswordStep(tester);

    expect(authService.verifyCodeCalls, 1);
    expect(find.text('사용할 비밀번호를 입력해 주세요'), findsOneWidget);
  });

  testWidgets('비밀번호 조건(영문·숫자·특수문자 8자) 미충족 시 다음이 비활성', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToPasswordStep(tester);

    await tester.enterText(
      find.byKey(const ValueKey('signup-password')),
      'abcdefg',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-password-confirmation')),
      'abcdefg',
    );
    await tester.pump();

    expect(find.text('영문, 숫자, 특수문자를 조합해 8자 이상 입력해 주세요'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '다음'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('비밀번호 눈 아이콘을 탭하면 표시/숨김이 토글된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToPasswordStep(tester);

    EditableText passwordField() => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('signup-password')),
        matching: find.byType(EditableText),
      ),
    );

    // 기본은 가림(●●●).
    expect(passwordField().obscureText, isTrue);

    // 눈 아이콘 탭 → 표시.
    await tester.tap(find.byKey(const ValueKey('signup-password-visibility')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);

    // 다시 탭 → 숨김.
    await tester.tap(find.byKey(const ValueKey('signup-password-visibility')));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
  });

  testWidgets('비밀번호 확인 불일치 시 에러와 함께 다음이 비활성', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToPasswordStep(tester);

    await tester.enterText(
      find.byKey(const ValueKey('signup-password')),
      'Modi1234!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-password-confirmation')),
      'Modi9999!',
    );
    await tester.pump();

    expect(find.text('비밀번호가 일치하지 않아요'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '다음'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('비밀번호가 유효·일치하면 프로필 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToProfileStep(tester);

    expect(find.text('MODI에서 보여질\n나만의 프로필을 만들어 보세요'), findsOneWidget);
  });

  testWidgets('닉네임 미입력이면 MODI 시작하기 버튼이 비활성', (tester) async {
    // 약관은 이메일 단계에서 이미 동의(_goToProfileStep 경유). 최종 게이트는 닉네임.
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: authService)),
    );
    await _goToProfileStep(tester);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'MODI 시작하기'),
    );
    expect(button.onPressed, isNull);
    expect(authService.signUpCalls, 0);
  });

  testWidgets('닉네임 형식이 틀리면 에러 메시지가 뜬다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToProfileStep(tester);

    await tester.enterText(find.byKey(const ValueKey('signup-nickname')), 'a');
    await tester.pump();

    expect(find.text('한글, 영문, 숫자 2~8자로 입력해 주세요'), findsOneWidget);
  });

  testWidgets('이미지 없이 닉네임만으로 MODI 시작하기가 활성화된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToProfileStep(tester); // 약관은 이메일 단계에서 이미 동의됨

    await tester.enterText(
      find.byKey(const ValueKey('signup-nickname')),
      '모디모디',
    );
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'MODI 시작하기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('유효한 입력으로 가입하면 Firebase 가입 계약에 값을 전달한다', (tester) async {
    final authService = _FakeAuthService();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SignupScreen(
          authService: authService,
          onCompleted: () async => completed = true,
        ),
      ),
    );
    // _goToProfileStep이 이메일 단계에서 약관 동의 + 비밀번호(Modi1234!)를 처리함.
    await _goToProfileStep(tester);

    await tester.enterText(
      find.byKey(const ValueKey('signup-nickname')),
      '모디모디',
    );
    await tester.pump();

    await tester.tap(find.text('MODI 시작하기'));
    await tester.pump();

    expect(authService.signUpCalls, 1);
    expect(authService.lastEmail, 'modi@example.com');
    expect(authService.nickname, '모디모디');
    expect(authService.password, 'Modi1234!');
    expect(completed, isTrue);
  });

  testWidgets('비밀번호 화면에서 뒤로 가면 인증코드 화면으로 돌아간다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToPasswordStep(tester);
    expect(find.text('사용할 비밀번호를 입력해 주세요'), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();

    expect(find.text('인증코드를 보냈어요'), findsOneWidget);
  });

  testWidgets('이메일 단계 약관의 > 를 탭하면 약관·정책 페이지로 이동한다', (tester) async {
    final router = GoRouter(
      initialLocation: '/signup',
      routes: [
        GoRoute(
          path: '/signup',
          builder: (context, state) =>
              SignupScreen(authService: _FakeAuthService()),
        ),
        GoRoute(
          path: '/legal',
          builder: (context, state) {
            final doc = state.uri.queryParameters['doc'] == 'privacy'
                ? LegalDoc.privacy
                : LegalDoc.terms;
            return LegalScreen(initialDoc: doc);
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 이용약관(첫 번째 화살표) → 이용약관 문서로 이동.
    await tester.ensureVisible(find.byTooltip('약관 보기').first);
    await tester.tap(find.byTooltip('약관 보기').first);
    await tester.pumpAndSettle();

    expect(find.text('약관 · 정책'), findsOneWidget);
    expect(find.text('제1조 (목적)'), findsOneWidget);

    // 뒤로 가서 개인정보(두 번째 화살표) → 개인정보 처리방침으로 이동.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('약관 보기').last);
    await tester.tap(find.byTooltip('약관 보기').last);
    await tester.pumpAndSettle();

    expect(find.text('2. 수집하는 개인정보 항목'), findsOneWidget);
  });

  testWidgets('프로필 이미지를 고르면 아바타 프리뷰가 교체된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupScreen(
          authService: _FakeAuthService(),
          pickImage: (ImageSource source) async => XFile('/fake/avatar.jpg'),
        ),
      ),
    );
    await _goToProfileStep(tester);

    // 픽 전 — 기본 아바타(backgroundImage 없음).
    var avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);

    await tester.tap(find.byKey(const ValueKey('profile-image-picker')));
    await tester.pump();

    avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNotNull);
  });

  testWidgets('TLD가 1글자면(gmail.c) 무효이고 .com이라야 유효하다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _agreeTerms(tester); // 약관 게이트를 지나 버튼이 이메일 유효성만 반영하게

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'hiky2002@gmail.c',
    );
    await tester.pump();
    // 성공 문구는 더 이상 없다 — 유효성은 CTA 활성으로만 확인한다.
    expect(find.text('사용할 수 있는 이메일이에요'), findsNothing);
    var button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '인증번호 보내기'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'hiky2002@gmail.com',
    );
    await tester.pump();
    expect(find.text('사용할 수 있는 이메일이에요'), findsNothing);
    button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '인증번호 보내기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('이메일이 유효해도 약관 미동의면 인증번호 보내기가 비활성', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );

    await tester.enterText(
      find.byKey(const ValueKey('signup-email')),
      'modi@example.com',
    );
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '인증번호 보내기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('비밀번호가 유효·일치하면 성공 문구 없이 다음이 활성된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authService: _FakeAuthService())),
    );
    await _goToPasswordStep(tester);

    await tester.enterText(
      find.byKey(const ValueKey('signup-password')),
      'Modi1234!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('signup-password-confirmation')),
      'Modi1234!',
    );
    await tester.pump();

    // 성공 문구는 띄우지 않는다 — 유효/일치는 불일치 에러가 없고 CTA가 활성인 것으로 확인.
    expect(find.text('비밀번호가 일치해요'), findsNothing);
    expect(find.text('비밀번호가 일치하지 않아요'), findsNothing);
    final next = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '다음'),
    );
    expect(next.onPressed, isNotNull);
  });
}
