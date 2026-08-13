# iOS 릴리스 (TestFlight) — Mac 에서 사람이 돌린다

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
| 번들 ID | `com.nomara.modi.app` · Share Extension `com.nomara.modi.app.ShareExtension` |
| Firebase iOS 앱 | 위 번들 ID 가 Firebase 프로젝트에 등록돼 있어야 한다 |
| Mac 에 필요한 것 | Xcode · CocoaPods · **Flutter 3.44.7** · Ruby 3.4+ · Bundler 2.7+ |
| App Store Connect | 앱 레코드가 있어야 한다 |
| match 저장소 | 인증서·프로파일을 담는 **private git 저장소** (내용은 암호화돼 저장된다) |

🔴 **번들 ID 를 먼저 확인할 것.** Apple 번들 ID 는 전 세계에서 유일하다. 이전 계정에
`com.nomara.modi.app` 이 등록된 채로 남아 있으면 새 팀 계정에서 같은 ID 를 못 쓴다 —
그 경우 ID 를 바꿔야 하고, 바꾸면 Firebase·`Info.plist`·App Group 식별자가 함께 바뀐다.

## 1. Apple Developer 준비 (1회)

1. Apple Developer Program 가입($99/년) → **Team ID**(10자)를 적어둔다.
2. App ID 등록: 위 번들 ID 두 개. **Sign in with Apple** capability 를 켠다 —
   카카오·구글 로그인이 있는 앱은 App Store 심사에서 이게 필수다(코드는 이미 있다).
3. **App Groups**(`group.com.nomara.modi`) 와 Keychain Sharing 을 두 타깃에 등록한다 —
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

App Store Connect API 키를 fastlane JSON 형태로 만든다(`.p8` 파일 그대로가 아니다):

```sh
jq -n \
  --arg key_id "KEY_ID" \
  --arg issuer_id "ISSUER_ID" \
  --rawfile key "/secure/AuthKey_KEY_ID.p8" \
  '{key_id: $key_id, issuer_id: $issuer_id, key: $key, in_house: false}' \
  > "/secure/ios-appstore-api-key.json"
chmod 600 "/secure/ios-appstore-api-key.json"
```

`app/env/prod.json` — `prod.example.json` 을 복사해 운영 `--dart-define` 값을 채운다
(`API_BASE_URL=https://api.maramodi.cloud` 등, gitignore 됨).

## 3. 인증서 생성 (1회, 계정을 새로 만든 직후)

`Matchfile` 에는 저장소 주소가 없다 — 환경변수로만 준다(주소를 코드에 박지 않는다).

```sh
cd app
export MATCH_GIT_URL="<private 서명 저장소 URL>"
export MATCH_PASSWORD="<저장소 복호화 암호>"
export ASC_API_KEY_PATH="/secure/ios-appstore-api-key.json"
bundle exec fastlane match appstore \
  --app_identifier "com.nomara.modi.app,com.nomara.modi.app.ShareExtension"
```

## 4. TestFlight 업로드 (매 릴리스)

```sh
cd app
export APPLE_TEAM_ID="<Apple Team ID>"
export ASC_API_KEY_PATH="/secure/ios-appstore-api-key.json"
export MATCH_GIT_URL="<private 서명 저장소 URL>"
export MATCH_PASSWORD="<저장소 복호화 암호>"
# HTTPS 저장소면 자격증명도 함께
export MATCH_GIT_USERNAME="<사용자명>"
export MATCH_GIT_PASSWORD="<토큰>"
bundle exec fastlane beta
```

`beta` 레인이 하는 일(`app/fastlane/Fastfile`):
match 로 프로파일 내려받기 → Xcode 서명 설정을 **임시로** manual 로 바꾸기 →
App Store Connect 의 현재 build number + 1 → `flutter build ios --release --no-codesign` →
`build_app`(app-store export) → `upload_to_testflight`(업로드만, 심사 제출 안 함) →
**`ensure` 블록에서 `project.pbxproj` 를 원본으로 복원**.

- `APPLE_TEAM_ID` 에 **기본값이 없다**(2026-08-13). 없으면 그 자리에서 멈춘다 — 기본값을 두면
  엉뚱한 팀으로 서명해도 빌드가 성공해서, 업로드가 거절될 때까지 아무도 모른다.
- 업로드 후 Apple 의 processing 이 끝나야 테스터에게 보인다. App Store Connect 에서 이어서 한다.

## 5. 출시 전에 반드시 남아 있는 검증

- 🔴 **외부 공유 시트 실기기 E2E**(S-25-D). 시뮬레이터 빌드와 Swift XCTest 는 통과했지만
  **실기기 공유는 한 번도 확인하지 않았고, 2026-08-05 에 추가한 iOS 변경분은 아직 실행조차
  안 됐다**(`PROJECT_PLAN.md` 아카이브 탭 항목).
- Sign in with Apple 실기기 로그인
- 푸시 알림 수신(FCM → APNs) — `docs/fcm-setup.md`
