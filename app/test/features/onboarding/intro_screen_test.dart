import 'package:app/features/onboarding/intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('S-01은 좌우 스와이프로 슬라이드를 넘기고 마지막에서만 시작하기가 페이드인된다', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(home: IntroScreen(onComplete: () async => completed = true)),
    );

    // '시작하기' 버튼을 감싼 AnimatedOpacity의 현재 투명도.
    double startOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('시작하기'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    // 첫 슬라이드 — '다음' 버튼은 없어지고, '시작하기'는 트리에 있으나 숨겨져 있다(투명).
    expect(find.byKey(const ValueKey('intro-slide-0')), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);
    expect(find.text('다음'), findsNothing);
    expect(startOpacity(), 0);

    // 좌로 스와이프 3번 → 마지막(4번째) 슬라이드.
    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }

    // 마지막 페이지 — 시작하기 페이드인(투명도 1), 건너뛰기 숨김.
    expect(find.byKey(const ValueKey('intro-slide-3')), findsOneWidget);
    expect(startOpacity(), 1);
    expect(find.text('건너뛰기'), findsNothing);

    await tester.tap(find.text('시작하기'));
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('페이지 인디케이터 점이 4개다(슬라이드 수와 일치)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntroScreen()));

    // 인디케이터 점 = AnimatedContainer 4개.
    expect(find.byType(AnimatedContainer), findsNWidgets(4));
  });

  testWidgets('캐러셀 PageView는 좌우 Padding 없이 전체 화면 폭을 사용한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: IntroScreen()));

    final pageRect = tester.getRect(find.byType(PageView));
    expect(pageRect.left, 0);
    expect(pageRect.right, 390);
  });
}
