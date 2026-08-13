/// 빌드 설정값 — 값은 실행/빌드 시 `--dart-define`으로 오버라이드한다.
/// 예: flutter run --dart-define=API_BASE_URL=http://localhost:8080
class Env {
  Env._();

  /// 기본값은 안드로이드 에뮬레이터 기준(10.0.2.2 = 개발 머신 localhost).
  /// 실기기(USB + adb reverse tcp:8080 tcp:8080)로 테스트할 때는
  /// API_BASE_URL=http://localhost:8080로 오버라이드한다.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// Kakao Native App Key. Keep it out of source control and pass it with
  /// --dart-define=KAKAO_NATIVE_APP_KEY=... for mobile builds.
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );
}
