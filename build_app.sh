#!/bin/bash

set -e

APP_NAME="CassettePlayer"
BUNDLE_ID="com.alexvario.CassettePlayer"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Сборка CassettePlayer ==="

swift build -c release

echo "=== Создание .app ==="

rm -rf "$APP_DIR"

mkdir -p \
    "$MACOS_DIR" \
    "$RESOURCES_DIR"

cp \
    "$BUILD_DIR/$APP_NAME" \
    "$MACOS_DIR/$APP_NAME"

if [ -d "$BUILD_DIR/CassettePlayer_CassettePlayer.bundle" ]; then
    cp -R \
        "$BUILD_DIR/CassettePlayer_CassettePlayer.bundle" \
        "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>

    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>NSHighResolutionCapable</key>
    <true/>

</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/$APP_NAME"

echo ""
echo "=== Готово ==="
echo "$APP_DIR"
echo ""
echo "Bundle ID:"
/usr/libexec/PlistBuddy \
    -c "Print :CFBundleIdentifier" \
    "$CONTENTS_DIR/Info.plist"

echo ""
echo "Проверка структуры:"
find "$APP_DIR/Contents" -maxdepth 2 -print

echo ""
echo "Для запуска:"
echo "open \"$APP_DIR\""