# iOS 릴리스 (TestFlight) — Mac 에서 사람이 돌린다

> 📌 **2026-08-14 첫 제출을 준비하는 중이라면 [](./ios-submission-handoff.md)
> 를 먼저 읽을 것** — 지금 어디까지 됐고 무엇이 남았는지, 그리고 이번엔  대신
> **Xcode 자동 서명**으로 간다는 결정이 거기 있다.

**출시 대상은 iOS 하나다**(2026-08-13 확정). 안드로이드 코드(`app/android/`)는 저장소에 남아
있지만 **CI 도 릴리스 경로도 없다** — 되살리려면 그 경로를 새로 만들어야 한다.

## 왜 자동화하지 않았나

옛 Jenkins 에는 macOS 에이전트를 붙인 `iOS: TestFlight` 스테이지가 있었다. GitHub Actions 로
옮길 때 **일부러 안 옮겼다**:

1. 저장소가 **프라이빗**이라 GitHub 제공 macOS 러너는 분수를 **10배**로 소모한다. 20분짜리
   빌드 한 번이 무료 분수 200분이다 — 월 열 번이 한계다.
2. 팀의 **Apple Developer 계정이 아직 없다.** 계정·번들 ID·인증서가 없으면 자동화를 만들어도
   한 번도 돌려볼 수 없고, 돌려보지 않은 CI 는 있으나 마나다.

나중에 자동화할 때는 팀 Mac 을 **self-hosted 러너**로 붙이는 쪽이 맞다(분수 소모 0, 옛 상주
macOS 에이전트 구성의 자연한 연장). 그때 이 문서의 절차를 워크플로로 옮기면 된다.

## 0. 선행 조건

| 항목 | 값 / 확인 방법 |
|---|---|
| 번들 ID | `com.intpsquad.modi` · Share Extension `com.intpsquad.modi.ShareExtension` |
| Firebase iOS 앱 | 위 번들 ID 가 Firebase 프로젝트에 등록돼 있어야 한다 |
| Mac 에 필요한 것 | Xcode · CocoaPods · **Flutter(`app/.fvmrc` 값 = 3.44.8)** |
| App Store Connect | 앱 레코드가 있어야 한다 |
| 서명 | 키체인의 **`Apple Distribution: … (89BSUAHRK7)`** 인증서 하나면 된다. 프로파일은 빌드 때 Xcode 가 만든다 |

> ⚠️ **`fastlane match` 는 쓰지 않는다**(2026-08-13 확정). `app/fastlane/Matchfile`·`Fastfile` 이
> 아직 match 전제로 남아 있지만 **그 서명 저장소가 존재하지 않는다**(옛 계정과 함께 사라졌다).
> 아래 3·4절이 실제로 쓰는 절차이고, 5절의 fastlane 경로는 되살릴 때를 위한 기록이다.

🔴 **번들 ID 를 먼저 확인할 것.** Apple 번들 ID 는 전 세계에서 유일하다. 이전 계정에
`com.intpsquad.modi` 이 등록된 채로 남아 있으면 새 팀 계정에서 같은 ID 를 못 쓴다 —
그 경우 ID 를 바꿔야 하고, 바꾸면 Firebase·`Info.plist`·App Group 식별자가 함께 바뀐다.

## 1. Apple Developer 준비 (1회)

1. Apple Developer Program 가입($99/년) → **Team ID**(10자)를 적어둔다.
2. App ID 등록: 위 번들 ID 두 개. **Sign in with Apple** capability 를 켠다 —
   카카오·구글 로그인이 있는 앱은 App Store 심사에서 이게 필수다(코드는 이미 있다).
3. **App Groups**(`group.com.intpsquad.modi`) 와 Keychain Sharing 을 두 타깃에 등록한다 —
   Share Extension 이 App Group Keychain 으로 로그인 세션을 공유한다.
4. App Store Connect → Users and Access → Integrations → **App Store Connect API → Team Keys**
   → Generate API Key → `.p8` 를 **한 번만** 내려받는다.
   - ⚠️ **Individual Key 가 아니라 Team Key 여야 한다.** fastlane match 의 provisioning API 는
     Individual Key 로는 동작하지 않는다.
   - `.p8` 는 재다운로드가 불가능하다. 유출되면 Apple 에서 즉시 revoke 하고 새로 발급한다.

## 2. 로컬 설정 (1회)

`app/ios/Flutter/Local.xcconfig` — `Local.xcconfig.example` 을 복사해 채운다(gitignore 됨):

```
KAKAO_NATIVE_APP_KEY = <카카오 네이티브 앱 키>
MODI_DEVELOPMENT_TEAM = <Apple Team ID>
```

`MODI_DEVELOPMENT_TEAM` 이 비면 **시뮬레이터 빌드는 되지만 실기기·아카이브 빌드가 실패한다**
(`project.pbxproj` 가 `DEVELOPMENT_TEAM = "$(MODI_DEVELOPMENT_TEAM)"` 로 이 값을 읽는다).

`app/env/prod.json` — `prod.example.json` 을 복사해 운영 `--dart-define` 값을 채운다
(`API_BASE_URL=https://api.maramodi.cloud` 등, gitignore 됨).

## 3. IPA 빌드 — `scripts/build-ios-ipa.sh` 를 쓴다

```sh
./scripts/build-ios-ipa.sh          # 산출물: app/build/ios/ipa/MODI.ipa
```

> ✅ **2026-08-14 오후 정정 — 기기를 하나 등록한 뒤로는 `flutter build ipa` 도 정상 동작한다.**
> 아래 실패는 **팀에 등록된 기기가 0대일 때** 일어난다. 기기가 있으면 개발용 프로파일이 만들어져
> 아카이브가 통과하고, 나온 IPA 도 배포 서명이 제대로 붙는다(실측). 그러니 평소에는
> `flutter build ipa --release --dart-define-from-file=env/prod.json` 을 써도 된다.
> **이 스크립트는 등록된 기기가 없을 때(계정을 새로 팠거나 기기가 빠졌을 때)를 위한 보험**이고,
> 검증 게이트가 붙어 있다는 이점도 있다. 아래 설명은 그 상황의 기록이다.
>
> ⚠️ **Organizer 로 배포하려면 `flutter build ipa` 쪽 아카이브를 써야 한다.** 이 스크립트의
> 아카이브는 일부러 서명이 없어 Organizer 가 `No Team Found in Archive` 로 거부한다
> (스크립트가 내놓는 `.ipa` 자체는 정상이므로 **Transporter 로는 그대로 올릴 수 있다**).

### 🔴 등록된 기기가 0대면 `flutter build ipa` 가 실패한다 *(2026-08-14 실측)*

```
Communication with Apple failed: Your team has no devices from which to
generate a provisioning profile.
No profiles for 'com.intpsquad.modi' were found: Xcode couldn't find any
iOS App Development provisioning profiles matching 'com.intpsquad.modi'.
```

**자동 서명이 아카이브 단계에서 "개발용"(iOS App Development) 프로파일을 먼저 찾기 때문**이고,
개발용 프로파일은 팀에 등록된 기기가 최소 하나 있어야 만들어진다. 반면 우리가 실제로 필요한
**App Store 배포용 프로파일은 기기 등록이 전혀 필요 없다** — 정작 만들 수 있는 프로파일 앞에서
막혀 있었던 것이다. `-allowProvisioningUpdates` 를 줘도 같은 자리에서 실패한다.

그래서 스크립트는 한 덩어리인 `flutter build ipa` 를 **두 단계로 쪼갠다**:

| 단계 | 하는 일 | 왜 |
|---|---|---|
| ① archive | `CODE_SIGNING_ALLOWED=NO` 로 서명 없이 아카이브 | 개발용 프로파일을 아예 안 찾는다 |
| ② export | `app-store-connect` 방식으로 내보내며 서명 | 여기서 배포용 프로파일을 Apple 에서 만들어 온다 |

⚠️ **기기를 등록했더라도 이 스크립트를 계속 쓴다.** 기기 등록은 개발용 프로파일을 되살릴 뿐이고,
릴리스 빌드가 개발용 프로파일에 의존할 이유가 없다. 등록된 기기가 빠지면 또 같은 자리에서 멈춘다.

스크립트는 빌드 뒤 **검증까지 한다** — 배포용 인증서 서명 여부와 `get-task-allow == false`.
후자가 중요한 이유는 개발용 프로파일이 섞여도 **빌드는 성공하고 업로드에서야 거절되기** 때문이다.

## 4. TestFlight 업로드 (매 릴리스)

Xcode Organizer 또는 **Transporter** 앱으로 3절의 `.ipa` 를 올린다.

- 업로드 후 Apple 의 processing(5~15분)이 끝나야 테스터에게 보인다.
- 내부 테스트는 심사가 없다. **기기 UDID 등록도 필요 없다** — TestFlight 앱으로 설치한다.
- 빌드 번호는 `app/pubspec.yaml` 의 `version: 1.0.0+N` 에서 온다. 같은 번호는 재업로드가 안 되므로
  올릴 때마다 `+N` 을 올린다.

### 실기기에 직접 깔아 확인하고 싶으면 (TestFlight 없이)

이때는 **개발용 프로파일이 필요해서 기기 UDID 등록이 필수다.** Xcode 로 워크스페이스를 열고
기기를 고른 뒤 ▶︎ 를 누르면 Xcode 가 **Register Device** 를 띄운다. 등록 후:

```sh
cd app && flutter build ios --release --dart-define-from-file=env/prod.json
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
```

- ⚠️ **디버그 빌드를 깔면 홈 화면 아이콘으로 안 열린다**(검은 화면에 안내문만 뜬다). iOS 14+ 는
  디버그 Flutter 앱의 단독 실행을 막는다 — 확인용으로는 위처럼 **release** 를 깐다.
- ⚠️ **옛 번들(`com.nomara.modi.app`)이 남아 있으면 이름이 똑같이 "MODI" 라 홈 화면에서 구분이
  안 된다.** iOS 는 번들 ID 가 다르면 별개 앱이라 새로 깔아도 옛 게 안 지워지고, 옛 앱을 열어놓고
  "기능이 예전 같다"고 오해하기 쉽다(2026-08-14 실제로 그랬다). 확인:
  `xcrun devicectl device info apps --device <UDID> | grep -i modi`

## 5. *(보관)* fastlane + match 경로 — 지금은 쓰지 않는다

`app/fastlane/Fastfile` 의 `beta` 레인은 match 로 프로파일을 받아 manual 서명으로 바꿔 빌드·업로드한다.
**서명 저장소가 없어 현재는 동작하지 않는다.** 되살리려면 private 저장소를 새로 만들고
`MATCH_GIT_URL`·`MATCH_PASSWORD`·`APPLE_TEAM_ID`·`ASC_API_KEY_PATH` 를 넘긴다.
App Store Connect API 키는 `.p8` 그대로가 아니라 fastlane JSON 형태여야 한다:

```sh
jq -n --arg key_id "KEY_ID" --arg issuer_id "ISSUER_ID" \
  --rawfile key "/secure/AuthKey_KEY_ID.p8" \
  '{key_id: $key_id, issuer_id: $issuer_id, key: $key, in_house: false}' \
  > "/secure/ios-appstore-api-key.json"
chmod 600 "/secure/ios-appstore-api-key.json"
```

- `APPLE_TEAM_ID` 에 **기본값이 없다**. 없으면 그 자리에서 멈춘다 — 기본값을 두면 엉뚱한 팀으로
  서명해도 빌드가 성공해서, 업로드가 거절될 때까지 아무도 모른다.

## 6. 출시 전에 반드시 남아 있는 검증

- ✅ ~~**Swift 테스트**(`ShareContentTests` 10건)~~ — **2026-08-14 처음으로 실행, 13건 전부 통과.**
  그전까지 한 번도 안 돌았던 이유는 로직이 아니라 **컴파일 실패**였다: `RunnerTests` 타깃에
  배포 타깃이 없어 프로젝트 기본값 iOS 13.0 으로 빌드됐고, 17.6 인 `Runner` 를
  `@testable import` 할 수 없었다. 세 설정에 `IPHONEOS_DEPLOYMENT_TARGET = 17.6` 을 박아 고쳤다.
  ```sh
  cd app/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
      -destination 'platform=iOS Simulator,name=iPhone 17'   # 기기 이름은 xcrun simctl list devices 로 확인
  ```
- 🔴 **외부 공유 시트 실기기 E2E**(S-25-D). Swift XCTest 는 통과했지만 **실기기 공유는 아직
  확인되지 않았다.** 위 4절의 "실기기에 직접 깔아 확인" 절차로 본다.
- 🔴 **카카오 로그인** — 카카오 콘솔에 iOS 번들 ID `com.intpsquad.modi` 가 등록돼야 동작한다.
  등록 전에는 실기기에서 실패하고, **동작하지 않는 기능은 Guideline 2.1 거부 사유다.**
- Sign in with Apple 실기기 로그인
- 푸시 알림 수신(FCM → APNs) — `docs/fcm-setup.md`. ⚠️ `.p8` APNs 키가 아직 없다(제출은 막지 않는다).
