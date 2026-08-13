import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/room/room_api.dart';

enum MembershipStatus { loading, none, has, error }

/// 인증 공급자가 노출하는 최소 사용자 정보.
/// Firebase User 객체를 앱 전체에 퍼뜨리지 않아 부팅 흐름을 단위 테스트할 수 있다.
class AuthUserSnapshot {
  const AuthUserSnapshot({required this.uid});

  final String uid;
}

/// 앱 부팅에 필요한 인증 계약.
/// 기본 구현은 Firebase Auth가 제공하며, 테스트에서는 메모리 구현으로 대체한다.
abstract interface class AuthSessionProvider {
  Stream<AuthUserSnapshot?> get authStateChanges;

  AuthUserSnapshot? get currentUser;

  Future<String?> getIdToken({bool forceRefresh = false});

  Future<void> signOut();
}

class FirebaseAuthSessionProvider implements AuthSessionProvider {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  Stream<AuthUserSnapshot?> get authStateChanges => _auth
      .authStateChanges()
      .map((user) => user == null ? null : AuthUserSnapshot(uid: user.uid));

  @override
  AuthUserSnapshot? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : AuthUserSnapshot(uid: user.uid);
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) {
    final user = _auth.currentUser;
    if (user == null) return Future.value(null);
    return user.getIdToken(forceRefresh);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// 인증 상태 + 방 소속 상태를 추적해 라우터 redirect(온보딩 게이팅, specs/0003-navigation.md)에 쓰는 세션.
/// bootstrap()을 호출하기 전에는 authKnown=false로 남아 있어(main()에서만 호출) 이를 호출하지 않는
/// 위젯 테스트는 항상 스플래시에 머문다.
class AppSession extends ChangeNotifier {
  AppSession({RoomApi? roomApi, AuthSessionProvider? authProvider})
    : _roomApi = roomApi ?? RoomApi(),
      _authProvider = authProvider ?? FirebaseAuthSessionProvider();

  final RoomApi _roomApi;
  final AuthSessionProvider _authProvider;
  StreamSubscription<AuthUserSnapshot?>? _authSub;
  Timer? _splashMinimumTimer;
  int _operationId = 0;
  String? _processedUserId;
  bool _processedSignedOut = false;
  bool _authenticationInvalidated = false;
  bool _disposed = false;
  String? _pendingInviteCode;

  bool authKnown = false;
  bool introKnown = false;
  bool introCompleted = false;
  MembershipStatus membership = MembershipStatus.loading;
  String? bootError;
  bool _splashMinimumElapsed = false;

  // 스플래시 최소 노출 — 페이드인(1000ms) 뒤 로고가 잠깐 머물도록 잡는다. 반드시
  // 페이드인 시간(splash_screen.dart)보다 커야 페이드가 끝난 뒤 넘어간다.
  // 너무 짧으면 로고가 뜨자마자 사라져 "휙" 지나가 보인다(2026-08-09 QA — 1.8초→1.2초 단축).
  static const splashMinimumDuration = Duration(milliseconds: 1200);

  bool get splashMinimumElapsed => _splashMinimumElapsed;

  bool get isSignedIn =>
      !_authenticationInvalidated && _authProvider.currentUser != null;

  String? get currentUserId => _authProvider.currentUser?.uid;

  /// 인증·온보딩 게이트를 통과하는 동안만 보관하는 카카오 방 초대 코드.
  ///
  /// URL을 각 로그인 화면 전환마다 전파하지 않아도, 로그인/가입 직후 참여 화면으로
  /// 돌아갈 수 있게 한다. 라우터가 방 참여 경로에 도착하면 즉시 비운다.
  String? get pendingInviteCode => _pendingInviteCode;

  void rememberPendingInviteCode(String code) {
    _pendingInviteCode = code;
  }

  void clearPendingInviteCode() {
    _pendingInviteCode = null;
  }

  void bootstrap() {
    _startSplashMinimumTimer();
    _authSub ??= _authProvider.authStateChanges.listen(
      _onAuthChanged,
      onError: _onAuthStreamError,
    );
  }

  void _startSplashMinimumTimer() {
    if (_splashMinimumElapsed || _splashMinimumTimer != null) return;
    _splashMinimumTimer = Timer(splashMinimumDuration, () {
      _splashMinimumTimer = null;
      if (_disposed) return;
      _splashMinimumElapsed = true;
      notifyListeners();
    });
  }

  /// SharedPreferences에서 읽은 S-01 완료 여부를 부팅 게이트에 반영한다.
  void setIntroStatus({required bool completed}) {
    introKnown = true;
    introCompleted = completed;
    notifyListeners();
  }

  /// S-01의 마지막 CTA 또는 건너뛰기를 누른 직후 라우터가 로그인으로 전환하게 한다.
  void markIntroCompleted() {
    introKnown = true;
    introCompleted = true;
    notifyListeners();
  }

  /// 서버 탈퇴가 성공한 뒤 Firebase의 로컬 signOut 결과와 무관하게 기존 계정 화면을
  /// 다시 열 수 없도록 인증 게이트를 먼저 닫는다. 이후 authStateChanges의 null 이벤트가
  /// 오면 일반적인 로그아웃 상태로 자연스럽게 수렴한다.
  void markAccountWithdrawn() {
    if (_disposed) return;
    _operationId++;
    _authenticationInvalidated = true;
    _processedUserId = null;
    _processedSignedOut = true;
    authKnown = true;
    membership = MembershipStatus.loading;
    bootError = null;
    notifyListeners();
  }

  Future<void> _onAuthChanged(AuthUserSnapshot? user) async {
    if (_disposed) return;

    final isDuplicate =
        authKnown &&
        !_authenticationInvalidated &&
        ((user == null && _processedSignedOut) ||
            (user != null && _processedUserId == user.uid));
    if (isDuplicate) return;

    _processedUserId = user?.uid;
    _processedSignedOut = user == null;
    authKnown = true;
    bootError = null;
    _authenticationInvalidated = false;
    if (user == null) {
      membership = MembershipStatus.loading;
      notifyListeners();
      return;
    }

    final operationId = ++_operationId;
    membership = MembershipStatus.loading;
    notifyListeners();
    await _loadMembership(user, operationId);
  }

  void _onAuthStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    debugPrint('인증 상태 스트림 초기화 실패: $error');
    authKnown = true;
    membership = MembershipStatus.error;
    bootError = '앱을 준비하지 못했어요.';
    notifyListeners();
  }

  Future<void> refreshMembership({bool forceRefresh = false}) async {
    final user = _authProvider.currentUser;
    if (user == null) {
      authKnown = true;
      membership = MembershipStatus.loading;
      notifyListeners();
      return;
    }

    _authenticationInvalidated = false;
    final operationId = ++_operationId;
    membership = MembershipStatus.loading;
    bootError = null;
    notifyListeners();
    await _loadMembership(
      user,
      operationId,
      firstAttemptForceRefresh: forceRefresh,
    );
  }

  Future<void> _loadMembership(
    AuthUserSnapshot user,
    int operationId, {
    bool firstAttemptForceRefresh = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final forceRefresh = firstAttemptForceRefresh || attempt == 1;
      String? idToken;
      try {
        idToken = await _authProvider.getIdToken(forceRefresh: forceRefresh);
        if (idToken == null || idToken.isEmpty) {
          if (attempt == 0 && !firstAttemptForceRefresh) continue;
          await _invalidateAuthentication(operationId);
          return;
        }
      } catch (error) {
        if (attempt == 0 && !firstAttemptForceRefresh) {
          // Firebase SDK가 토큰 갱신에 실패한 경우에도 한 번만 강제 갱신한다.
          continue;
        }
        await _invalidateAuthentication(operationId);
        return;
      }

      try {
        final rooms = await _roomApi.listMyRooms(idToken);
        if (!_isCurrentOperation(operationId, user)) return;
        membership = rooms.isEmpty
            ? MembershipStatus.none
            : MembershipStatus.has;
        bootError = null;
        notifyListeners();
        return;
      } on RoomApiException catch (error) {
        if (error.isUnauthorized && attempt == 0 && !firstAttemptForceRefresh) {
          continue;
        }
        if (error.isUnauthorized) {
          await _invalidateAuthentication(operationId);
          return;
        }
        _setBootError(operationId, user, error);
        return;
      } catch (error) {
        _setBootError(operationId, user, error);
        return;
      }
    }
  }

  bool _isCurrentOperation(int operationId, AuthUserSnapshot user) {
    return !_disposed &&
        operationId == _operationId &&
        isSignedIn &&
        currentUserId == user.uid;
  }

  void _setBootError(int operationId, AuthUserSnapshot user, Object error) {
    if (!_isCurrentOperation(operationId, user)) return;
    debugPrint('앱 부팅 중 방 목록 조회 실패: $error');
    membership = MembershipStatus.error;
    bootError = '앱을 준비하지 못했어요.';
    notifyListeners();
  }

  Future<void> _invalidateAuthentication(int operationId) async {
    if (_disposed || operationId != _operationId) return;
    _authenticationInvalidated = true;
    membership = MembershipStatus.loading;
    bootError = null;
    notifyListeners();
    try {
      await _authProvider.signOut();
    } catch (error) {
      // signOut 실패 시에도 로컬 게이트를 먼저 닫아 보호 화면으로 남지 않게 한다.
      debugPrint('만료된 인증 세션 정리 실패: $error');
    }
  }

  Future<void> retryBootstrap() async {
    if (_disposed) return;
    await refreshMembership();
  }

  /// 방 생성/참여 성공 직후 서버 재조회 없이 즉시 게이트를 통과시키기 위한 낙관적 업데이트.
  void markHasRooms() {
    bootError = null;
    membership = MembershipStatus.has;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _splashMinimumTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

final appSession = AppSession();
