import 'dart:convert';

import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:app/features/notifications/notifications_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('알림 내역 조회는 GET /me/notifications 계약을 파싱한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/notifications');
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'type': 'POKE',
            'title': '민지님의 콕찌르기',
            'body': '여름 스터디 방에서 투두를 확인해보세요',
            'roomId': 7,
            'read': false,
            'createdAt': '2026-08-09T01:00:00Z',
          },
          {
            'id': 2,
            'type': 'ARCHIVE_ANALYSIS_DONE',
            'title': '「자료」 분석이 끝났어요',
            'body': '모아보기에서 확인해 보세요',
            'roomId': null,
            'read': true,
            'createdAt': '2026-08-08T01:00:00Z',
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = NotificationsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    final items = await api.fetchHistory('token');

    expect(items, hasLength(2));
    expect(items[0].type, 'POKE');
    expect(items[0].title, '민지님의 콕찌르기');
    expect(items[0].roomId, 7);
    expect(items[0].read, isFalse);
    expect(items[1].roomId, isNull);
    expect(items[1].read, isTrue);
  });

  test('안읽은 알림 개수는 GET /me/notifications/unread-count 계약을 파싱한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/me/notifications/unread-count');
      return http.Response(
        jsonEncode({'count': 3}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = NotificationsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    expect(await api.fetchUnreadCount('token'), 3);
  });

  test(
    '전체 읽음 처리는 인증된 POST /me/notifications/read-all 요청이 204일 때만 성공한다',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/me/notifications/read-all');
        return http.Response('', 204);
      });
      final api = NotificationsApi(
        baseUrl: 'https://api.test',
        client: AuthenticatedHttpClient(
          client: client,
          tokenProvider: _FakeTokenProvider(),
        ),
      );

      await api.markAllRead('token'); // 예외 없이 끝나면 성공.
    },
  );

  test('전체 읽음 처리가 204가 아니면 실패로 처리한다', () async {
    final client = MockClient((request) async => http.Response('', 500));
    final api = NotificationsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    expect(api.markAllRead('token'), throwsStateError);
  });

  NotificationsApi apiReturning(int status, void Function(http.Request) check) {
    return NotificationsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: MockClient((request) async {
          check(request);
          return http.Response('', status);
        }),
        tokenProvider: _FakeTokenProvider(),
      ),
    );
  }

  test('알림 한 건 삭제는 DELETE /me/notifications/{id} 가 204면 성공한다(#111)', () async {
    final api = apiReturning(204, (request) {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/me/notifications/42');
    });

    await api.deleteNotification('token', 42); // 예외 없이 끝나면 성공.
  });

  /// 다른 기기에서 지웠거나 90일 보존 배치가 먼저 지운 알림이다. 화면에서 없애려던 목적은
  /// 이미 이뤄졌으니 실패로 보고 되살리지 않는다.
  test('알림 한 건 삭제가 404면 이미 지워진 것으로 보고 성공 처리한다', () async {
    final api = apiReturning(404, (_) {});

    await api.deleteNotification('token', 42);
  });

  test('알림 한 건 삭제가 그 밖의 상태면 실패로 처리한다', () async {
    final api = apiReturning(500, (_) {});

    expect(api.deleteNotification('token', 42), throwsStateError);
  });

  test('알림 전체 삭제는 DELETE /me/notifications 가 204면 성공한다(#111)', () async {
    final api = apiReturning(204, (request) {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/me/notifications');
    });

    await api.deleteAll('token');
  });

  test('알림 전체 삭제가 204가 아니면 실패로 처리한다', () async {
    final api = apiReturning(500, (_) {});

    expect(api.deleteAll('token'), throwsStateError);
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}
}
