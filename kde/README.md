# AndroLaunch for KDE Plasma (Linux)

Android device manager for **KDE Plasma 6** on Linux: a panel widget plus an
`androlaunch` command-line backend that drives `adb` and `scrcpy`.

<p align="center">
  <img src="https://github.com/user-attachments/assets/1da15d00-ab8a-4afb-8d26-fd23ae3a3cda" alt="AndroLaunch" width="120">
</p>

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash
```

The installer:

1. installs missing `adb` (`android-tools`), `scrcpy` and `python3` from your package manager,
2. installs the backend CLI to `~/.local/bin/androlaunch`,
3. installs the plasmoid `org.androlaunch.plasma`,
4. adds the widget to your panel.

Options: `--skip-deps`, `--no-panel`, `--bin-dir PATH`, `--uninstall`, `--help`.
Set `ANDROLAUNCH_REF` to install another git ref.

`scrcpy` comes from your package manager when the distro has a package for it. Fedora 44 ships none
(and RPM Fusion carries none either), so the installer then downloads the static **x86_64** build
from the [scrcpy releases](https://github.com/Genymobile/scrcpy/releases) into
`~/.local/share/scrcpy`, verifies it against the release `SHA256SUMS.txt` and puts a wrapper at
`~/.local/bin/scrcpy` (the path the backend looks at after `PATH`). Upstream publishes no Linux
aarch64 build — on those machines install scrcpy yourself.

From a checkout, run `./install.sh` in the repository root (it uses `kde/` directly).

## Requirements

| Component | Package | Needed for |
| --- | --- | --- |
| Plasma 6 (`kpackagetool6`, `plasmashell`) | `plasma-workspace` | the widget |
| `adb` | `android-tools` | everything |
| `scrcpy` (4.0+) | `scrcpy` | mirroring, camera, app mirroring; older versions are explicitly blocked |
| `python3` | `python3` | the backend CLI |
| `konsole` | `konsole` | interactive shell / logcat windows (optional) |

Package names vary by distribution: Platform-Tools may be packaged as `adb` or
`android-tools`. If your distribution does not provide it, install Google's
[Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools).
Install [scrcpy 4.0 or newer](https://github.com/Genymobile/scrcpy) separately if the
distribution package is older. Ensure the binaries are on the **Plasma session's PATH**
(a terminal-only shell alias is not enough), then use **Retry dependencies** in the popup.
The backend also checks `~/Android/Sdk/platform-tools/adb`, `~/.local/bin/adb` and
`~/.local/bin/scrcpy`. No privileged package-manager command runs from the widget.

The optional emulator is a separate Android SDK component, not part of adb. Use Android
Studio → SDK Manager → SDK Tools → Android Emulator, create a device in Device Manager,
and put the SDK's `emulator` directory on the Plasma session's PATH.

## Using the widget

Click the panel icon to open the popup. The Device, Apps, Wireless and Files tabs hold
everyday actions. The **Developer tools** icon beside them reveals Console and Emulators;
these features remain available without crowding the everyday navigation.

| Tab | What it does |
| --- | --- |
| **Device** | device identity/status, device switcher, eight switch tiles (Wi-Fi, Bluetooth, data, dark mode, airplane, location, DND, auto-rotate), brightness/volume sliders, mirror and camera buttons, device-targeted reboot/bootloader/recovery confirmation, reconnect to previous devices |
| **Apps** | search installed apps, open an app in its own window, mirror the phone with an app open, launch on Android only, install an APK; clear-data and uninstall require a confirmation naming the app, package and device |
| **Wireless** | QR pairing, manual `ip:port` + 6-digit code, direct `adb connect`, USB to TCP/IP, disconnect |
| **Files** | browse `/sdcard`, download, upload, create folders; permanent deletion requires a confirmation naming the path and device, with Cancel and no pretend undo |
| **Developer → Console** | one-off ADB shell commands, presets (screenshot, IP, battery, memory, processes, storage), interactive shell/logcat, manual companion-based clipboard transfer |
| **Developer → Emulators** | list and start Android Virtual Devices (needs the Android SDK emulator) |

The panel entry is the icon only — device name, connection type and battery level are in the
tooltip (hover) and in the popup.
The panel glyph is the real AndroLaunch mark from the macOS app (`macos/…/MenuIcons.imageset/MenuIcon.png`)
— a template image Plasma cannot tint, so it ships as a bitmap derived from that asset, one pixel
thick dark edge included, and stays legible on light and dark panels. (Panel applets must not use
`Kirigami.Theme.textColor` for this: it follows the *window* colour scheme, which is often the
opposite of the panel's.) Right-click the widget → **Configure AndroLaunch** to change
the backend path, the refresh interval and every scrcpy option (resolution, fps, bitrate, audio,
borderless, stay-awake, virtual display, camera facing/torch/zoom).

### Connection states and privacy

Unauthorized devices remain visible in the switcher but cannot run device actions. Unlock
Android and accept this computer's USB debugging RSA prompt; if it is missing, revoke USB
debugging authorizations in Developer options and reconnect. Offline devices likewise
disable controls and show USB/Wi-Fi recovery steps. Switching devices cancels pending
destructive confirmations. Requests carry the selected serial explicitly, so they do not
fall back to a newly selected device if the original disconnects.

Mirroring requires a detected scrcpy 4.0+; apps, files and ordinary ADB controls remain
available when scrcpy is missing or unsupported. **Configure AndroLaunch → Mirroring**
offers Balanced (1920 px, 60 fps, 8 Mbps), Low latency (1280 px, 60 fps, 8 Mbps),
High quality (native resolution, 60 fps, 16 Mbps), and Low bandwidth (1024 px,
30 fps, 4 Mbps) presets. These update the existing saved settings for new windows,
without changing audio, virtual-display or other choices; individual settings remain editable.

Clipboard transfer is **manual and opt-in**, not background synchronization.
**Copy output** in Console writes to the desktop clipboard only; desktop clipboard history
may retain it. **Send text to Android** requires the
[AdbClipboard companion](https://github.com/PRosenb/AdbClipboard) (`ch.pete.adbclipboard`)
and uses its documented explicit `WRITE` receiver. It never falls back to typing into the
foreground Android app. For Android-to-desktop transfer, open the companion, grant its
overlay permission and tap its floating window to export the current clipboard.
**Load Android's last clipboard export** reads that file into the transfer field; it is
not a live clipboard read and does not replace the desktop clipboard. Android permissions
may prevent access, in which case the error is shown rather than treating command output
as clipboard data. The companion retains its export on Android. Clearing the transfer field
does not erase that export or clipboard history. Avoid transferring secrets.

Wireless pairing is preferable to legacy USB-to-TCP/IP, which exposes ADB on the network.
Use legacy TCP/IP only on a trusted private network.

### App windows (multi-window)

The window button on an app row (`window-new`) starts the app on a **scrcpy virtual display**, so it
gets its own resizable window and several apps can run side by side next to your desktop windows.
The camera/`video-display` button mirrors the *phone screen* with the app in the foreground instead,
and the play button only launches the app on the device. Every window is listed under
**Open windows** in the Device tab with an individual close button (`stop-mirror`); "Stop mirroring"
closes them all. A window that fails to start reports scrcpy's error in the popup instead of failing
silently.

On **Android 12, 12L and 13** the virtual display is not used: the platform SystemUI dereferences a
null `DisplayLayout` for it on the next display-rotation event, crashes, and on restart re-shows the
lock screen — i.e. the phone ends up locked. There the app window button and the *Virtual display*
mirroring option fall back to mirroring the main screen with the app in the foreground, and the
popup says so. Android 14 removed that code path, so the virtual display is used everywhere else.

### App names

Rows show **only the app name**; there is no second line. Search and the row tooltip still match and
show the package id, and an app without a usable label is prettified (last package segment) instead
of printing a raw id.

Labels only exist in the APK resources and `scrcpy --list-apps` is the practical way to read them, so
it is the only source used. The result is cached per device in `~/.config/androlaunch/apps-cache.json`:
if scrcpy cannot start (stale port, busy device) the widget keeps showing the last list with real
labels and says so in the footer (`cached names (scrcpy unavailable)`). Only when no list has ever
been fetched does it fall back to `pm list packages`, and the footer then reads
`package names: scrcpy could not list apps` — never silently.

### Wireless debugging details

Android 11+ exposes one phone twice: as `adb-<hash>…._adb-tls-connect._tcp` and as `host:port`.
The backend keeps a single entry and prefers an **authorized mDNS serial** for scrcpy.
An offline or unauthorized alias is never marked ready merely because its address transport
is ready; that ready transport is selected instead. USB entries are not merged with Wi-Fi.
The `host:port` address is kept for display and reconnecting. Port changes are healed
through mDNS discovery when available; otherwise reconnect using the current address in Wireless.

Brightness is handled in percent: the 0–255 (older Android) and 0–4095 (Android 12+) ranges are
detected once per device (probe + cache) instead of being guessed from the current value, and volume
is mapped into the *stream's own* index range (music is 0–150 here, the ring stream 0–15). Dragging a
slider coalesces writes — one helper call in flight, the newest value wins — so a drag does not queue
one adb command per pixel, and the handle keeps showing the value under the finger until the device
confirms it.

Long lists scroll; actions report through the popup's message bar. No KDE-native runtime
verification was performed for this polish on the Windows development host.

### Native checks before release

On Plasma 6, check popup/configuration loading under Breeze light and dark themes, keyboard
focus and accessible names for icon actions, large-font/narrow-popup wrapping, all four
everyday tabs and both Developer tools. Exercise missing adb/scrcpy and scrcpy <4.0 repair
and Retry dependencies; no device, unauthorized, offline, and multiple-device selection;
confirmations canceled by selection/disconnection; app clear/uninstall and recursive file
deletion on a disposable device. Check every mirror preset with scrcpy 4.0+, camera and
app windows, clipboard with/without the real companion and with unreadable export storage,
wireless pairing/TCP/IP and AVD startup. These are required native smoke scenarios,
not claims of completed checks.

## Command line

The widget is a thin UI over the CLI, which you can use directly:

```bash
androlaunch                      # usage
androlaunch state                # devices + active device + quick actions (JSON)
androlaunch devices              # raw adb device list (JSON)
androlaunch select <id>
androlaunch mirror               # start scrcpy for the active device
androlaunch camera               # camera preview
androlaunch app-mirror <package>     # the app in its own window (virtual display)
androlaunch app-screen <package>     # phone screen with the app in the foreground
androlaunch stop-mirror <pid>        # close one window
androlaunch stop-mirrors             # close every window
androlaunch apps                 # installed user apps (JSON)
androlaunch toggle wifi on       # wifi|bluetooth|data|dark|airplane|location|dnd|rotate
androlaunch brightness 180       # 0-255
androlaunch volume 60            # 0-100
androlaunch reboot recovery      # normal|bootloader|recovery
androlaunch files /sdcard        # list a directory (JSON)
androlaunch apk-install ~/app.apk
androlaunch connect 192.168.1.42:5555
androlaunch pair 192.168.1.42:37123 123456
androlaunch shell "getprop ro.product.model"
androlaunch avds                 # emulators
```

For scripts, the machine interface is a single JSON envelope on stdout:

```bash
androlaunch call state
androlaunch call toggle "$(printf '{"what":"wifi","on":true}' | base64 -w0)"
```

```json
{"ok":true,"action":"state","token":"","message":"","error":"","adb":"/usr/bin/adb","scrcpy":"/usr/bin/scrcpy","data":{"devices":[],"active":null}}
```

## Architecture

```
panel icon ─ PlasmoidItem (contents/ui/main.qml)
              └─ Backend.qml  ── org.kde.plasma.plasma5support DataSource (executable engine)
                                  └─ androlaunch call <action> <base64-json> --token N
                                       └─ adb / scrcpy
```

* `kde/bin/androlaunch` — Python 3 CLI: all device logic, JSON in/out. Arguments travel as
  base64 JSON, so paths, package names and shell commands never go through a shell.
* `kde/plasma/` — the plasmoid package (`metadata.json`, `contents/{ui,code,config}`).
* Long-running things (scrcpy windows, Konsole) are detached; the widget never blocks.

## Troubleshooting

* **Icon shows a warning triangle** — `adb` is missing: `sudo dnf install android-tools`.
* **Widget shows "…" or does not appear after an upgrade** — Plasma caches compiled QML:
  `rm -rf ~/.cache/plasmashell/qmlcache && systemctl --user restart plasma-plasmashell`.
* **"Backend not available" in the popup** — run `androlaunch call version` in a terminal; the
  installer sets the widget's backend path to the absolute path of the installed CLI. Change it
  in the widget settings if you keep the CLI elsewhere.
* **Opening an app window locks the phone (Android 12–13)** — expected on those versions: scrcpy's
  virtual display crashes the platform SystemUI, which then re-shows the lock screen. AndroLaunch
  opens the app on the mirrored screen instead there; real virtual-display windows return on
  Android 14+ (the code path was removed upstream).
* **Nothing in the Emulators tab** — Fedora does not package the Android emulator; install the
  Android SDK emulator or Android Studio.
* **Wireless pairing fails** — enable *Wireless debugging* on the phone first; the QR flow needs
  both devices on the same network.
* **Clipboard read from the device** needs the
  [AdbClipboard](https://play.google.com/store/apps/details?id=ch.pete.adbclipboard) companion app.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash -s -- --uninstall
```

## Notes for maintainers

* **Never use a `ListView` for text rows in this applet.** In the plasmoid's QML context a
  `ListView` delegate does not paint its text at all — neither `PlasmaComponents3.Label` nor a plain
  `Text`, while `Kirigami.Icon` and buttons inside the very same delegate render fine. App and file
  lists therefore use `ScrollView { ColumnLayout { Repeater { delegate: … } } }`, the pattern that
  renders correctly in the tabs. If rows ever come up blank, this is the first thing to check.
  For colour, prefer `palette.*` over `Kirigami.Theme.*` inside delegates.
  Debug recipe: preload the tab (`preloadFullRepresentation: true`, `visitedTab: <n>`) and log the
  item's geometry, `color`, `palette.windowText` and `Kirigami.Theme.textColor` — the popup cannot be
  opened from outside, and `spectacle` cannot be used to inspect it either (it steals focus).
* Panel applets cannot use `Kirigami.Theme.textColor` for the panel glyph either (it follows the
  *window* scheme, which is often the opposite of the panel's) — that is why the panel mark is a
  bitmap with a hairline dark edge.

## Development

Run the widget's load test (instantiates every QML component against a stub backend, catching
unknown types, broken bindings and read-only property writes) and the backend parser tests:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_load.qml      # every QML component loads
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_sliders.qml   # payload encoding + write coalescing
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_reboot_confirm.qml   # power buttons need confirmation
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_toggle_chip.qml   # toggle tiles stay honest
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_device_labels.qml   # header/card device labels
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input kde/test/tst_power_row.qml   # power row is centred
python3 kde/test/test_backend.py                                             # parsers, mappings, app-list sources
```

`tst_sliders.qml` runs the real `Backend.qml` against `kde/test/fake_helper.py`, which records the
arguments it receives — that is how the "empty payload" bug (every action silently falling back to
its default) is kept from coming back.

`tst_reboot_confirm.qml` clicks the Device tab power buttons against a stub backend and asserts that
nothing reboots until the confirmation click, so a refactor cannot silently make bootloader/recovery
a one-click action again.

`tst_toggle_chip.qml` pins the toggle tile contract: a click requests the inverse state instead of
flipping the binding, the requested state shows immediately while `adb shell svc` is running, and the
optimistic state is retired by the device's echo (or by `pendingTimeout` when the toggle failed).

`tst_device_labels.qml` pins the popup's device lines: the header is a single identity line that is
never blank (it falls through name, model, address and id), while the device card carries transport,
address, Android version and battery.

`tst_power_row.qml` pins the Device tab's reboot / bootloader / recovery row: equal thirds, and each
button's icon + label pair centred. Plasma's stock button content left-aligns the label as soon as an
icon is visible, which is what made the row look ragged.

`./install.sh` from a checkout always installs the working tree, so iterate by editing
`kde/plasma/…` and re-running it; restart `plasma-plasmashell` after changing QML.

## License

GNU Affero General Public License v3.0 — see [../LICENSE](../LICENSE).
