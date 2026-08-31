import 'package:firebase_auth/firebase_auth.dart';

/// 죽은 Firebase Auth 세션이 원인으로 보이는 에러 코드.
///
/// `invalid-user-token`은 실기기 로그로 확인된 실제 실패 코드다(2026-08-30,
/// 이슈 #47):
/// ```
/// flutter: Apple 로그인 실패: [firebase_auth/invalid-user-token]
///   accessToken or refreshToken is nil
/// ```
/// `user-token-expired`는 같은 원인(Keychain에 저장된 세션의 토큰이 서버에서
/// 이미 무효화됨)의 자매 코드라 함께 잡는다.
const staleSessionErrorCodes = {'invalid-user-token', 'user-token-expired'};

/// 로그인 시도가 죽은 세션 때문에 실패하면 그 세션을 끊고 한 번만 다시 시도한다.
///
/// ## 왜 필요한가
///
/// iOS는 앱을 지워도 Keychain을 지우지 않는다. Firebase Auth가 세션을 거기
/// 두므로 재설치하면 옛 세션이 복원되는데(이슈 #29,
/// `routing/fresh_install.dart`), 그 항목의 토큰이 비어 있으면 **새 로그인
/// 시도조차** 위 코드로 실패한다.
///
/// `signOutIfFreshInstall`은 부팅 때 **딱 한 번**, 그것도 재설치가 감지될
/// 때만 돈다. 그 한 번의 창을 놓치면(예: 감지 시점에 `currentUser`가 아직
/// null이었거나 `signOut()`이 던져서 실패했다면) 사용자는 로그인 화면에서
/// 몇 번을 다시 눌러도 영구히 같은 에러를 본다. 이 함수는 그 자리에서
/// 스스로 복구되게 한다.
///
/// 해당 코드가 아닌 예외는 즉시 다시 던진다 — 멀쩡한 로그인 실패(예: 비밀번호
/// 오류)를 이 복구 경로가 건드리지 않는다. 재시도도 실패하면 그 예외를 그대로
/// 던진다(무한 재시도 없음).
///
/// ⚠️ **재시도는 `signIn` 전체를 처음부터 다시 부른다** — Firebase 세션
/// 교환만 다시 하는 게 아니다. 즉 Google/Kakao/Apple 로그인은 그 provider의
/// 네이티브 로그인 UI(카카오톡 전환, Apple 인증 시트 등)가 **한 번 더** 뜰 수
/// 있고, 카카오는 서버 `/auth/kakao` 교환도 한 번 더 탄다. 이 경로는 죽은
/// 세션 때문에 영구히 막혀 있던 사용자만 타므로(정상 로그인은 절대 재시도
/// 분기에 안 들어온다) UI가 한 번 더 뜨는 대가는 감수한다.
///
/// `signOut()` 자체가 던지면(예: 이 버그의 근본 원인인 손상된 세션 때문에
/// 로그아웃 처리 중에도 예외가 나는 경우) 그 예외로 원래의 유의미한 에러를
/// 가리지 않는다 — 무시하고 어차피 한 번은 재시도한다(`fresh_install.dart`의
/// `signOutIfFreshInstall`과 같은 선례: 부수 정리 실패가 본 동작을 막지 않는다).
Future<T> retryAfterClearingStaleSession<T>({
  required Future<T> Function() signIn,
  required Future<void> Function() signOut,
}) async {
  try {
    return await signIn();
  } on FirebaseAuthException catch (error) {
    if (!staleSessionErrorCodes.contains(error.code)) rethrow;
    try {
      await signOut();
    } catch (_) {
      // 아래 재시도가 어차피 원래 에러를 다시 낼 것이다 — signOut 실패로
      // 그 유의미한 에러를 가리지 않는다.
    }
    return await signIn();
  }
}
