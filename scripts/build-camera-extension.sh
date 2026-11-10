#!/usr/bin/env bash
# Builds and embeds the locally-signed CMIO camera system extension.
#
# Usage: scripts/build-camera-extension.sh [Debug|Release]
#
# This intentionally uses swiftc instead of an Xcode target so local testing does
# not need a paid team or a generated Xcode project. The resulting bundle is
# signed with the self-signed "AndroLaunch Local Dev" identity; macOS only
# activates self-signed system extensions after:
#   1. SIP is reduced with: csrutil enable --without kext --without debug
#   2. sudo systemextensionsctl developer on
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/dd-androlaunch-$(whoami)}"
APP="$DERIVED/Build/Products/$CONFIG/AndroLaunch.app"
EXT_ID="com.senpai.AndroLaunch.CameraExtension"
IDENTITY="${ANDROLAUNCH_SIGNING_IDENTITY:-AndroLaunch Local Dev}"

if [[ ! -d "$APP" ]]; then
  echo "app not found at $APP; building $CONFIG first"
  DERIVED_DATA_PATH="$DERIVED" "$ROOT/scripts/build-macos.sh" "$CONFIG"
fi

"$ROOT/scripts/bootstrap-local-signing.sh" >/dev/null

WORK="$(mktemp -d /tmp/androlaunch-camext.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/ext/Contents/MacOS" "$WORK/cache" "$WORK/tmp"
cp "$ROOT/macos/CameraExtension/Info.plist" "$WORK/ext/Contents/Info.plist"

echo "compiling $EXT_ID"
TMPDIR="$WORK/tmp" CLANG_MODULE_CACHE_PATH="$WORK/cache" \
SWIFT_MODULECACHE_PATH="$WORK/tmp" \
xcrun swiftc -O \
  -module-name AndroLaunchCameraExtension \
  -target arm64-apple-macos15.0 \
  -framework CoreMediaIO -framework CoreMedia \
  -framework CoreVideo -framework CoreGraphics -framework Foundation \
  -o "$WORK/ext/Contents/MacOS/$EXT_ID" \
  "$ROOT/macos/CameraExtension/main.swift" \
  "$ROOT/macos/CameraExtension/CameraProvider.swift" \
  "$ROOT/macos/CameraExtension/CameraStream.swift"

EXT_BUNDLE="$APP/Contents/Library/SystemExtensions/$EXT_ID.systemextension"
rm -rf "$EXT_BUNDLE"
mkdir -p "$(dirname "$EXT_BUNDLE")"
cp -R "$WORK/ext" "$EXT_BUNDLE"

echo "signing extension with '$IDENTITY'"
codesign --force --sign "$IDENTITY" --timestamp=none \
  --entitlements "$ROOT/macos/CameraExtension/CameraExtension.entitlements" \
  "$EXT_BUNDLE"

echo "signing host with system-extension entitlement"
codesign --force --sign "$IDENTITY" --timestamp=none \
  --entitlements "$ROOT/macos/CameraExtension/Host.entitlements" \
  "$APP"

codesign --verify --strict "$EXT_BUNDLE"
codesign --verify --strict "$APP"

echo "camera extension embedded:"
echo "  $EXT_BUNDLE"
codesign -dv --entitlements :- "$EXT_BUNDLE" 2>&1 | grep -E "Identifier=|TeamIdentifier=|system-extension|app-sandbox" || true
