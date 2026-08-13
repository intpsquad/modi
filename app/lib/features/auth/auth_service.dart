import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/env.dart';
import 'api_client.dart';

/// 소셜 로그인과 이메일 회원가입을 Firebase Authentication 세션으로 교환한다.
/// Google·Apple은 Firebase 네이티브 provider를 사용하고, Kakao는 Spring Custom Token을 교환한다.
class AuthService {
  AuthService({
    GoogleSignIn? googleSignIn,
    ApiClient? apiClient,
    KakaoLoginClient? kakaoLoginClient,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn(),
       _apiClient = apiClient ?? ApiClient(),
       _kakaoLoginClient = kakaoLoginClient ?? KakaoLoginClient();

  final GoogleSignIn _googleSignIn;
  final ApiClient _apiClient;
  final KakaoLoginClient _kakaoLoginClient;

  Future<User> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw StateError('로그인이 취소되었습니다.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Firebase 로그인에 실패했습니다.');
    }

    if (userCredential.additionalUserInfo?.isNewUser ?? false) {
      await _syncOAuthProfile(user);
    }
    return user;
  }

  /// Apple의 네이티브 인증 결과를 Firebase Authentication 세션으로 교환한다.
  /// Apple은 첫 승인 때만 이름과 이메일을 제공할 수 있으므로, 신규 사용자일 때
  /// Firebase 프로필을 서버 users 행에 한 번 동기화한다.
  Future<User> signInWithApple() async {
    if (kIsWeb) {
      throw StateError('애플 로그인은 현재 모바일 앱에서만 지원합니다.');
    }

    final appleProvider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCredential = await FirebaseAuth.instance.signInWithProvider(
      appleProvider,
    );
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Firebase 로그인에 실패했습니다.');
    }

    if (userCredential.additionalUserInfo?.isNewUser ?? false) {
      await _syncOAuthProfile(user);
    }
    return user;
  }

  /// 이메일·비밀번호로 기존 계정에 로그인한다(자체가입 계정 전용).
  /// 서버 ID 토큰 검증은 건드리지 않는다 — 클라이언트 Firebase 세션만 연다.
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final userCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Firebase 로그인에 실패했습니다.');
    }
    return user;
  }

  Future<User> signInWithKakao() async {
    final accessToken = await _kakaoLoginClient.signIn();
    final response = await _apiClient.exchangeKakaoAccessToken(accessToken);
    final userCredential = await FirebaseAuth.instance.signInWithCustomToken(
      response.firebaseToken,
    );
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Firebase 로그인에 실패했습니다.');
    }
    return user;
  }

  /// 이메일로 인증코드(6자리)를 발송한다.
  Future<void> sendEmailVerificationCode(String email) async {
    await _apiClient.sendEmailVerificationCode(email);
  }

  /// 이메일·코드 쌍을 검증한다.
  Future<void> verifyEmailCode(String email, String code) async {
    await _apiClient.verifyEmailCode(email, code);
  }

  /// 이메일·비밀번호 계정을 만들고, 입력한 프로필을 서버 users 행에 저장한다.
  Future<void> signUpWithEmail({
    required String email,
    required String nickname,
    required String password,
    String? profileImage,
  }) async {
    final userCredential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Firebase 회원가입에 실패했습니다.');
    }

    await user.updateDisplayName(nickname);
    if (profileImage != null && profileImage.isNotEmpty) {
      await user.updatePhotoURL(profileImage);
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('회원가입 세션을 준비하지 못했습니다.');
    }
    await _apiClient.updateProfile(
      idToken,
      nickname: nickname,
      profileImage: profileImage,
    );
  }

  /// 로그인한 사용자의 uid — 투두 탭의 "내 투두만" 필터·담당자 자동 지정(specs/0006-투두-탭.md)에 쓴다.
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// 서버 호출에 쓸 ID 토큰(JWT). 만료 임박 시 자동 갱신됨(getIdToken 기본 동작).
  Future<String> getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw StateError('ID 토큰을 가져오지 못했습니다.');
    }
    return token;
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  Future<void> _syncOAuthProfile(User user) async {
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('로그인 세션을 준비하지 못했습니다.');
    }

    final nickname = _oauthNickname(user);
    await _apiClient.updateProfile(
      idToken,
      nickname: nickname,
      profileImage: user.photoURL,
    );
  }

  String _oauthNickname(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = user.email;
    final localPart = email?.split('@').first.trim();
    if (localPart != null && localPart.isNotEmpty) return localPart;
    return '사용자';
  }
}

/// KakaoTalk을 우선 시도하고, KakaoTalk을 사용할 수 없으면 Kakao Account로 전환한다.
class KakaoLoginClient {
  Future<String> signIn() async {
    if (kIsWeb) {
      throw StateError('카카오 로그인은 현재 모바일 앱에서만 지원합니다.');
    }
    if (Env.kakaoNativeAppKey.isEmpty) {
      throw StateError(
        'KAKAO_NATIVE_APP_KEY가 설정되지 않았습니다. 모바일 실행 시 --dart-define으로 전달해 주세요.',
      );
    }

    final OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk();
      } on KakaoClientException catch (error) {
        if (error.reason == ClientErrorCause.cancelled) rethrow;
        return (await UserApi.instance.loginWithKakaoAccount()).accessToken;
      } on KakaoException {
        return (await UserApi.instance.loginWithKakaoAccount()).accessToken;
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }
    return token.accessToken;
  }
}
