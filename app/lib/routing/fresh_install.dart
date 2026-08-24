import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/onboarding/intro_screen.dart';

/// 앱을 지웠다 다시 깐 경우 남아 있는 로그인 세션을 끊는다.
///
/// **iOS 는 앱을 삭제해도 Keychain 을 지우지 않는다.** Firebase Auth 가 세션을 거기 두므로
/// 재설치하면 로그인 화면 없이 이전 계정으로 들어가진다(2026-08-16 실측, 이슈 #29).
/// Firebase 버그가 아니라 iOS 의 정상 동작이고, 우리는 공유 확장과 세션을 나누려고
/// `keychain-access-groups` 까지 써서 더 확실히 남는다.
///
/// 문제는 **폰을 넘기기 전에 앱만 지운 경우 다음 사람이 그 계정으로 들어간다**는 것이다.
/// 로그아웃한 적이 없으니 서버 세션도 살아 있다.
///
/// ## 어떻게 가려내나
///
/// `SharedPreferences` 는 Keychain 과 달리 **앱을 지우면 같이 지워진다.** 그 차이가 신호다.
///
/// | 상황 | 우리 설정값 | 세션 | 처리 |
/// |---|---|---|---|
/// | 기존 사용자가 업데이트 | 있음 | 있음 | 그대로 둔다 |
/// | 지웠다 재설치 | 없음 | **있음** | 🔴 로그아웃 |
/// | 완전 신규 | 없음 | 없음 | 할 것 없음 |
///
/// 🔴 **1행이 이 함수의 존재 이유다.** 표식을 새로 만들어 "없으면 로그아웃" 으로 짜면
/// 이 변경이 든 빌드로 올라오는 **실사용자가 전원 한 번 로그아웃된다.** 이미 있는
/// [onboardingIntroCompletedKey] 를 쓰면 그들은 값이 남아 있어 걸러진다.
///
/// 그 키를 고른 이유: 인트로의 「건너뛰기」와 마지막 버튼이 **둘 다** 같은 `_complete()` 를
/// 거쳐 이 값을 저장한다(`intro_screen.dart`). 즉 **로그인 화면에 도달한 사람은 예외 없이
/// `true`** 다. `last_viewed_room_id` 는 `RoomSession` 안에서 private 이라 쓸 수 없다.
///
/// 공유 확장은 따로 지우지 않아도 된다 — `ShareAuthSync` 가 `idTokenChanges` 를 듣고 있어
/// 로그아웃하면 Keychain 토큰을 함께 비운다.
///
/// [hasSession] 과 [signOut] 을 주입받는 것은 **Firebase 없이 테스트하기 위해서**다.
/// 로그아웃했으면 `true` 를 돌려준다.
Future<bool> signOutIfFreshInstall({
  required SharedPreferences prefs,
  required bool hasSession,
  required Future<void> Function() signOut,
}) async {
  // 이 기기에서 앱이 돌았던 적이 있다 → 업데이트다. 건드리지 않는다.
  if (prefs.getBool(onboardingIntroCompletedKey) ?? false) return false;

  // 새 설치인데 세션도 없다 → 정상적인 첫 실행.
  if (!hasSession) return false;

  // 새 설치인데 세션이 살아 있다 = Keychain 에서 되살아난 것이다.
  try {
    await signOut();
    debugPrint('재설치가 감지돼 남아 있던 로그인 세션을 끊었다(#29).');
    return true;
  } catch (error, stackTrace) {
    // 🔴 부팅을 막지 않는다. 다만 조용히 삼키지도 않는다 — 2026-08-16 FCM 초기화가
    // `unawaited` 로 예외를 삼켜 알림 권한이 왜 안 뜨는지 못 찾았던 것과 같은 자리다.
    debugPrint('재설치 로그아웃 실패 — 이전 계정으로 들어갈 수 있다: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  }
}
