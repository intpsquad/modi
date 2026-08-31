import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// 앱 수명 동안 보호 API 연결을 재사용하는 기본 클라이언트.
final appAuthenticatedHttpClient = AuthenticatedHttpClient();

/// 보호 API 호출에 필요한 Firebase 인증 세션의 최소 계약.
abstract interface class AuthTokenProvider {
  Future<String> getIdToken({bool forceRefresh = false});

  Future<void> signOut();
}

class FirebaseAuthTokenProvider implements AuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다.');
    }

    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('ID 토큰을 가져오지 못했습니다.');
    }
    return token;
  }

  @override
  Future<void> signOut() => FirebaseAuth.instance.signOut();
}

/// 모든 보호 API 요청의 Bearer 주입과 401 갱신 재시도를 한곳에서 처리한다.
///
/// 서버의 인증 필터가 컨트롤러 실행 전에 401을 반환하므로, 최초 401에 한해
/// Firebase ID 토큰을 강제 갱신하고 동일 요청을 한 번 재전송한다.
class AuthenticatedHttpClient {
  AuthenticatedHttpClient({
    http.Client? client,
    AuthTokenProvider? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _tokenProvider;

  Future<http.Response> get(
    Uri url, {
    required String idToken,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) => _client.get(url, headers: _headers(token, headers)),
    );
  }

  Future<http.Response> post(
    Uri url, {
    required String idToken,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) => _client.post(
        url,
        headers: _headers(token, headers),
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> put(
    Uri url, {
    required String idToken,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) => _client.put(
        url,
        headers: _headers(token, headers),
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> patch(
    Uri url, {
    required String idToken,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) => _client.patch(
        url,
        headers: _headers(token, headers),
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> delete(
    Uri url, {
    required String idToken,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) => _client.delete(
        url,
        headers: _headers(token, headers),
        body: body,
        encoding: encoding,
      ),
    );
  }

  /// multipart/form-data 업로드(이미지 등). JSON `_headers`와 달리 Content-Type을
  /// MultipartRequest가 boundary와 함께 직접 설정하므로 Authorization만 주입한다.
  ///
  /// 401 재시도 시 요청을 다시 보내야 하는데 MultipartRequest는 한 번 전송하면
  /// 스트림이 소비돼 재전송이 불가하므로, [_send]의 request 클로저 안에서 바이트로부터
  /// 매 시도마다 새 요청을 빌드한다.
  /// 파일 3종([fileField]·[bytes]·[filename])은 **선택**이다 — 셋 다 없으면 필드만 담은
  /// multipart를 보낸다. 피드백 제출(#70)은 스크린샷 없이 보내는 경우가 더 흔하다.
  Future<http.Response> sendMultipart(
    Uri url, {
    required String idToken,
    String? fileField,
    List<int>? bytes,
    String? filename,
    Map<String, String>? fields,
    String method = 'POST',
    bool retryOnUnauthorized = true,
  }) {
    return _send(
      idToken: idToken,
      retryOnUnauthorized: retryOnUnauthorized,
      request: (token) async {
        final req = http.MultipartRequest(method, url);
        req.headers['Authorization'] = 'Bearer $token';
        if (fields != null) req.fields.addAll(fields);
        if (fileField != null && bytes != null && filename != null) {
          req.files.add(
            http.MultipartFile.fromBytes(fileField, bytes, filename: filename),
          );
        }
        final streamed = await _client.send(req);
        return http.Response.fromStream(streamed);
      },
    );
  }

  Future<http.Response> _send({
    required String idToken,
    required bool retryOnUnauthorized,
    required Future<http.Response> Function(String token) request,
  }) async {
    final response = await request(idToken);
    if (response.statusCode != 401 || !retryOnUnauthorized) {
      return response;
    }

    late final String refreshedToken;
    try {
      refreshedToken = await _tokenProvider.getIdToken(forceRefresh: true);
      if (refreshedToken.isEmpty) {
        throw StateError('갱신된 ID 토큰이 비어 있습니다.');
      }
    } catch (error, stackTrace) {
      await _trySignOut();
      Error.throwWithStackTrace(error, stackTrace);
    }

    final retriedResponse = await request(refreshedToken);
    if (retriedResponse.statusCode == 401) {
      await _trySignOut();
    }
    return retriedResponse;
  }

  Map<String, String> _headers(String idToken, Map<String, String>? headers) =>
      {
        'Content-Type': 'application/json',
        ...?headers,
        'Authorization': 'Bearer $idToken',
      };

  Future<void> _trySignOut() async {
    try {
      await _tokenProvider.signOut();
    } catch (_) {
      // 인증 실패 응답이나 원래 토큰 갱신 오류를 signOut 오류로 덮지 않는다.
    }
  }

  void close() => _client.close();
}
