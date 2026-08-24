import 'dart:convert';

import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    '투두 이미지는 presigned URL 발급 후 PUT으로 업로드하고 공개 URL을 반환한다(2026-08-09)',
    () async {
      final protectedClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rooms/7/todos/image/upload-url');
        return http.Response(
          jsonEncode({
            'uploadUrl': 'https://storage.test/presigned',
            'publicUrl': 'https://storage.test/todos/7/abc.jpg',
          }),
          200,
        );
      });
      final uploadClient = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.toString(), 'https://storage.test/presigned');
        expect(request.bodyBytes, [1, 2, 3]);
        return http.Response('', 200);
      });
      final api = TodosApi(
        baseUrl: 'https://api.test',
        client: AuthenticatedHttpClient(
          client: protectedClient,
          tokenProvider: _FakeTokenProvider(),
        ),
        uploadClient: uploadClient,
      );

      final publicUrl = await api.uploadTodoImage(
        'token',
        7,
        bytes: const [1, 2, 3],
      );

      expect(publicUrl, 'https://storage.test/todos/7/abc.jpg');
    },
  );

  test('투두 생성 요청 바디에 imageUrl이 실린다', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['imageUrl'], 'https://storage.test/todos/7/abc.jpg');
      return http.Response(
        jsonEncode({
          'id': 1,
          'title': '장보기',
          'completed': false,
          'assignees': <dynamic>[],
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = TodosApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    final todo = await api.createTodo(
      'token',
      7,
      title: '장보기',
      imageUrl: 'https://storage.test/todos/7/abc.jpg',
    );

    expect(todo.title, '장보기');
  });

  test('투두 수정 응답의 imageUrl이 TodoItem에 파싱된다', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 1,
          'title': '장보기',
          'completed': false,
          'assignees': <dynamic>[],
          'imageUrl': 'https://storage.test/todos/7/abc.jpg',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = TodosApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    final todo = await api.updateTodo(
      'token',
      7,
      1,
      title: '장보기',
      detail: null,
      categoryId: null,
      assigneeUserIds: const [],
      dueDate: null,
      imageUrl: null,
    );

    expect(todo.imageUrl, 'https://storage.test/todos/7/abc.jpg');
  });

  /// 2026-08-25 #65 — 수정은 PUT 전체 교체라 **여섯 값이 전부 실려야** 한다.
  /// 하나라도 빠지면 서버가 그 필드를 지운다(실제로 사진이 그렇게 사라졌다).
  test('updateTodo는 여섯 필드를 모두 요청 바디에 싣는다', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 1,
          'title': '장보기',
          'completed': false,
          'assignees': <dynamic>[],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = TodosApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    await api.updateTodo(
      'token',
      7,
      1,
      title: '장보기',
      detail: '메모',
      categoryId: 3,
      assigneeUserIds: const ['u1'],
      dueDate: DateTime(2026, 9, 1),
      imageUrl: 'https://storage.test/keep.jpg',
    );

    expect(sent, isNotNull);
    expect(sent!['title'], '장보기');
    expect(sent!['detail'], '메모');
    expect(sent!['categoryId'], 3);
    expect(sent!['assigneeUserIds'], ['u1']);
    expect(sent!['dueDate'], '2026-09-01');
    expect(sent!['imageUrl'], 'https://storage.test/keep.jpg');
  });

  /// 2026-08-25 #65 — 화면이 낙관적으로 만드는 사본이 필드를 흘리지 않게 하는 안전망.
  /// 예전에는 화면마다 `TodoItem(...)`을 손으로 새로 지어서 사진이 빠졌다.
  group('TodoItem.copyWith', () {
    final base = TodoItem(
      id: 1,
      title: '원제목',
      detail: '원메모',
      completed: false,
      categoryId: 3,
      assignees: [MemberBrief(userId: 'u1', nickname: '철수')],
      createdAt: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 9, 1),
      imageUrl: 'https://storage.test/keep.jpg',
    );

    test('아무것도 안 넘기면 모든 값이 그대로다', () {
      final copy = base.copyWith();

      expect(copy.id, base.id);
      expect(copy.title, base.title);
      expect(copy.detail, base.detail);
      expect(copy.completed, base.completed);
      expect(copy.categoryId, base.categoryId);
      expect(copy.assignees, base.assignees);
      expect(copy.createdAt, base.createdAt);
      expect(copy.dueDate, base.dueDate);
      expect(copy.imageUrl, base.imageUrl);
    });

    test('제목·메모만 바꿔도 사진과 마감일이 따라온다', () {
      final copy = base.copyWith(title: '새제목', detail: '새메모');

      expect(copy.title, '새제목');
      expect(copy.detail, '새메모');
      expect(copy.imageUrl, 'https://storage.test/keep.jpg');
      expect(copy.dueDate, DateTime(2026, 9, 1));
      expect(copy.categoryId, 3);
    });

    test('메모에 null을 명시하면 비운다(생략과 구분된다)', () {
      expect(base.copyWith(detail: null).detail, isNull);
      expect(base.copyWith().detail, '원메모');
    });

    test('카테고리에 null을 명시하면 기타로 옮긴다', () {
      final moved = base.copyWith(categoryId: null);

      expect(moved.categoryId, isNull);
      expect(moved.imageUrl, 'https://storage.test/keep.jpg');
    });

    test('완료 상태만 바꿔도 나머지가 유지된다', () {
      final done = base.copyWith(completed: true);

      expect(done.completed, isTrue);
      expect(done.imageUrl, 'https://storage.test/keep.jpg');
      expect(done.assignees, base.assignees);
    });
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}
}
