/// 로그인 흐름을 단계별로 남긴다 — 이슈 #47.
///
/// ## 왜 있는가
///
/// #47 은 **코드를 읽어서 세운 가설 두 개가 연달아 틀린** 이슈다. 「entitlements
/// 누락」도 「재설치 후 Keychain 세션」도 아니었고, 2026-09-01 에 「Firebase 콘솔의
/// Apple 설정이 옛 계정 것」으로 원인을 확정했다가 그것도 철회했다(운영 DB 에
/// 팀 변경 이후 가입한 Apple 사용자가 7명 있었다 — 전원 실패가 아니다).
///
/// 매번 막힌 이유는 같다: **실패하는 기기에서 어디까지 갔는지를 모른다.**
/// 지금 아는 것은 `invalid-user-token` 한 줄뿐이고, 그것도 `964a3d4` 가
/// `catch (_)` 를 걷어낸 덕에 겨우 남은 것이다(`login_screen.dart:84`).
///
/// SDK 소스상 실패 지점은 여기다(`FirebaseAuth 11.15.0`, `Auth.swift:2114-2135`):
/// ```
/// VerifyAssertion → 200 → needConfirmation 아님 → providerID 있음
///                                                   ↑ 어서션 검증은 통과했다
/// → completeSignIn(idToken, refreshToken) → 둘 중 하나가 nil → invalid-user-token
/// ```
/// 즉 Apple 인증도 Firebase 검증도 **통과한 뒤** Firebase 응답에 자기 토큰이 없다.
/// 이 로그는 그 그림이 실기기에서도 맞는지, 아니면 더 앞에서 죽는지를 가른다.
///
/// ## 🔴 남기지 않는 것
///
/// **토큰·UID·이메일·이름은 어떤 형태로도 넣지 않는다.** 이 출력은 TestFlight
/// 빌드에서 Console.app 으로 그대로 보이고, 기기 로그는 우리가 지울 수 없다.
/// 세션은 **유무만**(`present`/`none`) 남긴다.
///
/// ## 읽는 법
///
/// Console.app 에서 프로세스 `Runner`, 검색어 `[auth]`. `debugPrint` 는 릴리스
/// 빌드에서도 시스템 로그로 나간다 — #47 의 기존 로그가 그렇게 잡혔다.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

const _tag = '[auth]';

/// 로그인 흐름의 한 단계. [step] 은 `apple.firebase.ok` 처럼 점으로 구분한다.
void logAuthStep(String step, {Map<String, Object?>? fields}) {
  debugPrint('$_tag $step${_render(fields)}');
}

/// 로그인 실패. 코드·메시지와 **그 시점의 세션 유무**를 함께 남긴다.
///
/// 세션 유무가 중요하다 — `completeSignIn` 이 실패했으므로 `none` 이어야 한다.
/// `present` 로 찍히면 실패 지점이 우리가 읽은 곳이 아니라는 뜻이고, 가설을
/// 다시 세워야 한다.
void logAuthFailure(
  String step,
  Object error, {
  bool isRetry = false,
  Map<String, Object?>? fields,
}) {
  final detail = <String, Object?>{
    if (error is FirebaseAuthException) ...{
      'code': error.code,
      'message': error.message,
    } else
      'error': error.runtimeType.toString(),
    'session': describeFirebaseSession(),
    'attempt': isRetry ? 'retry' : 'first',
    ...?fields,
  };
  debugPrint('$_tag $step${_render(detail)}');
}

/// 지금 Firebase 세션이 있는지 — **값이 아니라 유무만** 돌려준다.
///
/// Firebase 가 초기화되지 않은 환경(위젯 테스트 등)에서는 `unknown` 이다.
/// 진단 로그가 그 자체로 예외를 내서 흐름을 바꾸면 안 된다.
String describeFirebaseSession() {
  try {
    return FirebaseAuth.instance.currentUser == null ? 'none' : 'present';
  } catch (_) {
    return 'unknown';
  }
}

String _render(Map<String, Object?>? fields) {
  if (fields == null || fields.isEmpty) return '';
  final parts = fields.entries
      .where((e) => e.value != null)
      .map((e) => '${e.key}=${e.value}');
  return parts.isEmpty ? '' : ' ${parts.join(' ')}';
}
