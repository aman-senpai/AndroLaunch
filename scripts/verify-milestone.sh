#!/usr/bin/env bash
#
# One-command verification for the feature milestone:
#   macOS Debug build → shared logic tests → Android companion → Hub snapshots
#   → MCP stdio smoke test.
#
# Usage: scripts/verify-milestone.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-/tmp/dd-androlaunch-verify}"
APP="$DERIVED/Build/Products/Debug/AndroLaunch.app/Contents/MacOS/AndroLaunch"
OUT="$ROOT/build/hub-snapshots"

echo "== macOS build (Debug) =="
DERIVED_DATA_PATH="$DERIVED" "$ROOT/scripts/build-macos.sh" Debug

echo "== shared logic tests =="
"$ROOT/scripts/test-macos-logic.sh"

echo "== Android companion =="
( cd "$ROOT/android" && ./build.sh )
cp "$ROOT/android/AndroLaunchCompanion.apk" "$ROOT/macos/AndroLaunch/AndroLaunchCompanion.apk"

echo "== Hub + platform snapshots =="
DERIVED_DATA_PATH="$DERIVED" "$ROOT/scripts/render-hub-snapshots.sh" "$OUT"
echo "== Menu-bar glass panel snapshots =="
"$APP" --render-menu-bar-panel-snapshots "$ROOT/build/panel-snapshots"
if [[ -d "$ROOT/build/platform-snapshots" ]]; then
  echo "platform snapshots: $ROOT/build/platform-snapshots"
fi

echo "== app runtime smoke =="
"$APP" --open-menu-bar-panel >/tmp/androlaunch-verify-app.log 2>&1 &
APP_PID=$!
sleep 5
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "app crashed during launch; see /tmp/androlaunch-verify-app.log" >&2
  exit 1
fi
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

echo "== MCP stdio smoke =="
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | "$APP" --mcp-server > /tmp/androlaunch-verify-mcp.out 2>/tmp/androlaunch-verify-mcp.err
python3 - <<'PY'
import json
lines = [line for line in open('/tmp/androlaunch-verify-mcp.out') if line.strip()]
assert len(lines) == 2, f"expected 2 MCP responses, got {len(lines)}"
first = json.loads(lines[0])
second = json.loads(lines[1])
assert first["result"]["protocolVersion"] == "2025-06-18", first
assert len(second["result"]["tools"]) == 15, len(second["result"]["tools"])
print("MCP: 15 tools, initialize ok")
PY

echo
echo "All milestone checks passed."
echo "Snapshots: $OUT"
