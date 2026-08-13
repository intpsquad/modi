import 'package:app/features/home/activity_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Text.rich 안에서 [text] 조각의 fontWeight를 찾는다.
FontWeight? _weightOf(WidgetTester tester, String text) {
  final textWidget = tester.widget<Text>(find.byType(Text));
  FontWeight? found;
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text == text) found = span.style?.fontWeight;
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  visit(textWidget.textSpan!);
  return found;
}

void main() {
  testWidgets('메시지를 렌더하고 닉네임 조각만 굵게 그린다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ActivityCapsuleBanner(
          reduceMotion: true,
          messages: [
            ActivityMessage([
              ActivitySegment('지훈', bold: true),
              ActivitySegment('님이 투두 3개를 완료했어요 🔥'),
            ]),
          ],
        ),
      ),
    );

    expect(find.text('지훈님이 투두 3개를 완료했어요 🔥'), findsOneWidget);
    expect(_weightOf(tester, '지훈'), FontWeight.w700);
    expect(_weightOf(tester, '님이 투두 3개를 완료했어요 🔥'), isNot(FontWeight.w700));
  });

  testWidgets('메시지가 여러 개면 interval마다 다음 메시지로 넘어간다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ActivityCapsuleBanner(
          reduceMotion: false,
          interval: Duration(seconds: 4),
          messages: [
            ActivityMessage([ActivitySegment('첫 번째 소식')]),
            ActivityMessage([ActivitySegment('두 번째 소식')]),
          ],
        ),
      ),
    );

    expect(find.text('첫 번째 소식'), findsOneWidget);

    // 4초 경과 → 롤링 타이머 발동, 슬라이드 전환(300ms) 완료.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('두 번째 소식'), findsOneWidget);

    // 열려 있는 주기 타이머를 정리한다(테스트 종료 시 pending 방지).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion이면 여러 개여도 자동 회전하지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ActivityCapsuleBanner(
          reduceMotion: true,
          interval: Duration(seconds: 4),
          messages: [
            ActivityMessage([ActivitySegment('첫 번째 소식')]),
            ActivityMessage([ActivitySegment('두 번째 소식')]),
          ],
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 8));

    expect(find.text('첫 번째 소식'), findsOneWidget);
    expect(find.text('두 번째 소식'), findsNothing);
  });

  testWidgets('메시지가 없으면 아무것도 그리지 않는다', (tester) async {
    await tester.pumpWidget(_wrap(const ActivityCapsuleBanner(messages: [])));

    expect(
      find.descendant(
        of: find.byType(ActivityCapsuleBanner),
        matching: find.byType(Row),
      ),
      findsNothing,
    );
  });
}
