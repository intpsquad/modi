# FCM 및 알림 권한 설정

앱은 부팅 후 알림 권한을 확인하고, 권한이 허용된 로그인 사용자의 FCM 토큰을
`PUT /me/fcm-token`으로 등록합니다. 토큰이 갱신되거나 로그인 상태가 바뀌면 최신
토큰을 다시 등록합니다.

## Firebase 콘솔

1. Firebase 프로젝트에 iOS 앱 `com.intpsquad.modi`을 등록합니다.
2. Firebase 콘솔의 프로젝트 설정에서 iOS 앱에 APNs 인증 키를 업로드합니다.
   → **아래 「APNs 인증 키는 반드시 `Sandbox & Production` 으로 발급한다」를 먼저 읽으세요.**
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

🔴 **위 iOS 두 줄은 아래 「알림 배선」이 있어야 사실입니다.** 2026-09-14 이전에는 배선이
통째로 죽어 있어서 포그라운드 배너도, 알림 탭도, 푸시 자체도 동작하지 않았습니다.

### 🔴 APNs 인증 키는 반드시 `Sandbox & Production` 으로 발급한다 — 2026-09-14 (#66)

Apple Developer 에서 APNs 키를 만들 때 **Environment** 를 고르는 화면이 나옵니다. 기본값이
`Sandbox` 인데, 그대로 저장하면 **Xcode 로 직접 돌린 개발 빌드에만 먹힙니다.**
TestFlight·App Store 빌드는 프로덕션 APNs 를 쓰므로 푸시가 하나도 안 갑니다.

🔴 **Environment 는 저장 후 바꿀 수 없습니다.** 잘못 만들었으면 키를 새로 발급해야 합니다.

| 항목 | 값 |
|---|---|
| Environment | **`Sandbox & Production`** |
| Key Restriction | `Team Scoped (All Topics)` |

#### 증상과 판별법

서버 로그에 이렇게 남습니다:

```
FCM 푸시 발송 실패: Invalid APNs credential.
```

Firebase 콘솔에서 바로 확인됩니다 — 프로젝트 설정 → 클라우드 메시징 →
**`com.intpsquad.modi`** 선택 → 「APN 인증 키」:

```
📄 개발 APNs 인증 키              ← 키가 여기에만 있으면 잘못 발급된 것
프로덕션 APNs 인증 키가 없습니다.   ← 여기가 채워져 있어야 한다
```

2026-09-14 에 정확히 이 상태였습니다. `Sandbox` 로 저장된 키라 Firebase 가 개발용으로만
분류했고, TestFlight 빌드에서 위 오류가 났습니다.

#### ⚠️ 앱 목록에서 엉뚱한 앱을 고르지 말 것

Firebase 프로젝트에 Apple 앱이 **세 개** 있습니다. 우리 것은 **`com.intpsquad.modi`** 하나입니다.

| 앱 | 팀 ID |
|---|---|
| `com.mara.modi.app` | `695C73WCLD` — 옛 프로젝트 |
| **`com.intpsquad.modi`** | **`89BSUAHRK7`** ← 우리 것 |
| `com.nomara.modi.app` | 옛 프로젝트 |

업로드할 때 넣는 값은 `.p8` 파일, **Key ID**(파일명 `AuthKey_XXXXXXXXXX.p8` 의 `XXXXXXXXXX`),
**팀 ID `89BSUAHRK7`** 입니다. 옛 앱들의 삭제 버튼은 누르지 마세요 — 되돌릴 수 없습니다.

#### 키만 바꿀 때는 앱을 다시 빌드하지 않는다

APNs 키는 **Firebase 쪽 설정**이라 앱 바이너리와 무관합니다. 키를 새로 올리면 그 즉시
반영되므로, 이미 나가 있는 TestFlight 빌드 그대로 다시 테스트하면 됩니다.

### 🔴 iOS 알림 배선은 AppDelegate 가 직접 깨운다 — 2026-09-14 (#66)

`app/ios/Runner/AppDelegate.swift` 가 플러그인 등록 **직후**에 앱 실행 알림을 다시 쏩니다:

```swift
NotificationCenter.default.post(
  name: UIApplication.didFinishLaunchingNotification,
  object: UIApplication.shared,
  userInfo: /* launchOptions */
)
```

**이게 없으면 iOS 알림이 통째로 죽습니다.** 지우지 마세요 —
`app/test/features/notifications/apns_registration_test.dart` 가 CI 에서 잡습니다(주석 처리·
`#if` 로 감싸기·다른 함수로 옮기기까지 잡도록 만들어 뒀습니다).

#### 왜 필요한가

`firebase_messaging` 15.2.10 은 iOS 알림 배선 **전체**를
`UIApplicationDidFinishLaunchingNotification` 관찰자 하나에 몰아 넣습니다
(`FLTFirebaseMessagingPlugin.m` 의 `application_onDidFinishLaunchingNotification:`, 214-310행).
그 안에서 여섯 가지가 일어납니다:

1. 앱을 켠 알림 수집(`getInitialMessage()` 의 재료)
2. APNs 스위즐러 설치 — **토큰이 `FIRMessaging` 에 닿는 유일한 경로**
3. `didReceiveRemoteNotification:fetchCompletionHandler:` 도너 메서드
4. `addApplicationDelegate:` — 플러그인을 Flutter 생명주기 델리게이트로 등록
5. `UNUserNotificationCenter.delegate` 설정 — **포그라운드 배너와 알림 탭**
6. `registerForRemoteNotifications` — APNs 등록 시작

그 관찰자는 플러그인 `init` 에서 등록되는데, **이 앱은 UIScene 을 채택**해서
(`Info.plist` 의 `UIApplicationSceneManifest` + `SceneDelegate`) 플러그인 등록이
`didInitializeImplicitFlutterEngine` 에서, 즉 **그 알림이 이미 끝난 뒤에** 일어납니다.
관찰자가 영영 안 불려 위 여섯 가지가 통째로 실행되지 않습니다.

증상: `getAPNSToken()` 이 계속 nil → `getToken()` 이 `apns-token-not-set` 으로 실패 →
서버에 토큰이 없음 → **서버 로그에 `FCM 토큰이 없어 푸시를 건너뛴다` 만 남습니다.**
2026-09-14 실측으로 유저 44명 중 토큰 보유 8명이었습니다(그 8명이 어떤 기기인지는 확인되지
않았습니다 — `users` 테이블에 플랫폼 구분이 없습니다).

#### `registerForRemoteNotifications()` 만 부르면 안 되는 이유

처음엔 그 한 줄만 넣으려 했는데 **부족합니다.** 토큰을 받을 배선(2·4·5번)이 없는 채로 등록만
시작되고, 토큰이 `Firebase.initializeApp()`(Dart, `app/lib/main.dart`) 보다 먼저 도착하면
**아무도 받지 않고 버려집니다.** iOS 는 디바이스 토큰을 캐시하므로 두 번째 실행부터는 콜백이
수십 ms 만에 오는데, Dart VM 부팅 + 카카오 SDK + Firebase 채널 왕복은 보통 수백 ms 입니다.
그리고 그렇게 놓치면 **복구 경로가 없습니다** — 앱의 재시도 사다리는 `getToken()` 만 다시
부르지 등록을 다시 시작하지 않습니다.

알림을 쏘면 플러그인이 자기 설정을 전부 마치고, Firebase 가 아직 구성되지 않았으면 토큰을
스스로 스태시했다가 나중에 흘려보내므로 그 경합이 없습니다.

⚠️ **순서가 중요합니다.** 반드시 `GeneratedPluginRegistrant.register` **뒤**여야 합니다 —
관찰자가 있어야 알림이 의미가 있습니다.

⚠️ **`launchOptions` 를 실어 보냅니다.** 안 실으면 종료 상태에서 알림을 눌러 앱을 켰을 때
`getInitialMessage()` 가 비어서 해당 화면으로 이동하지 않습니다.

#### 🧹 언제 지우나

`firebase_messaging` 이 UIScene 에서 스스로 배선하게 되면 이 코드와 가드 테스트를 함께
지웁니다. 버전 상황과 판단은 `specs/OPEN.md` 에 적어 뒀습니다 — 15.x 에는 지원이 없고,
16.5.0 이 지원을 넣으면서 같은 증상의 회귀를 냈으며, 그 회귀 수정(flutterfire #18620)은
2026-09-07 머지됐지만 아직 릴리스 전입니다. **업그레이드해도 실기기에서 확인하기 전에는
이 코드를 먼저 지우지 마세요.**

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
