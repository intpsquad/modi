import 'package:app/design/theme.dart';
import 'package:app/features/archive/archive_widgets.dart';
import 'package:app/features/archive/crawl_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자료 목록의 칩 줄 — 2026-08-05 요청: "칩이 2줄이 되면 안돼. 한줄 넘어가면 ...으로 표기".

Future<Rect> pumpRow(
  WidgetTester tester, {
  required List<ChipSpec> chips,
  double width = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleLineChips(chips: chips),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byType(SingleLineChips));
}

List<ChipSpec> tags(int count) => [
  for (var i = 0; i < count; i++) ChipSpec.tag('태그$i'),
];

Future<double> renderedWidth(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byWidget(child)).width;
}

void main() {
  testWidgets('칩이 다 들어가면 그대로 한 줄로 보여준다', (tester) async {
    final rect = await pumpRow(tester, chips: tags(2), width: 300);

    expect(find.text('#태그0'), findsOneWidget);
    expect(find.text('#태그1'), findsOneWidget);
    expect(find.text('…'), findsNothing, reason: '자리가 남으면 말줄임을 붙이지 않는다');
    expect(rect.height, ArchiveTagChip.height, reason: '항상 한 줄 높이');
  });

  testWidgets('폭이 부족하면 들어가는 칩만 만들고 끝에 …를 붙인다', (tester) async {
    final rect = await pumpRow(tester, chips: tags(8), width: 160);

    expect(find.text('…'), findsOneWidget);
    expect(find.text('#태그0'), findsOneWidget);
    // 잘린 칩은 트리에 아예 없다 — 스크린리더도 읽지 않고 X도 눌리지 않는다.
    expect(find.text('#태그7'), findsNothing);
    expect(rect.height, ArchiveTagChip.height, reason: '2줄이 되지 않는다');
  });

  testWidgets('그려진 칩과 …는 줄 밖으로 넘치지 않는다', (tester) async {
    final rect = await pumpRow(tester, chips: tags(8), width: 160);

    expect(
      tester.getRect(find.text('…')).right,
      lessThanOrEqualTo(rect.right + 0.5),
    );
    for (var i = 0; i < 8; i++) {
      final chip = find.text('#태그$i');
      if (chip.evaluate().isEmpty) continue;
      expect(
        tester.getRect(chip).right,
        lessThanOrEqualTo(rect.right + 0.5),
        reason: '#태그$i 가 줄을 넘어간다',
      );
    }
  });

  testWidgets('칩이 하나도 못 들어갈 만큼 좁아도 죽지 않는다', (tester) async {
    await pumpRow(tester, chips: tags(4), width: 12);

    expect(tester.takeException(), isNull);
  });

  testWidgets('칩이 없으면 아무것도 그리지 않는다', (tester) async {
    final rect = await pumpRow(tester, chips: const []);

    expect(find.text('…'), findsNothing);
    expect(rect.height, 0, reason: '빈 줄이 자리를 차지하지 않는다');
  });

  // ---- 추정 폭은 **상한**이어야 한다 ----
  //
  // 과소평가하면 마지막 칩이 줄을 넘어 Row 오버플로 경고가 뜬다. 과대평가는 드물게 칩
  // 하나가 일찍 …로 넘어가는 정도라, 상한이면서 과하지 않은 범위를 못 박는다.

  testWidgets('태그 칩의 추정 폭은 실제 렌더 폭보다 작지 않다', (tester) async {
    for (final deletable in [false, true]) {
      final chip = ArchiveTagChip(
        label: '여행개발',
        onDeleted: deletable ? () {} : null,
      );
      final actual = await renderedWidth(tester, chip);
      final estimated =
          SingleLineChips.textWidth('#여행개발', TextScaler.noScaling) +
          ArchiveTagChip.extraWidthFor(deletable: deletable) +
          SingleLineChips.slack;

      expect(
        estimated,
        greaterThanOrEqualTo(actual),
        reason: 'deletable=$deletable — 과소평가하면 줄을 넘는다',
      );
      expect(
        estimated - actual,
        lessThanOrEqualTo(8),
        reason: 'deletable=$deletable — 너무 크게 잡으면 칩이 일찍 잘린다',
      );
    }
  });

  testWidgets('분석 상태 배지의 추정 폭도 상한이고 높이는 칩과 같다', (tester) async {
    const badge = CrawlStatusBadge(status: 'FAILED');
    final actual = await renderedWidth(tester, badge);
    final estimated =
        SingleLineChips.textWidth(
          CrawlStatusBadge.labelFor('FAILED'),
          TextScaler.noScaling,
        ) +
        CrawlStatusBadge.extraWidth +
        SingleLineChips.slack;

    expect(estimated, greaterThanOrEqualTo(actual));
    expect(estimated - actual, lessThanOrEqualTo(8));
    expect(
      tester.getRect(find.byWidget(badge)).height,
      ArchiveTagChip.height,
      reason: '칩과 같은 줄에 오므로 높이도 같다',
    );
  });
}
