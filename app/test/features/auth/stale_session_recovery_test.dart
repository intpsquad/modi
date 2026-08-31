import 'package:app/features/auth/stale_session_recovery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이슈 #47 — 재설치로 남은 죽은 Keychain 세션 때문에 `invalid-user-token`으로
/// 로그인이 영구히 실패하던 것. 실기기 로그(2026-08-30)로 확인된 코드다:
/// `[firebase_auth/invalid-user-token] accessToken or refreshToken is nil`.
void main() {
  Future<({Object? result, int signInCalls, int signOutCalls})> run({
    required List<Object Function()> signInAttempts,
    Future<void> Function()? signOut,
  }) async {
    var signInCalls = 0;
    var signOutCalls = 0;
    Object? result;
    Object? thrown;

    try {
      result = await retryAfterClearingStaleSession<Object>(
        signIn: () async {
          final attempt = signInAttempts[signInCalls];
          signInCalls++;
          return attempt();
        },
        signOut: () async {
          signOutCalls++;
          if (signOut != null) await signOut();
        },
      );
    } catch (error) {
      thrown = error;
    }

    if (thrown != null) throw thrown;
    return (
      result: result,
      signInCalls: signInCalls,
      signOutCalls: signOutCalls,
    );
  }

  test('정상 로그인은 그대로 통과하고 signOut을 부르지 않는다', () async {
    final r = await run(signInAttempts: [() => 'user']);

    expect(r.result, 'user');
    expect(r.signInCalls, 1);
    expect(r.signOutCalls, 0);
  });

  test('invalid-user-token이면 signOut 후 한 번 재시도해 성공한다', () async {
    final r = await run(
      signInAttempts: [
        () => throw FirebaseAuthException(code: 'invalid-user-token'),
        () => 'user',
      ],
    );

    expect(r.result, 'user');
    expect(r.signInCalls, 2);
    expect(r.signOutCalls, 1);
  });

  test('user-token-expired도 같은 방식으로 복구한다', () async {
    final r = await run(
      signInAttempts: [
        () => throw FirebaseAuthException(code: 'user-token-expired'),
        () => 'user',
      ],
    );

    expect(r.result, 'user');
    expect(r.signInCalls, 2);
    expect(r.signOutCalls, 1);
  });

  test('재시도도 실패하면 그 예외를 던진다 — 무한 재시도 없음', () async {
    await expectLater(
      run(
        signInAttempts: [
          () => throw FirebaseAuthException(code: 'invalid-user-token'),
          () => throw FirebaseAuthException(code: 'invalid-user-token'),
        ],
      ),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'invalid-user-token',
        ),
      ),
    );
  });

  test('signOut 자체가 던져도 원래 에러를 가리지 않고 재시도한다', () async {
    final r = await run(
      signInAttempts: [
        () => throw FirebaseAuthException(code: 'invalid-user-token'),
        () => 'user',
      ],
      signOut: () async => throw StateError('signOut도 깨진 세션 때문에 실패'),
    );

    expect(r.result, 'user');
    expect(r.signInCalls, 2);
    expect(r.signOutCalls, 1);
  });

  test('signOut이 던지고 재시도도 실패하면 원래 로그인 에러를 던진다(signOut 에러가 아님)', () async {
    await expectLater(
      run(
        signInAttempts: [
          () => throw FirebaseAuthException(code: 'invalid-user-token'),
          () => throw FirebaseAuthException(code: 'invalid-user-token'),
        ],
        signOut: () async => throw StateError('signOut도 실패'),
      ),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'invalid-user-token',
        ),
      ),
    );
  });

  test('관계없는 코드는 즉시 다시 던지고 signOut을 부르지 않는다', () async {
    await expectLater(
      run(
        signInAttempts: [
          () => throw FirebaseAuthException(code: 'wrong-password'),
        ],
      ),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'wrong-password',
        ),
      ),
    );
  });

  test('FirebaseAuthException이 아닌 예외도 즉시 다시 던진다', () async {
    await expectLater(
      run(signInAttempts: [() => throw StateError('로그인이 취소되었습니다.')]),
      throwsA(isA<StateError>()),
    );
  });
}
