#!/bin/bash
set -euo pipefail
LILT_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$LILT_PROJECT_DIR"
LILT_RELEASE_VERSION="${1:-}"
if ! [[ "$LILT_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]*$ ]]; then
  printf '%s\n' 'Usage: ./scripts/package-release.sh 0.1.0-beta.1' 'This script only packages explicitly unnotarized beta versions.' >&2
  exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  printf '%s\n' 'Commit the release sources first. Packaging requires a clean Git working tree.' >&2
  exit 2
fi
LILT_RELEASE_OUTPUT="$LILT_PROJECT_DIR/build/releases/$LILT_RELEASE_VERSION"
if [ -e "$LILT_RELEASE_OUTPUT" ]; then
  printf '%s\n' "Release output already exists: $LILT_RELEASE_OUTPUT" >&2
  exit 2
fi
LILT_SOURCE_REVISION="$(git rev-parse HEAD)"
mkdir -p "$LILT_PROJECT_DIR/build"
LILT_PACKAGE_STAGE="$(mktemp -d "/private/tmp/lilt-release-$LILT_RELEASE_VERSION.XXXXXX")"
mkdir -p "$LILT_PACKAGE_STAGE/source"
git archive HEAD | tar -x -C "$LILT_PACKAGE_STAGE/source"
LILT_VERSION="${LILT_RELEASE_VERSION%%-beta.*}" \
LILT_BUILD_NUMBER="${LILT_RELEASE_VERSION##*-beta.}" \
LILT_BUNDLE_ID=io.github.thimorrow.Lilt \
LILT_BUILD_UNIVERSAL=1 LILT_BUILD_MELD=0 LILT_SIGN_IDENTITY=- \
  "$LILT_PACKAGE_STAGE/source/scripts/build-app.sh"
LILT_PAYLOAD="$LILT_PACKAGE_STAGE/Lilt-$LILT_RELEASE_VERSION"
mkdir -p "$LILT_PAYLOAD"
ditto "$LILT_PACKAGE_STAGE/source/build/Lilt.app" "$LILT_PAYLOAD/Lilt.app"
codesign --verify --deep --strict "$LILT_PAYLOAD/Lilt.app"
lipo -verify_arch arm64 x86_64 "$LILT_PAYLOAD/Lilt.app/Contents/MacOS/Lilt"
ln -s /Applications "$LILT_PAYLOAD/Applications"
cp "$LILT_PACKAGE_STAGE/source/docs/INSTALL-BETA.txt" "$LILT_PAYLOAD/INSTALL.txt"
mkdir -p "$LILT_RELEASE_OUTPUT"
LILT_ASSET_NAME="Lilt-$LILT_RELEASE_VERSION-universal"
ditto -c -k --sequesterRsrc --keepParent "$LILT_PAYLOAD" "$LILT_RELEASE_OUTPUT/$LILT_ASSET_NAME.zip"
hdiutil create -quiet -volname "Lilt $LILT_RELEASE_VERSION" -srcfolder "$LILT_PAYLOAD" -format UDZO "$LILT_RELEASE_OUTPUT/$LILT_ASSET_NAME.dmg"
cat > "$LILT_RELEASE_OUTPUT/RELEASE-INFO.txt" <<INFO
Lilt $LILT_RELEASE_VERSION
Source commit: $LILT_SOURCE_REVISION
Bundle identifier: io.github.thimorrow.Lilt
Architectures: arm64 x86_64
Minimum macOS: 15.0
Signing: ad-hoc, not Developer ID
Notarization: not notarized; explicit macOS approval required
Meld Android bridge: not bundled
INFO
(
  cd "$LILT_RELEASE_OUTPUT"
  shasum -a 256 "$LILT_ASSET_NAME.dmg" "$LILT_ASSET_NAME.zip" RELEASE-INFO.txt > SHA256SUMS.txt
)
printf '%s\n' "Release assets: $LILT_RELEASE_OUTPUT" "Source commit: $LILT_SOURCE_REVISION"
