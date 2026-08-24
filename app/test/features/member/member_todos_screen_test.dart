import 'package:app/design/todo_checkbox.dart';
import 'package:app/design/tokens.dart';
import 'package:app/features/member/member_todos_screen.dart';
import 'package:app/features/settings/my_activity_card.dart';
import 'package:app/features/todos/todo_photo.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, _FakeMemberTodosApi api) async {
    // 프로필 행 + 캐릭터 카드 + 투두까지 한 화면에 담아 ListView 지연 생성으로
    // 투두 행이 트리에서 빠지지 않게 뷰포트를 넉넉히 잡는다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MemberTodosScreen(
          userId: 'member-1',
          roomId: 3,
          api: api,
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('프로필 행에 이름·완료율 문구·찌르기 버튼이 보인다', (tester) async {
    await pumpScreen(tester, _FakeMemberTodosApi());

    // 헤더 + 프로필 행 둘 다 이름만 노출.
    expect(find.text('준'), findsWidgets);
    expect(find.text('투두를 33% 완료했어요'), findsOneWidget); // 1/3 → 33%
    expect(find.text('찌르기'), findsOneWidget);
  });

  testWidgets('멤버 캐릭터 카드가 이름·캐릭터 데이터로 렌더된다', (tester) async {
    await pumpScreen(tester, _FakeMemberTodosApi());

    expect(find.text('요즘 준님은'), findsOneWidget);
    expect(find.text('미루기 장인'), findsOneWidget);
  });

  testWidgets('캐릭터 조회 실패해도 화면이 깨지지 않고 카드는 placeholder다', (tester) async {
    await pumpScreen(tester, _CharacterFailApi());

    // 카드는 placeholder(정체불명)로 남고, 투두 리스트는 정상 렌더된다.
    expect(find.text('정체불명'), findsOneWidget);
    expect(find.text('투 포인터 정리'), findsOneWidget);
  });

  testWidgets('사진이 첨부된 투두 행 아래에 썸네일이 보인다', (tester) async {
    // 2026-08-24 #65 — 멤버 행은 투두 탭 읽기 행과 동일 모양(specs/0006 :77③)이라 썸네일도 함께.
    await pumpScreen(tester, _FakeMemberTodosApi());

    expect(find.byKey(const ValueKey('todo-thumb-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-thumb-1')), findsNothing);
  });

  testWidgets('썸네일을 누르면 사진을 크게 볼 수 있다', (tester) async {
    // 2026-08-25 #65 — 읽기 전용 화면이라 보기만 된다.
    await pumpScreen(tester, _FakeMemberTodosApi());

    await tester.tap(find.byKey(const ValueKey('todo-thumb-3')));
    await tester.pumpAndSettle();

    expect(find.byType(TodoPhotoViewer), findsOneWidget);
  });

  testWidgets('읽기전용 — 체크 동그라미(TodoCheckbox)가 없다', (tester) async {
    await pumpScreen(tester, _FakeMemberTodosApi());

    // 체크 동그라미 없이 완료여부는 연한 색으로만 보인다.
    expect(find.byType(TodoCheckbox), findsNothing);
    // "읽기전용" pill·안내문구도 없다.
    expect(find.text('읽기전용'), findsNothing);
    expect(find.text('체크는 본인만 할 수 있어요'), findsNothing);
  });

  testWidgets('완료된 항목은 연한 색 + 엄청 연한 회색 취소선으로 표시된다', (tester) async {
    // 2026-08-09: 취소선을 다시 도입(홈·투두탭·멤버투두 공통). 색은 border-soft, 두께 1.
    await pumpScreen(tester, _FakeMemberTodosApi());

    final done = tester.widget<Text>(find.text('투 포인터 정리'));
    expect(done.style?.color, AppColors.completedTodo);
    expect(done.style?.decoration, TextDecoration.lineThrough);
    expect(done.style?.decorationColor, AppColors.borderSoft);
  });

  testWidgets('카테고리 헤더 셰브론을 탭하면 항목이 접힌다', (tester) async {
    await pumpScreen(tester, _FakeMemberTodosApi());

    expect(find.text('투 포인터 정리'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('member-category-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('투 포인터 정리'), findsNothing);
  });

  testWidgets('카테고리 없는 투두는 독립 ToDo가 아니라 기타로 표시된다', (tester) async {
    // 투두 탭(todos_screen.dart)·투두 추가 폼(todo_form_sheet.dart)은 "기타"로 통일됐지만
    // 이 화면만 리네임 작업 범위에서 빠져 "독립 ToDo"로 남아 있었다.
    await pumpScreen(tester, _FakeMemberTodosApi());

    expect(find.text('기타'), findsOneWidget);
    expect(find.text('독립 ToDo'), findsNothing);
  });

  testWidgets('재촉 CTA를 탭하면 poke가 전송되고 피드백을 준다', (tester) async {
    final api = _FakeMemberTodosApi();
    await pumpScreen(tester, api);

    await tester.tap(find.text('찌르기'));
    await tester.pumpAndSettle();

    expect(api.pokeCount, 1);
    expect(find.text('콕 찔렀어요'), findsOneWidget);
  });
}

class _FakeMemberTodosApi extends MemberTodosApi {
  int pokeCount = 0;

  @override
  Future<MemberTodosData> fetchMemberTodos(
    String idToken,
    int roomId,
    String userId,
  ) async {
    return MemberTodosData(
      memberName: '준',
      assignedTotal: 3,
      assignedDone: 1,
      categories: const {1: '알고리즘'},
      todos: [
        TodoItem(
          id: 1,
          title: '투 포인터 정리',
          detail: '보조 설명 줄',
          completed: true,
          categoryId: 1,
          assignees: const [],
        ),
        TodoItem(
          id: 2,
          title: 'DP 문제 풀기',
          completed: false,
          categoryId: 1,
          assignees: const [],
        ),
        TodoItem(
          id: 3,
          title: '독립 항목',
          completed: false,
          assignees: const [],
          // 2026-08-24 #65 — 행 썸네일 검증용. 스텁 HttpClient 400 → errorBuilder 폴백 렌더.
          imageUrl: 'https://storage.test/todo-3.jpg',
        ),
      ],
    );
  }

  @override
  Future<void> poke(String idToken, int roomId, String userId) async {
    pokeCount++;
  }

  @override
  Future<MyActivitySummary> fetchCharacter(
    String idToken,
    int roomId,
    String userId,
  ) async {
    return const MyActivitySummary(
      characterId: 'PROCRASTINATOR',
      characterName: '미루기 장인',
      characterQuote: '내일의 나를 믿는 타입',
      characterDetail: '몰아서 끝내고 있어요',
      deadlineKeptPercent: 50,
      bestStreakDays: 3,
      sharedCount: 1,
      completedCount: 1,
    );
  }
}

/// 캐릭터 조회만 실패하는 API(투두 등 나머지는 정상).
class _CharacterFailApi extends _FakeMemberTodosApi {
  @override
  Future<MyActivitySummary> fetchCharacter(
    String idToken,
    int roomId,
    String userId,
  ) async {
    throw StateError('boom');
  }
}
