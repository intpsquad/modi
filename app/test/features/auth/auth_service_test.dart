import 'package:app/features/auth/api_client.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingApiClient extends ApiClient {
  int sendCodeCalls = 0;
  int verifyCodeCalls = 0;
  String? email;
  String? code;

  @override
  Future<void> sendEmailVerificationCode(String email) async {
    sendCodeCalls++;
    this.email = email;
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    verifyCodeCalls++;
    this.email = email;
    this.code = code;
  }
}

void main() {
  test('디버그 빌드에서도 이메일 인증코드 발송 API를 호출한다', () async {
    final apiClient = _RecordingApiClient();
    final service = AuthService(apiClient: apiClient);

    await service.sendEmailVerificationCode('modi@example.com');

    expect(apiClient.sendCodeCalls, 1);
    expect(apiClient.email, 'modi@example.com');
  });

  test('디버그 빌드에서도 이메일 인증코드 검증 API를 호출한다', () async {
    final apiClient = _RecordingApiClient();
    final service = AuthService(apiClient: apiClient);

    await service.verifyEmailCode('modi@example.com', '123456');

    expect(apiClient.verifyCodeCalls, 1);
    expect(apiClient.email, 'modi@example.com');
    expect(apiClient.code, '123456');
  });
}
