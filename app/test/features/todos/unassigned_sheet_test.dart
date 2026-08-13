import 'dart:async';

import 'package:app/design/theme.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:app/features/todos/unassigned_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S-17 미지정 처리 시트 — specs/0006-투두-탭.md.
///
/// ⚠️ **앱 테마를 반드시 적용한다.** `outlinedButtonTheme` 의 `minimumSize` 가 무한 너비
/// (`Size.fromHeight`)라, 너비가 안 묶인 자리에 버튼을 놓으면 레이아웃이 깨진다. 테마 없이
/// 띄우면 그 버그가 **재현되지 않는다** — `ai_suggest_sheet_test.dart` 가 같은 이유로 테마를 쓴다.
///
/// 이 파일이 없어서 실제로 놓쳤다: 배너를 눌러도 시트가 **빈 채로** 떴다(2026-08-04, 에뮬레이터
/// 재현 + `Trailing widget consumes the entire tile width`). 화면 테스트는 배너가 *보이는지*만
/// 봤고 *누르는* 테스트가 없었다.
void main() {
  List<TodoItem> todosOf(int count) => [
    for (var i = 1; i <= count; i++)
      TodoItem(
        id: i,
        title: '미지정 투두 $i',
        completed: false,
        categoryId: null,
        assignees: const [],
      ),
  ];
  final members = [
    MemberBrief(userId: 'u1', nickname: '철수'),
    MemberBrief(userId: 'u2', nickname: '영희'),
  ];

  Future<void> pumpSheet(
    WidgetTester tester,
    List<TodoItem> initial, {
    Future<void> Function(TodoItem, List<String>)? onAssign,
    List<MemberBrief>? roomMembers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UnassignedSheet(
            initialTodos: initial,
            members: roomMembers ?? members,
            onAssign: onAssign ?? (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 행의 담당자 컨트롤(`미지정 ⌃⌄`). 행마다 하나씩 있다.
  Finder menuOfRow(int index) => find.byIcon(Icons.unfold_more).at(index);

  testWidgets('제목·부제·개수 뱃지와 미지정 행들이 예외 없이 렌더링된다', (tester) async {
    await pumpSheet(tester, todosOf(6));

    expect(tester.takeException(), isNull);
    expect(find.text('담당자 미지정'), findsOneWidget);
    expect(find.text('담당자를 지정하면 개인 진행률에 반영돼요'), findsOneWidget);
    expect(find.text('6개'), findsOneWidget);
    expect(find.text('미지정 투두 1'), findsOneWidget);
    // 행마다 "누르면 고른다"는 컨트롤이 있다.
    expect(find.text('미지정'), findsNWidgets(6));
    expect(find.byIcon(Icons.unfold_more), findsNWidgets(6));
  });

  testWidgets('닫기 버튼이 없다 — 마지막 항목을 처리하면 스스로 닫힌다', (tester) async {
    // 2026-08-04 확정: 목업의 [저장하고 닫기]를 없애고 즉시 반영·자동 닫힘을 유지한다.
    await pumpSheet(tester, todosOf(2));

    expect(find.widgetWithText(ElevatedButton, '저장하고 닫기'), findsNothing);
    expect(find.widgetWithText(TextButton, '닫기'), findsNothing);
  });

  testWidgets('컨트롤을 누르면 투두 추가와 동일한 담당자 선택 바텀시트가 뜬다', (tester) async {
    // 2026-08-09 행에 붙어 뜨던 팝업 메뉴 → 공용 담당자 선택 바텀시트.
    await pumpSheet(tester, todosOf(3));

    await tester.tap(menuOfRow(0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 시트 헤더 '담당자'(미지정 시트의 '담당자 미지정' 과는 다른 정확 일치) + 멤버 + 완료 버튼.
    expect(find.text('담당자'), findsOneWidget);
    expect(find.text('철수'), findsOneWidget);
    expect(find.text('영희'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '완료'), findsOneWidget);
  });

  testWidgets('시트에서 멤버를 골라 완료하면 지정되고 행이 사라진다', (tester) async {
    final assigned = <String>[];
    await pumpSheet(
      tester,
      todosOf(3),
      onAssign: (todo, ids) async =>
          assigned.add('${todo.id}:${ids.join(",")}'),
    );

    await tester.tap(menuOfRow(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영희'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
    await tester.pumpAndSettle();

    // 고른 담당자만 실려 서버로 나가고, 그 행은 사라진다.
    expect(assigned, ['2:u2']);
    expect(find.text('미지정 투두 2'), findsNothing);
    expect(find.text('미지정 투두 1'), findsOneWidget);
    expect(find.text('2개'), findsOneWidget);
  });

  testWidgets('지정에 실패하면 행이 남고 안내 문구가 뜬다', (tester) async {
    await pumpSheet(
      tester,
      todosOf(2),
      onAssign: (_, _) async => throw StateError('network'),
    );

    await tester.tap(menuOfRow(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('철수'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
    await tester.pumpAndSettle();

    expect(find.text('담당자 지정에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    expect(find.text('미지정 투두 1'), findsOneWidget);
    expect(find.text('2개'), findsOneWidget);
  });

  testWidgets('담당자 컨트롤의 탭 영역이 44px 이상이다', (tester) async {
    // 🔴 design.md §6·§9: 탭 가능한 요소의 실제 터치 영역은 최소 44×44.
    await pumpSheet(tester, todosOf(2));

    final control = find.ancestor(
      of: find.byIcon(Icons.unfold_more).first,
      matching: find.byType(GestureDetector),
    );

    expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
  });

  testWidgets('지정 중에도 행 높이가 그대로다', (tester) async {
    // 스피너가 20px 면 지정할 때마다 행이 튄다 — 컨트롤과 같은 높이 상자에 담았는지 본다.
    final gate = Completer<void>();
    await pumpSheet(tester, todosOf(2), onAssign: (_, _) => gate.future);

    // ⚠️ 제목 텍스트가 아니라 **카드 높이**를 잰다 — 제목 너비는 컨트롤이 좁아지면 늘어나는 게
    // 정상이고(첫 시도에 그걸 재서 헛돌았다), 우리가 막으려는 것은 **행 높이가 튀는 것**이다.
    final before = tester.getSize(find.byType(ListView)).height;
    await tester.tap(menuOfRow(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('철수'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
    // 시트가 닫히고(pop) _assign 이 시작돼 스피너가 뜬다. 스피너는 무한 애니메이션이라
    // pumpAndSettle 은 못 쓴다 — 팝 애니메이션 시간만큼 수동으로 넘긴다.
    await tester.pump(); // 팝 시작
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // 팝 완료 + await 해소 → busy
    await tester.pump(); // 스피너 프레임

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(ListView)).height, before);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('멤버 목록이 비어도 시트가 죽지 않는다', (tester) async {
    await pumpSheet(tester, todosOf(1), roomMembers: const []);

    await tester.tap(menuOfRow(0));
    await tester.pumpAndSettle();

    // 빈 멤버라도 담당자 선택 시트(헤더 + 완료)는 예외 없이 뜬다.
    expect(tester.takeException(), isNull);
    expect(find.text('담당자'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '완료'), findsOneWidget);
  });
}
