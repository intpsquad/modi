import 'package:app/design/notice_banner.dart';
import 'package:app/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// NoticeBanner — 흰 배경 + 연한 회색 테두리 + 회색 그림자 + 경고 아이콘의 일반 안내 배너.
/// (2026-08-09 담당자 미지정 배너를 AI 그라데이션 배너에서 이걸로 교체.)
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('문구를 그리고 높이는 40이다', (tester) async {
    await tester.pumpWidget(host(const NoticeBanner(text: 'MODI 안내 문구')));

    expect(find.text('MODI 안내 문구'), findsOneWidget);
    expect(tester.getSize(find.byType(NoticeBanner)).height, 40);
  });

  testWidgets('bold 로 준 부분만 굵게 그린다', (tester) async {
    await tester.pumpWidget(
      host(const NoticeBanner(text: 'MODI가 추천해줬어요', bold: 'MODI')),
    );

    // Text.rich 안에서 'MODI' span 만 w700, 나머지는 기본 굵기.
    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(NoticeBanner),
        matching: find.byType(RichText),
      ),
    );
    final spans = <TextSpan>[];
    (richText.text as TextSpan).visitChildren((span) {
      if (span is TextSpan) spans.add(span);
      return true;
    });
    final bold = spans.firstWhere((s) => s.text == 'MODI');
    expect(bold.style?.fontWeight, FontWeight.w700);
    final normal = spans.firstWhere((s) => s.text == '가 추천해줬어요');
    expect(normal.style?.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('onTap 이 있으면 눌린다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(NoticeBanner(text: '눌러보기', onTap: () => taps++)),
    );

    await tester.tap(find.byType(NoticeBanner));
    await tester.pump();
    expect(taps, 1);
  });
}
