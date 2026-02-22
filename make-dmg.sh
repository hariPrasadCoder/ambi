#!/bin/bash
# make-dmg.sh — Build Ambi and create a distributable DMG
set -e

SCHEME="Ambi"
PROJECT="Ambi.xcodeproj"
CONFIG="Release"
BUILD_DIR="./build"
VERSION=$(defaults read "$(pwd)/Ambi/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="Ambi-${VERSION}"

echo "→ Building Ambi ${VERSION}..."

# Build
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify 2>/dev/null || cat  # use xcbeautify if installed, else raw output

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/Ambi.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Build failed — app not found at $APP_PATH"
  exit 1
fi

echo "✓ Build succeeded"
echo "→ Creating DMG..."

# Clean up previous artifacts
rm -rf dmg_temp
rm -f temp.dmg

# Create staging folder
mkdir -p dmg_temp
cp -R "$APP_PATH" dmg_temp/Ambi.app
ln -s /Applications dmg_temp/Applications

# Create background image (uses ImageMagick if available, else skips)
if command -v convert &>/dev/null; then
  echo "  Creating styled background..."
  convert -size 660x400 \
    -define gradient:angle=135 \
    gradient:'#1a1a2e'-'#0d0d14' \
    -font Helvetica-Bold -pointsize 48 -fill white \
    -gravity North -annotate +0+60 'Ambi' \
    -font Helvetica -pointsize 15 -fill '#aaaacc' \
    -gravity North -annotate +0+120 'Voice Recorder & Transcription' \
    -fill '#7080ff' -stroke '#7080ff' -strokewidth 3 \
    -draw "line 230,210 410,210" \
    -draw "polygon 425,210 408,200 408,220" \
    -font Helvetica -pointsize 13 -fill '#888888' -stroke none \
    -gravity South -annotate +0+60 'Drag Ambi to Applications to install' \
    dmg-background.png
  HAS_BACKGROUND=true
else
  echo "  (Install imagemagick via 'brew install imagemagick' for a styled background)"
  HAS_BACKGROUND=false
fi

# Create writable DMG
hdiutil create -volname "Ambi" \
  -srcfolder dmg_temp \
  -ov -format UDRW \
  temp.dmg

# Mount it
MOUNT_DIR=$(hdiutil attach temp.dmg -readwrite -noverify -noautoopen | grep "/Volumes/Ambi" | awk '{print $3}')
echo "  Mounted at: $MOUNT_DIR"

# Add background if we made one
if [ "$HAS_BACKGROUND" = true ]; then
  mkdir -p "$MOUNT_DIR/.background"
  cp dmg-background.png "$MOUNT_DIR/.background/background.png"
fi

# Style the DMG window with Finder
if [ "$HAS_BACKGROUND" = true ]; then
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "Ambi"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 760, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Ambi.app" of container window to {165, 200}
    set position of item "Applications" of container window to {495, 200}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT
else
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "Ambi"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 660, 430}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set position of item "Ambi.app" of container window to {165, 200}
    set position of item "Applications" of container window to {495, 200}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT
fi

sync
hdiutil detach "$MOUNT_DIR"
sleep 2

# Compress to final DMG
hdiutil convert temp.dmg -format UDZO -imagekey zlib-level=9 -ov -o "${DMG_NAME}.dmg"
cp "${DMG_NAME}.dmg" Ambi-latest.dmg

# Clean up
rm -f temp.dmg
rm -rf dmg_temp
[ "$HAS_BACKGROUND" = true ] && rm -f dmg-background.png

echo ""
echo "✅ Done!"
echo "   ${DMG_NAME}.dmg ($(du -h "${DMG_NAME}.dmg" | cut -f1))"
echo ""
echo "⚠️  Note: App is unsigned. Friends must right-click → Open the first time."
echo "   Or: System Settings → Privacy & Security → 'Open Anyway'"
