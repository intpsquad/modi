// 이 파일은 **템플릿**이다. 실제 값이 들어간 lib/firebase_options.dart 는 커밋되지
// 않는다(.gitignore, README "로컬 전용 파일" 절).
//
// 로컬 개발: 아래 명령으로 실제 파일을 생성한다(이 템플릿을 복사해 쓰면 앱은 빌드되지만
//   Firebase 초기화가 실패해 로그인이 동작하지 않는다).
//     cd app && flutterfire configure -p modi-mara --platforms=android -a com.nomara.modi.app -y
//
// CI: .github/workflows/ci.yml 의 app 잡이 실제 파일이 없을 때 이 파일을
//   firebase_options.dart 로 복사한다. flutter analyze / dart format / flutter test 는
//   앱을 실행하지 않으므로 실제 키가 필요 없다 — 없으면 main.dart 가
//   "Target of URI doesn't exist" 로 analyze 에서 깨진다(2026-07-30 실측).
//
// FlutterFire CLI 가 실제 파일의 구조를 바꾸면 이 템플릿도 같이 맞춰야 한다.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // 전부 자리표시자다. 실제 값은 flutterfire configure 가 채운다.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-your-project-id',
    storageBucket: 'replace-with-your-project-id.firebasestorage.app',
  );
}
