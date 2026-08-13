import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env.dart';
import 'authenticated_http_client.dart';

/// 인증 왕복 검증용 스파이크 클라이언트: 보호된 GET /me 호출.
/// baseUrl 기본값/오버라이드는 config/env.dart 참고.
class ApiClient {
  ApiClient({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? authenticatedClient,
  }) : _authenticatedClient = authenticatedClient ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _authenticatedClient;

  Future<KakaoLoginResponse> exchangeKakaoAccessToken(
    String accessToken,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/kakao'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'accessToken': accessToken}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      throw StateError('카카오 로그인 토큰이 유효하지 않습니다.');
    }
    if (response.statusCode != 200) {
      throw StateError('카카오 로그인 서버 요청에 실패했습니다.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return KakaoLoginResponse(
      firebaseToken: body['firebaseToken'] as String,
      nickname: body['nickname'] as String,
    );
  }

  Future<Map<String, dynamic>> fetchMe(String idToken) async {
    final response = await _authenticatedClient.get(
      Uri.parse('$baseUrl/me'),
      idToken: idToken,
    );
    if (response.statusCode != 200) {
      throw StateError('GET /me 실패: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 인증 제공자가 준 기본 프로필을 서버의 users 행에 반영한다.
  ///
  /// 서버는 기존 사용자의 설정값을 덮어쓰지 않도록 호출 시점을 신규 가입으로
  /// 제한한다. 자체가입은 이 호출로 users 행을 생성하고, OAuth 가입은 제공자
  /// 기본값을 저장한다.
  /// 이메일 인증코드 발송 (백엔드: POST /auth/email/code).
  Future<void> sendEmailVerificationCode(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/email/code'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 409) {
      throw StateError('이미 가입된 이메일이에요. 다른 이메일을 사용해 주세요');
    }
    if (response.statusCode != 200) {
      throw StateError('인증코드 발송에 실패했어요. 잠시 후 다시 시도해 주세요');
    }
  }

  /// 이메일 인증코드 검증 (백엔드: POST /auth/email/code/verify).
  Future<void> verifyEmailCode(String email, String code) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/email/code/verify'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 400) {
      throw StateError('인증코드가 올바르지 않아요');
    }
    if (response.statusCode == 410) {
      throw StateError('인증코드가 만료됐어요. 다시 받아주세요');
    }
    if (response.statusCode != 200) {
      throw StateError('인증코드 확인에 실패했어요. 잠시 후 다시 시도해 주세요');
    }
  }

  Future<void> updateProfile(
    String idToken, {
    required String nickname,
    String? profileImage,
  }) async {
    final response = await _authenticatedClient
        .patch(
          Uri.parse('$baseUrl/me/profile'),
          idToken: idToken,
          body: jsonEncode({
            'nickname': nickname,
            'profileImage': profileImage,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      throw StateError('프로필 저장을 위해 다시 로그인해 주세요.');
    }
    if (response.statusCode != 200) {
      throw StateError('프로필 저장에 실패했습니다.');
    }
  }
}

class KakaoLoginResponse {
  const KakaoLoginResponse({
    required this.firebaseToken,
    required this.nickname,
  });

  final String firebaseToken;
  final String nickname;
}
