#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_NAME="Amatsume init"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
EXECUTABLE_PATH="$CONTENTS_DIR/MacOS/$APP_NAME"
ASSET_CATALOG="$PROJECT_DIR/Resources/Assets.xcassets"
ASSET_INFO_PLIST="$BUILD_DIR/asset-info.plist"

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

xcrun swiftc \
  -parse-as-library \
  -O \
  -module-cache-path /private/tmp/amatsume-init-swift-module-cache \
  "$PROJECT_DIR/Sources/ApplicationMain.swift" \
  "$PROJECT_DIR/Sources/AppDelegate.swift" \
  "$PROJECT_DIR/Sources/KeyboardMonitor.swift" \
  "$PROJECT_DIR/Sources/StatusIcon.swift" \
  -o "$EXECUTABLE_PATH"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
xcrun actool "$ASSET_CATALOG" \
  --compile "$CONTENTS_DIR/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-format human-readable-text \
  --output-partial-info-plist "$ASSET_INFO_PLIST"
plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
