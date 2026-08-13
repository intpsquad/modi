import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app.dart';
import 'package:app/features/splash/splash_screen.dart';

void main() {
  testWidgets('앱 부팅 시 스플래시 화면(로고)이 뜬다', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pump();

    expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
  });

  testWidgets('스플래시는 접근성 라벨을 제공하고 모션 비활성화에서도 유지된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SplashScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.bySemanticsLabel('MODI 로고, 앱을 준비하는 중'), findsOneWidget);
    expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
  });
}
