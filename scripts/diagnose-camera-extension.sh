#!/usr/bin/env bash
set -uo pipefail
APP="${1:-/Applications/AndroLaunch.app}"
EXT_ID="com.senpai.AndroLaunch.CameraExtension"
EXT="$APP/Contents/Library/SystemExtensions/$EXT_ID.systemextension"

echo "== identity =="
security find-identity -v -p codesigning 2>&1 | head -5
echo
echo "== SIP / developer mode =="
csrutil status 2>&1 | head -2
systemextensionsctl developer 2>&1 | head -3
echo
echo "== signatures =="
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -4
codesign -dv --entitlements :- "$APP" 2>&1 | grep -E "Identifier=|TeamIdentifier=|system-extension" || true
codesign -dv --entitlements :- "$EXT" 2>&1 | grep -E "Identifier=|TeamIdentifier=|app-sandbox|application-groups" || true
echo
echo "== extension list =="
systemextensionsctl list 2>&1 | sed -n '/cmio/,+6p'
