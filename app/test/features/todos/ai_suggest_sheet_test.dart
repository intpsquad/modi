import 'package:app/design/theme.dart';
import 'package:app/features/todos/ai_suggest_sheet.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 앱 테마를 반드시 적용한다 — outlinedButtonTheme의 minimumSize(무한 너비)가
  // Row 안의 [추가] 버튼과 충돌하는 레이아웃 버그는 테마 없이는 재현되지 않는다.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<List<TodoSuggestionCandidate>> Function() onFetch,
    Future<int> Function(TodoSuggestionCandidate)? onAdopt,
    Future<void> Function(int)? onCancelAdopt,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AiSuggestSheet(
            topPadding: 0,
            onFetch: onFetch,
            onAdopt: onAdopt ?? (_) async => 1,
            onCancelAdopt: onCancelAdopt ?? (_) async {},
          ),
        ),
      ),
    );
  }

  testWidgets('후보가 오면 행마다 제목과 [추가] 버튼이 레이아웃 예외 없이 렌더링된다', (tester) async {
    await pumpSheet(
      tester,
      onFetch: () async => [
        TodoSuggestionCandidate(title: '후보 A', sourceItemId: 1),
        TodoSuggestionCandidate(title: '후보 B', sourceItemId: 2),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('후보 A'), findsOneWidget);
    expect(find.text('후보 B'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '추가'), findsNWidgets(2));
  });

  testWidgets('카테고리는 후보 행에 표시하지 않는다', (tester) async {
    // AI 가 카테고리를 정하지 않는다. 채택하면 기타(미분류)로 들어간다.
    // ⚠️ 서버가 옛 버전이라 값을 계속 보내는 동안에도 화면에는 안 나와야 한다 —
    // 그래서 **값을 채워서** 넣고 안 보이는 것을 확인한다.
    await pumpSheet(
      tester,
      onFetch: () async => [
        TodoSuggestionCandidate(
          title: '후보 A',
          category: '시험전략',
          sourceItemId: 1,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('후보 A'), findsOneWidget);
    expect(find.text('시험전략'), findsNothing);
    expect(find.textContaining('새 카테고리'), findsNothing);
  });

  testWidgets('showModalBottomSheet가 top padding을 지워도(removeTop) 상태바를 넘지 않는다', (
    tester,
  ) async {
    // showModalBottomSheet(useSafeArea:false, 기본값)는 시트 내부 컨텍스트의 top padding을
    // MediaQuery.removePadding(removeTop:true)로 0으로 만든다(bottom_sheet.dart). 시트가
    // context에서 다시 top padding을 읽으면 항상 0이 나와 상한이 무효화된다 — 실제로 이
    // 버그가 있었다(2026-08-10 QA 신고, 재발). topPadding은 호출부(todos_screen.dart)가
    // removePadding 되기 전 컨텍스트에서 미리 읽어 넘겨야 하고, 여기서 그 계약을 검증한다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const topPadding = 100.0;
    final manyCandidates = List.generate(
      30,
      (i) => TodoSuggestionCandidate(title: '후보 $i', sourceItemId: i),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AiSuggestSheet(
                  topPadding: topPadding,
                  onFetch: () async => manyCandidates,
                  onAdopt: (_) async => 1,
                  onCancelAdopt: (_) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final topLeft = tester.getTopLeft(find.byType(AiSuggestSheet));
    expect(topLeft.dy, greaterThanOrEqualTo(topPadding - 0.5));
  });

  testWidgets('추가하면 [추가]가 [취소]로 바뀌고, 취소하면 다시 [추가]로 돌아온다', (tester) async {
    final adopted = <String>[];
    final canceled = <int>[];
    await pumpSheet(
      tester,
      onFetch: () async => [
        TodoSuggestionCandidate(title: '후보 A', sourceItemId: 1),
      ],
      onAdopt: (c) async {
        adopted.add(c.title);
        return 7; // 생성된 투두 id
      },
      onCancelAdopt: (id) async => canceled.add(id),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '추가'));
    await tester.pumpAndSettle();
    expect(adopted, ['후보 A']);
    expect(find.text('취소'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '추가'), findsNothing);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(canceled, [7], reason: '취소는 방금 만든 투두(id 7)를 삭제한다');
    expect(find.widgetWithText(OutlinedButton, '추가'), findsOneWidget);
  });
}
