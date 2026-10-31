#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
LILT_ANDROID_SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
LILT_JDK="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
LILT_INCLUDE_MELD=false
if [ "${LILT_BUILD_MELD:-auto}" != "0" ] && [ -f "$LILT_ANDROID_SDK/platforms/android-34/android.jar" ] && [ -x "$LILT_ANDROID_SDK/build-tools/36.0.0/d8" ] && [ -x "$LILT_JDK/bin/javac" ]; then
  "$PROJECT_DIR/scripts/build-meld-bridge.sh"
  LILT_INCLUDE_MELD=true
elif [ "${LILT_BUILD_MELD:-auto}" = "1" ]; then
  "$PROJECT_DIR/scripts/build-meld-bridge.sh"
else
  printf '%s\n' 'Building Spotify, Apple Music, Focus and Shelf without the optional Meld Android bridge.'
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/Lilt.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Lilt" "$APP_DIR/Contents/MacOS/Lilt"
if [ "$LILT_INCLUDE_MELD" = true ]; then
  cp "$PROJECT_DIR/build/meld-bridge/MeldBridge.jar" "$APP_DIR/Contents/Resources/MeldBridge.jar"
else
  rm -f "$APP_DIR/Contents/Resources/MeldBridge.jar"
fi
# Replace only this generated app's UI directory so removed assets cannot linger.
if [ -d "$APP_DIR/Contents/Resources/Web" ]; then
  mv "$APP_DIR/Contents/Resources/Web" "$PROJECT_DIR/build/Web.previous.$(date +%s)"
fi
cp -R "$PROJECT_DIR/Resources/Web" "$APP_DIR/Contents/Resources/Web"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/Licenses/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/Resources/Licenses/Familjen-Grotesk-OFL.txt" "$APP_DIR/Contents/Resources/Licenses/Familjen-Grotesk-OFL.txt"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lilt</string>
<key>CFBundleDisplayName</key><string>Lilt</string>
<key>CFBundleIdentifier</key><string>local.lilt.preview</string>
<key>CFBundleExecutable</key><string>Lilt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Lilt connects to your selected music app to show the current song and control playback when you ask.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
LILT_SIGNING_IDENTITY="${LILT_SIGN_IDENTITY:-}"
if [ -z "$LILT_SIGNING_IDENTITY" ]; then
  LILT_DEVELOPMENT_IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2}')"
  if [ "$(printf '%s\n' "$LILT_DEVELOPMENT_IDENTITIES" | awk 'NF { n++ } END { print n+0 }')" = "1" ]; then
    LILT_SIGNING_IDENTITY="$LILT_DEVELOPMENT_IDENTITIES"
  else
    LILT_SIGNING_IDENTITY="-"
  fi
fi
codesign --force --sign "$LILT_SIGNING_IDENTITY" "$APP_DIR"
printf '%s\n' "$APP_DIR"
