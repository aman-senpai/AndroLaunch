#!/usr/bin/env bash
# Builds, embeds, locally signs, and installs AndroLaunch + its camera extension.
#
# Usage: scripts/install-local-camera-extension.sh [Debug|Release]
#
# Requires:
#   * the "AndroLaunch Local Dev" self-signed identity (created automatically)
#   * developer mode for system extensions, which needs the SIP reduction:
#       csrutil enable --without kext --without debug   (Recovery, then reboot)
#       sudo systemextensionsctl developer on
#   * sudo for /Applications ownership (root:wheel)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/dd-androlaunch-$(whoami)}"
APP="$DERIVED/Build/Products/$CONFIG/AndroLaunch.app"
DEST="/Applications/AndroLaunch.app"
EXT_ID="com.senpai.AndroLaunch.CameraExtension"
IDENTITY="${ANDROLAUNCH_SIGNING_IDENTITY:-AndroLaunch Local Dev}"

SIP_STATUS="$(csrutil status 2>&1 || true)"
if printf '%s' "$SIP_STATUS" | grep -q "enabled"; then
  cat >&2 <<'MSG'
SIP is fully enabled. macOS will kill a self-signed host carrying
com.apple.developer.system-extension.install, so installing this build now would
make AndroLaunch fail to launch.

In Recovery Terminal run:
  csrutil enable --without kext --without debug

Reboot, then:
  sudo systemextensionsctl developer on

Then re-run this script.
MSG
  exit 2
fi

DERIVED_DATA_PATH="$DERIVED" "$ROOT/scripts/build-camera-extension.sh" "$CONFIG"

echo
echo "Installing signed app to $DEST"
sudo rm -rf "$DEST"
sudo ditto "$APP" "$DEST"
sudo chown -R root:wheel "$DEST"

# The signatures are created before the copy; re-signing a root-owned bundle as
# the login user would fail. Verify instead.
codesign --verify --strict "$DEST"
codesign --verify --strict "$DEST/Contents/Library/SystemExtensions/$EXT_ID.systemextension"

echo
echo "Installed: $DEST"
echo
echo "Next:"
echo "  1. Enable the local-extension developer lane once:"
echo "       sudo systemextensionsctl developer on"
echo "     (self-signed system extensions require the SIP developer-mode reduction)"
echo "  2. Open the app and go to Device › Camera Extension (or Settings › Camera)."
echo "  3. Click Install extension and approve it in"
echo "     System Settings › General › Login Items & Extensions › Camera Extensions."
echo
open "$DEST" || true
