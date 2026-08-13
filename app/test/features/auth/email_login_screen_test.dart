import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/auth/email_login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAuthService extends AuthService {
  _RecordingAuthService({this.error});

  final Object? error;
  int calls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    throw error ?? StateError('테스트: 성공 경로는 검증하지 않음');
  }
}

void main() {
  testWidgets('이메일/비밀번호 필드와 로그인 버튼이 렌더된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EmailLoginScreen(authService: _RecordingAuthService())),
    );

    expect(
      find.byKey(const ValueKey('email-login-email-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('email-login-password-field')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
  });

  testWidgets('빈 입력이면 로그인 버튼이 비활성이고 에러 문구도 없다', (tester) async {
    final fake = _RecordingAuthService();
    await tester.pumpWidget(
      MaterialApp(home: EmailLoginScreen(authService: fake)),
    );

    // 빈 필수값은 "입력해 주세요" 문구 대신 비활성 버튼으로 알린다(문구 없음).
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '로그인'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('이메일을 입력해 주세요'), findsNothing);
    expect(find.text('비밀번호를 입력해 주세요'), findsNothing);
    expect(fake.calls, 0);
  });

  testWidgets('자격 오류 시 친절한 문구를 보여준다', (tester) async {
    final fake = _RecordingAuthService(
      error: FirebaseAuthException(code: 'invalid-credential'),
    );
    await tester.pumpWidget(
      MaterialApp(home: EmailLoginScreen(authService: fake)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('email-login-email-field')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-login-password-field')),
      'secret123',
    );
    await tester.pump(); // onChanged → setState 로 로그인 버튼이 활성화되도록
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(fake.lastEmail, 'a@b.com');
    expect(fake.lastPassword, 'secret123');
    expect(find.text('이메일 또는 비밀번호가 올바르지 않아요'), findsOneWidget);
  });

  testWidgets('알 수 없는 오류는 공통 실패 문구로 처리한다', (tester) async {
    final fake = _RecordingAuthService(error: StateError('network'));
    await tester.pumpWidget(
      MaterialApp(home: EmailLoginScreen(authService: fake)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('email-login-email-field')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-login-password-field')),
      'secret123',
    );
    await tester.pump(); // onChanged → setState 로 로그인 버튼이 활성화되도록
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.text('로그인에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
  });
}
