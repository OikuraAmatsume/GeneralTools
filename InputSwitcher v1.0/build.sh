#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
xcrun swiftc \
  -module-cache-path /private/tmp/input-switcher-swift-module-cache \
  "$PROJECT_DIR/InputSwitcher.swift" \
  -o "$PROJECT_DIR/InputSwitcher"

echo "Built: $PROJECT_DIR/InputSwitcher"
