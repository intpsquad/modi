import 'package:firebase_auth/firebase_auth.dart';

import 'auth_diagnostics.dart';

/// 죽은 Firebase Auth 세션이 원인일 **수 있는** 에러 코드.
///
/// 🔴 **이 코드가 곧 「죽은 세션」은 아니다.** 2026-08-30 에는 그렇게 단정했는데
/// 틀렸다. `invalid-user-token` 은 Firebase iOS SDK 가 `completeSignIn` 에서
/// 토큰이 비면 던지는 코드이고(`User.retrieveUser`), 그 토큰은 **Apple 것이 아니라
/// Firebase 자신의 STS 토큰**이다. Keychain 에 남은 세션 말고도 그 자리에 도달하는
/// 길이 있다 — 이슈 #47 의 Apple 실패가 그렇다.
///
/// `user-token-expired` 는 같은 자리에서 나오는 자매 코드다.
const staleSessionErrorCodes = {'invalid-user-token', 'user-token-expired'};

/// 로그인이 위 코드로 실패하면 세션을 끊고 **한 번만** 다시 시도한다.
///
/// ## 왜 필요한가 (이슈 #29)
///
/// iOS 는 앱을 지워도 Keychain 을 지우지 않는다. Firebase Auth 가 세션을 거기
/// 두므로 재설치하면 옛 세션이 복원되는데(`routing/fresh_install.dart`), 그 항목의
/// 토큰이 비어 있으면 새 로그인 시도조차 위 코드로 실패한다.
///
/// `signOutIfFreshInstall` 은 부팅 때 **딱 한 번**, 그것도 재설치가 감지될 때만
/// 돈다. 그 창을 놓치면 사용자는 로그인 화면에서 몇 번을 눌러도 같은 에러를 본다.
///
/// ## ⚠️ 재시도는 네이티브 로그인 UI 를 한 번 더 띄운다
///
/// [signIn] 전체를 처음부터 다시 부른다 — Firebase 세션 교환만 다시 하는 게
/// 아니다. 카카오톡 전환·구글 계정 선택 시트가 **말없이 한 번 더** 뜬다.
///
/// 🔴 **Apple 은 이 함수를 쓰지 않는다.** [clearStaleSessionWithoutRetry] 를 쓴다 —
/// 이유는 거기 적었다.
Future<T> retryAfterClearingStaleSession<T>({
  required Future<T> Function() signIn,
  required Future<void> Function() signOut,
  String label = 'auth',
}) {
  return _recoverFromStaleSession(
    signIn: signIn,
    signOut: signOut,
    label: label,
    retry: true,
  );
}

/// 로그인이 위 코드로 실패하면 세션만 끊고 **에러를 그대로 던진다.** 자동
/// 재시도는 하지 않는다.
///
/// ## 왜 Apple 만 다른가 (이슈 #47)
///
/// 자동 재시도에는 전제가 있다 — **다시 하면 될 가능성이 있다.** Apple 에는
/// 그 전제가 깨져 있다:
///
/// - 재시도를 넣은 빌드(`4638bc5`)가 들어간 TestFlight 1.0.1 에서도 **똑같이
///   실패한다.** 실기기 로그에 `invalid-user-token` 이 연달아 찍혔다
/// - 그 재시도가 **Apple 인증 시트를 말없이 두 번 띄운다.** 사용자는 오류로
///   오해하고 두 번째를 닫는다 — #47 로그 `00:17:10` 의 `canceled` 가 실제 사례다
///
/// 즉 Apple 에서 재시도는 **고치지는 못하면서 방해만 한다.**
///
/// `signOut()` 은 남긴다. 세션을 끊어 두면 사용자가 **직접** 다시 눌렀을 때
/// 깨끗한 상태에서 시작한다 — #29 의 복구 효과는 그대로 두면서, 묻지 않고 시트를
/// 다시 띄우는 것만 뺀다. 한 번의 탭이 설명 없는 두 번째 인증창보다 낫다.
Future<T> clearStaleSessionWithoutRetry<T>({
  required Future<T> Function() signIn,
  required Future<void> Function() signOut,
  String label = 'auth',
}) {
  return _recoverFromStaleSession(
    signIn: signIn,
    signOut: signOut,
    label: label,
    retry: false,
  );
}

/// 해당 코드가 아닌 예외는 즉시 다시 던진다 — 멀쩡한 로그인 실패(비밀번호 오류 등)를
/// 이 경로가 건드리지 않는다. [retry] 재시도도 실패하면 그 예외를 그대로 던진다
/// (무한 재시도 없음).
///
/// `signOut()` 자체가 던지면 무시한다. 손상된 세션 때문에 로그아웃 처리 중에도
/// 예외가 날 수 있는데, 그걸로 원래의 유의미한 에러를 가리지 않는다
/// (`fresh_install.dart` 의 `signOutIfFreshInstall` 과 같은 선례).
Future<T> _recoverFromStaleSession<T>({
  required Future<T> Function() signIn,
  required Future<void> Function() signOut,
  required String label,
  required bool retry,
}) async {
  try {
    return await signIn();
  } on FirebaseAuthException catch (error) {
    if (!staleSessionErrorCodes.contains(error.code)) rethrow;
    logAuthFailure('$label.failed', error);
    try {
      await signOut();
    } catch (_) {
      // 아래가 원래 에러를 다시 낼 것이다 — signOut 실패로 그것을 가리지 않는다.
    }
    if (!retry) {
      logAuthStep('$label.retry.skipped', fields: {'reason': 'issue-47'});
      rethrow;
    }
    try {
      return await signIn();
    } on FirebaseAuthException catch (retryError) {
      logAuthFailure('$label.failed', retryError, isRetry: true);
      rethrow;
    }
  }
}
