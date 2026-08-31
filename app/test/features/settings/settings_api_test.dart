import 'dart:convert';

import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('프로필 사진은 presigned URL에 업로드하고 공개 URL을 반환한다', () async {
    final protectedClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/me/profile/photo/upload-url');
      return http.Response(
        jsonEncode({
          'uploadUrl': 'https://storage.test/presigned',
          'publicUrl': 'https://storage.test/profile/me',
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
    final api = SettingsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: protectedClient,
        tokenProvider: _FakeTokenProvider(),
      ),
      uploadClient: uploadClient,
    );

    final publicUrl = await api.uploadProfilePhoto(
      'token',
      bytes: const [1, 2, 3],
    );

    expect(publicUrl, 'https://storage.test/profile/me');
  });

  test('현재 초대코드 조회 API 계약을 사용한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/rooms/7/invite-code');
      return http.Response(jsonEncode({'inviteCode': 'ABC234'}), 200);
    });
    final api = SettingsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    expect(await api.fetchInviteCode('token', 7), 'ABC234');
  });

  test('회원 탈퇴는 인증된 DELETE /me 요청이 204일 때만 성공한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/me');
      expect(request.headers['authorization'], 'Bearer token');
      return http.Response('', 204);
    });
    final api = SettingsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    await api.withdraw('token');
  });

  test('회원 탈퇴가 204가 아니면 실패로 처리한다', () async {
    final client = MockClient((_) async => http.Response('', 500));
    final api = SettingsApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    expect(api.withdraw('token'), throwsStateError);
  });

  test('방 목록 응답의 대표 이미지와 상세 목표를 설정 프리필용으로 보존한다', () {
    final room = RoomSummary.fromMap({
      'id': 7,
      'name': '여름 알고리즘 스터디',
      'goal': '코딩테스트 통과하기',
      'goalDetail': '매주 문제를 풀고 함께 리뷰한다.',
      'status': 'ACTIVE',
      'startDate': '2026-07-28',
      'endDate': '2026-08-10',
      'coverImage': 'https://storage.test/room.jpg',
    });

    expect(room.goalDetail, '매주 문제를 풀고 함께 리뷰한다.');
    expect(room.coverImage, 'https://storage.test/room.jpg');
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}
}
