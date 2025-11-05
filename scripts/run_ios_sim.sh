#!/usr/bin/env bash

# Re-exec under bash if invoked with another shell (e.g., zsh from IntelliJ)
if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/mafia_manager.xcodeproj"
SCHEME="mafia_manager"
CONFIGURATION="Debug"
SIMULATOR_NAME="iPhone 17 Pro"
DERIVED_DATA="$PROJECT_ROOT/DerivedData"

echo "→ Building $SCHEME for $SIMULATOR_NAME..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build \
  >/tmp/run_ios_sim_build.log

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✖︎ Failed to locate built app at $APP_PATH"
  exit 1
fi

echo "→ Ad-hoc signing app bundle..."
/usr/bin/codesign --force --sign - --timestamp=none --deep "$APP_PATH" >/tmp/run_ios_sim_codesign.log 2>&1 || {
  echo "✖︎ codesign failed. See /tmp/run_ios_sim_codesign.log"
  exit 1
}

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")

echo "→ Booting simulator $SIMULATOR_NAME..."
xcrun simctl bootstatus "$SIMULATOR_NAME" >/dev/null 2>&1 || xcrun simctl boot "$SIMULATOR_NAME"
xcrun simctl bootstatus "$SIMULATOR_NAME" -b

echo "→ Installing app..."
xcrun simctl install "$SIMULATOR_NAME" "$APP_PATH"

echo "→ Launching $BUNDLE_ID..."
xcrun simctl launch "$SIMULATOR_NAME" "$BUNDLE_ID"

echo "✓ App launched on $SIMULATOR_NAME"
