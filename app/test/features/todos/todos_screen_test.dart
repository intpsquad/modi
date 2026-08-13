import 'dart:async';
import 'package:app/design/tokens.dart';
import 'package:app/design/theme.dart';
import 'package:app/design/todo_checkbox.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/shell/app_shell.dart';
import 'package:app/features/shell/tab_activation.dart';
import 'package:app/features/todos/ai_suggest_sheet.dart';
import 'package:app/features/todos/todo_form_sheet.dart';
import 'package:app/features/todos/todo_sync.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:app/features/todos/todos_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:app/features/todos/unassigned_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [
      {
        'id': 1,
        'name': '테스트방',
        'goal': '목표',
        'status': 'ACTIVE',
        'startDate': '2026-01-01',
        'endDate': '2026-12-31',
      },
    ];
  }
}

class _NoActiveRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [];
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.currentUserId});

  @override
  Future<String> getIdToken() async => 'fake-token';

  @override
  final String? currentUserId;
}

class _FakeTodosApi extends TodosApi {
  _FakeTodosApi({
    List<Category>? categories,
    List<TodoItem>? todos,
    List<MemberBrief>? members,
    this.throwOnFetch = false,
  }) : categories = categories ?? [],
       todos = todos ?? [],
       members = members ?? [];

  List<Category> categories;
  List<TodoItem> todos;
  List<MemberBrief> members;
  bool throwOnFetch;
  // 담당자 아닌 투두 완료 시도(서버 403, FR-39)를 흉내낸다.
  bool throwNotAssigneeOnComplete = false;
  int fetchCallCount = 0;
  final List<bool> completeCalls = [];
  final List<int> deleteCalls = [];
  bool throwOnDelete = false;
  final List<({int id, int? categoryId})> updateCalls = [];
  final List<int> deleteCategoryCalls = [];
  final List<String> createCategoryNames = [];
  final List<List<String>> createAssigneeCalls = [];
  final List<_TodoWrite> createDrafts = [];
  final List<_TodoWrite> updateDrafts = [];
  // S-17 미지정 처리가 부르는 경로 — "todoId:담당자들" 로 기록한다.
  final List<String> updateAssigneeCalls = [];

  // S-16-B AI 추천용. [aiCompleter]를 주입하면 응답을 붙잡아 로딩 프레임을 검증할 수 있다.
  List<TodoSuggestionCandidate> aiCandidates = [];
  bool throwOnAiSuggest = false;
  int aiSuggestCallCount = 0;
  Completer<List<TodoSuggestionCandidate>>? aiCompleter;

  @override
  Future<List<TodoSuggestionCandidate>> fetchAiSuggestions(
    String idToken,
    int roomId,
  ) async {
    aiSuggestCallCount++;
    if (throwOnAiSuggest) throw StateError('network');
    final completer = aiCompleter;
    if (completer != null) return completer.future;
    return aiCandidates;
  }

  @override
  Future<List<Category>> fetchCategories(String idToken, int roomId) async {
    fetchCallCount++;
    if (throwOnFetch) throw StateError('network');
    return categories;
  }

  @override
  Future<List<TodoItem>> fetchTodos(String idToken, int roomId) async {
    if (throwOnFetch) throw StateError('network');
    // [fetchGate]를 걸어두면 조회를 그 자리에 붙잡아, "재조회가 진행 중인 화면"을
    // 프레임 단위로 확인할 수 있다(스피너 대신 기존 목록이 남는지).
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return todos;
  }

  /// 완료시키기 전까지 fetchTodos 를 붙잡아 두는 게이트(테스트용).
  Completer<void>? fetchGate;

  @override
  Future<List<MemberBrief>> fetchMembers(String idToken, int roomId) async {
    if (throwOnFetch) throw StateError('network');
    return members;
  }

  @override
  Future<Category> createCategory(
    String idToken,
    int roomId,
    String name,
  ) async {
    createCategoryNames.add(name);
    final created = Category(id: categories.length + 1, name: name);
    categories = [...categories, created];
    return created;
  }

  @override
  Future<void> deleteCategory(
    String idToken,
    int roomId,
    int categoryId,
  ) async {
    deleteCategoryCalls.add(categoryId);
    categories = [
      for (final c in categories)
        if (c.id != categoryId) c,
    ];
    // 서버는 하위 투두의 category_id를 NULL로 만든다(ON DELETE SET NULL) — 기타로 남는다.
    todos = [
      for (final t in todos)
        if (t.categoryId == categoryId)
          TodoItem(
            id: t.id,
            title: t.title,
            detail: t.detail,
            completed: t.completed,
            assignees: t.assignees,
            dueDate: t.dueDate,
          )
        else
          t,
    ];
  }

  @override
  Future<TodoItem> createTodo(
    String idToken,
    int roomId, {
    required String title,
    String? detail,
    int? categoryId,
    List<String>? assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async {
    final resolved = assigneeUserIds ?? const <String>[];
    createAssigneeCalls.add(resolved);
    createDrafts.add((
      title: title,
      detail: detail,
      categoryId: categoryId,
      assigneeUserIds: resolved,
      dueDate: dueDate,
    ));
    final created = TodoItem(
      id: todos.length + 100,
      title: title,
      detail: detail,
      completed: false,
      categoryId: categoryId,
      assignees: [
        for (final id in resolved) MemberBrief(userId: id, nickname: id),
      ],
      dueDate: dueDate,
      imageUrl: imageUrl,
    );
    todos = [...todos, created];
    return created;
  }

  @override
  Future<String> uploadTodoImage(
    String idToken,
    int roomId, {
    required List<int> bytes,
  }) async => 'https://storage.test/todo-image';

  @override
  Future<void> setTodoCompleted(
    String idToken,
    int roomId,
    int todoId,
    bool completed,
  ) async {
    if (throwNotAssigneeOnComplete) {
      throw TodoNotAssigneeException();
    }
    completeCalls.add(completed);
    todos = [
      for (final t in todos)
        if (t.id == todoId) t.copyWith(completed: completed) else t,
    ];
  }

  @override
  Future<void> deleteTodo(String idToken, int roomId, int todoId) async {
    if (throwOnDelete) throw StateError('delete');
    deleteCalls.add(todoId);
    todos = todos.where((t) => t.id != todoId).toList();
  }

  /// S-17 미지정 처리가 담당자를 붙이는 경로. 실제 API 는 네트워크를 타므로 갈아끼운다.
  @override
  Future<TodoItem> updateTodo(
    String idToken,
    int roomId,
    int todoId, {
    required String title,
    String? detail,
    int? categoryId,
    List<String>? assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async {
    final resolved = assigneeUserIds ?? const <String>[];
    updateCalls.add((id: todoId, categoryId: categoryId));
    updateAssigneeCalls.add('$todoId:${resolved.join(",")}');
    updateDrafts.add((
      title: title,
      detail: detail,
      categoryId: categoryId,
      assigneeUserIds: resolved,
      dueDate: dueDate,
    ));
    final updated = TodoItem(
      id: todoId,
      title: title,
      detail: detail,
      // 완료 상태는 유지한다 — 담당자만 바꾸는 S-17 경로에서 완료가 풀리면 안 된다.
      completed: todos.firstWhere((t) => t.id == todoId).completed,
      categoryId: categoryId,
      assignees: [
        for (final id in resolved) MemberBrief(userId: id, nickname: id),
      ],
      dueDate: dueDate,
      imageUrl: imageUrl,
    );
    todos = [
      for (final t in todos)
        if (t.id == todoId) updated else t,
    ];
    return updated;
  }
}

/// 팩이 기록하는 생성/수정 요청 한 건. 2026-08-07 롤백으로 `TodoDraft`가 사라져 테스트 안에서만 쓰는
/// 레코드로 대체했다.
typedef _TodoWrite = ({
  String title,
  String? detail,
  int? categoryId,
  List<String> assigneeUserIds,
  DateTime? dueDate,
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 점선 원 = 투두 추가 바텀시트 직결(2026-08-07 롤백 — 인라인 작성기 경유 폐기).
  Future<void> openDirectAdd(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('add-todo-etc')));
    await tester.pumpAndSettle();
  }

  // AI 추천 = 하단 플로팅 'AI로 생성하기' 버튼 → AI 시트(직접추가와 분리).
  Future<void> openAiSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai-generate-fab')));
    await tester.pumpAndSettle();
  }

  /// **체크 원**을 눌러 완료를 토글한다(2026-08-05 개정: 체크는 체크 원에서만 된다).
  /// 더블탭이 없어져 탭은 즉시 실행되지만, 완료는 2초 뒤에 서버로 나간다 —
  /// [settleCommit]이 false 면 그 대기 상태에서 멈춰 "화면은 체크됐지만 아직 안 보냄"을 본다.
  /// pumpAndSettle 은 예약된 프레임만 기다려 2초 타이머를 넘기지 못하므로 직접 시간을 보낸다.
  Future<void> tapCheckbox(
    WidgetTester tester,
    int todoId, {
    bool settleCommit = true,
  }) async {
    await tester.tap(find.byKey(ValueKey('todo-checkbox-$todoId')));
    await tester.pumpAndSettle();
    if (settleCommit) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
  }

  /// 행을 왼쪽으로 [dx]만큼 스와이프한다. 드래그 도중 pump가 반드시 필요하다 —
  /// 액션 폭을 넘어선 다음 프레임에서 DismissiblePane이 마운트되며 그때 비로소
  /// `controller.isDismissibleReady`가 참이 되고, 그 상태로 손을 떼야 "끝까지 당겨 삭제"가 된다.
  /// (pump 없이 tester.drag만 쓰면 액션 패널만 열린 채로 끝난다.)
  Future<void> swipeLeft(
    WidgetTester tester,
    Finder finder, {
    double dx = 500,
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(Offset(-dx / 2, 0));
    await tester.pump();
    await gesture.moveBy(Offset(-dx / 2, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 미지정 투두 제목은 **시트와 뒤쪽 목록에 동시에** 있다(기타 섹션에도 그 투두가 있으므로).
  /// 시트 안으로 범위를 좁혀야 무엇을 눌렀는지가 분명해진다.
  Finder inSheet(String text) => find.descendant(
    of: find.byType(UnassignedSheet),
    matching: find.text(text),
  );

  testWidgets('카테고리별로 투두가 그룹핑되어 보인다', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 1,
          title: '투두A',
          completed: false,
          categoryId: 1,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('개발'), findsOneWidget);
    expect(find.text('투두A'), findsOneWidget);
  });

  testWidgets('카테고리 없는 투두는 기타 섹션에 보인다', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 2,
          title: '독립 투두',
          completed: false,
          categoryId: null,
          assignees: [],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기타'), findsOneWidget);
    expect(find.text('독립 투두'), findsOneWidget);
  });

  testWidgets('담당자 없는 투두가 있으면 미지정 배너가 보인다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 3,
          title: '미지정 투두',
          completed: false,
          categoryId: null,
          assignees: [],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unassigned-banner')), findsOneWidget);
    // 문구는 미지정 개수를 포함한다(2026-08-09). 미지정 1개 fixture.
    expect(find.text('주인 없는 투두 1개가 있어요!🥹'), findsOneWidget);
  });

  testWidgets('미지정 배너를 누르면 S-17 시트가 실제로 뜬다', (tester) async {
    // 🔴 **이 테스트가 없어서 화면이 깨진 채로 dev 에 들어갔다**(2026-08-04). 위 테스트는 배너가
    // *보이는지*만 봤고 *누르는* 테스트가 없어서, 시트가 레이아웃 예외로 빈 채 뜨는 것을 아무도
    // 못 봤다. 게다가 이 파일은 `MaterialApp` 을 **테마 없이** 띄우고 있었다 — 원인이었던
    // `outlinedButtonTheme.minimumSize`(무한 너비)는 테마가 없으면 재현되지 않는다.
    final fakeApi = _FakeTodosApi(
      members: [MemberBrief(userId: 'u1', nickname: '철수')],
      todos: [
        for (var i = 1; i <= 3; i++)
          TodoItem(
            id: i,
            title: '미지정 투두 $i',
            completed: false,
            categoryId: null,
            assignees: const [],
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light, // ⚠️ 테마 없이는 이 버그가 재현되지 않는다
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('unassigned-banner')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('담당자 미지정'), findsOneWidget);
    expect(find.text('3개'), findsOneWidget);
    expect(inSheet('미지정 투두 1'), findsOneWidget);
    expect(inSheet('미지정'), findsNWidgets(3));
  });

  testWidgets('시트에서 담당자를 고르면 즉시 나가고, 다 처리하면 시트가 스스로 닫힌다', (tester) async {
    final fakeApi = _FakeTodosApi(
      members: [MemberBrief(userId: 'u1', nickname: '철수')],
      todos: [
        for (var i = 1; i <= 2; i++)
          TodoItem(
            id: i,
            title: '미지정 투두 $i',
            completed: false,
            categoryId: null,
            assignees: const [],
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('unassigned-banner')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      // 행의 `미지정 ⌃⌄` 를 누르면 담당자 선택 바텀시트가 뜬다(2026-08-09).
      await tester.tap(find.byIcon(Icons.unfold_more).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('철수'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
      await tester.pumpAndSettle();
    }

    // 한 건씩 처리한다 — 시트에서 담당자를 골라 완료할 때마다 그 투두가 나간다.
    expect(fakeApi.updateAssigneeCalls, ['1:u1', '2:u1']);
    // 전부 처리되면 닫기 버튼 없이 스스로 닫히고, 배너도 사라진다.
    expect(find.text('담당자 미지정'), findsNothing);
    expect(find.textContaining('담당자 없는 투두'), findsNothing);
  });

  /// `PUT`은 전체 교체다 — 담당자만 지정하는 S-17 경로가 `dueDate`를 다시 실어 보내지 않으면
  /// 저장돼 있던 마감일이 조용히 지워진다. 마감일은 협업 캐릭터가 쓰는 유일한 신호라
  /// (specs/0006-투두-탭.md 2026-08-07 절) 회귀하면 티가 안 나면서 아프다.
  testWidgets('S-17 담당자 지정은 저장된 마감일을 지우지 않는다', (tester) async {
    final due = DateTime(2026, 9, 30);
    final fakeApi = _FakeTodosApi(
      members: [MemberBrief(userId: 'u1', nickname: '철수')],
      todos: [
        TodoItem(
          id: 1,
          title: '미지정 투두',
          completed: false,
          assignees: const [],
          dueDate: due,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('unassigned-banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.unfold_more).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('철수'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
    await tester.pumpAndSettle();

    expect(fakeApi.updateDrafts.single.assigneeUserIds, ['u1']);
    expect(fakeApi.updateDrafts.single.dueDate, due);
  });

  /// 위와 같은 이유로 카테고리 이동(드래그 드롭)도 마감일을 보존해야 한다.
  testWidgets('카테고리 이동은 저장된 마감일을 지우지 않는다', (tester) async {
    final due = DateTime(2026, 9, 30);
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 7, name: '기획')],
      members: [MemberBrief(userId: 'me', nickname: '나')],
      todos: [
        TodoItem(
          id: 1,
          title: '옮길 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'me', nickname: '나')],
          dueDate: due,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<TodosScreenState>(find.byType(TodosScreen));
    await state.debugMoveTodoAcross(fakeApi.todos.single, 7);
    await tester.pumpAndSettle();

    expect(fakeApi.updateCalls.single.categoryId, 7);
    expect(fakeApi.updateDrafts.single.dueDate, due);
  });

  testWidgets('모두 담당자가 있으면 미지정 배너가 보이지 않는다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 4,
          title: '할당됨',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unassigned-banner')), findsNothing);
  });

  testWidgets('체크박스를 탭하면 완료 처리되고 연한 색으로 인라인 표시된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '토글 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsNothing);

    await tapCheckbox(tester, 5);

    expect(fakeApi.completeCalls, [true]);
    // done 탭 폐기(0006 개정) — 완료 항목은 같은 목록에 연한 색으로 인라인 표시된다.
    final title = tester.widget<Text>(find.text('토글 투두'));
    expect(title.style?.color, AppColors.completedTodo);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('담당자 아닌 투두 완료 시 담당자 전용 안내 문구가 뜨고 토글이 롤백된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '남의 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'other', nickname: '영희')],
        ),
      ],
    )..throwNotAssigneeOnComplete = true;

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapCheckbox(tester, 5);

    // FR-39: 일반 실패 문구가 아니라 담당자 전용 안내가 보여야 한다.
    expect(find.text(TodoNotAssigneeException.defaultMessage), findsOneWidget);
    expect(find.text('완료 처리에 실패했어요. 다시 시도해 주세요'), findsNothing);
    // 낙관적 토글은 롤백되어 완료 표시(체크)가 남지 않는다.
    expect(find.byIcon(Icons.check), findsNothing);
    final title = tester.widget<Text>(find.text('남의 투두'));
    expect(title.style?.color, isNot(AppColors.completedTodo));
  });

  // FR-39 사전 비활성화(2026-08-08): 담당자가 있고 내가 담당이 아닌 투두는 눌러본 뒤
  // 403 롤백이 아니라 처음부터 회색 비활성 체크박스로 완료 불가를 드러낸다.
  testWidgets('담당자가 있는 남의 투두는 체크박스가 비활성이고 탭해도 완료되지 않는다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '남의 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'other', nickname: '영희')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 남의 투두는 "전체보기"에서만 보인다("내 투두만"은 애초에 걸러진다).
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();

    final cb = tester.widget<TodoCheckbox>(
      find.byKey(const ValueKey('todo-checkbox-5')),
    );
    expect(cb.enabled, isFalse, reason: '담당자가 있고 내가 담당이 아니면 비활성');

    await tapCheckbox(tester, 5);
    expect(
      fakeApi.completeCalls,
      isEmpty,
      reason: '비활성 체크박스 탭은 완료 API를 호출하지 않는다',
    );
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('전체보기에서 읽기전용(남의) 투두 행은 흐리게, 내 투두는 선명하게 표시된다', (tester) async {
    // 2026-08-09: 내가 담당이 아닌 투두는 opacity로 은은하게 낮춰 "내 것=선명"을 드러낸다.
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '남의 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'other', nickname: '영희')],
        ),
        TodoItem(
          id: 6,
          title: '내 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'me', nickname: '나')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();

    // 읽기전용 행만 dimming Opacity(<1)로 감싼다 — 내 행엔 그런 래퍼가 없다(=선명).
    double? dimOpacity(int id) {
      final dims = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byKey(ValueKey('todo-checkbox-$id')),
              matching: find.byType(Opacity),
            ),
          )
          .where((o) => o.opacity < 1);
      return dims.isEmpty ? null : dims.first.opacity;
    }

    expect(dimOpacity(5), 0.55, reason: '남의(읽기전용) 투두는 흐리게');
    expect(dimOpacity(6), isNull, reason: '내 투두는 선명(흐림 래퍼 없음)');
  });

  testWidgets('내가 담당인 투두는 체크박스가 활성이라 완료된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 6,
          title: '내 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'me', nickname: '나')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cb = tester.widget<TodoCheckbox>(
      find.byKey(const ValueKey('todo-checkbox-6')),
    );
    expect(cb.enabled, isTrue, reason: '내가 담당이면 활성');

    await tapCheckbox(tester, 6);
    expect(fakeApi.completeCalls, [true]);
  });

  testWidgets('더보기 메뉴 > 카테고리 관리 > 카테고리 추가로도 생성한다', (tester) async {
    final fakeApi = _FakeTodosApi(categories: [Category(id: 1, name: '개발')]);

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카테고리 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카테고리 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '기획');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(fakeApi.createCategoryNames, ['기획']);
  });

  testWidgets('카테고리도 투두도 없어도 기타 섹션과 점선 추가가 보인다', (tester) async {
    final fakeApi = _FakeTodosApi();

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // PRD §1: 빈 상태에서도 "기타" 섹션과 점선 추가 어포던스는 항상 노출된다.
    expect(find.text('기타'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-todo-etc')), findsOneWidget);
    // 1번박스는 텍스트 없이 점선 원만 — "할 일 추가" 라벨은 제거됐다(요청 1번박스 4).
    expect(find.text('할 일 추가'), findsNothing);
  });

  // 2026-08-07 롤백: 점선 원은 인라인 작성기가 아니라 투두 추가 바텀시트를 바로 연다.
  // 위치·태그·중요표시·사진은 폐기됐고 마감일만 남았다(협업 캐릭터가 쓰기 때문).
  testWidgets('점선 추가는 폼 시트를 열고 마감일까지 담아 생성한다', (tester) async {
    final fakeApi = _FakeTodosApi(
      members: [
        MemberBrief(userId: 'me', nickname: '나'),
        MemberBrief(userId: 'member-2', nickname: '모디'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-todo-etc')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-form-submit')), findsOneWidget);
    // 걷어낸 인라인 작성기의 잔재가 남아 있지 않은지 확인한다.
    expect(find.byKey(const ValueKey('todo-inline-composer')), findsNothing);
    expect(find.text('기존 입력 방식'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('todo-form-title')),
      '회의 준비',
    );
    await tester.enterText(
      find.byKey(const ValueKey('todo-form-detail')),
      '자료까지 챙기기',
    );
    // 마감일: 행 → 피커 → "내일".
    await tester.ensureVisible(find.text('마감일'));
    await tester.tap(find.text('마감일'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();
    // 담당자: 행 → 피커 → "모디" → 완료.
    await tester.ensureVisible(find.text('담당자'));
    await tester.tap(find.text('담당자'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모디').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
    await tester.pumpAndSettle();

    expect(fakeApi.createDrafts, hasLength(1));
    expect(fakeApi.createDrafts.single.title, '회의 준비');
    expect(fakeApi.createDrafts.single.detail, '자료까지 챙기기');
    final tomorrow = DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(days: 1));
    expect(fakeApi.createDrafts.single.dueDate, tomorrow);
    expect(fakeApi.createDrafts.single.assigneeUserIds, ['member-2']);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeTodosApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('투두를 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('담당자가 4명이면 3명만 표시되고 +1 뱃지가 보인다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 6,
          title: '담당자 많은 투두',
          completed: false,
          categoryId: null,
          assignees: [
            MemberBrief(userId: 'u1', nickname: '가'),
            MemberBrief(userId: 'u2', nickname: '나'),
            MemberBrief(userId: 'u3', nickname: '다'),
            MemberBrief(userId: 'u4', nickname: '라'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('진행 중인 방이 없으면 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: _FakeTodosApi(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중인 방이 없어요'), findsOneWidget);
  });

  testWidgets('기본값은 [내 투두만]이며 [전체보기]로 전환하면 남의 투두도 보인다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 7,
          title: '내 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'me', nickname: '나')],
        ),
        TodoItem(
          id: 8,
          title: '남의 투두',
          completed: false,
          categoryId: null,
          assignees: [MemberBrief(userId: 'other', nickname: '남')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 투두'), findsOneWidget);
    expect(find.text('남의 투두'), findsNothing);

    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();

    expect(find.text('내 투두'), findsOneWidget);
    expect(find.text('남의 투두'), findsOneWidget);
  });

  testWidgets('카테고리 헤더의 화살표를 탭하면 하위 투두가 접히고 다시 탭하면 펼쳐진다', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 9,
          title: '펼침 투두',
          completed: false,
          categoryId: 1,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('펼침 투두'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-toggle-1')));
    await tester.pumpAndSettle();

    expect(find.text('펼침 투두'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('category-toggle-1')));
    await tester.pumpAndSettle();

    expect(find.text('펼침 투두'), findsOneWidget);
  });

  testWidgets('점선 추가로 담당자 없이 저장하면 미지정 투두로 남는다', (tester) async {
    final fakeApi = _FakeTodosApi();

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // chooser 없이 점선 어포던스 → 투두 추가 폼 직결.
    await openDirectAdd(tester);
    await tester.enterText(find.byType(TextField).first, '담당자 없는 투두');
    await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
    await tester.pumpAndSettle();

    // 본인 자동 지정하지 않는다(2026-08-10) — 미선택이면 빈 담당자로 생성해 미지정으로 남긴다.
    expect(fakeApi.createAssigneeCalls, [<String>[]]);
  });

  // ---- S-16-B AI추천추가 (specs/0006-투두-탭.md 개정분) ----

  Future<_FakeTodosApi> pumpAndOpenAiSheet(
    WidgetTester tester,
    _FakeTodosApi fakeApi,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openAiSheet(tester);
    return fakeApi;
  }

  testWidgets('점선 추가는 폼 직결, AI 버튼은 AI 시트를 연다', (tester) async {
    final fakeApi = _FakeTodosApi();

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 점선 어포던스 → chooser 없이 투두 추가 폼이 바로 뜬다.
    await openDirectAdd(tester);
    expect(find.byKey(const ValueKey('todo-form-submit')), findsOneWidget);
    expect(find.text('직접추가'), findsNothing);
    expect(find.text('AI추천추가'), findsNothing);

    // 폼을 닫고 AI 플로팅 버튼 → AI 시트.
    await tester.tapAt(const Offset(20, 20)); // 바깥 탭으로 시트 닫기
    await tester.pumpAndSettle();
    await openAiSheet(tester);
    expect(find.text('AI 추천'), findsOneWidget);
  });

  testWidgets('AI추천추가는 로딩 문구를 거쳐 후보 목록을 보여준다', (tester) async {
    final fakeApi = _FakeTodosApi()
      ..aiCompleter = Completer<List<TodoSuggestionCandidate>>();

    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(currentUserId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-generate-fab')));
    // 응답이 붙잡혀 있는 동안 — design.md §6 지정 로딩 문구가 보인다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('목표를 분석해 투두를 추천하고 있어요'), findsOneWidget);

    fakeApi.aiCompleter!.complete([
      TodoSuggestionCandidate(title: '숙소 예약하기', category: null),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('숙소 예약하기'), findsOneWidget);
    expect(find.text('목표를 분석해 투두를 추천하고 있어요'), findsNothing);
  });

  testWidgets('후보를 추가하면 담당자 미지정으로 생성되고 시트는 유지된다', (tester) async {
    final fakeApi = _FakeTodosApi()
      ..aiCandidates = [
        TodoSuggestionCandidate(title: '숙소 예약하기', category: null),
        TodoSuggestionCandidate(title: '렌터카 비교하기', category: null),
      ];
    await pumpAndOpenAiSheet(tester, fakeApi);

    await tester.tap(find.widgetWithText(OutlinedButton, '추가').first);
    await tester.pumpAndSettle();

    // 직접추가와 달리 본인 자동 지정이 없다 — 미지정([])으로 생성.
    expect(fakeApi.createAssigneeCalls, [<String>[]]);
    // 추가 후 버튼은 '취소'로 바뀐다(2026-08-09 — 시트에서 바로 되돌리기).
    expect(find.text('취소'), findsOneWidget);
    // 시트는 열린 채 유지 — 나머지 후보를 이어서 채택할 수 있다(0003 개정).
    expect(find.text('AI 추천'), findsOneWidget);
    expect(find.text('렌터카 비교하기'), findsOneWidget);

    // 닫으면 목록이 갱신돼 미지정 배너가 나타난다.
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unassigned-banner')), findsOneWidget);
  });

  testWidgets('후보가 많아도 AI 추천 시트가 상태바를 덮지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    // 상태바 48px을 흉내낸다 — 수정 전에는 후보가 많을 때 시트가 y=0까지 자라
    // 이 영역을 덮었다.
    tester.view.viewPadding = const FakeViewPadding(top: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    final fakeApi = _FakeTodosApi()
      ..aiCandidates = List.generate(
        20,
        (i) => TodoSuggestionCandidate(title: '추천 투두 $i', category: null),
      );
    await pumpAndOpenAiSheet(tester, fakeApi);

    expect(tester.takeException(), isNull);
    expect(find.text('추천 투두 0'), findsOneWidget);
    expect(
      tester.getRect(find.byType(AiSuggestSheet)).top,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('AI 후보를 채택하면 카테고리 미지정(기타)으로 생성된다', (tester) async {
    // 🔴 . AI 가 카테고리를 정하지 않는다 — 분류는 사용자가 편집에서 한다.
    //
    // ⚠️ **서버가 값을 보내도 무시해야 한다.** 배포 순서상 옛 AI 서버가 한동안 `category` 를
    // 계속 보낸다. 그래서 **값을 채워서** 넣고, 카테고리를 만들지도 붙이지도 않는 것을 본다.
    // 원래 여기 있던 두 테스트(중복 생성 방지 · 기존 id 매칭)는 그 경로가 사라져 함께 지웠다.
    final fakeApi = _FakeTodosApi(categories: [Category(id: 7, name: '개발')])
      ..aiCandidates = [
        TodoSuggestionCandidate(title: 'API 명세 정리', category: '개발'),
        TodoSuggestionCandidate(title: '흑돼지 맛집 예약', category: '맛집'),
      ];
    await pumpAndOpenAiSheet(tester, fakeApi);

    // "(새 카테고리)" 라벨은 AI 시트에만 있던 것이라 사라져야 한다.
    // (후보 행에 카테고리를 아예 안 그리는 것은 `ai_suggest_sheet_test.dart` 가 따로 본다 —
    //  여기서 `find.text('개발')` 로 보면 시트 **뒤** 투두 목록의 섹션 헤더에 걸린다.)
    expect(find.textContaining('새 카테고리'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, '추가').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '추가').first);
    await tester.pumpAndSettle();

    expect(fakeApi.createCategoryNames, isEmpty, reason: '카테고리를 새로 만들면 안 된다');
    expect(
      fakeApi.todos.map((t) => t.categoryId),
      everyElement(isNull),
      reason: '기존 카테고리 id 에도 붙이면 안 된다 — 전부 기타로 간다',
    );
  });

  testWidgets('추천 로드 실패 시 다시 시도 버튼으로 재호출한다', (tester) async {
    final fakeApi = _FakeTodosApi()..throwOnAiSuggest = true;
    await pumpAndOpenAiSheet(tester, fakeApi);

    expect(find.text('추천을 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.aiSuggestCallCount, 1);

    fakeApi
      ..throwOnAiSuggest = false
      ..aiCandidates = [
        TodoSuggestionCandidate(title: '숙소 예약하기', category: null),
      ];
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.aiSuggestCallCount, 2);
    expect(find.text('숙소 예약하기'), findsOneWidget);
  });

  testWidgets('후보가 하나도 없으면 빈 상태 문구를 보여준다', (tester) async {
    final fakeApi = _FakeTodosApi(); // aiCandidates 기본값 []
    await pumpAndOpenAiSheet(tester, fakeApi);

    expect(find.text('추천할 투두를 찾지 못했어요'), findsOneWidget);
    expect(find.text('추천을 불러오지 못했어요'), findsNothing);
  });

  testWidgets('빈 상태 부제목이 원인을 단정하지 않는다', (tester) async {
    // ⚠️ 빈 결과의 원인은 둘이다 — 자료가 없거나, 이미 추천한 것과 겹치거나.
    // 시트는 어느 쪽인지 모른다(자료 개수가 안 들어온다). 원래 문구는 자료 탓만 해서,
    // 제외 창이 차서 빈 결과가 났을 때 **풀리지 않는 행동**을 시켰다.
    final fakeApi = _FakeTodosApi(); // aiCandidates 기본값 []
    await pumpAndOpenAiSheet(tester, fakeApi);

    expect(find.text('자료를 더 담거나, 잠시 후 다시 시도해 주세요'), findsOneWidget);
    expect(
      find.text('아카이브에 자료를 담으면 더 잘 추천할 수 있어요'),
      findsNothing,
      reason: '자료 탓만 하는 옛 문구 — 제외 창이 원인일 때 틀린 행동을 유도한다',
    );
  });

  // ---- 리디자인: 더보기 메뉴 / 완료 토글 / 정렬 / 일괄선택 ----

  Future<void> pumpTodos(
    WidgetTester tester,
    _FakeTodosApi fakeApi, {
    TabActivation? tabActivation,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
          // 전역 인스턴스를 쓰면 테스트끼리 신호가 새므로 테스트마다 새로 만든다.
          tabActivation:
              tabActivation ?? TabActivation(index: AppShell.todosIndex),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openOverflow(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('todo-overflow-menu')));
    await tester.pumpAndSettle();
  }
  // ---- 세그먼트 탭 규격 (2026-08-06 지정, design.md §6) ----

  group('세그먼트 탭', () {
    /// 트랙 = '내 투두만' 텍스트를 감싸는 가장 바깥 탭 컨테이너.
    Finder trackFinder() => find.byKey(const ValueKey('segmented-track'));
    Finder thumbFinder() => find.byKey(const ValueKey('segmented-thumb'));

    Color textColor(WidgetTester tester, String label) => tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color!;

    testWidgets('트랙은 높이 40 · pill · surface-soft다', (tester) async {
      await pumpTodos(tester, _FakeTodosApi());

      final rect = tester.getRect(trackFinder());
      expect(rect.height, 40);

      final decoration =
          tester.widget<Container>(trackFinder()).decoration as BoxDecoration;
      expect(decoration.color, AppColors.surfaceSoft);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.pill));
    });

    testWidgets('선택 칸은 primary 알약 + 흰 글씨, 비선택은 투명 + muted다', (tester) async {
      await pumpTodos(tester, _FakeTodosApi());

      final track = tester.getRect(trackFinder());
      final thumb = tester.getRect(thumbFinder());
      final decoration =
          tester.widget<Container>(thumbFinder()).decoration as BoxDecoration;

      expect(decoration.color, AppColors.primary);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.pill));
      expect(thumb.width, closeTo(track.width / 2, 0.5), reason: '2칸이므로 절반');
      expect(thumb.height, 40, reason: '트랙 높이를 꽉 채운다');
      expect(thumb.left, closeTo(track.left, 0.5), reason: '기본은 왼쪽 칸');

      expect(textColor(tester, '내 투두만'), AppColors.onPrimary);
      expect(textColor(tester, '전체보기'), AppColors.muted);
    });

    testWidgets('탭을 바꾸면 알약이 좌우로 미끄러진다', (tester) async {
      await pumpTodos(tester, _FakeTodosApi());
      final track = tester.getRect(trackFinder());
      final startLeft = tester.getRect(thumbFinder()).left;

      await tester.tap(find.text('전체보기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      final midLeft = tester.getRect(thumbFinder()).left;
      expect(
        midLeft,
        greaterThan(startLeft + 1),
        reason: '제자리에서 색만 바뀌면(칸별 배경) 여기서 걸린다',
      );
      expect(
        midLeft,
        lessThan(track.left + track.width / 2 - 1),
        reason: '이동 중',
      );

      await tester.pumpAndSettle();
      expect(
        tester.getRect(thumbFinder()).left,
        closeTo(track.left + track.width / 2, 0.5),
        reason: '오른쪽 칸에 정확히 앉는다',
      );
    });

    testWidgets('탭을 바꾸면 글씨색이 서서히 바뀐다', (tester) async {
      await pumpTodos(tester, _FakeTodosApi());

      await tester.tap(find.text('전체보기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      final mid = textColor(tester, '전체보기');
      expect(mid, isNot(AppColors.muted), reason: '이미 변하기 시작했다');
      expect(mid, isNot(AppColors.onPrimary), reason: '아직 다 변하지 않았다');

      await tester.pumpAndSettle();
      expect(textColor(tester, '전체보기'), AppColors.onPrimary);
      expect(textColor(tester, '내 투두만'), AppColors.muted);
    });
  });

  testWidgets('카테고리를 접으면 투두 목록이 높이 0으로 줄어들며 사라진다', (tester) async {
    // 2026-08-05 요청: "카테고리 열고 닫을 때 투두 리스트 내려오고 올라가는 애니메이션".
    // 기본 정렬이 수동이라 사용자가 보는 것은 flat(ReorderableListView) 경로다 —
    // 거기서는 접는 순간 행이 그냥 사라졌다.
    await pumpTodos(
      tester,
      _FakeTodosApi(
        categories: [Category(id: 1, name: '개발')],
        todos: [
          TodoItem(
            id: 1,
            title: '접힐투두',
            completed: false,
            categoryId: 1,
            assignees: [],
          ),
        ],
      ),
    );

    final box = find.byKey(const ValueKey('flat-collapse-todo-1'));
    final fullHeight = tester.getRect(box).height;
    expect(fullHeight, greaterThan(0));

    await tester.tap(find.text('개발'));
    await tester.pump(); // 접힘 시작
    await tester.pump(const Duration(milliseconds: 80));

    final mid = tester.getRect(box).height;
    expect(mid, lessThan(fullHeight), reason: '줄어드는 중');
    expect(mid, greaterThan(0), reason: '즉시 사라지지 않는다');

    await tester.pumpAndSettle();
    expect(tester.getRect(box).height, 0);

    // 다시 펼치면 높이가 되돌아온다.
    await tester.tap(find.text('개발'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final reopening = tester.getRect(box).height;
    expect(reopening, greaterThan(0));
    expect(reopening, lessThan(fullHeight), reason: '펼치는 중');

    await tester.pumpAndSettle();
    expect(tester.getRect(box).height, fullHeight);
  });

  testWidgets('항목 선택 모드로 들어가도 헤더 높이가 그대로다', (tester) async {
    // 2026-08-05 요청: "항목선택 눌렀을 때 헤더 높이 기존 높이로 (눌러도 레이아웃
    // 위아래 이동 안되게)". 기존엔 일반 헤더(패딩 16/12 + 24px 제목)와 선택 바의
    // 높이가 달라 목록이 위아래로 튀었다.
    await pumpTodos(
      tester,
      _FakeTodosApi(
        todos: [
          TodoItem(id: 1, title: '기준투두', completed: false, assignees: []),
        ],
      ),
    );

    final headerBefore = tester.getRect(
      find.byKey(const ValueKey('todo-top-bar')),
    );
    final rowBefore = tester.getRect(find.text('기준투두'));

    await openOverflow(tester);
    await tester.tap(find.text('항목 선택'));
    await tester.pumpAndSettle();

    final headerAfter = tester.getRect(
      find.byKey(const ValueKey('todo-top-bar')),
    );
    expect(headerAfter.height, headerBefore.height, reason: '헤더 높이가 같다');
    expect(
      tester.getRect(find.text('기준투두')).top,
      rowBefore.top,
      reason: '아래 목록이 위아래로 움직이지 않는다',
    );
  });

  testWidgets('더보기 메뉴에 4개 항목이 보인다', (tester) async {
    await pumpTodos(
      tester,
      _FakeTodosApi(categories: [Category(id: 1, name: '개발')]),
    );

    await openOverflow(tester);

    expect(find.text('항목 선택'), findsOneWidget);
    expect(find.text('카테고리 관리'), findsOneWidget);
    expect(find.text('완료된 항목 보기'), findsOneWidget);
    expect(find.text('정렬'), findsOneWidget);
  });

  testWidgets('완료된 항목 보기를 끄면 완료 투두가 숨겨진다', (tester) async {
    await pumpTodos(
      tester,
      _FakeTodosApi(
        todos: [
          TodoItem(id: 1, title: '미완료', completed: false, assignees: []),
          TodoItem(id: 2, title: '완료됨', completed: true, assignees: []),
        ],
      ),
    );

    expect(find.text('완료됨'), findsOneWidget);

    await openOverflow(tester);
    await tester.tap(find.text('완료된 항목 보기'));
    await tester.pumpAndSettle();

    expect(find.text('완료됨'), findsNothing);
    expect(find.text('미완료'), findsOneWidget);
  });

  testWidgets('정렬을 제목순으로 바꾸면 제목 오름차순으로 배치된다', (tester) async {
    await pumpTodos(
      tester,
      _FakeTodosApi(
        todos: [
          TodoItem(id: 1, title: '나중', completed: false, assignees: []),
          TodoItem(id: 2, title: '가장먼저', completed: false, assignees: []),
        ],
      ),
    );

    await openOverflow(tester);
    await tester.tap(find.text('정렬'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sort-option-title')));
    await tester.pumpAndSettle();

    final firstDy = tester.getTopLeft(find.text('가장먼저')).dy;
    final secondDy = tester.getTopLeft(find.text('나중')).dy;
    expect(firstDy, lessThan(secondDy));
  });

  testWidgets('전체보기에서는 수동 정렬을 고를 수 없다', (tester) async {
    // 2026-08-05 요청: "투두 전체보기에서는 수동정렬 없애자 (날짜랑 그런거만 남김)".
    await pumpTodos(
      tester,
      _FakeTodosApi(
        todos: [TodoItem(id: 1, title: '가', completed: false, assignees: [])],
      ),
    );

    // "내 투두만"에서는 세 가지 다 있다.
    await openOverflow(tester);
    await tester.tap(find.text('정렬'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sort-option-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('sort-option-created')), findsOneWidget);
    expect(find.byKey(const ValueKey('sort-option-title')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sort-option-manual')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();

    await openOverflow(tester);
    await tester.tap(find.text('정렬'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sort-option-manual')),
      findsNothing,
      reason: '전체보기에는 수동 정렬이 없다',
    );
    expect(find.byKey(const ValueKey('sort-option-created')), findsOneWidget);
    expect(find.byKey(const ValueKey('sort-option-title')), findsOneWidget);
    // 수동이 걸려 있던 상태이므로 생성일이 적용된 것으로 표시된다.
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('sort-option-created')))
          .trailing,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('sort-option-created')));
    await tester.pumpAndSettle();
  });

  testWidgets('일괄선택에서 항목을 골라 완료처리하면 서버에 반영된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '항목1', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await openOverflow(tester);
    await tester.tap(find.text('항목 선택'));
    await tester.pumpAndSettle();
    expect(find.text('0개 선택'), findsOneWidget);

    await tester.tap(find.text('항목1'));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);

    await tester.tap(find.text('완료처리'));
    await tester.pumpAndSettle();

    expect(fakeApi.completeCalls, [true]);
  });

  testWidgets('일괄선택에서 삭제하면 확인 모달 후 삭제된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '삭제대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await openOverflow(tester);
    await tester.tap(find.text('항목 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제대상'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('삭제')); // 선택 툴바 삭제
    await tester.pumpAndSettle();
    expect(find.text('1개 항목을 삭제할까요?'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('삭제')),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, [1]);
  });

  // ---- 홈↔투두 실시간 반영 ----

  testWidgets('외부 TodoSync 신호가 오면 투두 목록을 다시 불러온다', (tester) async {
    final sync = TodoSync();
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 1,
          title: 'A',
          completed: false,
          categoryId: 1,
          assignees: [],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
          todoSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = fakeApi.fetchCallCount;
    sync.markChanged(); // 홈 등 다른 화면이 완료를 바꾼 상황
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, before + 1); // 리로드됨
  });

  testWidgets('투두 탭에서 완료 토글해도 자기 리로드는 하지 않는다(낙관적만)', (tester) async {
    final sync = TodoSync();
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '토글', completed: false, assignees: [])],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodosScreen(
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
          todoSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = fakeApi.fetchCallCount;
    await tapCheckbox(tester, 5);

    expect(fakeApi.completeCalls, [true]);
    expect(fakeApi.fetchCallCount, before); // 자기 신호엔 리로드 안 함
  });

  // ---- 행 제스처(2026-08-05 개정): 체크 원=완료 / 그 밖=인라인 수정 / 더블탭 없음 ----

  testWidgets('제목을 탭하면 시트 없이 인라인 편집으로 바뀐다', (tester) async {
    // 2026-08-09: 제목 탭 = 그 자리 인라인 수정(바텀시트 아님). 상세 시트는 information으로만.
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '수정대상',
          completed: false,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await tester.tap(find.text('수정대상'));
    await tester.pumpAndSettle();

    // 시트가 아니라 인라인 TextField(제목 프리필)로 바뀐다.
    expect(find.byType(TodoFormSheet), findsNothing);
    final field = find.byType(TextField);
    expect(field, findsWidgets);
    expect(tester.widget<TextField>(field.first).controller?.text, '수정대상');
    expect(fakeApi.completeCalls, isEmpty, reason: '제목 탭은 체크가 아니다');
  });

  testWidgets('편집 중 information 아이콘을 누르면 상세 바텀시트가 열린다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '짧음', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    // 평소엔 information 없음.
    expect(find.byKey(const ValueKey('todo-info-5')), findsNothing);

    await tester.tap(find.text('짧음')); // 편집 진입
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo-info-5')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-info-5')));
    await tester.pumpAndSettle();
    expect(find.byType(TodoFormSheet), findsOneWidget);
    expect(fakeApi.completeCalls, isEmpty);
  });

  testWidgets('제목을 고친 뒤 information을 누르면 한 번만 저장되고 상세 시트가 열린다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '옛제목', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await tester.tap(find.text('옛제목'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '고친제목');
    await tester.tap(find.byKey(const ValueKey('todo-info-5')));
    await tester.pumpAndSettle();

    // 저장은 정확히 1회(포커스 상실 + information 경로가 겹쳐도 이중 저장 없음).
    expect(fakeApi.updateDrafts.length, 1);
    expect(fakeApi.updateDrafts.single.title, '고친제목');
    // 상세 시트는 저장된 최신 값으로 열린다.
    expect(find.byType(TodoFormSheet), findsOneWidget);
  });

  testWidgets('체크 원을 탭하면 편집 없이 완료만 토글된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '체크대상',
          completed: false,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await tapCheckbox(tester, 5);

    expect(fakeApi.completeCalls, [true]);
    expect(find.byType(TextField), findsNothing, reason: '체크 원 탭은 편집이 아니다');
  });

  testWidgets('제목을 고쳐 바깥을 탭하면 저장되고(updateTodo) 편집이 닫힌다', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 3, name: '개발')],
      todos: [
        TodoItem(
          id: 5,
          title: '옛제목',
          detail: '옛메모',
          completed: false,
          categoryId: 3,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
          dueDate: DateTime(2026, 9, 1),
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await tester.tap(find.text('옛제목'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '새제목');
    // 바깥(앱바 영역) 탭 → 포커스 해제 → 저장.
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    final draft = fakeApi.updateDrafts.single;
    expect(draft.title, '새제목');
    expect(draft.detail, '옛메모', reason: '메모는 그대로');
    expect(draft.categoryId, 3, reason: 'PUT 전체교체 — 카테고리 보존');
    expect(draft.dueDate, DateTime(2026, 9, 1), reason: '마감일 보존');
    expect(draft.assigneeUserIds, ['u1'], reason: '담당자 보존');
    expect(find.byType(TextField), findsNothing, reason: '저장 후 편집 종료');
  });

  testWidgets('메모가 있으면 제목 아래 13/muted로 보이고 탭하면 메모 편집으로 들어간다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '제목',
          detail: '메모내용',
          completed: false,
          assignees: [],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    final memo = tester.widget<Text>(find.text('메모내용'));
    expect(memo.style?.fontSize, 13);
    expect(memo.style?.color, AppColors.muted);

    await tester.tap(find.text('메모내용'));
    await tester.pumpAndSettle();
    // 편집 진입 → 제목/메모 두 TextField(메모 없던 투두도 빈 메모칸이 뜬다).
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('왼쪽으로 스와이프하면 즉시 삭제된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '스와이프삭제',
          completed: false,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    // 끝까지 당기면 버튼을 거치지 않고 그대로 삭제(DismissiblePane).
    await swipeLeft(tester, find.text('스와이프삭제'));

    expect(fakeApi.deleteCalls, [5]);
    expect(find.text('스와이프삭제'), findsNothing);
  });

  // ---- 스와이프 액션: [삭제]만 50×28 / 한 번에 하나만 (2026-08-05 개정) ----

  testWidgets('살짝 스와이프하면 [삭제]만 50×28로 드러난다(수정 버튼 없음)', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '액션대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('액션대상'), dx: 200);

    final delete = find.byKey(const ValueKey('todo-delete-5'));
    expect(delete, findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo-edit-5')),
      findsNothing,
      reason: '수정은 행 탭으로 옮겼다',
    );

    // 시각 크기는 50×28, 오른쪽 끝은 전역 좌우 여백(20)에 정렬.
    final box = find.descendant(of: delete, matching: find.byType(Container));
    expect(tester.getSize(box), const Size(50, 28));
    expect(tester.getTopRight(box).dx, 800 - 20);
    // 히트박스는 행 높이 전체(44) — design.md §6 최소 탭 영역 44.
    expect(tester.getSize(delete).height, 44);
    // 행(투두 박스)과 버튼 사이 4px.
    final row = tester.getRect(find.byKey(const ValueKey('todo-press-5')));
    expect(tester.getTopLeft(box).dx - row.right, 4);
  });

  testWidgets('스와이프 버튼은 시각 박스(28) 밖 행 높이 안을 눌러도 동작한다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '히트박스', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('히트박스'), dx: 200);
    final delete = find.byKey(const ValueKey('todo-delete-5'));
    // 시각 박스 위쪽 6px(= 28박스 밖, 44 히트박스 안)을 탭한다.
    await tester.tapAt(tester.getCenter(delete) - const Offset(0, 18));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, [5]);
  });

  testWidgets('끝까지 당기면 삭제 배경이 좌우로 넓어지고 그대로 삭제된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '늘어남대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    final row = tester.getRect(find.byKey(const ValueKey('todo-press-5')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('늘어남대상')),
    );
    // 액션 폭(54)만 넘긴 지점 — 아직 버튼 모양.
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    // 삭제 확정 구간까지 끌면 버튼 대신 '배경이 넓어진' 버전이 나온다.
    await gesture.moveBy(const Offset(-400, 0));
    await tester.pump();

    final stretched = find.descendant(
      of: find.byType(Slidable),
      matching: find.text('삭제'),
    );
    expect(stretched, findsOneWidget);
    final background = tester.getRect(
      find.ancestor(of: stretched, matching: find.byType(Container)).first,
    );
    expect(
      background.width,
      greaterThan(200),
      reason: '고정 50이 아니라 당긴 만큼 좌우로 넓어진다',
    );
    expect(background.height, 28, reason: '배경만 넓어진다 — 높이는 그대로');
    expect(background.right, row.right, reason: '행 오른쪽 끝에 맞춰 늘어난다');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(fakeApi.deleteCalls, [5]);
    expect(find.text('늘어남대상'), findsNothing);
  });

  testWidgets('스와이프 [삭제]를 누르면 삭제된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '삭제할것', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('삭제할것'), dx: 200);
    await tester.tap(find.byKey(const ValueKey('todo-delete-5')));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, [5]);
    expect(find.text('삭제할것'), findsNothing);
  });

  testWidgets('액션은 하나만 열린다 — 다른 항목을 스와이프하면 먼저 열린 것이 닫힌다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(id: 5, title: '첫째', completed: false, assignees: []),
        TodoItem(id: 6, title: '둘째', completed: false, assignees: []),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('첫째'), dx: 200);
    expect(find.byKey(const ValueKey('todo-delete-5')), findsOneWidget);

    await swipeLeft(tester, find.text('둘째'), dx: 200);

    expect(find.byKey(const ValueKey('todo-delete-6')), findsOneWidget);
    // 먼저 열려 있던 첫째는 되돌아간다(액션 패널이 사라진다).
    expect(find.byKey(const ValueKey('todo-delete-5')), findsNothing);
  });

  testWidgets('액션이 열린 상태에서 다른 항목을 탭하면 닫히고 그 항목의 완료 토글도 실행된다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(id: 5, title: '열린것', completed: false, assignees: []),
        TodoItem(id: 6, title: '탭할것', completed: false, assignees: []),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('열린것'), dx: 200);
    expect(find.byKey(const ValueKey('todo-delete-5')), findsOneWidget);

    await tapCheckbox(tester, 6);

    // 열린 액션은 닫히고(되돌아가고), 탭한 동작(완료 토글)은 그대로 실행된다(사용자 확정).
    expect(find.byKey(const ValueKey('todo-delete-5')), findsNothing);
    expect(fakeApi.completeCalls, [true]);
    expect(
      tester.widget<Text>(find.text('탭할것')).style?.color,
      AppColors.completedTodo,
    );
  });

  testWidgets('카테고리 헤더는 스와이프하면 [삭제]만 나오고 확인 모달을 거친다', (tester) async {
    final fakeApi = _FakeTodosApi(categories: [Category(id: 1, name: '개발')]);
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('개발'), dx: 200);

    expect(find.byKey(const ValueKey('category-delete-1')), findsOneWidget);
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('category-delete-1')),
          matching: find.byType(Container),
        ),
      ),
      const Size(50, 28),
    );
    // 카테고리엔 수정 버튼이 없다(이름 수정은 롱프레스 메뉴 유지).
    expect(find.byKey(const ValueKey('category-edit-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('category-delete-1')));
    await tester.pumpAndSettle();
    expect(find.text('카테고리를 삭제할까요?'), findsOneWidget);
    expect(fakeApi.deleteCategoryCalls, isEmpty); // 확정 전엔 삭제 안 함

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('삭제')),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCategoryCalls, [1]);
  });

  testWidgets('카테고리는 끝까지 당겨도 삭제되지 않는다(확인 모달을 반드시 거친다)', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 5,
          title: '살아있어야함',
          completed: false,
          categoryId: 1,
          assignees: [],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    // 투두는 이 거리에서 즉시 삭제되지만(DismissiblePane), 카테고리는 그러면 안 된다.
    await swipeLeft(tester, find.text('개발'));

    expect(fakeApi.deleteCategoryCalls, isEmpty);
    expect(find.text('개발'), findsOneWidget);
    expect(find.text('살아있어야함'), findsOneWidget);
    // 액션만 열려 있다.
    expect(find.byKey(const ValueKey('category-delete-1')), findsOneWidget);
  });

  testWidgets('카테고리 삭제 확인 모달에서 취소하면 아무 일도 없다', (tester) async {
    final fakeApi = _FakeTodosApi(categories: [Category(id: 1, name: '개발')]);
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('개발'), dx: 200);
    await tester.tap(find.byKey(const ValueKey('category-delete-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('취소')),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCategoryCalls, isEmpty);
    expect(find.text('개발'), findsOneWidget);
  });

  testWidgets('"기타" 헤더와 일괄선택 모드에는 스와이프 액션이 없다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '기타투두', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    // 기타는 실제 카테고리가 아니라 삭제 액션이 없다.
    await swipeLeft(tester, find.text('기타'), dx: 200);
    expect(find.byKey(const ValueKey('category-delete-etc')), findsNothing);
    expect(find.text('삭제'), findsNothing);

    // 일괄선택 모드에서는 투두 행도 스와이프되지 않는다.
    await openOverflow(tester);
    await tester.tap(find.text('항목 선택'));
    await tester.pumpAndSettle();
    await swipeLeft(tester, find.text('기타투두'), dx: 200);

    expect(find.byKey(const ValueKey('todo-delete-5')), findsNothing);
    expect(find.byKey(const ValueKey('todo-edit-5')), findsNothing);
    expect(fakeApi.deleteCalls, isEmpty);
  });

  testWidgets('스크롤을 시작하면 열려 있던 액션이 닫힌다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        for (var i = 1; i <= 20; i++)
          TodoItem(id: i, title: '항목$i', completed: false, assignees: []),
      ],
    );
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('항목1'), dx: 200);
    expect(find.byKey(const ValueKey('todo-delete-1')), findsOneWidget);

    await tester.drag(find.text('항목3'), const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-delete-1')), findsNothing);
  });

  // ---- 레이아웃: 카테고리 > 투두 높이, 행 박스 좌우 20 여백 (QA 요청) ----

  testWidgets('카테고리 헤더가 투두 행보다 높다', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 5,
          title: '높이비교',
          completed: false,
          categoryId: 1,
          assignees: [],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    final headerH = tester
        .getSize(find.byKey(const ValueKey('category-toggle-1')))
        .height;
    final rowH = tester
        .getSize(find.byKey(const ValueKey('todo-press-5')))
        .height;
    expect(headerH, greaterThan(rowH));
  });

  testWidgets('행 박스는 좌우 20px 여백을 남긴다(눌림 색이 화면 끝까지 번지지 않게)', (tester) async {
    final fakeApi = _FakeTodosApi(
      categories: [Category(id: 1, name: '개발')],
      todos: [
        TodoItem(
          id: 5,
          title: '여백확인',
          completed: false,
          categoryId: 1,
          assignees: [],
        ),
      ],
    );
    await pumpTodos(tester, fakeApi);

    final row = tester.getRect(find.byKey(const ValueKey('todo-press-5')));
    expect(row.left, 20);
    expect(row.right, 800 - 20);

    final header = tester.getRect(
      find.byKey(const ValueKey('category-toggle-1')),
    );
    expect(header.left, 20);
    expect(header.right, 800 - 20);
  });

  // (2026-08-09) 읽기모드 행의 눌림 배경(_PressableBox)은 인라인 편집 도입으로 제거됨 —
  // 제목/메모만 탭 대상이고 나머지 여백은 무반응. "슬라이드 중 배경색" 테스트는 그 전제가
  // 사라져 삭제했다.

  // ---- 완료 체크는 2초 뒤에 서버로 나간다 (요청 3) ----

  testWidgets('체크하면 화면은 바로 체크되지만 서버 반영은 2초 뒤다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '지연대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await tapCheckbox(tester, 5, settleCommit: false);

    // 화면은 즉시 체크(연한 색)되지만 아직 서버로 가지 않았다.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('지연대상')).style?.color,
      AppColors.completedTodo,
    );
    expect(fakeApi.completeCalls, isEmpty, reason: '2초 전에는 보내지 않는다');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(fakeApi.completeCalls, [true]);
  });

  testWidgets('2초 안에 다시 누르면 취소되어 서버로 아무것도 가지 않는다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '취소대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    await tapCheckbox(tester, 5, settleCommit: false);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // 마음이 바뀌어 다시 누른다.
    await tapCheckbox(tester, 5, settleCommit: false);
    expect(find.byIcon(Icons.check), findsNothing, reason: '체크가 풀린다');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(fakeApi.completeCalls, isEmpty, reason: '취소했으므로 끝까지 보내지 않는다');
  });

  testWidgets('완료된 항목 보기가 꺼져 있어도 2초 동안은 행이 남아 되돌릴 수 있다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '숨김대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    // 더보기 > 완료된 항목 보기 → 끄기.
    await openOverflow(tester);
    await tester.tap(find.text('완료된 항목 보기'));
    await tester.pumpAndSettle();

    await tapCheckbox(tester, 5, settleCommit: false);
    expect(
      find.text('숨김대상'),
      findsOneWidget,
      reason: '바로 걸러버리면 다시 눌러 취소할 대상이 없어진다(홈과 동일하게 남긴다)',
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(fakeApi.completeCalls, [true]);
    expect(find.text('숨김대상'), findsNothing, reason: '반영된 뒤에야 숨긴다');
  });

  testWidgets('2초가 지나기 전에 탭을 옮기면 즉시 서버에 반영된다', (tester) async {
    final tabs = TabActivation(index: AppShell.todosIndex);
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 5, title: '이탈대상', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi, tabActivation: tabs);

    await tapCheckbox(tester, 5, settleCommit: false);
    expect(fakeApi.completeCalls, isEmpty);

    tabs.index = AppShell.homeIndex; // 다른 탭으로 이동
    await tester.pumpAndSettle();

    expect(fakeApi.completeCalls, [
      true,
    ], reason: '대기 중인 체크는 화면을 떠날 때 즉시 보낸다(사용자 확정)');
  });

  // ---- 탭을 다시 켜면 조용히 새로고침한다 (요청 1) ----

  testWidgets('투두 탭이 다시 켜지면 스피너 없이 최신 목록으로 갱신된다', (tester) async {
    final tabs = TabActivation(index: AppShell.todosIndex);
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '처음것', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi, tabActivation: tabs);
    final afterFirstLoad = fakeApi.fetchCallCount;

    // 다른 탭으로 갔다가 돌아온다. 그동안 서버 쪽 목록이 바뀌어 있다고 가정.
    tabs.index = AppShell.homeIndex;
    await tester.pump();
    expect(fakeApi.fetchCallCount, afterFirstLoad, reason: '다른 탭에선 조회하지 않는다');

    fakeApi.todos = [
      TodoItem(id: 2, title: '다른데서추가된것', completed: false, assignees: []),
    ];
    tabs.index = AppShell.todosIndex;
    await tester.pump();
    expect(find.text('투두를 불러오고 있어요'), findsNothing, reason: '조용히 갱신한다');

    await tester.pumpAndSettle();
    expect(fakeApi.fetchCallCount, greaterThan(afterFirstLoad));
    expect(find.text('다른데서추가된것'), findsOneWidget);
    expect(find.text('처음것'), findsNothing);
  });

  testWidgets('탭을 다시 켜면 재조회가 끝날 때까지 이전 목록을 그대로 보여준다', (tester) async {
    // 2026-08-05 요청: "로딩중 안 뜨면 좋겠으니까 이전 데이터 먼저 보여주고 새로 불러와줘".
    final tabs = TabActivation(index: AppShell.todosIndex);
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '이전데이터', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi, tabActivation: tabs);
    expect(find.text('이전데이터'), findsOneWidget);

    tabs.index = AppShell.homeIndex;
    await tester.pumpAndSettle();

    // 돌아올 때의 재조회를 붙잡아 세운다 — 응답이 오기 전 프레임을 검사하려고.
    fakeApi.fetchGate = Completer<void>();
    fakeApi.todos = [
      TodoItem(id: 2, title: '새데이터', completed: false, assignees: []),
    ];
    tabs.index = AppShell.todosIndex;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 조회가 도는 동안: 스피너도 빈 화면도 아니고 **이전 데이터**가 보인다.
    expect(find.text('투두를 불러오고 있어요'), findsNothing);
    expect(find.text('이전데이터'), findsOneWidget, reason: '캐시된 이전 목록을 먼저 보여준다');
    expect(find.text('새데이터'), findsNothing);

    fakeApi.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('새데이터'), findsOneWidget);
    expect(find.text('이전데이터'), findsNothing);
  });

  // ---- 재조회 중에도 화면을 유지한다 (요청 6) ----

  testWidgets('두 번째 로드부터는 전체 스피너 대신 기존 목록을 유지한다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '남아있을것', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);
    expect(find.text('남아있을것'), findsOneWidget);

    // 투두를 추가하면 저장 후 목록을 다시 부른다 — 그 재조회를 붙잡아 세운다.
    fakeApi.fetchGate = Completer<void>();
    await openDirectAdd(tester);
    await tester.enterText(find.byType(TextField).first, '나중에나타날것');
    await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
    await tester.pump(); // 저장 → 시트 닫힘 → 재조회 시작
    await tester.pump(const Duration(milliseconds: 400)); // 시트 닫힘 애니메이션

    // 조회가 도는 동안에도 화면은 그대로 — 스피너로 갈아끼우지 않는다.
    expect(
      find.text('투두를 불러오고 있어요'),
      findsNothing,
      reason: '두 번째 로드부터는 전체 스피너로 화면을 비우지 않는다',
    );
    expect(find.text('남아있을것'), findsOneWidget);
    expect(find.text('나중에나타날것'), findsNothing);

    // 응답이 오면 그때 목록만 갈아끼운다("띵 하고 하나 더 나타나는" 동작).
    fakeApi.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('나중에나타날것'), findsOneWidget);
  });

  // ---- 성능: 저장 없이 닫으면 리로드하지 않는다 (PRD §7) ----

  testWidgets('투두 추가 시트를 저장 없이 닫으면 리로드하지 않는다', (tester) async {
    final fakeApi = _FakeTodosApi();
    await pumpTodos(tester, fakeApi);

    final before = fakeApi.fetchCallCount;
    await openDirectAdd(tester);
    expect(find.byKey(const ValueKey('todo-form-submit')), findsOneWidget);

    await tester.tapAt(const Offset(20, 20)); // 바깥 탭으로 닫기(저장 안 함)
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, before); // 재조회 없음
  });

  // ---- 폼: 카테고리 옵션 '기타' (PRD §6-1) ----

  testWidgets('투두 추가 폼의 카테고리 옵션은 독립ToDo가 아니라 기타로 표시된다', (tester) async {
    final fakeApi = _FakeTodosApi();
    await pumpTodos(tester, fakeApi);

    await openDirectAdd(tester);

    expect(find.text('독립 ToDo'), findsNothing);
    // 카테고리 행의 기본값이 '기타'로 표시된다(피커로 리디자인, 2026-08-08).
    // 배경 목록의 '기타' 그룹 헤더와 겹치므로 시트 안으로 범위를 좁힌다.
    expect(
      find.descendant(
        of: find.byType(TodoFormSheet),
        matching: find.text('기타'),
      ),
      findsOneWidget,
    );
  });

  // ---- 수동 정렬: 저장된 순서가 적용된다 (PRD §3-1, 기기 로컬 영속) ----

  testWidgets('저장된 수동 순서대로 투두가 배치된다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'todo_manual_order_1': ['20', '10'],
    });
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(id: 10, title: '먼저생성', completed: false, assignees: []),
        TodoItem(id: 20, title: '나중생성', completed: false, assignees: []),
      ],
    );
    await pumpTodos(tester, fakeApi);

    // 저장 순서 [20, 10] → '나중생성'(20)이 '먼저생성'(10)보다 위에 온다.
    final dy20 = tester.getTopLeft(find.text('나중생성')).dy;
    final dy10 = tester.getTopLeft(find.text('먼저생성')).dy;
    expect(dy20, lessThan(dy10));
  });

  testWidgets('스와이프 삭제가 서버에서 실패하면 항목이 복원되고 에러가 뜬다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [
        TodoItem(
          id: 5,
          title: '삭제실패',
          completed: false,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      ],
    )..throwOnDelete = true;
    await pumpTodos(tester, fakeApi);

    await swipeLeft(tester, find.text('삭제실패'));

    // 낙관적 제거 후 서버 실패 → 복원 + 인라인 에러.
    expect(find.text('삭제실패'), findsOneWidget);
    expect(find.text('삭제에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
  });

  // ---- 구분선: 그룹 "사이"에만 (마지막 그룹 아래엔 없음) ----

  testWidgets('구분선은 그룹 사이에만 그려진다(그룹 N개 → N-1개, 기타 아래엔 없음)', (tester) async {
    // 개발/기획 + 기타 = 그룹 3개 → 구분선 2개.
    await pumpTodos(
      tester,
      _FakeTodosApi(
        categories: [
          Category(id: 1, name: '개발'),
          Category(id: 2, name: '기획'),
        ],
      ),
    );

    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('기타 헤더를 탭하면 기타 하위 목록이 접힌다', (tester) async {
    final fakeApi = _FakeTodosApi(
      todos: [TodoItem(id: 1, title: '기타투두', completed: false, assignees: [])],
    );
    await pumpTodos(tester, fakeApi);

    expect(find.text('기타투두'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-toggle-etc')));
    await tester.pumpAndSettle();

    expect(find.text('기타투두'), findsNothing);
  });

  // ---- 드래그 재정렬 핵심 계산(순수 함수) — 결정적 검증 (PRD §3) ----
  // ReorderableListView 드래그 시뮬레이션은 불안정하므로, 드롭 위치→카테고리 판정과
  // 새 순서 계산 로직을 순수 함수 computeFlatReorder로 분리해 여기서 직접 검증한다.

  // 개발(1)/기획(2)/기타(null) 3섹션에 개발 아래 투두 하나(id5)만 있는 flat 배치.
  List<({String kind, int? categoryId, int? todoId})> sampleFlat() => [
    (kind: 'header', categoryId: 1, todoId: null),
    (kind: 'todo', categoryId: 1, todoId: 5),
    (kind: 'add', categoryId: 1, todoId: null),
    (kind: 'header', categoryId: 2, todoId: null),
    (kind: 'add', categoryId: 2, todoId: null),
    (kind: 'header', categoryId: null, todoId: null),
    (kind: 'add', categoryId: null, todoId: null),
  ];

  test('computeFlatReorder: 다른 카테고리 헤더 아래로 옮기면 그 카테고리로 판정된다', () {
    // 제거 후 header(2)는 index2 → 그 아래(index3)로 삽입.
    final r = computeFlatReorder(sampleFlat(), 1, 3);
    expect(r.targetCategoryId, 2);
    expect(r.visibleOrder, [5]);
  });

  test('computeFlatReorder: 기타(null) 헤더 아래로 옮기면 카테고리가 null이 된다', () {
    // 제거 후 header(null)은 index4 → 그 아래(index5)로 삽입.
    final r = computeFlatReorder(sampleFlat(), 1, 5);
    expect(r.targetCategoryId, isNull);
    expect(r.visibleOrder, [5]);
  });

  test('computeFlatReorder: 같은 카테고리 내 재정렬은 카테고리를 유지하고 순서만 바꾼다', () {
    final items = [
      (kind: 'header', categoryId: 1, todoId: null),
      (kind: 'todo', categoryId: 1, todoId: 5),
      (kind: 'todo', categoryId: 1, todoId: 6),
      (kind: 'add', categoryId: 1, todoId: null),
    ];
    // id5를 id6 아래로: 제거 후 todo6은 index1 → index2로 삽입.
    final r = computeFlatReorder(items, 1, 2);
    expect(r.targetCategoryId, 1);
    expect(r.visibleOrder, [6, 5]);
  });

  test('computeFlatReorder: 맨 위 카테고리 헤더 위로는 못 올라간다', () {
    // 첫 헤더 위(newIndex 0)로 드롭해도 첫 카테고리(1) 아래로 클램프된다(요청 화면전체 5).
    final r = computeFlatReorder(sampleFlat(), 1, 0);
    expect(r.targetCategoryId, 1);
    expect(r.visibleOrder, [5]);
  });

  test('computeFlatReorder: 맨 밑 "할 일 추가" 아래로는 못 내려간다', () {
    // 끝(추가행 아래, newIndex 큰 값)으로 드롭해도 마지막 섹션(기타) 안·추가행 위로 클램프된다(요청 화면전체 4).
    final r = computeFlatReorder(sampleFlat(), 1, 99);
    expect(r.targetCategoryId, isNull);
    expect(r.visibleOrder, [5]);
  });
}
