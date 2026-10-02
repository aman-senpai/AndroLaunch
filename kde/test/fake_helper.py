#!/usr/bin/env python3
"""Records AndroLaunch helper invocations and reports them, so tests can assert on the
number of calls the widget issues (e.g. that dragging a slider does not flood the device)."""
import base64
import json
import pathlib
import sys

LOG = pathlib.Path("/tmp/androlaunch-test-calls.log")
args = sys.argv[1:]

if len(args) > 2 and args[1] == "shell":
    try:
        payload = json.loads(base64.b64decode(args[2] + "=" * (-len(args[2]) % 4)).decode())
    except (ValueError, TypeError):
        payload = {}
    if payload.get("command") == "reset":   # tests start from a clean slate
        LOG.unlink(missing_ok=True)
action = args[1] if len(args) > 1 and args[0] == "call" else "runShell"
payload = args[2] if len(args) > 2 else ""
data = {}
if payload and payload != "call":
    try:
        data = json.loads(base64.b64decode(payload + "=" * (-len(payload) % 4)).decode())
    except (ValueError, TypeError):
        data = {}

with LOG.open("a") as handle:
    handle.write(f"{action} {json.dumps(data)} argv={sys.argv[1:]!r}\n")

EXPECTED = "settings put system screen_brightness 12 && echo \"ünïcode ✓\""

lines = [line.split(" argv=")[0] for line in (LOG.read_text().splitlines() if LOG.exists() else [])]
brightness = [line for line in lines if line.startswith("brightness ")]
volume = [line for line in lines if line.startswith("volume ")]
last_brightness = json.loads(brightness[-1][len("brightness "):]) if brightness else {}
last_volume = json.loads(volume[-1][len("volume "):]) if volume else {}
commands = [json.loads(line[len("shell "):]) for line in lines if line.startswith("shell ")]
# ignore the report requests themselves
commands = [c for c in commands if c.get("command") != "report"]
last_command = commands[-1].get("command") if commands else ""
command_state = "MATCH" if last_command == EXPECTED else "MISMATCH"

print(json.dumps({
    "ok": True,
    "action": action,
    "message": f"brightness={len(brightness)} lastBrightness={last_brightness.get('percent')} "
               f"volume={len(volume)} lastVolume={last_volume.get('value')} "
               f"lastCommand={last_command!r} {command_state}",
    "error": "",
    "adb": "/usr/bin/adb",
    "scrcpy": "/usr/bin/scrcpy",
    "data": {},
}))
