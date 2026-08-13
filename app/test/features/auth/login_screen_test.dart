import 'dart:async';

import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/auth/email_login_screen.dart';
import 'package:app/design/modi_wordmark.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuthService extends AuthService {}

class _LoadingAuthService extends AuthService {
  final Completer<User> googleResult = Completer<User>();

  @override
  Future<User> signInWithGoogle() => googleResult.future;
}

void main() {
  testWidgets('레퍼런스 로그인 화면의 브랜드와 로그인 채널이 렌더된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(authService: _FakeAuthService())),
      ),
    );

    expect(find.byType(ModiWordmark), findsOneWidget);
    expect(find.text('또는'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('이메일로 로그인'), findsOneWidget);
    expect(find.byKey(const ValueKey('kakao-login-symbol')), findsOneWidget);
    expect(find.byKey(const ValueKey('google-login-symbol')), findsOneWidget);
    expect(find.byKey(const ValueKey('email-login-symbol')), findsOneWidget);
    // 두 번째 소셜 버튼은 플랫폼별 — 테스트 기본(android)에선 구글만 뜨고 애플은 없다.
    expect(find.text('Apple로 계속하기'), findsNothing);
    expect(find.byKey(const ValueKey('apple-login-symbol')), findsNothing);
    expect(find.text('계정이 없으신가요?'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);

    final kakaoButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('카카오로 계속하기'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(kakaoButton.onPressed, isNotNull);
  });

  testWidgets('세 로그인 버튼은 52px 컨테이너와 아이콘+텍스트 중앙 묶음을 지킨다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(authService: _FakeAuthService())),
      ),
    );

    for (final label in ['카카오로 계속하기', 'Google로 계속하기', '이메일로 로그인']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(ElevatedButton),
      );
      expect(tester.getSize(button).height, 52);
    }

    // 아이콘이 라벨 왼쪽에 오고, [아이콘 … 라벨] 묶음이 버튼 중앙 근처에 온다.
    final kakaoButtonRect = tester.getRect(
      find.ancestor(
        of: find.text('카카오로 계속하기'),
        matching: find.byType(ElevatedButton),
      ),
    );
    final kakaoIconCenter = tester.getCenter(
      find.byKey(const ValueKey('kakao-login-symbol')),
    );
    final kakaoLabelCenter = tester.getCenter(find.text('카카오로 계속하기'));
    expect(kakaoIconCenter.dx, lessThan(kakaoLabelCenter.dx));
    expect(
      (kakaoIconCenter.dx + kakaoLabelCenter.dx) / 2,
      closeTo(kakaoButtonRect.center.dx, 40),
    );

    final kakaoLabel = tester.widget<Text>(find.text('카카오로 계속하기'));
    expect(kakaoLabel.style?.fontSize, 16);
    expect(kakaoLabel.style?.fontWeight, FontWeight.w600);
    expect(kakaoLabel.style?.color, const Color(0xD9000000));

    final kakaoShape = tester
        .widget<ElevatedButton>(
          find.ancestor(
            of: find.text('카카오로 계속하기'),
            matching: find.byType(ElevatedButton),
          ),
        )
        .style!
        .shape!
        .resolve({});
    expect(
      (kakaoShape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
  });

  testWidgets('iOS에서는 구글 대신 애플로 계속하기가 뜬다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: LoginScreen(authService: _FakeAuthService()),
        ),
      ),
    );

    expect(find.text('Apple로 계속하기'), findsOneWidget);
    expect(find.byKey(const ValueKey('apple-login-symbol')), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsNothing);
    expect(find.byKey(const ValueKey('google-login-symbol')), findsNothing);
    // 카카오·이메일은 플랫폼 무관하게 공통.
    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('이메일로 로그인'), findsOneWidget);
  });

  testWidgets('로그인 중에는 개별 버튼이 아닌 전체 화면 오버레이를 표시한다', (tester) async {
    final authService = _LoadingAuthService();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(authService: authService)),
      ),
    );

    await tester.tap(find.text('Google로 계속하기'));
    await tester.pump();

    expect(find.byKey(const ValueKey('login-loading-overlay')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    authService.googleResult.completeError(StateError('테스트 로그인 실패'));
    await tester.pump();
  });

  testWidgets('이메일로 로그인 버튼은 이메일 로그인 화면으로 이동한다', (tester) async {
    final router = GoRouter(
      initialLocation: '/onboarding/login',
      routes: [
        GoRoute(
          path: '/onboarding/login',
          builder: (_, _) => LoginScreen(authService: _FakeAuthService()),
        ),
        GoRoute(
          path: '/onboarding/login/email',
          builder: (_, _) => EmailLoginScreen(authService: _FakeAuthService()),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('이메일로 로그인'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('email-login-email-field')),
      findsOneWidget,
    );
  });

  testWidgets('320px 화면에서도 로그인 선택지가 모두 도달 가능하다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: LoginScreen(authService: _FakeAuthService())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('이메일로 로그인'), 240);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('kakao-login-symbol')), findsOneWidget);
    expect(find.text('이메일로 로그인'), findsOneWidget);
  });
}
