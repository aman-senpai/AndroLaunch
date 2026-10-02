#!/usr/bin/env python3
"""Backend tests for AndroLaunch: parsers, the app-list source rules and the slider value
mapping. No device required — device-facing paths are exercised with a bogus serial.

    python3 kde/test/test_backend.py
"""
import base64
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
HELPER = pathlib.Path(__file__).resolve().parents[1] / "bin" / "androlaunch"
loader = importlib.machinery.SourceFileLoader("androlaunch", str(HELPER))
spec = importlib.util.spec_from_loader("androlaunch", loader)
al = importlib.util.module_from_spec(spec)
loader.exec_module(al)

FAILURES: list[str] = []


def check(name: str, got, want) -> None:
    if got != want:
        FAILURES.append(f"{name}\n   got:  {got!r}\n   want: {want!r}")


# ---------------------------------------------------------------- parsers ----
devices = al.parse_devices(
    "List of devices attached\n"
    "R58M12ABCDE            device product:beyond1lte model:SM_G973F device:beyond1 transport_id:1\n"
    "192.168.1.42:5555      device product:beyond1lte model:SM_G973F device:beyond1 transport_id:2\n"
    "emulator-5554          offline\n"
    "R58M99ZZZZZ            unauthorized usb:1-2\n"
)
check("devices.count", len(devices), 4)
check(
    "devices.usb",
    (devices[0]["id"], devices[0]["name"], devices[0]["connected"], devices[0]["wireless"]),
    ("R58M12ABCDE", "SM G973F", True, False),
)
check("devices.wifi", (devices[1]["id"], devices[1]["address"]), ("192.168.1.42:5555", "192.168.1.42:5555"))
check("devices.offline", (devices[2]["emulator"], devices[2]["connected"]), (True, False))

# one phone exposed twice (Android 11+ wireless debugging) collapses to one usable entry
twins = al.parse_devices(
    "List of devices attached\n"
    "adb-9ce66ab6-wEAQDl._adb-tls-connect._tcp device product:apollo model:M2007J17I device:apollo\n"
    "192.168.1.37:40687     device product:apollo model:M2007J17I device:apollo\n"
)
check("dedupe.count", len(twins), 1)
check("dedupe.keeps_mdns_serial", twins[0]["id"], "adb-9ce66ab6-wEAQDl._adb-tls-connect._tcp")
check("dedupe.keeps_address", twins[0]["address"], "192.168.1.37:40687")
check("dedupe.wireless", twins[0]["wireless"], True)

info = al.parse_info(
    "MODEL:SM_G973F\nVER:13\nSDK:33\n  level: 87\n  powered: true\nWIFI:1\nBT:0\nDARK:yes\n"
    "AIR:0\nDATA:1\nLOC:3\nDND:zen_mode = 2\nROT:0\nBRI:204\nvolume is 7 in range [0..15]\n"
)
check("info.battery", info["battery"], 87)
check("info.toggles", [info["wifi"], info["bluetooth"], info["darkMode"], info["airplaneMode"],
                       info["mobileData"], info["location"], info["dnd"], info["autoRotate"]],
      [True, False, True, False, True, True, True, False])
check("info.volume", info["volume"], 47)

apps = al.parse_scrcpy_apps(
    "List of apps:\n * Settings com.android.settings\n - Spotify com.spotify.music\n - My Notes com.example.my_notes\n"
)
check("apps.pkgs", [a["package"] for a in apps], ["com.android.settings", "com.spotify.music", "com.example.my_notes"])
check("apps.names", [a["name"] for a in apps], ["Settings", "Spotify", "My Notes"])
check("apps.system", [a["system"] for a in apps], [True, False, False])

entries = al.parse_ls(
    "total 32\n"
    "drwxrwx--x  5 root sdcard_rw 4096 2024-05-01 12:33 Android\n"
    "-rw-rw----  1 root sdcard_rw  120 2024-05-01 12:34 my notes.txt\n"
    "lrwxrwxrwx  1 root root        21 2024-05-01 12:35 sdcard -> /storage/self/primary\n",
    "/sdcard",
)
by_name = {e["name"]: e for e in entries}
check("ls.dir", (by_name["Android"]["isDirectory"], by_name["Android"]["formattedSize"]), (True, "--"))
check("ls.file", (by_name["my notes.txt"]["path"], by_name["my notes.txt"]["size"]), ("/sdcard/my notes.txt", 120))
check("ls.symlink", by_name["sdcard"]["name"], "sdcard")

check("decode_args", al.decode_args(base64.b64encode(b'{"path":"/sdcard"}').decode()), {"path": "/sdcard"})
check("decode_args.bad", al.decode_args("!!!notb64"), {})
check("envelope", al.envelope("files", "tok", {"ok": False, "data": [], "path": "/x"})["path"], "/x")

# ----------------------------------------------------------------- mapping ----
check("percent_to_raw.20", al.percent_to_raw(20, 4095), 819)
check("percent_to_raw.80", al.percent_to_raw(80, 4095), 3276)
check("percent_to_raw.255", al.percent_to_raw(50, 255), 128)
check("percent_to_raw.clamp", (al.percent_to_raw(-5, 255), al.percent_to_raw(150, 255)), (0, 255))
check("percent_to_index.music", al.percent_to_index(30, 0, 150), 45)
check("percent_to_index.ring", al.percent_to_index(30, 0, 15), 5)
check("percent_to_index.offset", al.percent_to_index(50, 1, 15), 8)

# ------------------------------------------------------- app list sources ----
cache = al.APPS_CACHE
backup = cache.read_text() if cache.exists() else None
try:
    al.APPS_CACHE = pathlib.Path("/tmp/androlaunch-apps-test.json")
    al.APPS_CACHE.unlink(missing_ok=True)

    good = [{"package": "com.spotify.music", "name": "Spotify", "system": False}]
    al._store_apps("device-x", good)
    check("apps_cache.roundtrip", al._cached_apps("device-x"), good)

    # scrcpy unavailable, cache warm -> clean names stay, never package-derived ones
    os.environ["ANDROLAUNCH_SCRCPY"] = "/nonexistent"
    al.SCRCPY = al.find_scrcpy()
    warm = al.action_apps({"device": "device-x"})
    check("apps.cache_source", warm["source"], "cache")
    check("apps.cache_names", [a["name"] for a in warm["data"]], ["Spotify"])

    # scrcpy unavailable and no cache -> package names, honestly labelled
    al.APPS_CACHE.unlink()
    cold = al.action_apps({"device": "device-x"})
    check("apps.pm_source", cold["source"], "pm")
    check("apps.pm_message", "package names" in cold["message"], True)

    # cache can be bypassed
    al._store_apps("device-x", good)
    forced = al.action_apps({"device": "device-x", "refresh": True})
    check("apps.refresh_bypasses_cache", forced["source"], "pm")
finally:
    os.environ.pop("ANDROLAUNCH_SCRCPY", None)
    al.APPS_CACHE.unlink(missing_ok=True)
    if backup is not None:
        cache.write_text(backup)

print("\n".join(FAILURES) if FAILURES else "ALL BACKEND TESTS PASSED")
sys.exit(1 if FAILURES else 0)
