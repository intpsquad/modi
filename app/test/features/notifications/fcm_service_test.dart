import 'dart:async';

import 'package:app/features/notifications/fcm_service.dart';
import 'package:app/routing/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMessaging implements FcmMessagingClient {
  _FakeMessaging();

  FcmAuthorizationStatus permission = FcmAuthorizationStatus.authorized;
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  int permissionRequests = 0;
  int tokenRequests = 0;
  String? token = 'fcm-token';

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<String?> getToken() async {
    tokenRequests++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => _tokenController.stream;

  @override
  Future<void> configureForegroundPresentation() async {}

  void emitToken(String value) {
    token = value;
    _tokenController.add(value);
  }

  Future<void> close() => _tokenController.close();
}

class _FakeAuthSession implements AuthSessionProvider {
  final StreamController<AuthUserSnapshot?> _authController =
      StreamController<AuthUserSnapshot?>.broadcast();

  @override
  AuthUserSnapshot? currentUser;

  String? idToken = 'id-token';

  @override
  Stream<AuthUserSnapshot?> get authStateChanges => _authController.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => idToken;

  @override
  Future<void> signOut() async {}

  void emitUser(String uid) {
    currentUser = AuthUserSnapshot(uid: uid);
    _authController.add(currentUser);
  }

  Future<void> close() => _authController.close();
}

class _FakeTokenRegistrar implements FcmTokenRegistrar {
  final calls = <({String idToken, String fcmToken})>[];

  @override
  Future<void> register({
    required String idToken,
    required String fcmToken,
  }) async {
    calls.add((idToken: idToken, fcmToken: fcmToken));
  }
}

Future<void> _settle() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeMessaging messaging;
  late _FakeAuthSession authSession;
  late _FakeTokenRegistrar registrar;
  late FcmService service;

  setUp(() {
    messaging = _FakeMessaging();
    authSession = _FakeAuthSession();
    registrar = _FakeTokenRegistrar();
    service = FcmService(
      messaging: messaging,
      authSession: authSession,
      tokenRegistrar: registrar,
      supportedPlatform: true,
      registerBackgroundHandler: false,
      listenToMessages: false,
    );
  });

  tearDown(() async {
    await service.dispose();
    await messaging.close();
    await authSession.close();
  });

  test('권한이 허용된 로그인 사용자에게 앱 시작 시 FCM 토큰을 등록한다', () async {
    authSession.currentUser = const AuthUserSnapshot(uid: 'user-1');

    await service.initialize();
    await _settle();

    expect(messaging.permissionRequests, 1);
    expect(registrar.calls, [(idToken: 'id-token', fcmToken: 'fcm-token')]);
  });

  test('알림 권한이 거부되면 FCM 토큰을 서버에 등록하지 않는다', () async {
    messaging.permission = FcmAuthorizationStatus.denied;
    authSession.currentUser = const AuthUserSnapshot(uid: 'user-1');

    await service.initialize();
    await _settle();

    expect(registrar.calls, isEmpty);
    expect(messaging.tokenRequests, 0);
  });

  test('로그인 전 부팅 후 로그인하면 FCM 토큰을 등록한다', () async {
    await service.initialize();
    authSession.emitUser('user-1');
    await _settle();

    expect(registrar.calls, [(idToken: 'id-token', fcmToken: 'fcm-token')]);
  });

  test('FCM 토큰이 갱신되면 최신 토큰을 다시 등록한다', () async {
    authSession.currentUser = const AuthUserSnapshot(uid: 'user-1');

    await service.initialize();
    await _settle();
    messaging.emitToken('new-fcm-token');
    await _settle();

    expect(registrar.calls, [
      (idToken: 'id-token', fcmToken: 'fcm-token'),
      (idToken: 'id-token', fcmToken: 'new-fcm-token'),
    ]);
  });

  /// 🔴 **권한 요청은 앞 단계가 어떻게 되든 반드시 나가야 한다**(2026-08-16).
  ///
  /// 2026-08-15 TestFlight 빌드 5 에서 **알림 권한 팝업이 아예 뜨지 않았고**, iOS 설정에
  /// 「알림」 항목조차 안 생겼다. `initialize()` 가 권한 요청 **앞의** 메시지 수신 배선에서
  /// 멈추면 그렇게 되는데, main.dart 가 `unawaited(...)` 로 부르는 탓에 **에러가 통째로
  /// 사라져** 원인을 알 수 없었다.
  ///
  /// 이 테스트는 `listenToMessages: true` 로 두어 그 배선이 실제로 실패하게 만든다
  /// (테스트 환경에는 Firebase 가 없다). 그래도 권한 요청은 나가야 한다.
  test('메시지 수신 배선이 실패해도 권한 요청은 나간다', () async {
    final wired = FcmService(
      messaging: messaging,
      authSession: authSession,
      tokenRegistrar: registrar,
      supportedPlatform: true,
      registerBackgroundHandler: false,
      listenToMessages: true,
    );
    addTearDown(wired.dispose);

    await wired.initialize();
    await _settle();

    expect(messaging.permissionRequests, 1);
  });
}
