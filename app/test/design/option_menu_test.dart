import 'package:app/design/option_menu.dart';
import 'package:app/design/theme.dart';
import 'package:app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공통 옵션창 규격 — specs/design.md §6 (2026-08-05 지정).
/// 좌우 패딩 22 · 상하 패딩 18 · radius 20 · 약한 그림자 · 좌측 정렬 ·
/// 아이콘 20 · 텍스트 16 · gap 10 · **누른 버튼 바로 아래**에 뜬다.

final anchorKey = GlobalKey();
String? tapped;

Future<void> openMenu(
  WidgetTester tester, {
  List<OptionMenuItem<String>>? items,
  Alignment anchorAt = Alignment.topRight,
  Size screen = const Size(400, 800),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tapped = null;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: anchorAt,
          child: Builder(
            builder: (context) => IconButton(
              key: anchorKey,
              onPressed: () async {
                tapped = await showOptionMenu<String>(
                  context: context,
                  anchorKey: anchorKey,
                  items:
                      items ??
                      [
                        OptionMenuItem(
                          label: '수정',
                          value: 'edit',
                          icon: Icons.edit_outlined,
                        ),
                        OptionMenuItem(
                          label: '삭제',
                          value: 'delete',
                          icon: Icons.delete_outline,
                          danger: true,
                        ),
                      ],
                );
              },
              icon: const Icon(Icons.more_vert),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(anchorKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('카드가 누른 버튼 바로 아래에 뜬다', (tester) async {
    await openMenu(tester);

    final anchor = tester.getRect(find.byKey(anchorKey));
    final card = tester.getRect(find.byType(OptionMenuCard<String>));

    expect(card.top, greaterThanOrEqualTo(anchor.bottom - 1), reason: '버튼 아래');
    // 버튼 오른쪽 끝에 맞추되 화면 가장자리에 붙지는 않는다(여백 8을 남긴다).
    expect(card.right, lessThanOrEqualTo(anchor.right));
    expect(anchor.right - card.right, lessThanOrEqualTo(8));
    expect(card.right, lessThan(400), reason: '화면 끝에 붙지 않는다');
  });

  testWidgets('버튼이 화면 아래쪽이면 위로 뒤집는다', (tester) async {
    await openMenu(tester, anchorAt: Alignment.bottomRight);

    final anchor = tester.getRect(find.byKey(anchorKey));
    final card = tester.getRect(find.byType(OptionMenuCard<String>));

    expect(card.bottom, lessThanOrEqualTo(anchor.top + 1), reason: '버튼 위로');
  });

  testWidgets('패딩 22/18 · radius 20 · 약한 그림자', (tester) async {
    await openMenu(tester);

    // 패딩은 위젯 속성 대신 실제 좌표로 잰다 — 카드 안에 Padding이 여러 개라 어느 것을
    // 집었는지에 결과가 좌우되면 안 된다.
    final card = tester.getRect(find.byType(OptionMenuCard<String>));
    final firstIcon = tester.getRect(find.byIcon(Icons.edit_outlined));
    final firstLabel = tester.getRect(find.text('수정'));
    final lastLabel = tester.getRect(find.text('삭제'));
    expect(firstIcon.left - card.left, 22, reason: '좌측 패딩 22');
    // 상하 패딩은 **행** 기준이다 — 아이콘(20)은 행 높이(텍스트 24)보다 낮아 세로 중앙에
    // 놓이므로 2px 안쪽으로 들어간다. 행 높이를 채우는 라벨로 잰다.
    expect(firstLabel.top - card.top, 18, reason: '상단 패딩 18');
    expect(card.bottom - lastLabel.bottom, 18, reason: '하단 패딩 18');

    final decoration =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byType(OptionMenuCard<String>),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(20),
      reason: 'radius 20',
    );
    // 약한 그림자 = design.md §5 float 티어(유일하게 허용된 그림자).
    // Material의 숫자 elevation은 같은 자리에서 딱딱한 검정 테두리처럼 보인다.
    expect(decoration.boxShadow, AppElevation.float);
  });

  testWidgets('항목은 아이콘 20 · 텍스트 16 · gap 10 · 좌측 정렬이다', (tester) async {
    await openMenu(tester);

    final icon = tester.getRect(find.byIcon(Icons.edit_outlined));
    final label = tester.getRect(find.text('수정'));

    expect(icon.width, 20);
    expect(icon.height, 20);
    expect(label.left - icon.right, 10, reason: '아이콘↔텍스트 gap 10');
    expect(
      tester.widget<Text>(find.text('수정')).style?.fontSize,
      16,
      reason: '텍스트 16',
    );
    // 좌측 정렬 — 두 항목의 아이콘 왼쪽이 같은 x에 선다.
    expect(tester.getRect(find.byIcon(Icons.delete_outline)).left, icon.left);
  });

  testWidgets('danger 항목은 accent-danger로 그린다', (tester) async {
    await openMenu(tester);

    expect(
      tester.widget<Text>(find.text('삭제')).style?.color,
      AppColors.accentDanger,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
      AppColors.accentDanger,
    );
  });

  testWidgets('항목을 탭하면 그 값을 돌려주고 닫힌다', (tester) async {
    await openMenu(tester);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(tapped, 'delete');
    expect(find.byType(OptionMenuCard<String>), findsNothing);
  });

  testWidgets('바깥을 탭하면 null로 닫힌다', (tester) async {
    await openMenu(tester);

    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();

    expect(tapped, isNull);
    expect(find.byType(OptionMenuCard<String>), findsNothing);
  });

  testWidgets('아이콘이 없는 항목도 좌측 정렬로 그린다', (tester) async {
    await openMenu(
      tester,
      items: [
        OptionMenuItem(label: '이름 수정', value: 'rename'),
        OptionMenuItem(label: '삭제', value: 'delete', danger: true),
      ],
    );

    final first = tester.getRect(find.text('이름 수정'));
    final second = tester.getRect(find.text('삭제'));
    expect(second.left, first.left);
    expect(find.byType(Icon), findsOneWidget, reason: '트리거 아이콘만 남는다');
  });
}
