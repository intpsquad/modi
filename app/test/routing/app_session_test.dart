import 'dart:async';

import 'package:app/features/room/room_api.dart';
import 'package:app/routing/app_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthProvider implements AuthSessionProvider {
  _FakeAuthProvider()
    : _authStateController = StreamController<AuthUserSnapshot?>.broadcast();

  final StreamController<AuthUserSnapshot?> _authStateController;
  final List<bool> forceRefreshCalls = [];
  String? credential = 'id-value';
  @override
  AuthUserSnapshot? currentUser;
  Object? tokenError;
  int signOutCalls = 0;

  @override
  Stream<AuthUserSnapshot?> get authStateChanges => _authStateController.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    forceRefreshCalls.add(forceRefresh);
    if (tokenError != null) throw tokenError!;
    return credential;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUser = null;
    _authStateController.add(null);
  }

  void emitUser(String uid) {
    currentUser = AuthUserSnapshot(uid: uid);
    _authStateController.add(currentUser);
  }

  Future<void> close() => _authStateController.close();
}

class _FakeRoomApi extends RoomApi {
  _FakeRoomApi(this.handler);

  final Future<List<Map<String, dynamic>>> Function(String token) handler;
  final List<String> receivedTokens = [];

  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) {
    receivedTokens.add(idToken);
    return handler(idToken);
  }
}

Future<void> _settle() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _room(int id) => {
  'id': id,
  'name': '방$id',
  'goal': '목표$id',
  'status': 'ACTIVE',
  'startDate': '2026-01-01',
  'endDate': '2026-12-31',
};

void main() {
  late _FakeAuthProvider authProvider;
  late AppSession session;

  setUp(() {
    authProvider = _FakeAuthProvider();
  });

  tearDown(() async {
    session.dispose();
    await authProvider.close();
  });

  test('bootstrap을 여러 번 호출해도 인증 스트림과 부팅 요청은 한 번만 연결된다', () async {
    var roomRequests = 0;
    final roomApi = _FakeRoomApi((_) async {
      roomRequests++;
      return [_room(1)];
    });
    session = AppSession(roomApi: roomApi, authProvider: authProvider);

    session.bootstrap();
    session.bootstrap();
    authProvider.emitUser('user-1');
    await _settle();

    expect(roomRequests, 1);
    expect(session.membership, MembershipStatus.has);
  });

  test('앱 최초 부팅 스플래시는 최소 노출 시간을 유지한다', () {
    session = AppSession(
      roomApi: _FakeRoomApi((_) async => []),
      authProvider: authProvider,
    );

    fakeAsync((async) {
      expect(session.splashMinimumElapsed, isFalse);
      session.bootstrap();

      expect(session.splashMinimumElapsed, isFalse);
      // 최소 노출 직전까지는 아직 false.
      async.elapse(
        AppSession.splashMinimumDuration - const Duration(milliseconds: 1),
      );
      expect(session.splashMinimumElapsed, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(session.splashMinimumElapsed, isTrue);
    });
  });

  test('인증된 사용자에게 방이 있으면 자동 로그인 후 홈 게이트를 통과한다', () async {
    session = AppSession(
      roomApi: _FakeRoomApi((_) async => [_room(1)]),
      authProvider: authProvider,
    );
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();

    expect(session.authKnown, true);
    expect(session.isSignedIn, true);
    expect(session.membership, MembershipStatus.has);
    expect(session.bootError, isNull);
    expect(authProvider.forceRefreshCalls, [false]);
  });

  test('인증된 사용자에게 방이 없으면 방 설정 게이트로 남는다', () async {
    session = AppSession(
      roomApi: _FakeRoomApi((_) async => []),
      authProvider: authProvider,
    );
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();

    expect(session.membership, MembershipStatus.none);
    expect(session.isSignedIn, true);
  });

  test('방 목록 401이면 ID 토큰을 강제 갱신해 한 번 재시도한다', () async {
    var requestCount = 0;
    final roomApi = _FakeRoomApi((token) async {
      requestCount++;
      if (requestCount == 1) {
        throw const RoomApiException(statusCode: 401, operation: '내 방 목록 조회');
      }
      expect(token, 'id-value');
      return [_room(1)];
    });
    session = AppSession(roomApi: roomApi, authProvider: authProvider);
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();

    expect(requestCount, 2);
    expect(authProvider.forceRefreshCalls, [false, true]);
    expect(authProvider.signOutCalls, 0);
    expect(session.membership, MembershipStatus.has);
  });

  test('토큰 강제 갱신 뒤에도 401이면 인증 정보를 지우고 로그인 게이트로 돌아간다', () async {
    final roomApi = _FakeRoomApi(
      (_) async =>
          throw const RoomApiException(statusCode: 401, operation: '내 방 목록 조회'),
    );
    session = AppSession(roomApi: roomApi, authProvider: authProvider);
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();

    expect(authProvider.forceRefreshCalls, [false, true]);
    expect(authProvider.signOutCalls, 1);
    expect(session.isSignedIn, false);
    expect(session.membership, MembershipStatus.loading);
  });

  test('인증 외의 부팅 오류를 방이 없는 상태로 오인하지 않는다', () async {
    final roomApi = _FakeRoomApi(
      (_) async =>
          throw const RoomApiException(statusCode: 503, operation: '내 방 목록 조회'),
    );
    session = AppSession(roomApi: roomApi, authProvider: authProvider);
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();

    expect(session.membership, MembershipStatus.error);
    expect(session.bootError, isNotNull);
    expect(session.isSignedIn, true);
    expect(authProvider.signOutCalls, 0);
  });

  test('회원 탈퇴 완료는 Firebase 로그아웃 전에도 앱 접근 게이트를 닫는다', () {
    session = AppSession(
      roomApi: _FakeRoomApi((_) async => [_room(1)]),
      authProvider: authProvider,
    );
    authProvider.currentUser = const AuthUserSnapshot(uid: 'user-1');

    session.markAccountWithdrawn();

    expect(session.isSignedIn, false);
    expect(session.membership, MembershipStatus.loading);
    expect(session.bootError, isNull);
  });

  test('이전 부팅 요청의 늦은 응답은 최신 인증 상태를 덮어쓰지 않는다', () async {
    final firstRequest = Completer<List<Map<String, dynamic>>>();
    final roomApi = _FakeRoomApi((token) {
      if (token == 'first-id') return firstRequest.future;
      return Future.value([]);
    });
    authProvider.credential = 'first-id';
    session = AppSession(roomApi: roomApi, authProvider: authProvider);
    session.bootstrap();

    authProvider.emitUser('user-1');
    await _settle();
    authProvider.credential = 'second-id';
    authProvider.emitUser('user-2');
    await _settle();
    expect(session.membership, MembershipStatus.none);

    firstRequest.complete([_room(1)]);
    await _settle();

    expect(session.currentUserId, 'user-2');
    expect(session.membership, MembershipStatus.none);
  });
}
