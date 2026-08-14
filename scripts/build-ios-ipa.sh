#!/usr/bin/env bash
#
# App Store 제출용 IPA 를 만든다. **Mac 에서만 돈다.**
#
# 🔴 **왜 `flutter build ipa` 를 쓰지 않는가** (2026-08-14 실측, 첫 제출 준비 중 발견)
#
# `flutter build ipa` 는 이 프로젝트에서 **서명 단계에서 실패한다**:
#
#     Communication with Apple failed: Your team has no devices from which to
#     generate a provisioning profile.
#     No profiles for 'com.intpsquad.modi' were found: Xcode couldn't find any
#     iOS App Development provisioning profiles matching 'com.intpsquad.modi'.
#
# 자동 서명이 **아카이브 단계에서 "개발용"(iOS App Development) 프로파일을 먼저 찾기** 때문이다.
# 개발용 프로파일은 팀에 등록된 기기가 최소 하나 있어야 만들어진다. 반면 **App Store 배포용
# 프로파일은 기기 등록이 전혀 필요 없다** — 즉 우리가 실제로 필요한 프로파일은 만들 수 있는데,
# 그 앞의 개발용 프로파일에서 막혀 거기까지 못 갔던 것이다.
# `-allowProvisioningUpdates` 를 줘도 같은 자리에서 실패한다(실측).
#
# 그래서 한 덩어리인 `flutter build ipa` 를 **두 단계로 쪼갠다**:
#
#   ① archive : 서명을 아예 끄고(CODE_SIGNING_ALLOWED=NO) 아카이브만 만든다 → 개발용 프로파일 불필요
#   ② export  : app-store-connect 방식으로 내보내며 **여기서** 배포용 인증서로 서명한다
#
# ⚠️ **기기를 등록해도 이 스크립트를 계속 쓰는 편이 낫다.** 기기 등록은 개발용 프로파일을
# 되살릴 뿐이고, 릴리스 빌드가 개발용 프로파일에 의존할 이유가 없다. 등록된 기기가 만료되거나
# 팀에서 빠지면 `flutter build ipa` 는 또 같은 자리에서 멈춘다.
#
# ⚠️ **`--dart-define-from-file` 은 필수다.** 빠지면 앱이 에뮬레이터 기본 주소(10.0.2.2)를
# 들고 나간다. 안드로이드는 Gradle 이 빌드를 실패시키지만 **iOS 에는 그 안전장치가 없어
# 조용히 통과한다.** 아래 STEP 0 이 그 값을 Generated.xcconfig 에 굽는다.
#
# 필요한 것: Xcode, CocoaPods, Flutter(app/.fvmrc 와 같은 버전),
#            app/ios/Flutter/Local.xcconfig(MODI_DEVELOPMENT_TEAM), app/env/prod.json,
#            키체인에 "Apple Distribution: … (<TEAM_ID>)" 인증서
#
# 절차 전체 맥락은 docs/ios-release.md 를 본다.
set -euo pipefail

# 🔴 CocoaPods 는 UTF-8 로케일이 아니면 `pod install` 이 죽는다(2026-08-14 실측):
#
#     Unicode Normalization not appropriate for ASCII-8BIT (Encoding::CompatibilityError)
#
# 셸에 LANG 이 없거나 C/POSIX 면 그렇다. `flutter build ipa` 로는 안 터지는데 그건 Flutter 가
# 자기 하위 프로세스에 UTF-8 을 넣어주기 때문이고, 여기서 직접 부를 때는 우리가 넣어야 한다.
export LANG="${LANG:-en_US.UTF-8}"
case "${LANG}" in C|POSIX|"") export LANG=en_US.UTF-8 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/app"
IOS="${APP}/ios"
ENV_FILE="${APP}/env/prod.json"
LOCAL_XCCONFIG="${IOS}/Flutter/Local.xcconfig"
OUT="${OUT:-${APP}/build/ios/ipa}"
ARCHIVE="${OUT}/Runner.xcarchive"

fail() { printf 'IPA 빌드 실패: %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS 에서만 돈다"
[[ -f "${ENV_FILE}" ]] || fail "없다: ${ENV_FILE} (env/prod.example.json 을 복사해 채운다)"
[[ -f "${LOCAL_XCCONFIG}" ]] || fail "없다: ${LOCAL_XCCONFIG} (Local.xcconfig.example 을 복사해 채운다)"

TEAM_ID="$(sed -n 's/^[[:space:]]*MODI_DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "${LOCAL_XCCONFIG}" | tr -d '[:space:]')"
[[ -n "${TEAM_ID}" ]] || fail "Local.xcconfig 의 MODI_DEVELOPMENT_TEAM 이 비어 있다 — 아카이브가 서명되지 않는다"

# 배포용 인증서가 없으면 ② 에서야 실패한다. 20분짜리 아카이브를 다 돌린 뒤 깨지지 않게 먼저 본다.
security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Distribution: .*(${TEAM_ID})" \
  || fail "키체인에 팀 ${TEAM_ID} 의 'Apple Distribution' 인증서가 없다 — Xcode > Settings > Accounts 에서 내려받는다"

printf '팀 %s · 출력 %s\n\n' "${TEAM_ID}" "${OUT}"
rm -rf "${ARCHIVE}"
mkdir -p "${OUT}"

# ── STEP 0 ── Flutter 자산과 Generated.xcconfig(=dart-define 값)를 만든다.
# `flutter build ios --no-codesign` 은 서명 없이 여기까지만 한다 — 위에서 설명한 자동 서명
# 함정을 건드리지 않으므로 이 단계는 그대로 쓸 수 있다.
printf '── ① Flutter 빌드 (서명 없음)\n'
(cd "${APP}" && flutter pub get >/dev/null)
(cd "${IOS}" && pod install >/dev/null)
(cd "${APP}" && flutter build ios --release --no-codesign --dart-define-from-file="${ENV_FILE}")

# 주소가 실제로 구워졌는지 확인한다. 이게 비면 앱은 정상 동작하는 것처럼 보이면서
# 아무 서버에도 못 붙는다 — 심사에서 "앱이 안 켜진다"로 돌아온다.
grep -q '^DART_DEFINES=' "${IOS}/Flutter/Generated.xcconfig" \
  || fail "Generated.xcconfig 에 DART_DEFINES 가 없다 — --dart-define-from-file 이 안 먹었다"

# ── STEP 1 ── 서명 없이 아카이브.
printf '\n── ② 아카이브 (서명 끔)\n'
xcodebuild \
  -workspace "${IOS}/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE}" \
  archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# ── STEP 2 ── 배포용으로 서명해 내보낸다. 프로파일이 없으면 Apple 에서 만들어 온다
# (-allowProvisioningUpdates). App Store 프로파일이라 기기 등록은 필요 없다.
printf '\n── ③ 내보내기 (App Store 서명)\n'
EXPORT_OPTIONS="${OUT}/ExportOptions.generated.plist"
cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${OUT}" \
  -allowProvisioningUpdates

IPA="$(find "${OUT}" -maxdepth 1 -name '*.ipa' -print -quit)"
[[ -n "${IPA}" ]] || fail "내보내기는 끝났는데 .ipa 가 없다: ${OUT}"

# ── 검증 ── "빌드가 성공했다"와 "제출할 수 있는 물건이 나왔다"는 다르다.
# 개발용 프로파일로 서명된 IPA 도 빌드는 성공한다 — 업로드에서야 거절당한다.
printf '\n── ④ 검증\n'
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
unzip -q "${IPA}" -d "${WORK}"
APP_BUNDLE="$(find "${WORK}/Payload" -maxdepth 1 -name '*.app' -print -quit)"

# ⚠️ 검사 결과를 **변수에 먼저 담고** 나서 grep 한다. `cmd | grep -q` 로 쓰면 안 된다 —
# `grep -q` 는 첫 매치에서 즉시 끝내며 파이프를 닫고, 그러면 앞의 명령이 SIGPIPE 로 죽어
# `set -o pipefail` 이 파이프라인을 실패로 본다. **매치에 성공했기 때문에 실패하는** 함정이다
# (2026-08-14 이 스크립트를 처음 완주시킬 때 실제로 걸렸다).
SIGN_INFO="$(codesign -dv --verbose=2 "${APP_BUNDLE}" 2>&1 || true)"
grep -q "Apple Distribution" <<<"${SIGN_INFO}" \
  || fail "배포용 인증서로 서명되지 않았다"

PROFILE_PLIST="$(security cms -D -i "${APP_BUNDLE}/embedded.mobileprovision" 2>/dev/null || true)"
GET_TASK_ALLOW="$(plutil -extract Entitlements.get-task-allow raw -o - - <<<"${PROFILE_PLIST}" 2>/dev/null || true)"
[[ "${GET_TASK_ALLOW}" == "false" ]] \
  || fail "get-task-allow 가 '${GET_TASK_ALLOW:-없음}' 이다 — 개발용 프로파일이 들어갔다(업로드가 거절된다)"

# 🔴 **확장의 버전이 본체와 다르면 Apple 이 업로드를 거부한다**(오류 90473).
# 여기서 잡지 않으면 빌드·서명·전송을 다 끝낸 뒤 Transporter 에서야 알게 된다
# (2026-08-14 실제로 그랬다 — 확장 Info.plist 에 버전이 하드코딩돼 있었고, 첫 업로드가
#  마침 `1.0.0 (1)` 이라 우연히 일치해 드러나지 않다가 `+2` 로 올리는 순간 터졌다).
# 두 파일 사이의 약속이라 Swift 테스트·flutter analyze·Xcode Validate 어느 것도 못 잡는다.
APP_SHORT="$(plutil -extract CFBundleShortVersionString raw -o - "${APP_BUNDLE}/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw -o - "${APP_BUNDLE}/Info.plist")"

while IFS= read -r EXT_BUNDLE; do
  [ -n "${EXT_BUNDLE}" ] || continue
  EXT_NAME="$(basename "${EXT_BUNDLE}")"
  EXT_SHORT="$(plutil -extract CFBundleShortVersionString raw -o - "${EXT_BUNDLE}/Info.plist" 2>/dev/null || true)"
  EXT_BUILD="$(plutil -extract CFBundleVersion raw -o - "${EXT_BUNDLE}/Info.plist" 2>/dev/null || true)"
  [[ "${EXT_BUILD}" == "${APP_BUILD}" && "${EXT_SHORT}" == "${APP_SHORT}" ]] \
    || fail "$(printf '%s 의 버전이 본체와 다르다 — 업로드가 거절된다(오류 90473).\n       본체 %s (%s) / %s %s (%s)\n       확장 Info.plist 가 $(FLUTTER_BUILD_NAME)/$(FLUTTER_BUILD_NUMBER) 를 쓰는지,\n       그 타깃의 xcconfig 가 Flutter/Generated.xcconfig 를 include 하는지 확인할 것.' \
        "${EXT_NAME}" "${APP_SHORT}" "${APP_BUILD}" "${EXT_NAME}" "${EXT_SHORT:-없음}" "${EXT_BUILD:-없음}")"
done < <(find "${APP_BUNDLE}/PlugIns" -maxdepth 1 -name '*.appex' 2>/dev/null)

printf '\n✅ %s\n' "${IPA}"
codesign -dv --verbose=2 "${APP_BUNDLE}" 2>&1 | grep -E '^(Identifier|Authority=Apple Distribution|TeamIdentifier)'
printf '   버전 %s (%s)  — 확장도 동일함을 확인\n' "${APP_SHORT}" "${APP_BUILD}"
printf '\n다음: **Transporter** 로 업로드한다(이 스크립트가 만든 아카이브는 Xcode Organizer 가\n      "No Team Found in Archive" 로 거부한다 — docs/ios-release.md 4절).\n      open -R %s\n' "${IPA}"
