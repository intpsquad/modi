import 'dart:async';

import 'package:app/features/notifications/fcm_service.dart';
import 'package:app/routing/app_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMessaging implements FcmMessagingClient {
  _FakeMessaging();

  FcmAuthorizationStatus permission = FcmAuthorizationStatus.authorized;
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  int permissionRequests = 0;
  int tokenRequests = 0;
  String? token = 'fcm-token';

  /// 처음 이 횟수만큼의 `getToken()` 을 실패시킨다 — 실기기에서 APNs 토큰이 늦게 와서
  /// 첫 시도가 죽는 상황을 재현한다(2026-08-31 실측: 권한 승인 2.028초 뒤 예외).
  int failuresBeforeSuccess = 0;

  /// 실패를 **null 반환**으로 낸다. 예외가 아니라 조용한 null 도 실기기에서 나오는
  /// 모양이고, 예전 코드는 이걸 로그 한 줄 없이 넘겼다.
  bool failWithNull = false;

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<String?> getToken() async {
    tokenRequests++;
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      if (failWithNull) return null;
      throw StateError('APNS token has not been set yet');
    }
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

  /// 등록을 매달아 둔다 — "동기화가 진행 중일 때" 를 재현할 때 쓴다.
  Completer<void>? gate;

  @override
  Future<void> register({
    required String idToken,
    required String fcmToken,
  }) async {
    calls.add((idToken: idToken, fcmToken: fcmToken));
    if (gate != null) await gate!.future;
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
      // AppLifecycleListener 는 위젯 바인딩을 요구한다. 테스트는 onAppResumed() 를 직접 부른다.
      listenToLifecycle: false,
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
  ///
  /// **2026-08-31: 생명주기 구독도 같은 자리에 들어왔다.** `AppLifecycleListener` 는 위젯
  /// 바인딩을 요구해서 이 테스트 환경에서 실제로 던진다 — `listenToLifecycle: true` 로 두어
  /// 그 예외가 권한 요청을 막지 않는지 함께 못 박는다(감싸지 않았을 때 실제로 깨졌다).
  test('앞 단계 배선이 실패해도 권한 요청은 나간다', () async {
    final wired = FcmService(
      messaging: messaging,
      authSession: authSession,
      tokenRegistrar: registrar,
      supportedPlatform: true,
      registerBackgroundHandler: false,
      listenToMessages: true,
      listenToLifecycle: true,
    );
    addTearDown(wired.dispose);

    await wired.initialize();
    await _settle();

    expect(messaging.permissionRequests, 1);
  });

  /// 🔴 **토큰 등록은 한 번 실패하면 스스로 되살아나야 한다**(2026-08-31, 이슈 #66).
  ///
  /// 실기기 로그로 확인된 실제 실패다 — 권한은 승인됐는데 2.028초 뒤 토큰 등록이 예외로
  /// 죽었다(iOS 는 APNs 토큰이 등록된 뒤에야 FCM 토큰을 준다). 그런데 그 뒤로 **아무도
  /// 다시 시도하지 않아** 그 사용자는 영구히 푸시를 못 받았다. `authStateChanges` 는 권한
  /// 설정 **전에** 이미 발화했고, `onTokenRefresh` 는 토큰을 못 받았으니 오지 않는다.
  ///
  /// 그 결과가 운영 DB 에 그대로 있었다 — **유저 40명 중 토큰 보유 8명.** 2초 안에 운 좋게
  /// 받은 사람만 등록돼 있었다.
  ///
  /// 시간은 `fakeAsync` 로 흘린다(`app_session_test.dart` 선례).
  group('토큰 등록 재시도', () {
    /// `initialize()` 는 await 할 수 없으니(가짜 시간 안이다) 시작만 시키고 흘려보낸다.
    void start(FakeAsync async) {
      authSession.currentUser = const AuthUserSnapshot(uid: 'user-1');
      unawaited(service.initialize());
      async.elapse(Duration.zero);
    }

    test('첫 시도가 실패하면 예약된 간격 뒤에 다시 시도한다', () {
      fakeAsync((async) {
        messaging.failuresBeforeSuccess = 1;
        start(async);
        expect(registrar.calls, isEmpty, reason: '첫 시도는 실패했다');

        async.elapse(FcmService.tokenRetryDelays.first);

        expect(registrar.calls, [(idToken: 'id-token', fcmToken: 'fcm-token')]);
      });
    });

    test('토큰이 null 로 와도 실패로 보고 다시 시도한다', () {
      fakeAsync((async) {
        messaging
          ..failuresBeforeSuccess = 1
          ..failWithNull = true;
        start(async);
        expect(registrar.calls, isEmpty);

        async.elapse(FcmService.tokenRetryDelays.first);

        expect(registrar.calls, hasLength(1));
      });
    });

    test('한 번 성공하면 더 이상 시도하지 않는다', () {
      fakeAsync((async) {
        start(async);
        expect(registrar.calls, hasLength(1));

        async.elapse(const Duration(minutes: 10));

        expect(registrar.calls, hasLength(1), reason: '성공 뒤에는 재시도가 없어야 한다');
      });
    });

    test('정해진 횟수를 다 쓰면 멈춘다', () {
      fakeAsync((async) {
        // 계속 실패시킨다.
        messaging.failuresBeforeSuccess = 1000;
        start(async);

        async.elapse(const Duration(minutes: 30));

        expect(
          messaging.tokenRequests,
          FcmService.tokenRetryDelays.length + 1,
          reason: '첫 시도 + 재시도 횟수만큼만 부른다(무한 재시도 금지)',
        );
      });
    });

    /// 🔴 권한 없음·로그인 전은 **실패가 아니라 "아직 할 때가 아님"** 이다. 재시도를 걸면
    /// 로그인도 안 한 사용자에게 타이머만 돈다. `tokenRequests` 만 보면 이 구분이 검증되지
    /// 않는다 — 권한 확인이 `getToken()` **앞**이라 재시도가 돌아도 그 카운터는 안 오른다
    /// (2026-08-31 리뷰에서 이 구멍이 뮤테이션으로 드러났다). 예약 여부를 직접 본다.
    test('권한이 거부되면 재시도를 예약조차 하지 않는다', () {
      fakeAsync((async) {
        messaging.permission = FcmAuthorizationStatus.denied;
        start(async);

        expect(service.hasPendingTokenRetry, isFalse);
        async.elapse(const Duration(minutes: 30));

        expect(messaging.tokenRequests, 0);
        expect(registrar.calls, isEmpty);
      });
    });

    test('로그인 전에는 재시도를 예약하지 않는다', () {
      fakeAsync((async) {
        // start() 와 달리 로그인시키지 않는다.
        unawaited(service.initialize());
        async.elapse(Duration.zero);

        expect(service.hasPendingTokenRetry, isFalse);
        async.elapse(const Duration(minutes: 30));

        expect(messaging.tokenRequests, 0);
      });
    });

    test('성공하면 재시도 예산이 0으로 돌아간다', () {
      fakeAsync((async) {
        messaging.failuresBeforeSuccess = 1;
        start(async);
        expect(service.tokenRetryAttempt, 1, reason: '1회 예약된 상태');

        async.elapse(FcmService.tokenRetryDelays.first);

        expect(service.tokenRetryAttempt, 0);
        expect(service.hasPendingTokenRetry, isFalse);
      });
    });

    test('새 트리거(로그인)가 오면 재시도 예산을 처음부터 다시 센다', () {
      fakeAsync((async) {
        messaging.failuresBeforeSuccess = 1000;
        start(async);
        async.elapse(FcmService.tokenRetryDelays[0]);
        async.elapse(FcmService.tokenRetryDelays[1]);
        expect(service.tokenRetryAttempt, 3, reason: '예산을 3회 썼다');

        authSession.emitUser('user-1');
        async.elapse(Duration.zero);

        expect(service.tokenRetryAttempt, 1, reason: '새 트리거는 사슬을 이어받지 않는다');
      });
    });

    test('dispose 뒤에는 예약된 재시도가 돌지 않는다', () {
      fakeAsync((async) {
        messaging.failuresBeforeSuccess = 1000;
        start(async);
        final before = messaging.tokenRequests;

        unawaited(service.dispose());
        async.elapse(const Duration(minutes: 30));

        expect(messaging.tokenRequests, before, reason: '타이머가 남아 돌면 안 된다');
      });
    });

    /// 🔴 **서버 등록이 실패해도 재시도해야 한다.** 그동안 재시도 테스트는 전부
    /// `getToken()` 실패만 다뤘는데, 실제로는 등록 요청(HTTP)이 실패하는 경로가 **재시도
    /// 대상에서 통째로 빠져 있었다** — 진단용 `debugPrintStack` 이 던지면서 그 예외가
    /// catch 블록을 빠져나가 재시도 예약을 건너뛰었다(2026-08-31 실측).
    test('서버 등록이 실패하면 다시 시도한다', () {
      fakeAsync((async) {
        registrar.gate = Completer<void>();
        start(async);
        expect(registrar.calls, hasLength(1));

        registrar.gate!.completeError(StateError('망 끊김'));
        async.flushMicrotasks();

        expect(service.hasPendingTokenRetry, isTrue, reason: '재시도가 예약돼야 한다');

        registrar.gate = null; // 이번엔 성공한다
        async.elapse(FcmService.tokenRetryDelays.first);

        expect(registrar.calls, hasLength(2));
      });
    });

    /// dispose 가 **동기화 도중에** 불리는 경우. 위 테스트는 동기화가 끝난 뒤 dispose 해서
    /// 이 경로를 못 덮는다 — `_scheduleRetry` 의 `_disposed` 가드를 지워도 통과했다.
    test('동기화 도중에 dispose 하면 새 재시도를 예약하지 않는다', () {
      fakeAsync((async) {
        registrar.gate = Completer<void>();
        start(async);
        expect(registrar.calls, hasLength(1), reason: '등록 호출이 매달려 있다');

        unawaited(service.dispose());
        registrar.gate!.completeError(StateError('연결 끊김'));

        // ⚠️ **타이머를 흘리기 전에** 본다. 시간을 먼저 흘려버리면 예약된 타이머가 이미
        // 발화해 `isActive` 가 false 가 되고, 그 재시도는 `_syncTokenOnce` 의 dispose
        // 검사에 막혀 흔적도 안 남는다 — 두 방어가 서로를 가려 테스트가 아무것도 못 잡는다
        // (2026-08-31 리뷰 후 뮤테이션으로 확인).
        async.flushMicrotasks();
        expect(
          service.hasPendingTokenRetry,
          isFalse,
          reason: 'dispose 뒤에는 새 타이머를 걸면 안 된다',
        );

        async.elapse(const Duration(minutes: 30));
        expect(registrar.calls, hasLength(1));
      });
    });

    /// 🔴 재시도 예산(약 112초)을 다 써도 **앱이 다시 앞으로 나오면 처음부터 다시 시도한다.**
    /// 이게 없으면 창을 2초에서 112초로 넓혔을 뿐 #66 과 같은 영구 침묵이 남는다
    /// (2026-08-31 리뷰 지적). 토큰을 한 번도 못 받은 기기는 `onTokenRefresh` 가 오지 않고,
    /// 로그인 상태가 유지되면 `authStateChanges` 도 오지 않는다.
    test('예산을 다 쓴 뒤에도 앱이 다시 앞으로 나오면 처음부터 다시 시도한다', () {
      fakeAsync((async) {
        messaging.failuresBeforeSuccess = 1000;
        start(async);
        async.elapse(const Duration(minutes: 30));
        final exhausted = messaging.tokenRequests;
        expect(exhausted, FcmService.tokenRetryDelays.length + 1);
        expect(service.hasPendingTokenRetry, isFalse, reason: '예산 소진');

        messaging.failuresBeforeSuccess = 0; // 이번엔 네트워크가 돌아왔다
        service.onAppResumed();
        async.elapse(Duration.zero);

        expect(messaging.tokenRequests, exhausted + 1);
        expect(registrar.calls, hasLength(1));
      });
    });

    test('dispose 뒤 포그라운드 복귀는 아무것도 하지 않는다', () {
      fakeAsync((async) {
        start(async);
        final before = messaging.tokenRequests;
        unawaited(service.dispose());

        service.onAppResumed();
        async.elapse(const Duration(minutes: 1));

        expect(messaging.tokenRequests, before);
      });
    });
  });
}
