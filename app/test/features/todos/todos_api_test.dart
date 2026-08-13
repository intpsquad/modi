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

    final todo = await api.updateTodo('token', 7, 1, title: '장보기');

    expect(todo.imageUrl, 'https://storage.test/todos/7/abc.jpg');
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}
}
