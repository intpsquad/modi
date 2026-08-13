import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/todos/todo_detail_screen.dart';
import 'package:app/features/todos/todos_api.dart';
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

class _FakeAuthService extends AuthService {
  @override
  Future<String> getIdToken() async => 'fake-token';
}

class _FakeTodosApi extends TodosApi {
  _FakeTodosApi({this.todo, this.fetchError, this.updateError});

  TodoItem? todo;
  Object? fetchError;
  Object? updateError;
  final List<TodoItem> updated = [];

  @override
  Future<TodoItem> fetchTodo(String idToken, int roomId, int todoId) async {
    if (fetchError != null) throw fetchError!;
    return todo!;
  }

  @override
  Future<List<Category>> fetchCategories(String idToken, int roomId) async {
    return [Category(id: 7, name: '기획')];
  }

  @override
  Future<List<MemberBrief>> fetchMembers(String idToken, int roomId) async {
    return [
      MemberBrief(userId: 'u1', nickname: '철수'),
      MemberBrief(userId: 'u2', nickname: '영희'),
    ];
  }

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
    if (updateError != null) throw updateError!;
    final result = TodoItem(
      id: todoId,
      title: title,
      detail: detail,
      completed: false,
      categoryId: categoryId,
      assignees: (assigneeUserIds ?? const [])
          .map((id) => MemberBrief(userId: id, nickname: id))
          .toList(),
      dueDate: dueDate,
      imageUrl: imageUrl,
    );
    updated.add(result);
    return result;
  }

  @override
  Future<String> uploadTodoImage(
    String idToken,
    int roomId, {
    required List<int> bytes,
  }) async => 'https://storage.test/todo-image';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    _FakeTodosApi fakeApi, {
    int todoId = 5,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodoDetailScreen(
          todoId: todoId,
          api: fakeApi,
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          authService: _FakeAuthService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TodoDetailScreen', () {
    testWidgets('서버 최신값으로 제목·내용·카테고리·담당자가 채워진다', (tester) async {
      final fakeApi = _FakeTodosApi(
        todo: TodoItem(
          id: 5,
          title: '회의 자료 정리',
          detail: '회의 전에 공유해요',
          completed: false,
          categoryId: 7,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      );

      await pumpDetail(tester, fakeApi);

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('todo-form-title')))
            .controller!
            .text,
        '회의 자료 정리',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('todo-form-detail')))
            .controller!
            .text,
        '회의 전에 공유해요',
      );
    });

    testWidgets('저장하면 updateTodo가 전체 필드로 호출되고 화면이 뒤로 돌아간다', (tester) async {
      final fakeApi = _FakeTodosApi(
        todo: TodoItem(
          id: 5,
          title: '원래 제목',
          completed: false,
          categoryId: 7,
          assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) => TodoDetailScreen(
                todoId: 5,
                api: fakeApi,
                roomSession: RoomSession(roomApi: _FakeRoomApi()),
                authService: _FakeAuthService(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('todo-form-title')),
        '수정된 제목',
      );
      await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
      await tester.pumpAndSettle();

      final saved = fakeApi.updated.single;
      expect(saved.title, '수정된 제목');
      expect(saved.categoryId, 7);
      expect(saved.assignees.map((a) => a.userId), ['u1']);
      expect(
        find.byType(TodoDetailScreen),
        findsNothing,
        reason: '저장 후 뒤로 돌아간다',
      );
    });

    testWidgets('저장이 실패하면 화면에 남아 인라인 에러를 보여준다', (tester) async {
      final fakeApi = _FakeTodosApi(
        todo: TodoItem(
          id: 5,
          title: '원래 제목',
          completed: false,
          assignees: const [],
        ),
        updateError: StateError('저장 실패'),
      );

      await pumpDetail(tester, fakeApi);

      await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
      await tester.pumpAndSettle();

      expect(fakeApi.updated, isEmpty);
      expect(
        find.byType(TodoDetailScreen),
        findsOneWidget,
        reason: '실패하면 화면에 남는다',
      );
    });

    // specs/0006-투두-탭.md: 삭제는 목록 행 좌측 스와이프가 유일한 경로다.
    // "기존 입력 방식"은 2026-08-07 롤백으로 인라인 작성기와 함께 사라졌다.
    testWidgets('삭제 버튼과 "기존 입력 방식" 버튼이 없다', (tester) async {
      final fakeApi = _FakeTodosApi(
        todo: TodoItem(
          id: 5,
          title: '제목',
          completed: false,
          assignees: const [],
        ),
      );

      await pumpDetail(tester, fakeApi);

      expect(find.text('삭제'), findsNothing);
      expect(find.text('기존 입력 방식'), findsNothing);
    });

    /// 마감일은 롤백 후 남은 유일한 메타데이터다 — 서버 값이 칩으로 선택돼 보이고,
    /// 저장할 때 그대로 다시 실려 나가야 한다(안 실으면 PUT 전체 교체로 지워진다).
    testWidgets('서버의 마감일이 칩으로 선택돼 있고 저장 시 유지된다', (tester) async {
      final tomorrow = DateUtils.dateOnly(
        DateTime.now(),
      ).add(const Duration(days: 1));
      final fakeApi = _FakeTodosApi(
        todo: TodoItem(
          id: 5,
          title: '마감 있는 투두',
          completed: false,
          assignees: const [],
          dueDate: tomorrow,
        ),
      );

      await pumpDetail(tester, fakeApi);

      // 마감일 행 값이 '내일'로 표시된다(피커 리디자인, 2026-08-08).
      expect(find.text('내일'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
      await tester.pumpAndSettle();

      expect(fakeApi.updated.single.dueDate, tomorrow);
    });

    testWidgets('조회 실패 시 에러와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
      final fakeApi = _FakeTodosApi(fetchError: StateError('네트워크 오류'));

      await pumpDetail(tester, fakeApi);

      expect(find.text('투두를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);

      fakeApi.fetchError = null;
      fakeApi.todo = TodoItem(
        id: 5,
        title: '복구된 제목',
        completed: false,
        assignees: const [],
      );
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('todo-form-title')))
            .controller!
            .text,
        '복구된 제목',
      );
    });
  });
}
