#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_NAME="Amatsume init"
DEPLOYMENT_TARGET="arm64-apple-macosx13.0"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
EXECUTABLE_PATH="$CONTENTS_DIR/MacOS/$APP_NAME"
FINDER_EXTENSION_NAME="AmatsumeFinderExtension"
FINDER_EXTENSION_BUNDLE="$CONTENTS_DIR/PlugIns/$FINDER_EXTENSION_NAME.appex"
FINDER_EXTENSION_CONTENTS="$FINDER_EXTENSION_BUNDLE/Contents"
FINDER_EXTENSION_EXECUTABLE="$FINDER_EXTENSION_CONTENTS/MacOS/$FINDER_EXTENSION_NAME"
ASSET_CATALOG="$PROJECT_DIR/Resources/Assets.xcassets"
ASSET_INFO_PLIST="$BUILD_DIR/asset-info.plist"

rm -rf "$APP_BUNDLE"
mkdir -p \
  "$CONTENTS_DIR/MacOS" \
  "$CONTENTS_DIR/Resources" \
  "$FINDER_EXTENSION_CONTENTS/MacOS"

xcrun swiftc \
  -parse-as-library \
  -O \
  -target "$DEPLOYMENT_TARGET" \
  -module-cache-path /private/tmp/amatsume-init-swift-module-cache \
  "$PROJECT_DIR/Sources/ApplicationMain.swift" \
  "$PROJECT_DIR/Sources/AppDelegate.swift" \
  "$PROJECT_DIR/Sources/KeyboardMonitor.swift" \
  "$PROJECT_DIR/Sources/StatusIcon.swift" \
  "$PROJECT_DIR/Sources/TerminalApplication.swift" \
  -framework FinderSync \
  -o "$EXECUTABLE_PATH"

xcrun swiftc \
  -parse-as-library \
  -O \
  -application-extension \
  -target "$DEPLOYMENT_TARGET" \
  -module-name "$FINDER_EXTENSION_NAME" \
  -module-cache-path /private/tmp/amatsume-finder-swift-module-cache \
  "$PROJECT_DIR/FinderExtension/FinderSync.swift" \
  -framework AppKit \
  -framework FinderSync \
  -Xlinker -e \
  -Xlinker _NSExtensionMain \
  -o "$FINDER_EXTENSION_EXECUTABLE"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/FinderExtension/Info.plist" "$FINDER_EXTENSION_CONTENTS/Info.plist"
xcrun actool "$ASSET_CATALOG" \
  --compile "$CONTENTS_DIR/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-format human-readable-text \
  --output-partial-info-plist "$ASSET_INFO_PLIST"
plutil -lint "$CONTENTS_DIR/Info.plist"
plutil -lint "$FINDER_EXTENSION_CONTENTS/Info.plist"
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --entitlements "$PROJECT_DIR/FinderExtension/FinderExtension.entitlements" \
  "$FINDER_EXTENSION_BUNDLE"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
