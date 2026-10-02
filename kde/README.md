# AndroLaunch for KDE Plasma (Linux)

Android device manager for **KDE Plasma 6** on Fedora: a panel (menubar) widget plus an
`androlaunch` command-line backend that drives `adb` and `scrcpy`.

<p align="center">
  <img src="https://github.com/user-attachments/assets/1da15d00-ab8a-4afb-8d26-fd23ae3a3cda" alt="AndroLaunch" width="120">
</p>

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash
```

The installer:

1. installs missing `adb` (`android-tools`) and `scrcpy` from your package manager,
2. installs the backend CLI to `~/.local/bin/androlaunch`,
3. installs the plasmoid `org.androlaunch.plasma`,
4. adds the widget to your panel.

Options: `--skip-deps`, `--no-panel`, `--bin-dir PATH`, `--uninstall`, `--help`.
Set `ANDROLAUNCH_REF` to install another git ref.

From a checkout, run `./install.sh` in the repository root (it uses `kde/` directly).

## Requirements

| Component | Package | Needed for |
| --- | --- | --- |
| Plasma 6 (`kpackagetool6`, `plasmashell`) | `plasma-workspace` | the widget |
| `adb` | `android-tools` | everything |
| `scrcpy` (v2+) | `scrcpy` | mirroring, camera, app mirroring |
| `python3` | `python3` | the backend CLI |
| `konsole` | `konsole` | interactive shell / logcat windows (optional) |

## Using the widget

Click the panel icon to open the popup. Its header is a single line naming the active device; the
transport, battery percentage and Android version live on the device card below it, and the tab bar
uses plain-language labels instead of the old `Quick`/`Pair`/`AVDs` names:

| Tab | What it does |
| --- | --- |
| **Device** | device card (name, model, Android version, battery), device switcher, eight switch tiles (Wi-Fi, Bluetooth, data, dark mode, airplane, location, DND, auto-rotate — each shows the requested state until the phone echoes it back), brightness/volume sliders, mirror + camera + shell + logcat buttons, power (reboot / bootloader / recovery, each buffered behind a confirmation row that names the device), reconnect to previous devices |
| **Apps** | search installed apps (labels always come from `scrcpy --list-apps`), **open an app in its own window**, mirror the phone screen with the app open, launch it on the device only, clear its data, uninstall (double confirmation), install an APK |
| **Wireless** | wireless debugging: QR pairing, manual `ip:port` + 6-digit code, direct `adb connect`, switch a USB device to TCP/IP, disconnect |
| **Files** | browse `/sdcard`, download, upload, create folders, delete (double confirmation) |
| **Console** | run one-off ADB shell commands, presets (screenshot, IP, battery, memory, processes, storage), open an interactive shell or logcat in Konsole, clipboard sync |
| **Emulators** | list and start Android Virtual Devices (needs the Android SDK emulator) |

The panel entry is the icon only — device name, connection type and battery level are in the
tooltip (hover) and in the popup.
The panel glyph is the real AndroLaunch mark from the macOS app (`macos/…/MenuIcons.imageset/MenuIcon.png`)
— a template image Plasma cannot tint, so it ships as a bitmap derived from that asset, one pixel
thick dark edge included, and stays legible on light and dark panels. (Panel applets must not use
`Kirigami.Theme.textColor` for this: it follows the *window* colour scheme, which is often the
opposite of the panel's.) Right-click the widget → **Configure AndroLaunch** to change
the backend path, the refresh interval and every scrcpy option (resolution, fps, bitrate, audio,
borderless, stay-awake, virtual display, camera facing/torch/zoom).

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
The backend keeps a single entry and uses the **mDNS serial**, because `scrcpy` refuses the
`ip:port` serial while the alias transport exists (that mismatch is what made app names fall back
to raw package ids). The `host:port` address is kept for display and for reconnecting, and the
phone's port changing on every wireless-debugging toggle is healed automatically: stale offline
endpoints are dropped and the device is re-connected via mDNS discovery.

Brightness is handled in percent: the 0–255 (older Android) and 0–4095 (Android 12+) ranges are
detected once per device (probe + cache) instead of being guessed from the current value, and volume
is mapped into the *stream's own* index range (music is 0–150 here, the ring stream 0–15). Dragging a
slider coalesces writes — one helper call in flight, the newest value wins — so a drag does not queue
one adb command per pixel, and the handle keeps showing the value under the finger until the device
confirms it.

Long lists are virtualised and scroll; actions report back through the message bar in the popup.

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

* **Icon shows a warning triangle** — `adb` is missing: `sudo dnf install android-tools scrcpy`.
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

MIT — see [../LICENSE](../LICENSE).
