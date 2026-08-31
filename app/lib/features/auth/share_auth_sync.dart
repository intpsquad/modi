import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/env.dart';

/// Keeps the Firebase ID token available to the iOS Share Extension.
///
/// iOS Share Extensions run in a separate process, so they cannot read the
/// Flutter Firebase Auth instance directly. The native AppDelegate stores the
/// token in a shared Keychain access group; this class only passes the current
/// token over a private method channel and never writes it to Dart storage.
class ShareAuthSync {
  ShareAuthSync._();

  static const _channel = MethodChannel('com.nomara.modi/share_auth');
  static StreamSubscription<User?>? _authSubscription;

  static void bind() {
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        _authSubscription != null) {
      return;
    }
    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen(
      (_) {
        unawaited(syncCurrentSession());
      },
      onError: (Object error, StackTrace stackTrace) {
        // 🔴 핸들러가 없으면 스트림 에러가 어디에도 안 남는다 — 이슈 #47 재현 중
        // syncCurrentSession()의 catch 가 타입명만 찍어 원인을 못 찾았던 것과
        // 같은 자리다. 부팅을 막지 않되 흔적은 남긴다.
        debugPrint('iOS 공유 세션 인증 상태 스트림 오류: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
  }

  static Future<void> syncCurrentSession() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await clearSharedSession();
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        await clearSharedSession();
        return;
      }

      await _channel.invokeMethod<void>('setSession', {
        'idToken': idToken,
        'apiBaseUrl': Env.apiBaseUrl,
      });
    } on PlatformException catch (error) {
      // Keep app startup resilient if the optional extension capability is not
      // present in a local build. Do not print token values or server details.
      debugPrint('iOS 공유 세션 동기화 실패: ${error.code}');
    } catch (error) {
      // 🔴 타입명만 남기면 안 된다(이슈 #47) — 여기서 던지는 FirebaseAuthException이
      // 죽은 Keychain 세션의 첫 증거였는데, `runtimeType`만 찍혀 원인 추적이
      // 오래 걸렸다. `FirebaseAuthException`은 code+message뿐이라(토큰 문자열을
      // 담지 않음) 이 catch-all에서 메시지 전체를 찍어도 된다.
      debugPrint('iOS 공유 세션 동기화 실패: $error');
    }
  }

  /// Firebase 로컬 세션 상태와 별개로 iOS 공유 확장의 Keychain 토큰을 지운다.
  /// 회원 탈퇴처럼 서버 계정은 이미 삭제됐지만 signOut이 실패한 경우에도 호출한다.
  static Future<void> clearSharedSession() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      await _channel.invokeMethod<void>('clearSession');
    } on PlatformException catch (error) {
      debugPrint('iOS 공유 세션 정리 실패: ${error.code}');
    } catch (error) {
      debugPrint('iOS 공유 세션 정리 실패: ${error.runtimeType}');
    }
  }
}
