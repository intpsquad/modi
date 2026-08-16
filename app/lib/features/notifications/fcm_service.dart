import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/env.dart';
import '../../firebase_options.dart';
import '../../routing/app_session.dart';
import '../auth/authenticated_http_client.dart';
import 'notification_router.dart';

/// 앱에서 필요한 알림 권한 상태만 노출한다.
enum FcmAuthorizationStatus { authorized, provisional, denied, notDetermined }

/// 실제 Firebase Messaging과 앱 부팅/토큰 동기화 로직을 분리하기 위한 계약.
abstract interface class FcmMessagingClient {
  Future<FcmAuthorizationStatus> requestPermission();

  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  Future<void> configureForegroundPresentation();
}

class FirebaseMessagingClient implements FcmMessagingClient {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<FcmAuthorizationStatus> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => FcmAuthorizationStatus.authorized,
      AuthorizationStatus.provisional => FcmAuthorizationStatus.provisional,
      AuthorizationStatus.denied => FcmAuthorizationStatus.denied,
      AuthorizationStatus.notDetermined => FcmAuthorizationStatus.notDetermined,
    };
  }

  @override
  Future<String?> getToken() async {
    // iOS는 APNs 토큰이 등록된 뒤에 FCM 토큰을 요청해야 한다. 실기기 부팅
    // 직후의 짧은 등록 지연만 흡수하고, 시뮬레이터/실패 상황은 상위에서
    // 앱 부팅을 막지 않도록 처리한다.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (await _messaging.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    return _messaging.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> configureForegroundPresentation() {
    return _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
}

/// 서버의 FCM 토큰 등록 API 계약.
abstract interface class FcmTokenRegistrar {
  Future<void> register({required String idToken, required String fcmToken});
}

class ApiFcmTokenRegistrar implements FcmTokenRegistrar {
  ApiFcmTokenRegistrar({String? baseUrl, AuthenticatedHttpClient? client})
    : _baseUrl = baseUrl ?? Env.apiBaseUrl,
      _client = client ?? appAuthenticatedHttpClient;

  final String _baseUrl;
  final AuthenticatedHttpClient _client;

  @override
  Future<void> register({
    required String idToken,
    required String fcmToken,
  }) async {
    final response = await _client.put(
      Uri.parse('$_baseUrl/me/fcm-token'),
      idToken: idToken,
      body: jsonEncode(<String, String>{'token': fcmToken}),
    );
    if (response.statusCode != 204) {
      throw StateError('FCM 토큰 등록 실패 (${response.statusCode})');
    }
  }
}

/// 앱 시작 시 권한을 확인하고, 로그인된 사용자의 FCM 토큰을 서버에 등록한다.
///
/// 권한 요청이나 토큰 등록 실패는 핵심 화면 진입을 막지 않는다. 다음 부팅,
/// 인증 상태 변경 또는 FCM 토큰 갱신 시 다시 시도한다.
class FcmService {
  FcmService({
    FcmMessagingClient? messaging,
    AuthSessionProvider? authSession,
    FcmTokenRegistrar? tokenRegistrar,
    this.supportedPlatform,
    this.registerBackgroundHandler = true,
    this.listenToMessages = true,
  }) : _messaging = messaging ?? FirebaseMessagingClient(),
       _authSession = authSession ?? FirebaseAuthSessionProvider(),
       _tokenRegistrar = tokenRegistrar ?? ApiFcmTokenRegistrar();

  final FcmMessagingClient _messaging;
  final AuthSessionProvider _authSession;
  final FcmTokenRegistrar _tokenRegistrar;
  final bool? supportedPlatform;

  final bool registerBackgroundHandler;
  final bool listenToMessages;

  /// 안드로이드 포그라운드 알림을 직접 띄우기 위한 로컬 알림 플러그인.
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'modi_default',
    'MODI 알림',
    description: 'MODI의 활동·일정 알림',
    importance: Importance.high,
  );

  StreamSubscription<AuthUserSnapshot?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  FcmAuthorizationStatus? _authorizationStatus;
  String? _latestToken;
  bool _initialized = false;
  bool _backgroundHandlerRegistered = false;
  bool _syncInProgress = false;
  bool _syncRequested = false;

  FcmAuthorizationStatus? get authorizationStatus => _authorizationStatus;

  bool get _isSupported =>
      supportedPlatform ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android));

  /// 백그라운드 메시지 핸들러는 앱 UI를 띄우기 전에도 등록할 수 있다.
  void registerBackgroundMessageHandler() {
    if (!registerBackgroundHandler ||
        !_isSupported ||
        _backgroundHandlerRegistered) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  Future<void> initialize() async {
    if (_initialized || !_isSupported) return;
    _initialized = true;

    registerBackgroundMessageHandler();

    // 🔴 **이 블록이 실패해도 아래 권한 요청까지 막으면 안 된다**(2026-08-16).
    //
    // 예전에는 이 안의 `await` 가 던지거나 영영 안 끝나면 `initialize()` 전체가 거기서
    // 끝났고, main.dart 가 `unawaited(...)` 로 부르는 탓에 **에러가 통째로 사라졌다.**
    // 그러면 `requestPermission()` 이 영영 안 불려 **알림 권한 팝업이 뜨지 않고**,
    // iOS 설정에 「알림」 항목조차 안 생긴다 — 로그에 아무 흔적이 없어 원인을 못 찾는다.
    // (2026-08-15 Apple 로그인의 `catch (_)` 와 같은 계열이다.)
    //
    // 메시지 수신 배선은 "있으면 좋은 것"이고 권한 요청은 "없으면 기능이 죽는 것"이라,
    // 실패해도 삼키지 말고 **남기고 계속 간다.**
    if (listenToMessages) {
      try {
        await _initLocalNotifications();
        _messageSubscription = FirebaseMessaging.onMessage.listen(
          _onForegroundMessage,
        );
        // 백그라운드에서 알림을 탭해 앱을 열었을 때.
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => unawaited(handleNotificationData(message.data)),
        );
        // 종료 상태에서 알림 탭으로 앱을 시작했을 때.
        // ⚠️ 타임아웃을 건다 — 이 호출이 안 끝나면 그 뒤 권한 요청도 영영 안 나간다.
        final initialMessage = await FirebaseMessaging.instance
            .getInitialMessage()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (initialMessage != null) {
          unawaited(handleNotificationData(initialMessage.data));
        }
      } catch (error, stackTrace) {
        debugPrint('FCM 메시지 수신 배선 실패(권한 요청은 계속한다): $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    _authSubscription = _authSession.authStateChanges.listen(
      (_) => unawaited(_syncToken()),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('FCM 인증 상태 연동 실패: ${error.runtimeType}');
      },
    );
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _latestToken = token;
      unawaited(_syncToken());
    });

    try {
      await _messaging.configureForegroundPresentation();
    } catch (error, stackTrace) {
      debugPrint('FCM foreground 설정 실패: ${error.runtimeType}');
      debugPrintStack(stackTrace: stackTrace);
    }

    // 🔴 결과를 **성공·실패 양쪽 다** 남긴다. 예전에는 실패만, 그것도 `runtimeType` 만
    // 찍어서 "팝업이 안 뜬다"를 신고받았을 때 **요청이 나갔는지조차 알 수 없었다**
    // (2026-08-16, TestFlight 빌드 5). 권한 상태 한 줄이면 진단이 몇 분으로 끝난다.
    try {
      _authorizationStatus = await _messaging.requestPermission();
      debugPrint('FCM 알림 권한: $_authorizationStatus');
      await _syncToken();
    } catch (error, stackTrace) {
      debugPrint('FCM 권한 요청 실패: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      // 상태바 작은 아이콘은 투명 배경 흰 실루엣이어야 한다(컬러 런처 아이콘을 쓰면
      // 하얀 네모로 뜸). MODI "M" 모노크롬 아이콘을 쓴다.
      android: AndroidInitializationSettings('@drawable/ic_stat_modi'),
      // 권한은 FCM(requestPermission)에서 이미 요청하므로 여기선 요청하지 않는다.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = (jsonDecode(payload) as Map).cast<String, dynamic>();
          unawaited(handleNotificationData(data));
        } catch (_) {
          // 잘못된 페이로드는 무시한다.
        }
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }

  void _onForegroundMessage(RemoteMessage message) {
    // iOS는 configureForegroundPresentation 설정으로 시스템이 배너를 띄운다.
    // Android는 포그라운드에서 자동 배너가 없어, 로컬 알림으로 직접 띄운다.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_modi',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _syncToken() async {
    if (_syncInProgress) {
      _syncRequested = true;
      return;
    }
    _syncInProgress = true;
    try {
      do {
        _syncRequested = false;
        await _syncTokenOnce();
      } while (_syncRequested);
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _syncTokenOnce() async {
    final permission = _authorizationStatus;
    if (permission != FcmAuthorizationStatus.authorized &&
        permission != FcmAuthorizationStatus.provisional) {
      return;
    }

    final user = _authSession.currentUser;
    if (user == null) return;

    try {
      final token = _latestToken ??= await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      final idToken = await _authSession.getIdToken();
      if (idToken == null || idToken.isEmpty) return;

      await _tokenRegistrar.register(idToken: idToken, fcmToken: token);
    } catch (error, stackTrace) {
      // 토큰 등록 실패는 로그인/화면 진입을 막지 않고 다음 이벤트에서 재시도한다.
      debugPrint('FCM 토큰 서버 등록 실패: ${error.runtimeType}');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
