import 'package:app/features/onboarding/intro_screen.dart';
import 'package:app/routing/fresh_install.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 이슈 #29 — 앱을 지웠다 다시 깔아도 이전 계정으로 들어가지던 것.
///
/// iOS 는 앱 삭제로 Keychain 을 지우지 않아 Firebase 세션이 되살아난다. 반면
/// SharedPreferences 는 함께 지워지므로, **우리 값이 없는데 세션만 있으면 재설치**다.
void main() {
  /// 세 갈래를 한 곳에서 돌린다. `signOut` 호출 횟수를 세서 판정한다.
  Future<({bool signedOut, int calls})> run({
    required Map<String, Object> stored,
    required bool hasSession,
    Future<void> Function()? signOut,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final signedOut = await signOutIfFreshInstall(
      prefs: prefs,
      hasSession: hasSession,
      signOut: () async {
        calls++;
        if (signOut != null) await signOut();
      },
    );
    return (signedOut: signedOut, calls: calls);
  }

  /// 🔴 **이 파일에서 가장 중요한 테스트.** 깨지면 이 빌드로 업데이트하는 실사용자가
  /// 전원 한 번 로그아웃된다. 표식을 새로 만들지 않고 이미 있는 인트로 키를 쓰는 이유다.
  test('쓰던 앱을 업데이트한 사용자는 로그아웃되지 않는다', () async {
    final r = await run(
      stored: {onboardingIntroCompletedKey: true},
      hasSession: true,
    );

    expect(r.signedOut, isFalse);
    expect(r.calls, 0);
  });

  test('앱을 지웠다 다시 깔았는데 세션이 살아 있으면 로그아웃한다', () async {
    // 앱을 지우면 SharedPreferences 도 함께 지워져 비어 있다.
    final r = await run(stored: {}, hasSession: true);

    expect(r.signedOut, isTrue);
    expect(r.calls, 1);
  });

  test('완전 신규 설치는 아무것도 하지 않는다', () async {
    final r = await run(stored: {}, hasSession: false);

    expect(r.signedOut, isFalse);
    expect(r.calls, 0);
  });

  /// 부팅 경로에서 불리므로 실패해도 앱이 뜨는 것을 막으면 안 된다.
  /// (2026-08-16 FCM 초기화가 예외를 삼켜 알림 권한을 못 찾았던 것과 같은 자리다.)
  test('로그아웃이 실패해도 던지지 않고 false 를 돌려준다', () async {
    final r = await run(
      stored: {},
      hasSession: true,
      signOut: () async => throw StateError('네트워크 오류'),
    );

    expect(r.signedOut, isFalse);
    expect(r.calls, 1); // 시도는 했다
  });

  test('인트로 키가 false 로 남아 있어도 재설치로 본다', () async {
    // 인트로를 끝내면 반드시 true 가 들어간다(intro_screen.dart의 _complete).
    // false 가 저장돼 있는 경로는 없지만, 방어적으로 고정해 둔다.
    final r = await run(
      stored: {onboardingIntroCompletedKey: false},
      hasSession: true,
    );

    expect(r.signedOut, isTrue);
  });
}
