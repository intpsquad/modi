# FCM 및 알림 권한 설정

앱은 부팅 후 알림 권한을 확인하고, 권한이 허용된 로그인 사용자의 FCM 토큰을
`PUT /me/fcm-token`으로 등록합니다. 토큰이 갱신되거나 로그인 상태가 바뀌면 최신
토큰을 다시 등록합니다.

## Firebase 콘솔

1. Firebase 프로젝트에 iOS 앱 `com.intpsquad.modi`을 등록합니다.
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
  `com.intpsquad.modi`과 일치해야 합니다.

## 동작 범위

- iOS는 앱이 foreground일 때도 알림 배너/배지/소리를 허용합니다.
- background 또는 종료 상태에서는 FCM notification payload를 OS가 표시합니다.
- Android foreground에서 수신한 메시지는 로컬 알림(`modi_default` 채널)으로 직접 띄웁니다.

### 토큰 등록 재시도 — 2026-08-31 (#66)

권한 요청이나 토큰 등록 실패는 앱 부팅을 막지 않습니다. 실패하면 **2초 → 5초 → 15초 →
30초 → 60초** 로 다섯 번 다시 시도하고, 그 예산을 다 써도 **앱이 다시 앞으로 나올 때마다**
처음부터 다시 시도합니다. 로그인·토큰 갱신 때도 처음부터 다시 셉니다.

🔴 **이 문단은 원래 "다음 로그인·토큰 갱신·앱 재실행 시 다시 시도합니다" 였고, 그게 사실이
아니었습니다.** iOS는 APNs 토큰이 등록된 뒤에야 FCM 토큰을 주는데, 그때까지 2초만 기다리고
포기한 뒤 **아무도 다시 부르지 않았습니다** — 토큰을 못 받았으니 토큰 갱신 이벤트가 오지 않고,
로그인 상태가 유지되면 인증 상태 변경도 오지 않으며, iOS 사용자는 앱을 강제 종료하는 일이
드물어 "앱 재실행"도 며칠 뒤일 수 있습니다. 그래서 **한 번 놓친 사용자는 영구히 푸시를 못
받았습니다**(2026-08-31 기준 유저 40명 중 토큰 보유 8명). 이 문장이 그 버그를 "설계된 동작"처럼
보이게 만들었으므로, 재시도 사다리를 바꾸면 여기도 반드시 함께 고칩니다.

실패 원인은 기기 로그에 남습니다 — Mac에 아이폰을 연결하고 **Console.app** 에서 `FCM` 으로
검색하면 됩니다. 토큰 값 자체는 기기 식별자라 절대 찍지 않습니다.

서버 쪽에서는 토큰이 없어 발송을 건너뛴 것도 로그로 남습니다
(`FCM 토큰이 없어 푸시를 건너뛴다`). 그전에는 조용히 넘어가서 "발송 성공"과 "시도조차 안 함"을
구분할 수 없었습니다.

## 로컬 검증

```bash
cd app
flutter pub get
flutter test test/features/notifications/fcm_service_test.dart
```
