import 'package:app/design/empty_state.dart';
import 'package:app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('아이콘과 문구를 렌더한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.folder_outlined, message: '아직 폴더가 없어요'),
        ),
      ),
    );

    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.text('아직 폴더가 없어요'), findsOneWidget);
  });

  testWidgets('actionLabel이 없으면 버튼을 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.search_off_rounded,
            message: '검색 결과가 없어요',
          ),
        ),
      ),
    );

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('actionLabel이 있으면 primary 텍스트 버튼이 뜨고 탭 시 콜백된다', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.event_outlined,
            message: '일정이 없어요',
            actionLabel: '일정 추가하기',
            onAction: () => tapped++,
          ),
        ),
      ),
    );

    final button = find.widgetWithText(TextButton, '일정 추가하기');
    expect(button, findsOneWidget);
    // + 아이콘(add) 동반.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    // primary 전경색.
    final style = tester.widget<TextButton>(button).style;
    final fg = style?.foregroundColor?.resolve({});
    expect(fg, AppColors.primary);

    await tester.tap(button);
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('액션-only: 아이콘·문구 없이 버튼만 렌더한다(홈)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(actionLabel: '투두 추가하기', onAction: () {}),
        ),
      ),
    );

    expect(find.widgetWithText(TextButton, '투두 추가하기'), findsOneWidget);
    // 아이콘은 add(+)만 있고 라인 아이콘(40px)은 없다.
    expect(find.byType(Text), findsOneWidget); // 버튼 라벨뿐
  });

  testWidgets('문구-only: 아이콘·버튼 없이 문구만 렌더한다(일정탭)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EmptyState(message: '일정이 없어요')),
      ),
    );

    expect(find.text('일정이 없어요'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
