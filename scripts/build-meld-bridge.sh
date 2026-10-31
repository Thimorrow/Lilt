#!/bin/bash
set -euo pipefail
LILT_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LILT_ANDROID_SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
LILT_JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
LILT_BRIDGE_BUILD="$LILT_PROJECT_DIR/build/meld-bridge"
LILT_ANDROID_JAR="$LILT_ANDROID_SDK/platforms/android-34/android.jar"
LILT_D8="$LILT_ANDROID_SDK/build-tools/36.0.0/d8"
if [ ! -f "$LILT_ANDROID_JAR" ] || [ ! -x "$LILT_D8" ] || [ ! -x "$LILT_JAVA_HOME/bin/javac" ]; then
  printf '%s\n' 'Meld bridge needs Android SDK platform 34, build-tools 36.0.0 and a JDK (Android Studio or JAVA_HOME).' >&2
  exit 1
fi
mkdir -p "$LILT_BRIDGE_BUILD/classes" "$LILT_BRIDGE_BUILD/dex"
"$LILT_JAVA_HOME/bin/javac" --release 8 -Xlint:-options -classpath "$LILT_ANDROID_JAR" -d "$LILT_BRIDGE_BUILD/classes" "$LILT_PROJECT_DIR/Resources/Android/MeldBridge.java"
"$LILT_JAVA_HOME/bin/jar" cf "$LILT_BRIDGE_BUILD/classes.jar" -C "$LILT_BRIDGE_BUILD/classes" .
JAVA_HOME="$LILT_JAVA_HOME" "$LILT_D8" --lib "$LILT_ANDROID_JAR" --output "$LILT_BRIDGE_BUILD/dex" "$LILT_BRIDGE_BUILD/classes.jar"
"$LILT_JAVA_HOME/bin/jar" cf "$LILT_BRIDGE_BUILD/MeldBridge.jar" -C "$LILT_BRIDGE_BUILD/dex" classes.dex
printf '%s\n' "$LILT_BRIDGE_BUILD/MeldBridge.jar"
