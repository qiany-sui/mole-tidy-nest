#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/mole-tidy-nest.app"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
ICON_SOURCE="$PROJECT_DIR/build/app-icon.png"

cd "$PROJECT_DIR"
xcrun swift build --configuration release --product MoleTidyNest
xcrun swift build --configuration release --product MoleTidyNestBridge
BINARY_DIR="$(xcrun swift build --configuration release --show-bin-path)"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Helpers" "$ICONSET_DIR"
cp "$BINARY_DIR/MoleTidyNest" "$APP_BUNDLE/Contents/MacOS/MoleTidyNest"
cp "$BINARY_DIR/MoleTidyNestBridge" "$APP_BUNDLE/Contents/Helpers/MoleTidyNestBridge"
ditto "$BINARY_DIR/MoleTidyNest_MoleTidyNestEngine.bundle" "$APP_BUNDLE/Contents/Resources/MoleTidyNest_MoleTidyNestEngine.bundle"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

xcrun swift "$PROJECT_DIR/scripts/make-icon.swift" "$ICON_SOURCE"
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}.png" > /dev/null
    RETINA_SIZE=$((ICON_SIZE * 2))
    sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" > /dev/null
done
iconutil --convert icns "$ICONSET_DIR" --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# 本地自用构建使用 ad-hoc 签名；正式发行需要独立的 Developer ID 流程。
codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/MoleTidyNestBridge"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
printf '已生成：%s\n' "$APP_BUNDLE"
