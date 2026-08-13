# FCM 및 알림 권한 설정

앱은 부팅 후 알림 권한을 확인하고, 권한이 허용된 로그인 사용자의 FCM 토큰을
`PUT /me/fcm-token`으로 등록합니다. 토큰이 갱신되거나 로그인 상태가 바뀌면 최신
토큰을 다시 등록합니다.

## Firebase 콘솔

1. Firebase 프로젝트에 iOS 앱 `com.nomara.modi.app`을 등록합니다.
2. Firebase 콘솔의 프로젝트 설정에서 iOS 앱에 APNs 인증 키를 업로드합니다.
3. CI가 주입하는 `GoogleService-Info.plist`와 `firebase_options.dart`가 같은 Firebase
   프로젝트를 가리키는지 확인합니다.

## iOS

- Xcode Runner target의 Signing & Capabilities에 `Push Notifications` capability를
  추가합니다.
- `Background Modes` capability를 추가하고 `Remote notifications`를 켭니다.
- `Runner.entitlements`의 `aps-environment`가 Debug에서는 `development`,
  Release/Profile에서는 `production`으로 해석되는지 확인합니다.
- 새 capability가 포함된 새 빌드를 TestFlight에 올려야 합니다. 기존 빌드에는
  capability가 소급 적용되지 않습니다.

## Android

- Android 13 이상에서는 앱 첫 실행 시 알림 권한 요청이 표시됩니다.
- Firebase Android 앱의 패키지와 CI가 주입하는 `google-services.json`의 패키지가
  `com.nomara.modi.app`과 일치해야 합니다.

## 동작 범위

- iOS는 앱이 foreground일 때도 알림 배너/배지/소리를 허용합니다.
- background 또는 종료 상태에서는 FCM notification payload를 OS가 표시합니다.
- Android foreground에서 수신한 메시지는 현재 수신 로그만 남깁니다. foreground에서도
  시스템 알림을 표시하려면 별도의 로컬 알림 채널/표시 정책을 추가해야 합니다.
- 권한 요청이나 토큰 등록 실패는 앱 부팅을 막지 않으며 다음 로그인·토큰 갱신·앱
  재실행 시 다시 시도합니다.

## 로컬 검증

```bash
cd app
flutter pub get
flutter test test/features/notifications/fcm_service_test.dart
```
