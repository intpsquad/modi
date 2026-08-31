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

> 🔴 **제출용 빌드는 이 스크립트로만 만든다.** `flutter build ipa` 는 쓰지 않는다.
>
> 2026-08-14 에는 *"기기를 하나 등록한 뒤로는 `flutter build ipa` 도 정상 동작하니 평소엔 그걸
> 써도 된다"* 고 적혀 있었다. **그 판단이 이번 사고를 키웠다** — `flutter build ipa` 든 이
> 스크립트든 **검증이 없으면 권한이 빠진 IPA 가 그대로 나간다.** 지금 이 스크립트에만
> **entitlements 검증 게이트**가 있다(아래 "스크립트의 검증 게이트").
>
> 굳이 `flutter build ipa` 를 써야 한다면, 나온 IPA 를 **직접 열어** 권한을 확인할 것:
> ```sh
> unzip -q -o build/ios/ipa/MODI.ipa -d /tmp/ipa && \
>   codesign -d --entitlements - --xml /tmp/ipa/Payload/Runner.app
> ```
>
> ⚠️ **업로드는 Transporter 로 한다.** 2026-08-14 에는 이 스크립트의 아카이브에 서명이 없어
> Organizer 가 `No Team Found in Archive` 로 거부했다. 지금은 아카이브 단계에서 서명하므로 그
> 제약이 사라졌을 수 있으나 **다시 확인하지 않았다.** Transporter 경로는 검증돼 있다(4절).

### 🔴 등록된 기기가 0대면 `flutter build ipa` 가 실패한다 *(2026-08-14 실측)*

```
Communication with Apple failed: Your team has no devices from which to
generate a provisioning profile.
No profiles for 'com.intpsquad.modi' were found: Xcode couldn't find any
iOS App Development provisioning profiles matching 'com.intpsquad.modi'.
```

자동 서명이 아카이브 단계에서 **"개발용"(iOS App Development) 프로파일**을 찾았기 때문이고,
개발용 프로파일은 팀에 등록된 기기가 최소 하나 있어야 만들어진다. 반면 우리가 실제로 필요한
**App Store 배포용 프로파일은 기기 등록이 전혀 필요 없다.**

### 🔴 그때의 처방이 틀렸다 — 배포 빌드가 4번까지 망가진 채 나갔다 *(2026-08-15)*

**왜 개발용을 찾았느냐**가 진짜 질문이었다. 답은 `project.pbxproj` 의 **Release 설정이 개발용
인증서를 지정하고 있었다**는 것이다(`CODE_SIGN_IDENTITY = "Apple Development"`, 프로젝트 전역은
`"iPhone Developer"`). 그런데 당시 처방은 원인이 아니라 **증상을 껐다** — 아카이브에서 서명
자체를 끈 것이다(`CODE_SIGNING_ALLOWED=NO`).

**서명을 안 하면 entitlements 도 안 붙는다.** 아카이브에 권한이 없으니 `-exportArchive` 가
배포 인증서로 다시 서명해도 붙일 것이 없어, 프로파일에서 유도되는 기본 4개만 남았다:

```
$ codesign -d --entitlements - --xml Payload/Runner.app      # 빌드 1.0.0 (4)
  application-identifier / beta-reports-active / team-identifier / get-task-allow
  ← Runner.entitlements 의 네 개가 전부 없다
```

| 기능 | 디버그 빌드 | **배포 빌드 1~4** |
|---|---|---|
| Apple 로그인 | ✅ | ❌ `applesignin` 없음 → UI 뜨기 전 즉시 실패 |
| 푸시 알림 | ✅ | ❌ `aps-environment` 없음 |
| 공유 확장 | ✅ | ❌ App Group 없어 세션을 못 읽음 |

⚠️ **디버그 빌드에서는 멀쩡했다.** 자동 서명이 개발용 프로파일로 권한을 다 붙여주기 때문이다.
그래서 "실기기에서 확인했다"는 기록이 여러 건 있었는데도 배포 빌드는 죽어 있었다 —
**아무도 배포 바이너리의 entitlements 를 열어보지 않았다.** TestFlight `1.0.0 (4)` 를 받은
사용자가 Apple 로그인을 눌러보고서야 드러났고, 첫 심사 제출을 내려야 했다.

지금 스크립트는 이렇게 돈다:

| 단계 | 하는 일 | 왜 |
|---|---|---|
| ① archive | **배포용 인증서로 서명해서** 아카이브 | Release 가 `Apple Distribution` 을 가리키므로 개발용을 안 찾는다. **entitlements 가 여기서 붙는다** |
| ② export | `app-store-connect` 방식으로 내보낸다 | |
| ③ 검증 | **entitlements 가 실제로 들어갔는지 확인** | 이 사고의 재발 방지책 |

⚠️ **`CODE_SIGNING_ALLOWED=NO` 를 다시 넣지 말 것.** 빌드는 통과하고 기능만 조용히 죽는다.

### 스크립트의 검증 게이트

빌드 뒤 세 가지를 본다. **하나라도 어긋나면 IPA 를 내주지 않는다.**

| 보는 것 | 놓치면 |
|---|---|
| 배포용 인증서로 서명됐나 | 업로드가 거절된다 |
| `get-task-allow == false` | 개발용 프로파일이 섞여도 **빌드는 성공하고** 업로드에서야 거절된다 |
| 🔴 **서명된 entitlements 에 필요한 키가 다 있나** | 위 사고. 빌드·업로드·심사까지 다 통과하고 **기능만 죽는다** |

세 번째는 `Runner.app` 에서 `applesignin`·`aps-environment`·`application-groups`·
`keychain-access-groups` 를, `ShareExtension.appex` 에서 뒤의 둘을 확인한다.

⚠️ **프로파일이 아니라 "서명된 결과물"을 본다.** 사고 당시 프로파일은 네 권한을 다 허용하고
있었다 — 문제는 빌드가 그걸 안 붙인 것이었다. 프로파일만 보면 똑같이 놓친다.

## 4. TestFlight 업로드 (매 릴리스)

🔴 **`scripts/build-ios-ipa.sh` 로 만든 산출물은 Xcode Organizer 로 못 올린다.** 열면
`No Team Found in Archive` 가 뜬다(2026-08-14 실측) — 스크립트는 `xcodebuild archive` 를
직접 부르는데 Organizer 가 기대하는 형태로 팀 정보가 남지 않아서다.

**대신 [Transporter](https://apps.apple.com/app/id1450874784)(Mac App Store, 무료)로 `.ipa` 를 끌어다 놓는다.**
스크립트가 이미 배포용 서명과 App Store 프로파일까지 끝낸 파일이라 그대로 올라간다.

```sh
open -R app/build/ios/ipa/MODI.ipa   # Finder 에서 위치 열기 → Transporter 창에 드래그
```

⚠️ **아카이브가 두 군데 생긴다.** 스크립트는 `app/build/ios/ipa/Runner.xcarchive` 에 만들고,
Xcode 의 Product → Archive 는 `app/build/ios/archive/` 에 만든다. **옛 빌드가 남아 있으면
Organizer 목록에서 같은 버전이 둘로 보여 헷갈린다** — 업로드 전에 버전·빌드 번호를 확인할 것.

> Organizer 를 꼭 쓰고 싶으면 스크립트 대신 Xcode 에서 **Product → Archive** 로 만든다.
> 그 경로는 팀이 기록돼 Organizer 의 Distribute App 이 동작한다(2026-08-14 `1.0.0 (1)` 이 그 방식이었다).

- 업로드 후 Apple 의 processing(5~15분)이 끝나야 테스터에게 보인다.
- 내부 테스트는 심사가 없다. **기기 UDID 등록도 필요 없다** — TestFlight 앱으로 설치한다.
- 빌드 번호는 `app/pubspec.yaml` 의 `version: 1.0.0+N` 에서 온다. 같은 번호는 재업로드가 안 되므로
  올릴 때마다 `+N` 을 올린다.
- 🔴 **오류처럼 보이는 메시지가 사실은 경고이고, 그 빌드는 이미 접수돼 번호를 소모한다**
  (2026-08-14 실측). `1.0.0 (2)` 를 올렸을 때 확장 버전 불일치가 이렇게 떴다:

  ```
  CFBundleVersion Mismatch. The CFBundleVersion value '1' of extension
  'ShareExtension.appex' does not match ... '2' of its containing application. (90473)
  ```

  이걸 실패로 읽고 원인을 고쳐 **같은 번호로 다시 올렸더니** 이렇게 거절됐다:

  ```
  The provided entity includes an attribute with a value that has already been used (-19232)
  빌드 버전은 이전에 업로드한 버전보다 상위 버전이어야 합니다. '2'.
  ```

  Transporter 의 **전송 기록**을 보면 이유가 분명하다 — `1.0.0 (2)` 는 *"⚠️ 경고와 함께
  전송됨 · 내부 테스트 준비 완료"* 로 남아 있었다. **90473 은 거절이 아니라 경고였고 빌드는
  접수된 것이다.**

  **판단 기준은 Transporter 의 전송 기록이다.** 메시지 문구가 아니라 그 목록에 올라갔는지를
  본다. 올라갔다면 그 번호는 끝난 것이므로 재시도 시 `+N` 을 한 칸 더 올린다.

  ⚠️ 경고로 통과한 빌드는 **테스터에게는 보이지만 심사에는 쓰지 않는다** — 경고의 원인이
  그대로 남아 있다. 고친 빌드를 새 번호로 올려 그걸 쓴다.

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

- 🔴 **실기기 확인은 반드시 TestFlight 빌드로 한다.** 디버그 빌드는 자동 서명이 권한을 다
  붙여주기 때문에 **배포 빌드에서만 죽는 문제를 통과시킨다.** 2026-08-15 사고가 정확히
  이것이었다 — Apple 로그인·푸시·공유 확장이 배포 빌드에서 전부 죽어 있었는데 "실기기 확인
  완료" 기록이 여러 건 있었다(전부 디버그 빌드였다). 위 3절 참고.
  확인할 것: **Apple 로그인 · 푸시 수신 · 공유 확장** 셋.

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
- 푸시 알림 수신(FCM → APNs) — `docs/fcm-setup.md`.
  **2026-08-31: `.p8` APNs 키를 발급해 Firebase 에 등록했다**(이슈 #66). 그전까지 인앱 알림만
  오고 푸시가 안 오던 원인이 이것이었다 — 앱은 처음부터 준비돼 있었고 보낼 열쇠가 없었다.
  발급 시 **Environment 를 `Sandbox & Production` 으로** 골라야 한다. `Sandbox` 만 고르면
  Xcode 로 직접 돌린 개발 빌드에만 먹히고 TestFlight·App Store 빌드는 계속 안 온다.
  **저장 후에는 바꿀 수 없다.**
  ⚠️ Firebase 콘솔의 Apple 앱 목록에는 옛 프로젝트 앱이 함께 보인다(`com.mara.modi.app`,
  `com.nomara.modi.app` — 팀 ID 가 `695C73WCLD` 라 우리 것이 아니다).
  키는 반드시 **`com.intpsquad.modi`** 앱에 올린다.
  🔴 **수신 확인은 아직 남아 있다** — TestFlight 빌드로 콕찌르기 알림이 실제로 오는지 봐야
  #66 을 닫는다(디버그 빌드로는 이 검증이 안 된다, 위 첫 항목 참고).
