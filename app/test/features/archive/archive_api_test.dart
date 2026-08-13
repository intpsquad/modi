import 'dart:convert';

import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/auth/authenticated_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    '폴더 직접 업로드 이미지는 presigned URL 발급 후 PUT으로 업로드하고 공개 URL을 반환한다(V28)',
    () async {
      final protectedClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rooms/7/archive/items/image/upload-url');
        return http.Response(
          jsonEncode({
            'uploadUrl': 'https://storage.test/presigned',
            'publicUrl': 'https://storage.test/archive-images/7/abc.jpg',
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
      final api = ArchiveApi(
        baseUrl: 'https://api.test',
        client: AuthenticatedHttpClient(
          client: protectedClient,
          tokenProvider: _FakeTokenProvider(),
        ),
        uploadClient: uploadClient,
      );

      final publicUrl = await api.uploadArchiveImage(
        'token',
        7,
        bytes: const [1, 2, 3],
      );

      expect(publicUrl, 'https://storage.test/archive-images/7/abc.jpg');
    },
  );

  test('자료 등록 요청 바디에 imageUrl·title이 실린다', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['imageUrl'], 'https://storage.test/archive-images/7/abc.jpg');
      expect(body['title'], '여행 사진');
      expect(body['url'], null);
      expect(body['text'], null);
      return http.Response(
        jsonEncode({
          'id': 1,
          'folderId': 3,
          'title': '여행 사진',
          'url': null,
          'source': null,
          'thumbnail': null,
          'imageUrl': 'https://storage.test/archive-images/7/abc.jpg',
          'memo': null,
          'summary': null,
          'bodyText': null,
          'pinned': false,
          'tags': <dynamic>[],
          'likeCount': 0,
          'likedByMe': false,
          'createdAt': '2026-08-09T00:00:00Z',
          'crawlStatus': 'DONE',
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ArchiveApi(
      baseUrl: 'https://api.test',
      client: AuthenticatedHttpClient(
        client: client,
        tokenProvider: _FakeTokenProvider(),
      ),
    );

    final detail = await api.createItem(
      'token',
      7,
      3,
      imageUrl: 'https://storage.test/archive-images/7/abc.jpg',
      title: '여행 사진',
    );

    expect(detail.title, '여행 사진');
    expect(detail.imageUrl, 'https://storage.test/archive-images/7/abc.jpg');
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => 'token';

  @override
  Future<void> signOut() async {}
}
