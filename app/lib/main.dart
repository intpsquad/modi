import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config/env.dart';
import 'features/auth/share_auth_sync.dart';
import 'features/notifications/fcm_service.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/room/invite_share.dart';
import 'firebase_options.dart';
import 'routing/app_router.dart';
import 'routing/app_session.dart';

final appFcmService = FcmService();

/// Kakao Flutter SDK가 수신하는 `kakao{NativeAppKey}://kakaolink` 실행 URL을
/// GoRouter의 방 참여 경로로 전달한다. 라우터가 인증·온보딩 중이면 초대 코드를
/// AppSession에 잠시 보관했다가 S-11에서 프리필한다.
void _routeKakaoInvite(Uri uri) {
  final location = inviteJoinLocation(uri);
  if (location != null) appRouter.go(location);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  if (!kIsWeb && Env.kakaoNativeAppKey.isNotEmpty) {
    // Kakao common plugin이 kakaolink intent를 직접 처리하므로 Flutter 기본
    // deep-link handler가 아니라 SDK callback에서 GoRouter로 넘긴다.
    receiveKakaoScheme(_routeKakaoInvite);
    await KakaoSdk.init(nativeAppKey: Env.kakaoNativeAppKey);
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ShareAuthSync.bind();
  unawaited(ShareAuthSync.syncCurrentSession());
  final prefs = await SharedPreferences.getInstance();
  appSession.setIntroStatus(
    completed: prefs.getBool(onboardingIntroCompletedKey) ?? false,
  );
  appSession.bootstrap();
  appFcmService.registerBackgroundMessageHandler();
  runApp(const ProviderScope(child: App()));
  // 권한 팝업/토큰 등록이 첫 화면 진입을 막지 않도록 UI가 올라온 뒤 시작한다.
  //
  // 🔴 **맨 `unawaited` 로 두지 말 것**(2026-08-16). 그러면 이 안에서 던진 예외가
  // 어디에도 안 남아 **알림 권한 팝업이 안 뜨는데 이유를 알 수 없는** 상태가 된다
  // (TestFlight 빌드 5 실측). 부팅을 막지 않되 흔적은 남긴다.
  unawaited(
    appFcmService.initialize().catchError((Object error, StackTrace stack) {
      debugPrint('FCM 초기화 실패 — 알림이 오지 않는다: $error');
      debugPrintStack(stackTrace: stack);
    }),
  );
}
