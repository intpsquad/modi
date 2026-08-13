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
    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen((_) {
      unawaited(syncCurrentSession());
    });
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
      debugPrint('iOS 공유 세션 동기화 실패: ${error.runtimeType}');
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
