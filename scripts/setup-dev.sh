#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-modi-mara}"
ANDROID_PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.intpsquad.modi}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.intpsquad.modi}"
API_BASE_URL=""
CONFIGURE_FIREBASE=false
PRINT_FINGERPRINTS=false
DRY_RUN=false
SKIP_PUB_GET=false

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-dev.sh [options]

Create the local development files shared by the app, Spring server, and AI server.
Existing local files are preserved. No secret value is generated or committed.

Options:
  --configure-firebase  Run FlutterFire configure for Android, iOS, and Web.
  --print-fingerprints   Print Android debug signing fingerprints.
  --api-base-url URL     Use URL when creating a new app/env/dev.json.
  --dry-run              Show actions without writing files or running tools.
  --skip-pub-get         Do not run flutter pub get.
  -h, --help             Show this help.

Environment overrides:
  FIREBASE_PROJECT_ID, ANDROID_PACKAGE_NAME, IOS_BUNDLE_ID
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup] warning: %s\n' "$*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configure-firebase)
      CONFIGURE_FIREBASE=true
      shift
      ;;
    --print-fingerprints)
      PRINT_FINGERPRINTS=true
      shift
      ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "--api-base-url requires a URL"
      API_BASE_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (use --help)"
      ;;
  esac
done

copy_if_missing() {
  local source_path="$1"
  local destination_path="$2"

  [[ -f "$source_path" ]] || die "template not found: $source_path"
  if [[ -e "$destination_path" ]]; then
    log "keep existing $destination_path"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] copy $source_path -> $destination_path"
    return
  fi

  mkdir -p "$(dirname "$destination_path")"
  cp "$source_path" "$destination_path"
  chmod 600 "$destination_path"
  log "created $destination_path"
}

copy_dev_config() {
  local source_path="$1"
  local destination_path="$2"

  [[ -f "$source_path" ]] || die "template not found: $source_path"
  if [[ -e "$destination_path" ]]; then
    log "keep existing $destination_path"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    if [[ -n "$API_BASE_URL" ]]; then
      log "[dry-run] create $destination_path with API_BASE_URL=$API_BASE_URL"
    else
      log "[dry-run] copy $source_path -> $destination_path"
    fi
    return
  fi

  mkdir -p "$(dirname "$destination_path")"
  if [[ -z "$API_BASE_URL" ]]; then
    cp "$source_path" "$destination_path"
  else
    command -v python3 >/dev/null 2>&1 || die "--api-base-url requires python3 on macOS/Linux"
    python3 - "$source_path" "$destination_path" "$API_BASE_URL" <<'PY'
import json
import pathlib
import sys

source, destination, api_base_url = sys.argv[1:]
data = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
data["API_BASE_URL"] = api_base_url
pathlib.Path(destination).write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  fi
  chmod 600 "$destination_path"
  log "created $destination_path"
}

resolve_flutterfire() {
  if command -v flutterfire >/dev/null 2>&1; then
    command -v flutterfire
    return 0
  fi

  local home_dir="${HOME:-}"
  local pub_cache="${PUB_CACHE:-$home_dir/.pub-cache}"
  if [[ -x "$pub_cache/bin/flutterfire" ]]; then
    printf '%s\n' "$pub_cache/bin/flutterfire"
    return 0
  fi
  return 1
}

configure_firebase() {
  local command_path
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cd app && flutterfire configure --project=$FIREBASE_PROJECT_ID --platforms=android,ios,web --android-package-name=$ANDROID_PACKAGE_NAME --ios-bundle-id=$IOS_BUNDLE_ID --yes"
    return
  fi

  command -v flutter >/dev/null 2>&1 || die "Flutter is required for Firebase configuration"
  command_path="$(resolve_flutterfire)" || die "FlutterFire CLI not found; install flutterfire_cli or add it to PATH"
  log "run FlutterFire configure for project $FIREBASE_PROJECT_ID"
  (
    cd "$ROOT_DIR/app"
    "$command_path" configure \
      "--project=$FIREBASE_PROJECT_ID" \
      --platforms=android,ios,web \
      "--android-package-name=$ANDROID_PACKAGE_NAME" \
      "--ios-bundle-id=$IOS_BUNDLE_ID" \
      --yes
  )
}

print_fingerprints() {
  local gradle_wrapper="$ROOT_DIR/app/android/gradlew"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cd app/android && ./gradlew signingReport"
    return
  fi

  if [[ ! -x "$gradle_wrapper" ]]; then
    warn "Android Gradle wrapper is missing or not executable: $gradle_wrapper"
    return
  fi
  log "print Android debug SHA-1/SHA-256 fingerprints"
  (
    cd "$ROOT_DIR/app/android"
    ./gradlew signingReport
  )
}

validate_local_files() {
  local required_paths=(
    "$ROOT_DIR/app/env/dev.json"
    "$ROOT_DIR/server/.env"
    "$ROOT_DIR/ai/.env"
  )

  if [[ "$(uname -s)" == "Darwin" ]]; then
    required_paths+=("$ROOT_DIR/app/ios/Flutter/Local.xcconfig")
  fi

  for path in "${required_paths[@]}"; do
    if [[ -f "$path" ]]; then
      log "ready ${path#$ROOT_DIR/}"
    else
      warn "missing ${path#$ROOT_DIR/}"
    fi
  done

  local firebase_options="$ROOT_DIR/app/lib/firebase_options.dart"
  if [[ -f "$firebase_options" ]]; then
    if grep -q 'REPLACE_WITH' "$firebase_options"; then
      warn "firebase_options.dart still contains placeholders"
    else
      log "ready app/lib/firebase_options.dart"
    fi
  else
    warn "missing app/lib/firebase_options.dart; run with --configure-firebase"
  fi

  local google_services="$ROOT_DIR/app/android/app/google-services.json"
  if [[ -f "$google_services" ]]; then
    if grep -Fq "\"package_name\": \"$ANDROID_PACKAGE_NAME\"" "$google_services"; then
      log "ready app/android/app/google-services.json ($ANDROID_PACKAGE_NAME)"
    else
      warn "google-services.json does not contain Android package $ANDROID_PACKAGE_NAME; run with --configure-firebase"
    fi
  else
    warn "missing app/android/app/google-services.json; run with --configure-firebase"
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ -f "$ROOT_DIR/app/ios/Runner/GoogleService-Info.plist" ]]; then
      log "ready app/ios/Runner/GoogleService-Info.plist ($IOS_BUNDLE_ID must match its bundle ID)"
    else
      warn "missing app/ios/Runner/GoogleService-Info.plist; run with --configure-firebase"
    fi
  fi

  if [[ ! -f "$ROOT_DIR/server/src/main/resources/firebase-service-account.json" ]]; then
    warn "missing server/src/main/resources/firebase-service-account.json; Firebase-protected API calls will return 401"
  fi

  if ! grep -Fq "applicationId = \"$ANDROID_PACKAGE_NAME\"" "$ROOT_DIR/app/android/app/build.gradle.kts"; then
    warn "app/android/app/build.gradle.kts does not use Android package $ANDROID_PACKAGE_NAME"
  fi
}

log "workspace: $ROOT_DIR"
log "Android package: $ANDROID_PACKAGE_NAME"
log "iOS bundle: $IOS_BUNDLE_ID"

copy_if_missing "$ROOT_DIR/server/.env.example" "$ROOT_DIR/server/.env"
copy_if_missing "$ROOT_DIR/ai/.env.example" "$ROOT_DIR/ai/.env"
copy_dev_config "$ROOT_DIR/app/env/dev.macos.example.json" "$ROOT_DIR/app/env/dev.json"

if [[ "$(uname -s)" == "Darwin" ]]; then
  copy_if_missing \
    "$ROOT_DIR/app/ios/Flutter/Local.xcconfig.example" \
    "$ROOT_DIR/app/ios/Flutter/Local.xcconfig"
else
  warn "not macOS; skipping iOS Local.xcconfig"
fi

if [[ "$SKIP_PUB_GET" == false ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cd app && flutter pub get"
  elif command -v flutter >/dev/null 2>&1; then
    log "run flutter pub get"
    (cd "$ROOT_DIR/app" && flutter pub get)
  else
    warn "Flutter not found; skipped flutter pub get"
  fi
fi

if [[ "$CONFIGURE_FIREBASE" == true ]]; then
  configure_firebase
fi

if [[ "$PRINT_FINGERPRINTS" == true ]]; then
  print_fingerprints
fi

validate_local_files

cat <<'EOF'

Setup finished. Next steps:
  1. Fill server/.env and ai/.env with team-provided values.
  2. Add each developer's Android debug SHA-1 in Firebase Console.
  3. Run with --configure-firebase after Firebase fingerprints are updated.
  4. Start dependencies from server/: docker compose up -d

Production deploy/.env is intentionally not created by this developer setup.
EOF
