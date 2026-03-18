#!/usr/bin/env bash

set -euo pipefail

PROJECT="JuiceBar.xcodeproj"
SCHEME="JuiceBar"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-JuiceBar}"
VERSION_FILE="${VERSION_FILE:-$PWD/VERSION}"
DIST_DIR="${DIST_DIR:-$PWD/dist}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$DIST_DIR/$APP_NAME.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$DIST_DIR/export}"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/$APP_NAME.zip}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-$DIST_DIR/ExportOptions.plist}"
TEAM_ID="${DEVELOPMENT_TEAM:-${TEAM_ID:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
MARKETING_VERSION_OVERRIDE="${MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION_OVERRIDE="${CURRENT_PROJECT_VERSION:-}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release.sh unsigned
  ./scripts/release.sh archive
  ./scripts/release.sh export
  ./scripts/release.sh zip
  ./scripts/release.sh notarize
  ./scripts/release.sh all

Environment:
  DEVELOPMENT_TEAM=YOURTEAMID   Required for signed archive/export if not already set in Xcode
  NOTARY_PROFILE=profile-name   Required for notarize/all
  CONFIGURATION=Release         Optional build configuration
  DIST_DIR=./dist               Optional output directory
EOF
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_team_if_needed() {
  if [[ -z "$TEAM_ID" ]]; then
    echo "DEVELOPMENT_TEAM is not set. Set it in Xcode or pass DEVELOPMENT_TEAM=YOURTEAMID." >&2
    exit 1
  fi
}

load_version_defaults() {
  if [[ -z "$MARKETING_VERSION_OVERRIDE" && -f "$VERSION_FILE" ]]; then
    MARKETING_VERSION_OVERRIDE="$(tr -d '[:space:]' < "$VERSION_FILE")"
  fi

  if [[ -z "$CURRENT_PROJECT_VERSION_OVERRIDE" ]]; then
    CURRENT_PROJECT_VERSION_OVERRIDE="1"
  fi
}

prepare_dist() {
  mkdir -p "$DIST_DIR"
}

unsigned_build_app() {
  prepare_dist
  load_version_defaults

  rm -rf "$EXPORT_DIR"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE" \
    CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION_OVERRIDE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    SYMROOT="$DIST_DIR/build" \
    OBJROOT="$DIST_DIR/build-obj" \
    build

  mkdir -p "$EXPORT_DIR"
  rm -rf "$APP_PATH"
  cp -R "$DIST_DIR/build/$CONFIGURATION/$APP_NAME.app" "$APP_PATH"
}

write_export_options() {
  prepare_dist

  cat > "$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
EOF
}

archive_app() {
  require_team_if_needed
  prepare_dist
  load_version_defaults

  rm -rf "$ARCHIVE_PATH"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE" \
    CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION_OVERRIDE" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -archivePath "$ARCHIVE_PATH" \
    archive
}

export_app() {
  require_team_if_needed
  require_file "$ARCHIVE_PATH"
  write_export_options

  rm -rf "$EXPORT_DIR"

  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH"
}

zip_app() {
  require_file "$APP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

notarize_zip() {
  require_file "$ZIP_PATH"

  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARY_PROFILE is not set. Create one with: xcrun notarytool store-credentials \"juicebar-notary\"" >&2
    exit 1
  fi

  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  zip_app
}

command="${1:-help}"

case "$command" in
  unsigned)
    unsigned_build_app
    zip_app
    ;;
  archive)
    archive_app
    ;;
  export)
    export_app
    ;;
  zip)
    zip_app
    ;;
  notarize)
    notarize_zip
    ;;
  all)
    archive_app
    export_app
    zip_app
    notarize_zip
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage
    exit 1
    ;;
esac
