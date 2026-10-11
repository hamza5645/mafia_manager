#!/usr/bin/env bash
# Builds the Debug app with Tuist and Xcode's normal signing, then installs and launches it
# on a simulator. Usage: ./scripts/run_ios_sim.sh ["Simulator Name"]
# Without a name it uses the first available iPhone simulator.

# Re-exec under bash if invoked with another shell (e.g., zsh from IntelliJ)
if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_PATH="$PROJECT_ROOT/mafia_manager.xcworkspace"
SCHEME="mafia_manager"
CONFIGURATION="Debug"
# The first available iPhone. awk reads the whole list, so no pipe is cut short under pipefail.
first_iphone() {
  xcrun simctl list devices available \
    | awk '/^ +iPhone / && !found { sub(/^ +/, ""); sub(/ \([0-9A-F-]+\) \(.*$/, ""); print; found = 1 }'
}
SIMULATOR_NAME="${1:-$(first_iphone)}"
if [[ -z "$SIMULATOR_NAME" ]]; then
  echo "✖︎ No available iPhone simulator. Pass a simulator name: $0 \"iPhone 18 Pro\""
  exit 1
fi
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/mafia_manager-run_ios_sim"
LOG_DIR="${TMPDIR:-/tmp}"
BUILD_LOG="$LOG_DIR/run_ios_sim_build.log"

cd "$PROJECT_ROOT"

echo "→ Resolving dependencies and generating the workspace..."
tuist install >"$LOG_DIR/run_ios_sim_tuist.log" 2>&1 \
  && tuist generate --no-open >>"$LOG_DIR/run_ios_sim_tuist.log" 2>&1 || {
  echo "✖︎ Tuist failed. See $LOG_DIR/run_ios_sim_tuist.log"
  exit 1
}

echo "→ Building $SCHEME for $SIMULATOR_NAME..."
xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  >"$BUILD_LOG" 2>&1 || {
  echo "✖︎ Build failed. Full log: $BUILD_LOG"
  grep -E ": (error|fatal error):" "$BUILD_LOG" | sort -u | head -20 || true
  exit 1
}

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✖︎ Failed to locate built app at $APP_PATH (build log: $BUILD_LOG)"
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")

echo "→ Booting simulator $SIMULATOR_NAME..."
# -b boots a shut-down device, then waits until it has finished booting.
xcrun simctl bootstatus "$SIMULATOR_NAME" -b

echo "→ Installing app..."
xcrun simctl install "$SIMULATOR_NAME" "$APP_PATH"

echo "→ Launching $BUNDLE_ID..."
xcrun simctl launch "$SIMULATOR_NAME" "$BUNDLE_ID"

echo "✓ App launched on $SIMULATOR_NAME"
