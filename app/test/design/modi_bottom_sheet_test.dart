import 'package:app/design/modi_bottom_sheet.dart';
import 'package:app/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공통 바텀시트 규격 — specs/design.md §6 (2026-08-05 지정).
/// 최소 450 / 최대 600 · 하단 버튼은 바닥에서 24 떠 있고 스크롤과 분리 ·
/// 내용 하단 여백 40 · 내용이 많으면 내용만 스크롤(버튼 고정).

/// 시트를 띄우고 그 사각형을 돌려준다.
Future<Rect> openSheet(
  WidgetTester tester, {
  required Widget content,
  Widget? button,
  String? title,
  Size screen = const Size(400, 900),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModiSheet<void>(
              context: context,
              builder: (_) =>
                  ModiBottomSheet(title: title, button: button, child: content),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return tester.getRect(find.byType(ModiBottomSheet));
}

Widget tallContent() => Column(
  children: [
    for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('줄 $i')),
  ],
);

void main() {
  testWidgets('내용이 짧아도 높이는 최소 450이다', (tester) async {
    final rect = await openSheet(
      tester,
      content: const SizedBox(height: 20, child: Text('짧은 내용')),
    );

    expect(rect.height, 450);
  });

  testWidgets('내용이 많아도 높이는 최대 600에서 멈춘다', (tester) async {
    final rect = await openSheet(tester, content: tallContent());

    expect(rect.height, 600);
  });

  testWidgets('내용이 많으면 내용만 스크롤되고 버튼은 제자리다', (tester) async {
    await openSheet(tester, content: tallContent(), button: const Text('확인'));

    final buttonBefore = tester.getRect(find.text('확인'));
    final firstLineBefore = tester.getRect(find.text('줄 0'));

    await tester.drag(find.text('줄 3'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('확인')),
      buttonBefore,
      reason: '버튼은 스크롤과 분리돼 움직이지 않는다',
    );
    expect(
      tester.getRect(find.text('줄 0')).top,
      lessThan(firstLineBefore.top),
      reason: '내용은 스크롤된다',
    );
  });

  testWidgets('버튼은 시트 바닥에서 24 떠 있다', (tester) async {
    final rect = await openSheet(
      tester,
      content: const SizedBox(height: 20),
      button: const Text('확인'),
    );

    final button = tester.getRect(find.text('확인'));
    expect(rect.bottom - button.bottom, 24);
  });

  testWidgets('끝까지 스크롤해도 마지막 줄이 버튼에 붙지 않는다 (내용 아래 40)', (tester) async {
    // 짧은 내용에서는 남는 공간이 크므로 "정확히 40"을 잴 수 없다 — 내용이 넘칠 때
    // 마지막 줄과 버튼 사이가 40인지가 이 규격의 실제 의미다.
    await openSheet(tester, content: tallContent(), button: const Text('확인'));

    await tester.fling(find.text('줄 3'), const Offset(0, -3000), 1000);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('확인')).top -
          tester.getRect(find.text('줄 39')).bottom,
      40,
    );
  });

  testWidgets('버튼이 없어도 내용 아래 40 여백은 남는다', (tester) async {
    final rect = await openSheet(tester, content: tallContent());

    await tester.fling(find.text('줄 3'), const Offset(0, -3000), 1000);
    await tester.pumpAndSettle();

    expect(rect.bottom - tester.getRect(find.text('줄 39')).bottom, 40);
  });

  testWidgets('화면이 낮으면 화면 높이가 최소 450보다 우선한다', (tester) async {
    // 최소 높이를 그대로 밀어붙이면 작은 기기에서 시트가 화면을 넘는다.
    final rect = await openSheet(
      tester,
      content: const SizedBox(height: 20),
      screen: const Size(400, 420),
    );

    expect(rect.height, lessThanOrEqualTo(420));
  });

  testWidgets('제목을 주면 스크롤되지 않는 고정 영역에 그린다', (tester) async {
    await openSheet(tester, title: '시트 제목', content: tallContent());

    final titleBefore = tester.getRect(find.text('시트 제목'));
    await tester.drag(find.text('줄 3'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('시트 제목')), titleBefore);
  });

  testWidgets('showModiSheet은 루트 네비게이터에 띄운다', (tester) async {
    // 그러지 않으면 플로팅 하단 네비가 시트 위로 올라온다(design.md §8).
    // 루트에 떴다면 Scaffold 아래가 아니라 최상위 Overlay에 있다.
    await openSheet(tester, content: const SizedBox(height: 20));

    expect(find.byType(ModiBottomSheet), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(ModiBottomSheet),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
      reason: '호출한 화면의 Scaffold 안이 아니라 그 위에 뜬다',
    );
  });
}
