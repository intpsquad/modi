#!/bin/zsh

# Xcode Cloud runs this immediately before its configured xcodebuild action.
# Keep all Flutter setup here: Xcode Cloud custom scripts run in ephemeral
# environments, so no later step may rely on locally installed tooling or
# untracked release configuration.
set -euo pipefail

readonly FLUTTER_VERSION="3.44.8"
readonly REPOSITORY_ROOT="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"
readonly WORKSPACE_ROOT="${CI_WORKSPACE_PATH:?CI_WORKSPACE_PATH is required}"
readonly APP_ROOT="${REPOSITORY_ROOT}/app"
readonly IOS_ROOT="${APP_ROOT}/ios"
readonly FLUTTER_SDK_ROOT="${WORKSPACE_ROOT}/flutter-${FLUTTER_VERSION}"
readonly FIREBASE_OPTIONS_PATH="${APP_ROOT}/lib/firebase_options.dart"
readonly GOOGLE_SERVICE_INFO_PATH="${IOS_ROOT}/Runner/GoogleService-Info.plist"
readonly LOCAL_XCCONFIG_PATH="${IOS_ROOT}/Flutter/Local.xcconfig"
readonly PROD_ENV_PATH="${APP_ROOT}/env/prod.json"

fail() {
  print -u2 -- "Xcode Cloud iOS preflight failed: $1"
  exit 1
}

require_env() {
  local variable_name="$1"
  [[ -n "${(P)variable_name:-}" ]] || fail "required secret environment variable is empty: ${variable_name}"
}

write_base64_secret() {
  local variable_name="$1"
  local destination="$2"
  local encoded_value="${(P)variable_name}"

  mkdir -p "${destination:h}"
  umask 077
  print -n -- "$encoded_value" | /usr/bin/base64 -D > "$destination" \
    || fail "could not decode ${variable_name}"
  chmod 600 "$destination"
  [[ -s "$destination" ]] || fail "decoded ${variable_name} is empty"
}

for variable_name in \
  MODI_FIREBASE_OPTIONS_B64 \
  MODI_GOOGLE_SERVICE_INFO_B64 \
  MODI_LOCAL_XCCONFIG_B64 \
  MODI_PROD_ENV_B64; do
  require_env "$variable_name"
done

if [[ -z "${CI_BUILD_NUMBER:-}" || "$CI_BUILD_NUMBER" != <-> || "$CI_BUILD_NUMBER" -le 0 ]]; then
  fail "CI_BUILD_NUMBER must be a positive integer"
fi

if [[ ! -x "${FLUTTER_SDK_ROOT}/bin/flutter" ]]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_SDK_ROOT"
fi

export PATH="${FLUTTER_SDK_ROOT}/bin:${PATH}"
export FLUTTER_SUPPRESS_ANALYTICS=true
export COCOAPODS_DISABLE_STATS=true

flutter_version_line="$(flutter --version 2>&1 | sed -n '1p')"
[[ "$flutter_version_line" == "Flutter ${FLUTTER_VERSION}"* ]] \
  || fail "Flutter ${FLUTTER_VERSION} is required"

flutter precache --ios

write_base64_secret MODI_FIREBASE_OPTIONS_B64 "$FIREBASE_OPTIONS_PATH"
write_base64_secret MODI_GOOGLE_SERVICE_INFO_B64 "$GOOGLE_SERVICE_INFO_PATH"
write_base64_secret MODI_LOCAL_XCCONFIG_B64 "$LOCAL_XCCONFIG_PATH"
write_base64_secret MODI_PROD_ENV_B64 "$PROD_ENV_PATH"

grep -q 'static const FirebaseOptions ios' "$FIREBASE_OPTIONS_PATH" \
  || fail "Firebase options must include an iOS FirebaseOptions value"

google_app_id="$(/usr/bin/plutil -extract GOOGLE_APP_ID raw -o - "$GOOGLE_SERVICE_INFO_PATH" 2>/dev/null || true)"
google_bundle_id="$(/usr/bin/plutil -extract BUNDLE_ID raw -o - "$GOOGLE_SERVICE_INFO_PATH" 2>/dev/null || true)"
[[ -n "$google_app_id" ]] || fail "GoogleService-Info.plist is missing GOOGLE_APP_ID"
[[ "$google_bundle_id" == "com.nomara.modi.app" ]] \
  || fail "GoogleService-Info.plist BUNDLE_ID must be com.nomara.modi.app"

grep -qE '^[[:space:]]*KAKAO_NATIVE_APP_KEY[[:space:]]*=[[:space:]]*[^[:space:]]+' "$LOCAL_XCCONFIG_PATH" \
  || fail "Local.xcconfig must define KAKAO_NATIVE_APP_KEY"
grep -q 'YOUR_KAKAO_NATIVE_APP_KEY' "$LOCAL_XCCONFIG_PATH" \
  && fail "Local.xcconfig contains the example Kakao key"

python3 - "$PROD_ENV_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as source:
        values = json.load(source)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Xcode Cloud iOS preflight failed: invalid prod.json ({error})")

for key in ("API_BASE_URL", "KAKAO_NATIVE_APP_KEY"):
    value = values.get(key)
    if not isinstance(value, str) or not value.strip() or value.startswith("YOUR_"):
        raise SystemExit(f"Xcode Cloud iOS preflight failed: prod.json requires {key}")
PY

cd "$APP_ROOT"
flutter pub get
bundle install --jobs 4 --retry 3
flutter build ios --config-only --release --no-codesign --no-pub \
  --build-number="$CI_BUILD_NUMBER" \
  --dart-define-from-file="$PROD_ENV_PATH"

cd "$IOS_ROOT"
bundle exec pod install --deployment

print -- "Xcode Cloud iOS preflight passed: Flutter ${FLUTTER_VERSION}, build ${CI_BUILD_NUMBER}"
