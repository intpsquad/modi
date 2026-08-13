import 'package:app/design/tokens.dart';
import 'package:app/features/legal/legal_content.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  // 긴 문서라 기본 뷰포트에선 ListView가 하단 절을 지연 생성해 찾지 못한다.
  // 전체 본문이 한 번에 렌더되도록 큰 화면을 준다.
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('기본은 이용약관을 보여주고 운영주체·문의·시행일이 노출된다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(const LegalScreen()));
    await tester.pumpAndSettle();

    expect(find.text('제1조 (목적)'), findsOneWidget);
    expect(find.text('제11조 (문의처)'), findsOneWidget);
    expect(find.textContaining(kLegalOperator), findsWidgets);
    expect(find.textContaining(kLegalContactEmail), findsWidgets);
    expect(find.textContaining('시행일'), findsOneWidget);
  });

  testWidgets('세그먼트를 탭하면 개인정보 처리방침으로 전환된다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(const LegalScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('개인정보 처리방침'));
    await tester.pumpAndSettle();

    expect(find.text('2. 수집하는 개인정보 항목'), findsOneWidget);
    // 실제 데이터 처리(FCM 푸시)가 방침에 반영돼 있다.
    expect(find.textContaining('FCM'), findsWidgets);
    // 약관 절은 더 이상 보이지 않는다.
    expect(find.text('제1조 (목적)'), findsNothing);
  });

  testWidgets('라인 탭: 활성은 primary·Bold, 비활성은 muted·Regular로 렌더된다', (
    tester,
  ) async {
    useTallView(tester);
    await tester.pumpWidget(wrap(const LegalScreen()));
    await tester.pumpAndSettle();

    // 활성 탭('이용약관') — 같은 문자열이 본문 제목(section)에도 있으므로,
    // 그중 라인 탭 스타일(primary + w700)인 Text가 하나 있는지 확인한다.
    final activeTexts = tester.widgetList<Text>(find.text('이용약관'));
    expect(
      activeTexts.any(
        (t) =>
            t.style?.color == AppColors.primary &&
            t.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
      reason: '활성 탭 라벨은 primary·Bold여야 한다',
    );

    // 비활성 탭('개인정보 처리방침') — 이용약관 화면에선 본문에 없고 탭에만 있다.
    final inactive = tester.widget<Text>(find.text('개인정보 처리방침'));
    expect(inactive.style?.color, AppColors.muted);
    expect(inactive.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('initialDoc으로 개인정보 처리방침을 바로 열 수 있다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(
      wrap(const LegalScreen(initialDoc: LegalDoc.privacy)),
    );
    await tester.pumpAndSettle();

    // 제3자 처리(위탁) 절과 AI 처리 언급이 보인다.
    expect(find.text('4. 개인정보의 제3자 처리 위탁'), findsOneWidget);
    expect(find.textContaining('AI'), findsWidgets);
  });
}
