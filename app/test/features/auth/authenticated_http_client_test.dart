import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeTokenProvider implements AuthTokenProvider {
  String refreshedToken = 'fresh-token';
  Object? refreshError;
  final List<bool> forceRefreshCalls = [];
  int signOutCalls = 0;

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    forceRefreshCalls.add(forceRefresh);
    if (refreshError != null) throw refreshError!;
    return refreshedToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

void main() {
  test('요청에 Bearer 토큰을 주입하고 호출자 헤더를 보존한다', () async {
    http.Request? captured;
    final client = AuthenticatedHttpClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      }),
      tokenProvider: _FakeTokenProvider(),
    );

    await client.get(
      Uri.parse('https://api.example.com/me'),
      idToken: 'initial-token',
      headers: const {
        'X-Request-Id': 'request-1',
        'Authorization': 'Bearer caller-token',
      },
    );

    expect(captured?.headers['authorization'], 'Bearer initial-token');
    expect(captured?.headers['x-request-id'], 'request-1');
    expect(captured?.headers['content-type'], 'application/json');
  });

  test('PUT, PATCH, DELETE에서도 메서드와 본문을 그대로 전달한다', () async {
    final requests = <http.Request>[];
    final client = AuthenticatedHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      }),
      tokenProvider: _FakeTokenProvider(),
    );
    final uri = Uri.parse('https://api.example.com/resource');

    await client.put(uri, idToken: 'token', body: '{"method":"put"}');
    await client.patch(uri, idToken: 'token', body: '{"method":"patch"}');
    await client.delete(uri, idToken: 'token', body: '{"method":"delete"}');

    expect(requests.map((request) => request.method), [
      'PUT',
      'PATCH',
      'DELETE',
    ]);
    expect(requests.map((request) => request.body), [
      '{"method":"put"}',
      '{"method":"patch"}',
      '{"method":"delete"}',
    ]);
  });

  test('401이면 ID 토큰을 강제 갱신해 같은 요청을 한 번 재시도한다', () async {
    final requests = <http.Request>[];
    final tokenProvider = _FakeTokenProvider();
    final client = AuthenticatedHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', requests.length == 1 ? 401 : 200);
      }),
      tokenProvider: tokenProvider,
    );

    final response = await client.post(
      Uri.parse('https://api.example.com/rooms'),
      idToken: 'stale-token',
      body: '{"name":"모디"}',
    );

    expect(response.statusCode, 200);
    expect(requests, hasLength(2));
    expect(requests[0].headers['authorization'], 'Bearer stale-token');
    expect(requests[1].headers['authorization'], 'Bearer fresh-token');
    expect(requests[0].body, requests[1].body);
    expect(tokenProvider.forceRefreshCalls, [true]);
    expect(tokenProvider.signOutCalls, 0);
  });

  test('강제 갱신 뒤에도 401이면 인증 세션을 정리하고 응답을 반환한다', () async {
    final tokenProvider = _FakeTokenProvider();
    final client = AuthenticatedHttpClient(
      client: MockClient((_) async => http.Response('', 401)),
      tokenProvider: tokenProvider,
    );

    final response = await client.get(
      Uri.parse('https://api.example.com/me'),
      idToken: 'stale-token',
    );

    expect(response.statusCode, 401);
    expect(tokenProvider.forceRefreshCalls, [true]);
    expect(tokenProvider.signOutCalls, 1);
  });

  test('강제 토큰 갱신 자체가 실패하면 세션을 정리하고 오류를 전달한다', () async {
    final tokenProvider = _FakeTokenProvider()
      ..refreshError = StateError('refresh failed');
    final client = AuthenticatedHttpClient(
      client: MockClient((_) async => http.Response('', 401)),
      tokenProvider: tokenProvider,
    );

    await expectLater(
      client.get(
        Uri.parse('https://api.example.com/me'),
        idToken: 'stale-token',
      ),
      throwsStateError,
    );

    expect(tokenProvider.signOutCalls, 1);
  });

  test('부팅처럼 호출자가 401을 처리하면 자동 재시도를 끌 수 있다', () async {
    final tokenProvider = _FakeTokenProvider();
    final client = AuthenticatedHttpClient(
      client: MockClient((_) async => http.Response('', 401)),
      tokenProvider: tokenProvider,
    );

    final response = await client.get(
      Uri.parse('https://api.example.com/rooms'),
      idToken: 'stale-token',
      retryOnUnauthorized: false,
    );

    expect(response.statusCode, 401);
    expect(tokenProvider.forceRefreshCalls, isEmpty);
    expect(tokenProvider.signOutCalls, 0);
  });
}
