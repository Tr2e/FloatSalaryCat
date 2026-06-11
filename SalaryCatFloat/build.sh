#!/bin/bash
set -e

APP_NAME="月薪喵"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$BUILD_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "🐱 Building $APP_NAME..."

# Clean
rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Compile Swift source
echo "  Compiling..."
ARCHS=("arm64" "x86_64")
OBJ_FILES=()
for ARCH in "${ARCHS[@]}"; do
    OBJ="$BUILD_DIR/.build/月薪喵_$ARCH.o"
    mkdir -p "$(dirname "$OBJ")"
    swiftc \
        -o "$OBJ" \
        -framework Cocoa \
        -framework AVFoundation \
        -target "$ARCH-apple-macos11.0" \
        -O \
        "$BUILD_DIR/Sources/main.swift"
    OBJ_FILES+=("$OBJ")
done
lipo -create "${OBJ_FILES[@]}" -output "$MACOS_DIR/$APP_NAME"

# Copy resources
echo "  Copying resources..."
cp "$BUILD_DIR/Resources/cat.GIF" "$RESOURCES_DIR/"
cp "$BUILD_DIR/Resources/music.mp3" "$RESOURCES_DIR/"

# Generate app icon from cat GIF first frame
TMP_ICONSET="$(mktemp -d)/caticon.iconset"
mkdir -p "$TMP_ICONSET"
python3 -c "
from PIL import Image
gif = Image.open('$BUILD_DIR/Resources/cat.GIF')
gif.seek(0)
frame = gif.convert('RGBA')
iconset = '$TMP_ICONSET'
for s in [16,32,64,128,256,512]:
    frame.resize((s,s), Image.LANCZOS).save(f'{iconset}/icon_{s}x{s}.png')
    frame.resize((s*2,s*2), Image.LANCZOS).save(f'{iconset}/icon_{s}x{s}@2x.png')
"
iconutil -c icns "$TMP_ICONSET" -o "$RESOURCES_DIR/caticon.icns"
rm -rf "$(dirname "$TMP_ICONSET")"
echo "  App icon generated"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>月薪喵</string>
    <key>CFBundleDisplayName</key>
    <string>月薪喵</string>
    <key>CFBundleIdentifier</key>
    <string>com.tr2e.salarycatfloat</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>月薪喵</string>
    <key>CFBundleIconFile</key>
    <string>caticon</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PEOF

# Create PkgInfo
echo "APPL????" > "$CONTENTS/PkgInfo"

# Set executable bit
chmod +x "$MACOS_DIR/$APP_NAME"

# Ad-hoc code sign (mitigates some Gatekeeper checks)
echo "  Signing..."
codesign --force --deep -s - "$APP_BUNDLE" 2>/dev/null || true

# Remove any existing quarantine
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Create DMG for distribution
echo "  Creating DMG..."
DMG_PATH="$BUILD_DIR/dist/月薪喵.dmg"
DMG_TMP="$(mktemp -d)"
cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications" 2>/dev/null || true
hdiutil create -volname "月薪喵" -srcfolder "$DMG_TMP" -ov -format UDZO "$DMG_PATH" > /dev/null 2>&1
rm -rf "$DMG_TMP"

echo "✅ Build complete: $APP_BUNDLE"
echo "   DMG: $DMG_PATH"
echo ""
echo "Run: open '$APP_BUNDLE'"
echo "Or drag 月薪喵.app to Applications"
