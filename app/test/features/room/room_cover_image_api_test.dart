import 'dart:convert';

import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'fresh';
  @override
  Future<void> signOut() async {}
}

AuthenticatedHttpClient _client(MockClient mock) =>
    AuthenticatedHttpClient(client: mock, tokenProvider: _FakeTokenProvider());

void main() {
  test(
    'uploadCoverImage는 Bearer + multipart로 /rooms/cover-image에 올리고 URL을 파싱한다',
    () async {
      http.Request? captured;
      final api = RoomApi(
        client: _client(
          MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({'coverImage': 'https://cdn/room/9.jpg'}),
              201,
            );
          }),
        ),
      );

      final url = await api.uploadCoverImage(
        'tok',
        bytes: [1, 2, 3],
        filename: 'cover.jpg',
      );

      expect(url, 'https://cdn/room/9.jpg');
      expect(captured?.method, 'POST');
      expect(captured?.url.path, endsWith('/rooms/cover-image'));
      expect(captured?.headers['authorization'], 'Bearer tok');
      expect(
        captured?.headers['content-type'],
        startsWith('multipart/form-data'),
      );
    },
  );

  test(
    'SettingsApi.updateRoom은 coverImage를 그대로 전송한다(더 이상 null 하드코딩 아님)',
    () async {
      Map<String, dynamic>? sentBody;
      final api = SettingsApi(
        client: _client(
          MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
        ),
      );

      await api.updateRoom(
        'tok',
        1,
        name: '방',
        goal: '목표',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 2, 1),
        coverImage: 'https://cdn/room/9.jpg',
      );

      expect(sentBody?['coverImage'], 'https://cdn/room/9.jpg');
    },
  );
}
