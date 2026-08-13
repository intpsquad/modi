# iOS 심사 제출 인계 — Windows → Mac (2026-08-13)

> **읽는 사람**: Mac 에서 IPA 빌드·TestFlight 업로드·심사 제출을 이어받는 사람(또는 그 세션의 AI).
> **목표**: 2026-08-14 App Store 심사 제출.
> 절차 자체는 [`docs/ios-release.md`](./ios-release.md) 가 단일 진실이고, 이 문서는 **지금 어디까지
> 됐고 무엇이 남았는지**만 적는다. 제출이 끝나면 이 파일은 지워도 된다.

---

## 📌 2026-08-14 Mac 작업 결과 — 여기부터 읽는다

**IPA 가 실제로 나왔다.** 아래 2·3·4절(Swift 테스트 · 서명 · IPA 빌드)은 **끝났다.**

| 항목 | 결과 |
|---|---|
| Swift 테스트 | ✅ **13건 전부 통과 — 최초 실행.** 실패가 아니라 **컴파일이 안 되고 있었다**(`RunnerTests` 배포 타깃 13.0 vs `Runner` 17.6). 세 설정에 17.6 을 박아 고쳤다 |
| Flutter 테스트 | ✅ 639건 통과 · `flutter analyze` 0건 · `dart format` 0건 |
| 서명 | ✅ Xcode 자동 서명. 키체인의 `Apple Distribution: … (89BSUAHRK7)` 사용 |
| IPA | ✅ `1.0.0 (1)` · Apple Distribution 서명 · App Store 프로파일 · `get-task-allow=false` · 확장도 서명됨 |
| 실기기 | ✅ 기기 등록 + 릴리스 빌드 설치. 옛 번들 `com.nomara.modi.app` 제거(이름이 같아 혼동됐다) |
| 운영 서버 | ✅ `/rooms` 401 · `/actuator/health` 404 — 기대값과 일치 |

고친 것은 커밋 `6669f85`. 상세는 [`ios-release.md`](./ios-release.md) 3절.

### ✅ 2026-08-14 추가로 끝난 것

- **App Store Connect 앱 레코드** — 이미 있다. `modi-modi` · "iOS 1.0 제출 준비 중"
  (계정 소유자 Juha Yoon 세션에서 확인). 업로드를 막던 항목이 해소됐다.
- **개인정보처리방침 URL · 지원 URL** — `maramodi.cloud` 에 정적 페이지를 올렸다.
  DNS 는 원래 서버를 가리켰지만 Caddyfile 블록이 없어 **인증서가 없었고 https 가 연결
  자체를 실패**하던 상태였다. 상세는 README "배포 → 소개·지원·약관 정적 페이지".

  | App Store Connect 항목 | 붙여 넣을 주소 |
  |---|---|
  | 개인정보처리방침 URL | `https://maramodi.cloud/privacy` |
  | 지원 URL | `https://maramodi.cloud/` |

  실측(2026-08-14): 세 주소 모두 200, http→https 308, Let's Encrypt 인증서 발급 완료.
  🔴 **앱 약관(`legal_content.dart`)을 고치면 `deploy/site/*.html` 도 함께 고친다** —
  `app/test/features/legal/legal_web_sync_test.dart` 가 어긋나면 CI 를 실패시킨다.

### 🔴 남은 것 — 사람이 해야 한다

1. **EU 거래자(Trader) 자격 신고** *(2026-08-14 신규 발견 — App Store Connect 배너)*
   — "새 앱을 제출하려면 거래자 자격 여부를 제공해야 하고, 그러지 않으면 EU App Store 에서
   앱이 삭제된다"고 안내한다. **계정 소유자만** 설정할 수 있다(비즈니스 섹션).
   한국 대상 앱이면 **비거래자로 신고하고 EU 배포를 빼는 선택**이 가장 간단하다 —
   그 경우 EU 에서만 안 보이고 국내 출시는 영향이 없다.
2. **연령 등급 — 소셜 미디어 질문** *(2026-08-14 신규 발견)* — '앱 정보' 에 새로 생긴 질문에
   답해야 한다. MODI 는 방 안에서 팀원끼리 콘텐츠를 공유하므로 해당될 수 있다.
3. **App Store 표시 이름이 `modi-modi` 다** *(2026-08-14 신규 발견)* — 그대로 두면 검색·완성도
   양쪽에서 손해다. **홈 화면 아이콘 이름은 별개이고 이미 `MODI` 다**(`Info.plist` 의
   `CFBundleDisplayName`) — 바꿀 필요 없다. App Store 이름은 전 세계에서 유일해야 해서
   `MODI`·`모디` 단독은 선점됐을 가능성이 높다. 한국 대상이면 이름·부제에 **한글**이 있어야
   검색에 잡힌다(예: 이름 `모디 - 팀 목표 협업`, 부제 `투두·일정·자료를 팀과 한 곳에서`).
   **제출 전까지는 자유롭게 바꿀 수 있고 심사에 들어가면 잠긴다** — 제출 직전에 확정할 것.
4. **카카오 콘솔에 iOS 번들 ID 등록** — 아래 6절. 안 하면 카카오 로그인이 실패하고
   **동작하지 않는 기능은 Guideline 2.1 거부 사유다**. (버튼을 숨기는 안은 검토했다가
   *"카카오가 팀 핵심 기능"* 이라 **그대로 두기로 했다** — 2026-08-14 결정)
5. **스크린샷**(6.7" 세트, 시뮬레이터 캡처) · App Privacy 설문 · 수출 규정
6. **실기기 확인** — 아래
7. **심사자가 앱을 실제로 써볼 수 있는가** *(2026-08-14 신규)* — MODI 는 **방에 팀이 모여야**
   의미가 생긴다. 심사자가 혼자 가입해 방을 만들면 투두 0개·멤버 1명·아카이브 0개인 빈 화면을
   본다. **데이터가 들어 있는 방을 하나 만들어 두고 심사 메모에 데모 계정과 초대 코드를
   적어 주는 것**이 안전하다(Guideline 2.1 의 흔한 거부 패턴).

### 🔴 실기기에서 아직 한 번도 확인 안 된 것

빌드는 이미 아이폰에 깔려 있어 TestFlight 없이 지금 바로 볼 수 있다.

- [x] **공유 확장 E2E — Safari(네이버 블로그 링크) 성공** *(2026-08-14 실기기 최초 확인).*
      확장이 뜨고 방·폴더 선택 후 등록까지 간다 = 프로세스·App Group Keychain 인증·서버 등록이
      전부 살아 있다는 뜻이다. **가장 위험했던 경로가 닫혔다.**
- [x] **공유 확장 — 네이버 지도 앱 공유 성공** *(2026-08-14 실기기)*. 제목이 `하이디라오 영등포점`
      으로 들어갔다(`[네이버지도] …` 가 아니다) = **2026-08-05 URL 추출 수정이 실기기에서 검증됐다.**
      덤으로 한 번에 확인된 것: 서버의 `naver.me` 리다이렉트 한 홉 추종 · 크롤링(제목·썸네일) ·
      **자동 태깅 5개** · **요약(문장별 줄바꿈 서식)**. 즉 **운영에서 OpenAI 직접 호출 경로 두 개가
      살아 있다** — 2026-08-13 게이트웨이 이탈 후 실측은 이번이 처음이다.
- [ ] ~~공유 확장 — 네이버 지도 앱에서 공유~~ *(완료, 위 참조)*. 위 Safari 케이스는 통짜 URL 이라
      추출 로직이 거의 관여하지 않는다. **2026-08-05 수정이 겨냥한 것은 이쪽**이다:
      `[네이버지도] 돼지통 역삼2호점 … https://naver.me/52aGF4S5` 처럼 설명이 앞에 붙어 오고,
      옛 코드는 이걸 텍스트로 등록해 **크롤링이 아예 안 일어났다**(안드로이드 실측).
      서버 경로도 다르다 — `naver.me` 는 3xx 라 `NaverUrlCrawler` 만 예외로 한 홉을 따라간다.
      **iOS 추출 + 서버 리다이렉트 추종이 함께 걸리는 유일한 케이스다.**
      판정: 등록된 자료에 제목·썸네일이 붙으면 성공, 제목이 `[네이버지도] …` 면 실패.
- [x] **Sign in with Apple 실기기 로그인 성공** *(2026-08-14)*
- [x] **계정 삭제 성공** *(2026-08-14)* — 확인 모달까지가 아니라 **실제로 삭제되는 것**까지 봤다.
      Apple 은 심사자가 계정을 만들어 직접 지워본다(Guideline 5.1.1(v)).
  - 🔴 **다만 서버에 Apple 토큰 폐기(revoke) 호출이 없다**(`server/` 에 revoke 관련 코드 0건).
        Apple 은 Sign in with Apple 사용 앱이 계정 삭제 시 Apple 의 토큰 폐기 엔드포인트를
        호출하도록 요구한다. **심사자에 따라 지적되기도 하고 넘어가기도 하는 항목**이라
        이번 제출을 막지는 않을 수 있으나, 지적되면 그 자리에서 서버 작업이 필요하다.
  - ⚠️ Apple 로그인 계정을 지운 뒤 다시 테스트하려면 **iOS 설정 → Apple 계정 → Apple로 로그인
        → MODI → 사용 중단**을 먼저 눌러야 한다. Apple 은 이메일·이름을 **최초 인증에만** 준다.
- [ ] 프로필 사진 업로드 · 투두 추천 · 알림 권한 요청

### 업로드하는 법

`.p8` APNs 키·App Store Connect API 키 모두 없다. **Xcode Organizer** 가 가장 간단하다
(이미 로그인돼 있다) — 단 `flutter build ipa` 로 만든 아카이브여야 한다. `.ipa` 를 직접
올리려면 **Transporter**(Mac App Store). 자세한 건 `ios-release.md` 4절.

> ⚠️ 안드로이드 네이티브 테스트(아래 2절 끝)는 **돌릴 수 없다** — `app/android/gradlew`
> 래퍼가 저장소에 없다. 안드로이드는 릴리스 경로 자체가 없으므로 지금은 문제되지 않는다.

---

## 왜 Mac 이 필요한가

Windows 에서 할 수 있는 것은 다 했다. Mac 이 필요한 것은 셋뿐이다:

1. `xcodebuild` / `flutter build ipa` — IPA 는 macOS 에서만 만들어진다
2. **Swift 테스트 실행** — 아래 🔴 항목
3. App Store 스크린샷(시뮬레이터)

---

## ✅ 이미 끝난 것 (다시 하지 말 것)

| 항목 | 상태 |
|---|---|
| 백엔드 | `https://api.maramodi.cloud` **가동 중**. DNS 전환·TLS 인증서 발급 완료 |
| 무중단 배포 | blue/green + `caddy reload`. `dev` push → 테스트 → rsync → 서버(ARM) 빌드 → 전환. 실측 1195요청 중 5xx 0건 |
| 번들 ID | `com.intpsquad.modi` (확장 `.ShareExtension`, App Group `group.com.intpsquad.modi`) |
| Apple 포털 | App ID 2개 + App Group 1개 등록. capability Push · Sign in with Apple · App Groups |
| Team ID | `89BSUAHRK7` (계정 보유자 **윤주하**) |
| Firebase | 새 번들로 iOS 앱 등록 + `GoogleService-Info.plist` |
| Google 로그인 | `Info.plist` URL 스킴을 새 `REVERSED_CLIENT_ID` 로 교체 |

외부에서 실측한 백엔드 응답(이 값이 나오면 정상):

```
/rooms            401   FirebaseAuthFilter 동작 = 앱이 붙을 수 있다
/actuator/health  404   Caddy 가 actuator 차단
/docs             401   Basic 인증
storage/          403   MinIO 접두사 정책
```

---

## 1. Mac 준비

```bash
git clone git@github.com:modintps/modi.git      # 또는 HTTPS
cd modi
```

### 로컬 전용 파일 4개를 Windows PC 에서 가져온다

**커밋되지 않는 파일이라 clone 만으로는 없다.** 없으면 빌드가 실패하거나 로그인이 조용히 깨진다.

| 파일 | 없으면 |
|---|---|
| `app/ios/Flutter/Local.xcconfig` | Team ID·카카오 키 부재 → **아카이브 실패** |
| `app/ios/Runner/GoogleService-Info.plist` | Firebase 초기화·Google 로그인 실패 |
| `app/lib/firebase_options.dart` | `flutter analyze` 부터 깨진다 |
| `app/env/prod.json` | 릴리스 빌드가 API 주소 없이 나간다(Gradle 은 실패시키고 iOS 는 조용히 통과) |

가장 안전한 방법은 Windows PC 에서 **그 4개를 그대로 복사**하는 것이다.

> 🔴 **`flutterfire configure` 를 Mac 에서 다시 돌리지 말 것.** 파일을 새로 만들려는 유혹이 있는데,
> 그러면 `GoogleService-Info.plist` 가 덮어써질 수 있고 `Info.plist` 의 URL 스킴과 어긋나
> **Google 로그인만 조용히 실패**한다. Windows 에서 이미 맞춰 뒀다 —
> 네 곳(`firebase.json` 의 `ios.default` · `dart(ios)` · plist 의 `GOOGLE_APP_ID` ·
> `firebase_options.dart`)이 모두 `1:144575316035:ios:f6dca4aa347f93095dd4f6` 다.
> 정말 다시 돌려야 하면 돌린 뒤 그 네 값이 여전히 같은지 확인할 것.

### 확인

```bash
xcodebuild -version                     # Xcode 26.6 / Build 17F113 확인됨
grep MODI_DEVELOPMENT_TEAM app/ios/Flutter/Local.xcconfig   # 89BSUAHRK7
/usr/bin/plutil -extract BUNDLE_ID raw -o - app/ios/Runner/GoogleService-Info.plist
# → com.intpsquad.modi
```

---

## 2. 🔴 Swift 테스트를 **가장 먼저** 돌린다

`specs/0014-외부-공유-등록.md` 에 이렇게 적혀 있다:

> **2026-08-05 에 추가한 URL 추출 규칙과 `ShareContentTests` 10건은 아직 한 번도 실행되지 않았다**
> — 작업 머신이 Windows 라 Swift 툴체인이 없다(`swift: command not found`).

즉 **읽고 판단한 것이 전부인 네이티브 코드가 심사에 들어간다.** 공유 확장이 크래시하면
Guideline 2.1 로 거부된다. Mac 이 생긴 지금이 처음으로 돌려볼 수 있는 시점이다.

```bash
cd app/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
    -destination 'platform=iOS Simulator,name=iPhone 15'
```

- 시뮬레이터 이름이 없다고 하면 `xcrun simctl list devices` 로 실제 이름을 확인해 바꾼다
- **실패하면 거기서 멈추고 고친다.** 안드로이드 쪽 같은 규칙은 8건 통과했으니
  (`SharedTextUrlTest.kt`) 기대 동작은 그 파일이 기준이다

같이 돌려볼 것 — 안드로이드 네이티브 테스트도 CI 가 안 돌린다:

```bash
cd app/android && ./gradlew :app:testDebugUnitTest
```

---

## 3. 서명은 Xcode 자동 서명으로 간다 (match 쓰지 않는다)

`app/fastlane/Matchfile` · `Fastfile` 은 `fastlane match` 를 전제로 쓰여 있지만, **그 서명
저장소가 아직 없다**(옛 계정과 함께 사라졌다). 새로 만들면 시간만 먹는다.

```bash
open app/ios/Runner.xcworkspace
```

Xcode → Runner 타깃 → Signing & Capabilities:
- ☑️ **Automatically manage signing**
- Team: **디 모 (89BSUAHRK7)**
- **ShareExtension 타깃에도 같은 팀**을 지정한다(타깃이 둘이다 — 하나만 하면 아카이브가 실패한다)

Xcode 가 Distribution 인증서와 프로파일을 자동 발급한다. Apple 포털에 capability 가 이미
등록돼 있으므로 그대로 통과해야 한다.

---

## 4. IPA 빌드

```bash
cd app
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --dart-define-from-file=env/prod.json
```

`--dart-define-from-file` 이 **필수**다. 빠지면 앱이 에뮬레이터 기본 주소를 들고 나간다
(안드로이드는 Gradle 이 빌드를 실패시키지만 **iOS 는 그 안전장치가 없다**).

산출물: `build/ios/ipa/*.ipa`

> `flutter build ipa` 가 서명 문제로 실패하면 Xcode 에서 **Product → Archive** 로 진행한다.
> Organizer 창에서 그대로 **Distribute App → App Store Connect** 로 올릴 수 있다.

---

## 5. TestFlight 업로드 → 실기기 확인

Xcode Organizer 또는 Transporter 로 업로드한다. 업로드 후 App Store Connect 에서
processing 이 끝나면(5~15분) **내부 테스트**로 자기 기기에 설치한다 — 내부 테스트는 심사가 없다.

**실기기에서 반드시 볼 것** (심사에서 터질 순서대로):

- [ ] 로그인 4종 — Google · **Apple** · 이메일 · 카카오
      (⚠️ 카카오는 아래 6번 결정 전까지 실패한다)
- [ ] **공유 확장** — Safari 에서 링크 공유 → MODI 선택 → 방·폴더 선택 → 등록
      한 번도 실행된 적 없는 경로다
- [ ] 프로필 사진 업로드/표시 (MinIO presigned URL + `storage.maramodi.cloud`)
- [ ] 투두 추천(AI) 1회
- [ ] **계정 삭제** — Apple 필수 요건
- [ ] 알림 권한 요청이 뜨는지

---

## 6. 🔴 제출 전에 반드시 정해야 하는 것 — 카카오 로그인

**카카오 앱이 옛 프로젝트 팀원 소유다.** 그 콘솔의 **iOS 플랫폼 번들 ID** 를
`com.intpsquad.modi` 로 바꾸지 못하면 **카카오 로그인이 실패**한다. 카카오 서버가 요청의
번들 ID 를 검증하기 때문이고, 코드에는 번들 ID 가 없어서 이 저장소에서는 잡을 수 없다.

**동작하지 않는 기능은 거부 사유다**(Guideline 2.1 App Completeness). 셋 중 하나를 골라야 한다:

| 선택 | 시간 | 비고 |
|---|---|---|
| 옛 팀원에게 카카오 앱 팀원 초대 요청 | 상대 응답 | 가장 간단. `developers.kakao.com` → 앱 → 팀 관리 |
| **새 카카오 앱 생성**(본인 계정) | 20분 | 서버는 access token 만 검증하므로 **코드 변경 없음**. 새 네이티브 앱 키를 `Local.xcconfig`·`app/env/prod.json`(+안드로이드 매니페스트 placeholder)에 넣으면 된다. 카카오 로그인 활성화 + 동의항목(닉네임·프로필사진·이메일) 설정 필요 |
| 첫 릴리스에서 **카카오 버튼 숨기기** | 30분 | 거부 위험 0. 로그인 수단 3종으로 출시하고 다음 릴리스에 되살린다 |

---

## 7. App Store Connect — 제출에 필요한 것

Apple 이 없으면 **제출 버튼 자체를 막는다**:

- [x] 앱 레코드 생성 — **이미 있다**(`modi-modi`, iOS 1.0 제출 준비 중, 2026-08-14 확인)
- [x] 🔴 **개인정보처리방침 URL** → `https://maramodi.cloud/privacy` *(2026-08-14 구축)*
- [x] **지원 URL** → `https://maramodi.cloud/` *(2026-08-14 구축)*
- [ ] 스크린샷 — **6.7"** 세트 필수(시뮬레이터에서 캡처)
- [ ] 앱 이름 · 부제 · 설명 · 키워드 · 카테고리 — 위 "남은 것" 3번(이름이 `modi-modi` 다)
- [ ] **App Privacy** 설문 — 이 앱은 **이메일·이름·프로필 사진**을 수집한다(신고 필요)
- [ ] 연령 등급(소셜 미디어 질문 포함) · 수출 규정(암호화 사용 여부)
- [ ] 🔴 **EU 거래자(Trader) 자격** — 위 "남은 것" 1번. 계정 소유자만 설정 가능
- [ ] **Sign in with Apple** 이 App ID capability 에 켜져 있는지 재확인 — 소셜 로그인 제공 시 필수

> ⚠️ **`.p8` APNs 인증 키는 아직 없다.** 푸시가 실제로 오게 하려면 Apple 포털 **Keys** →
> ➕ → Apple Push Notifications service → `.p8` 다운로드 → Firebase 콘솔의 iOS 앱 설정에
> 업로드해야 한다. **빌드·제출을 막지는 않으므로** 제출 후에 해도 된다.

---

## 알아두면 좋은 것 (이 저장소의 함정)

- **`dart format` 은 별개 게이트다.** `analyze`·`test` 를 통과해도 CI 가 포맷으로 깨진다.
  커밋 전 셋 다 돌릴 것. 그리고 **Flutter 버전을 `app/.fvmrc`(3.44.8)와 맞출 것** —
  포맷터 출력이 버전마다 다르다.
- `lib/firebase_options.dart` 는 생성 파일이라 포맷 검사에서 걸릴 수 있다. gitignore 돼 있고
  CI 는 그 자리에 커밋된 example 을 복사해 쓰므로 무시해도 된다.
- **이미 적용된 Flyway 마이그레이션 파일을 고치지 말 것.** 주석 한 글자만 바꿔도 운영 부팅이
  깨진다(2026-08-13 실제로 그렇게 멈췄다). `FlywayMigrationImmutabilityTest` 가 잡는다.
- 서버에서 `git pull` 은 안 된다(GitHub 자격증명이 없다). 최신 코드로 배포하려면
  **Actions → CI → Run workflow**, 이미 있는 코드로 재배포는 `./deploy/deploy.sh`.
- 안드로이드는 **릴리스 경로가 없다**(서명 키·CI 없음). `applicationId` 는 iOS 와 같은 값으로
  바꿨지만 Kotlin 코드 패키지(`com.nomara.modi.app`)와 `namespace` 는 일부러 그대로다.
