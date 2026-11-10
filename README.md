# AndroLaunch - Your Android Device Management App for macOS, Windows & Linux

<p align="center">
  <img src="https://github.com/user-attachments/assets/1da15d00-ab8a-4afb-8d26-fd23ae3a3cda" alt="AndroLaunch" width="150">
</p>

**AndroLaunch** connects your Android devices to your desktop using ADB and scrcpy. Mirror your screen, manage apps, and move files through native macOS, Windows, and KDE Plasma interfaces. Developer tools remain available without getting in the way of everyday tasks.

## 🚀 Key Features at a Glance

| Workflow | What you can do |
| :-- | :-- |
| Connect | Detect USB devices, authorize debugging, and pair wirelessly with QR or a pairing code. |
| Control | Open device apps, change supported Android settings, and manage installed APKs. |
| Mirror | Mirror the display or camera, choose a quality preset, and adjust advanced settings when needed. |
| Transfer | Browse device files, upload, and download. Windows includes a transfer queue, measured progress where available, cancellation, conflict choices, and failed-item retry. |
| Capture on Windows | Save PNG screenshots, copy them to the clipboard, or record an MP4 with explicit stop/save controls. |
| Quick access on Windows | Search actions with **Ctrl+K**, save favorite apps/actions/commands, and revisit recent actions. |
| Continuity on macOS | One identity per phone across USB, Wi-Fi and Bonjour: preferences follow the device, connections race and fail over, and reconnect themselves after sleep. |
| Dashboard on macOS | One Liquid Glass menu-bar surface with **Apps / Notifications / Storage / Device / Settings**: live USB and Wi-Fi pairing, an app catalog with Frame Mode windows, phone features, tools and preferences. |
| Phone on the Mac | Calls with best-effort Answer/Decline, now-playing media controls, notification actions with inline reply, phone storage, APK/APKS/APKM/XAPK installation, camera preview, and trackpad gestures. |
| AI on your phone | **Android Use**: a local stdio MCP server with 15 phone tools, an activity log, and a stop control. Works with Codex, Claude Code, Cursor and other MCP clients. |
| Day-to-day loops | Opt-in clipboard sharing with companion detection, drop-to-send file transfer, Android notification mirroring, a Glance desktop board, and a Finder **Send to Android** service. |
| Develop | Access shell, Logcat, saved commands, reboot modes, and optional Android emulators. |

Platform capabilities differ; Windows capture/quick actions and the transfer queue described below are not claims of identical features on macOS or KDE.

## 🧪 Verify the macOS milestone

```bash
./scripts/verify-milestone.sh
```

This builds the macOS app, runs the Foundation logic suite, builds the
Android companion, renders the dashboard and platform snapshots to `build/`, launches the
app once, and exercises the local MCP server over stdio. The individual scripts are
`scripts/build-macos.sh`, `scripts/test-macos-logic.sh`,
`scripts/render-hub-snapshots.sh` and `android/build.sh`.

## 🛠️ Setup: Get Started in Minutes

AndroLaunch requires `adb` to communicate with Android devices. For screen mirroring features, `scrcpy` is also required.

### macOS Installation

Requires **macOS 15.3 (Sequoia) or later**.

**Option A — Homebrew (recommended)**

```bash
brew install --cask aman-senpai/apps/androlaunch
```

This installs AndroLaunch.app to `/Applications`; dependencies (`adb` and `scrcpy`) are installed automatically if missing.

The tap-qualified name is the reliable form. After adding the tap (`brew tap aman-senpai/apps`) the short `brew install --cask androlaunch` works too, but it fails with *"Cask androlaunch exists in multiple taps"* when this repository is also tapped under its old name — in that case run `brew untap aman-senpai/tap`.

Homebrew 5+ asks you to trust a third-party tap the first time: accept the prompt, or run `brew trust aman-senpai/apps` (needed in scripts and on CI).

> **Note**: the app is ad-hoc signed (not notarized), so macOS may refuse the first launch. Either right-click AndroLaunch in `/Applications` → **Open**, or run `xattr -dr com.apple.quarantine /Applications/AndroLaunch.app`.

**Option B — Manual download**

1.  **Launch**: Download the [macOS v0.3.9 build](https://github.com/aman-senpai/AndroLaunch/releases/download/v0.3.9/v0.3.9-macos.zip), move AndroLaunch.app to Applications, and run. This remains the latest published macOS binary; v0.4.0 includes macOS source improvements but no newly built macOS application.

2.  **Onboarding Wizard**: On first launch, AndroLaunch guides you through dependency setup with an interactive onboarding window:
    - Automatically detects existing ADB and scrcpy installations
    - Offers one-click **Install with Homebrew** for missing dependencies
    - Shows real-time installation progress
    - Lets you skip and configure later via Settings

    > **Note**: Requires scrcpy v4.0+ for all features.

3.  **Manual CLI Install** (optional): Prefer the terminal?
    ```bash
    brew install --cask android-platform-tools
    brew install scrcpy
    ```

### Windows Installation

1. **Install AndroLaunch 0.4.0** using the [Windows x64 installer](https://github.com/aman-senpai/AndroLaunch/releases/download/v0.4.0/AndroLaunch-0.4.0-windows-x64-setup.exe). No administrator privileges are required. Alternatively, extract the entire [portable ZIP](https://github.com/aman-senpai/AndroLaunch/releases/download/v0.4.0/v0.4.0-windows.zip) and run `AndroLaunch/AndroLaunch.WinUI.exe`; keep its companion files together.
2. **Open Setup** to detect ADB and scrcpy. Install missing dependencies with the offered **winget** actions, or use the linked official downloads. Scoop and Chocolatey installations are also detected.
3. **Connect a device** using the USB instructions below, then refresh Setup. Unauthorized and offline devices have recovery guidance. Finish requires an authorized device, or explicitly choose **Skip for now**.
4. **Mirror** with scrcpy **4.0 or newer**. Setup checks the actual executable version, including a configured override. Missing or unsupported scrcpy does not prevent ordinary ADB app/file management.

The Windows app uses **WinUI 3**: native navigation, menus, dialogs, system light/dark styling and a Mica backdrop. It includes device controls and mirroring configuration, app management and APK installation/export, a file browser, an Android emulator manager, QR/manual wireless pairing, saved commands, preferences and dependency onboarding. Android SDK command-line tools and the emulator are required only for AVD management; configure their paths in Settings.
The native Windows title bar follows the same system app mode and updates live when Windows switches between light and dark.

The Windows 10 (1809+) / Windows 11 x64 packages include .NET and Windows App SDK; neither runtime needs a separate installation. The notification-area icon is the same monochrome Android mark as the macOS menu bar, embedded in light/dark variants. Windows may initially put it under **Hidden icons**; drag it onto the taskbar to pin it. Closing the main window leaves AndroLaunch running in the tray; choose **Exit** to quit.

[Release notes](https://github.com/aman-senpai/AndroLaunch/releases/tag/v0.4.0) · [SHA-256 checksums](https://github.com/aman-senpai/AndroLaunch/releases/download/v0.4.0/SHA256SUMS.txt)

To verify a download in PowerShell, run `Get-FileHash .\AndroLaunch-0.4.0-windows-x64-setup.exe -Algorithm SHA256` (or use the ZIP filename), then compare the result with `SHA256SUMS.txt`.

#### Windows 0.4.0 workflows

- **Devices:** Mirror, Apps, Files, and Capture stay prominent. Quick settings, background clipboard sharing, camera configuration, and developer/power actions expand when needed. Unauthorized/offline targets cannot run device actions. Separate ADB serials remain separate targets, including phones of the same model.
- **Mirror presets:** Balanced, Best quality, Low bandwidth, and Presentation explain their quality/bandwidth tradeoffs. Presets and custom mirror/camera options persist per device. Manual changes become Custom.
- **Files:** upload files/folders or download selections through a queue. Existing destinations require **Overwrite**, **Skip**, or **Rename**. Transfers stage beside the destination before committing; cancellation keeps earlier completed items and attempts to remove incomplete staging data. Cleanup failures identify any retained temporary path.
- **Folder overwrite means replacement, not merge.** Linked upload sources and downloaded directory trees containing symbolic links are rejected. Failed-only retry does not repeat successful, skipped, or cancelled items. Progress shows measured bytes/rate/ETA when available; otherwise adb percentages or an indeterminate state. **Show in folder** opens the download location.
- **Capture:** choose a save directory and filename prefix; timestamps and unique suffixes prevent filename collisions. Screenshots save as PNG and can be copied or opened. Recording opens a scrcpy window and saves MP4; use **Stop and save recording** or close that recording window to finalize. Do not unplug the device before saving. Protected content may not be capturable. Capture recording does not enable clipboard sharing.
- **Quick actions:** **Ctrl+K** searches navigation, connected-device actions, saved commands, and favorite apps. Use **Include installed apps** to search the full app catalog. Favorites and recent actions are stored locally. Select the target device explicitly when several are connected.
- **Shortcuts:** **Ctrl+1/2/3** opens Devices/Apps/Files; **Ctrl+M** mirrors the selected authorized device; **Ctrl+Shift+S** opens Capture; **Ctrl+F** focuses app search on the Apps page.
- **Settings:** Android SDK/emulator paths and manual tool overrides are optional collapsed sections. SDK installation is not required for managing a physical device.

**Build on Windows:** install the .NET 8 SDK, Visual Studio Windows App SDK/WinUI build prerequisites and Inno Setup 6. Then run:

```powershell
dotnet build windows/AndroLaunch.WinUI/AndroLaunch.WinUI.csproj -c Release
./scripts/publish-windows.ps1 -Iscc 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

Windows release artifacts are versioned under `build/windows/v<version>/`: an unpackaged `AndroLaunch/` directory, portable ZIP, and per-user setup executable. The publish script takes the version from the project and refuses to overwrite an existing release directory.

The Windows release is unsigned; Windows SmartScreen may warn when launching it.

### Linux Installation (KDE Plasma 6)

One command installs the dependencies, the `androlaunch` CLI and the Plasma panel widget, then
adds the widget to your panel:

```bash
curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash
```

Requirements: KDE Plasma 6 (`plasma-workspace`). `android-tools` (adb), `scrcpy` and `python3` are
installed with your package manager (`dnf`, `apt-get`, `pacman`, `zypper`, `apk`) if they are
missing. When the distro packages no scrcpy — Fedora 44 ships none, and RPM Fusion carries none
either — the installer downloads the static **x86_64** build from the
[scrcpy releases](https://github.com/Genymobile/scrcpy/releases) into `~/.local/share/scrcpy`
(checksum-verified against the release `SHA256SUMS.txt`, wrapper at `~/.local/bin/scrcpy`); upstream
publishes no Linux aarch64 build, so there scrcpy must be installed manually. Everything is
user-local: backend at `~/.local/bin/androlaunch`, widget at
`~/.local/share/plasma/plasmoids/org.androlaunch.plasma`. Uninstall with `--uninstall`.

**Features on Linux**:
- Native panel (menubar) widget: device/battery status, tabbed popup with quick toggles,
  mirroring, app manager, file browser, wireless pairing, ADB shell and AVD control
- Wireless pairing via QR code or 6-digit pairing code
- Full CLI (`androlaunch devices|state|mirror|toggle|apps|files|shell|...`)

See [`kde/README.md`](kde/README.md) for details, CLI reference and troubleshooting.

### Step 2: Configure Your Android Device

1. On Android, open **Settings → About phone**, then tap **Build number** seven times to enable Developer options (the exact path varies by manufacturer).
2. Enable **USB debugging** in Developer options. Connect a data-capable USB cable, unlock the phone, and approve the computer's RSA fingerprint prompt.
3. Refresh devices in AndroLaunch. If authorization is missing, reconnect the cable and look for the prompt. Revoke USB debugging authorizations and authorize again only if necessary.
4. For wireless debugging on Android 11+, keep both devices on the same trusted network and use **Wireless pairing**. Use the pairing screen's port/code, not the separate connection port.

ADB grants powerful access to your device. Authorize only computers you trust and disable debugging when it is no longer needed. Device manufacturers and Android versions restrict some settings; unavailable or unconfirmed actions should be handled on the phone directly.

-----

## ✨ Features In-Depth

### 📱 Device and System Management

Manage your device's core functions directly from your Mac menu bar:

  * **Real-time Device List**: See all connected Android devices and their status (e.g., *Connected*, *Unauthorized*).
  * **Quick Toggles**: Instantly switch Wi-Fi, Bluetooth, Mobile Data, Location, and other critical system settings on or off.
  * **Power Controls**: Easily **Reboot** your device into the System, Bootloader, or Recovery modes.
  * **Volume & Brightness**: Adjust device volume and screen brightness sliders without touching your phone.

### 🔌 Seamless Connectivity

  * **Automatic Setup**: AndroLaunch automatically discovers ADB from common install locations (Homebrew, Android Studio) and manages the ADB daemon.
  * **Wireless Pairing**: Connect through Android's wireless-debugging QR or pairing-code flow.
  * **ADB Shell**: Open a dedicated terminal for the selected device to execute custom ADB commands directly.

### 📂 App Control and Installation

Control your installed applications and manage APK files effortlessly:

  * **App List and Search**: Browse all installed apps with a quick search function.
  * **Launch Apps**: Open any app instantly from the menu.
  * **App Windows**: Open an app in its own resizable window on a scrcpy virtual display. On Android 12–13 the app is instead opened on the mirrored screen (foreground), because the platform SystemUI crashes on such virtual displays and locks the device.
  * **App Uninstall**: Remove an app after confirming the target and consequences.
  * **Clear App Data**: Permanently reset an app's local data; this is not an undoable action.
  * **Install APK**: Select or drop an APK to install it on the intended device.

### 🖥️ Full Screen Mirroring (via Scrcpy)

Mirror your Android screen to your Mac with advanced options:

  * **Full Mirroring**: Launch a window showing your device's screen.
  * **Borderless Mode**: For a cleaner, more integrated view.
  * **Camera Mirroring**: Preview your device's camera (front or back) in a separate window with custom FPS and resolution settings.
  * **Audio Toggle**: Choose to mirror the audio from your device to your Mac.
  * **Window behavior**: Configure borderless presentation and supported aspect-ratio behavior.
  * **Quality presets**: Choose an outcome first; tune resolution, frame rate, and bitrate under advanced settings.
  * **Virtual displays**: Open supported app windows or use flexible display sizing where the Android version permits it.
  * **Camera settings**: Choose facing, frame rate, and size according to device capabilities.

Advanced options vary by platform and scrcpy version. A successful launch also depends on Android authorization, device encoders, and camera permissions.

### 🔗 Continuity layer (macOS)

The macOS app treats a phone as one device, not as whichever ADB transport it is
reachable on.

- **One identity per phone.** Preferences, mirror presets and clipboard opt-in are
  keyed by the hardware serial, so unplugging USB and reconnecting over Wi-Fi keeps
  the device configured exactly as it was. Existing v0.3/v0.4 preferences are
  migrated automatically on first launch.
- **Racing connections and failover.** AndroLaunch remembers every transport it has
  seen for a device — USB, a Bonjour service name, a remembered LAN address, or an
  address you add yourself (Tailscale, ZeroTier, an SSH forward) — and races the
  wireless candidates, preferring USB, then Bonjour, then a stored IP. When a cable
  is unplugged or the network changes, it fails over instead of dropping the session.
  A 9-second presence check reconnects devices that come back, after sleep, or after
  a brief Wi-Fi drop. Disconnecting on purpose does not fight the user.
- **Clipboard.** Android → Mac reuses an open mirror session when it can, and
  otherwise runs one hidden session; Mac → Android detects real pasteboard changes
  instead of polling text. Mac → Android is delivered by **AndroLaunch Comp**, the
  first-party companion that ships with this app — choose **Install AndroLaunch
  Comp** in the Clipboard menu and AndroLaunch installs it over ADB. No third-party
  app and no Play Store dependency. AndroLaunch Comp is a Jetpack Compose +
  Material 3 control panel (Material You dynamic color, system light/dark, the
  real app icon) with a compact brand-colored connection notification. Its loopback socket (behind
  `adb forward`) serves clipboard writes, platform-parsed notification data, and
  opt-in call awareness with best-effort answer/decline on the phone. The macOS app
  now surfaces calls in a floating banner and the status menu, with Answer/Decline
  (audio always stays on the phone). Protocol v5 adds notification actions and
  inline reply, media transport, ring phone, storage information and clipboard
  images, real launcher icons, and the storage-permission handshake. See [`android/README.md`](android/README.md).
- **Drag, drop, send.** Drop files on the file browser, choose **Send Files to
  Device…** in a device's menu, or use Finder → **Services → Send to Android**.
  Transfers are queued one at a time with per-file results and a completion
  notification.
- **Notification mirroring.** Opt in per device to see Android notifications in
  macOS Notification Center; clicking one opens the app on the phone. Sensitive apps
  (banking, password managers, authenticators, mail) are hidden by default, and
  notifications without readable text are never mirrored.

The design and file layout for this layer are documented in
[`docs/continuity-architecture.md`](docs/continuity-architecture.md).

### ✨ Menu-bar dashboard (macOS)

The menu bar is the only main surface: left-click the status icon for the floating
**Liquid Glass dashboard**, right-click for the classic menu. The dashboard is
built around five tabs — Apps, Notifications, Storage, Device and Settings — with
no separate second window.

- **Devices.** A USB card with live device rows (status, Android version, battery,
  transport) and three-step guidance; a Wi-Fi card with four connection methods —
  **QR code** (generated by the app, scanned by Android’s Wireless debugging),
  **Pairing code** (Bonjour discovery + `adb pair`), **IP address** (validated
  IPv4 / bracketed IPv6 + `adb connect`), and **Companion app** (installs
  AndroLaunch Comp over ADB); and an “On this Mac” entry for the emulator manager.
- **Apps.** Search the phone’s launchable apps, pin favourites, install
  APK/APKS/APKM/XAPK packages with a permission/compatibility inspector, drag files
  onto the dashboard to send them, and open an Android app in its own **Frame Mode**
  window on Android 14+ (main-display mirroring with an honest explanation on
  older releases). Desktop shortcuts and Spotlight indexing are included.
- **Settings.** Fusion mode (Frame Mode, Spotlight Search, Open Links on Mac,
  Handoff), Hardware support (phone-camera preview + an honest camera-extension
  status, trackpad gestures, Glance desktop board), **AI → Android Use** (MCP
  command, activity log, stop server), device/notification/clipboard controls,
  storage, launch at login, and About.

The panel has the same five tabs (Apps, Notifications, Storage, Device, Settings),
a device/Frame Mode header and the app grid, plus a **Tools** sheet for Mirror
Controls, Storage Analytics, Finder Mirror, Copy Clipboard to Android, camera,
commands, AVD, Wi-Fi and Mirror Controls. There is no bottom
status strip; refresh lives in Tools. Notifications are on by default and poll the
companion directly, so the panel works even if macOS banners are denied. Wi-Fi
pairing, AVDs, saved commands, Mirror Controls, Storage Analytics and the full
Settings surface expand **inside the panel** instead of opening windows. A
Bluetooth quick action is in Tools. Scrollbars are hidden throughout; the panel adapts to
**light and dark** desktop appearances (real Liquid Glass on macOS 26+, a
thin-material fallback on older releases).

The camera extension has a **local-signing test lane**: `scripts/install-local-camera-extension.sh Release`
builds, self-signs and embeds a real CMIO system extension, then installs the app
to `/Applications`. It emits a 720p test pattern so FaceTime/Zoom/QuickTime can
select **AndroLaunch Camera**; see [`docs/camera-extension-local-signing.md`](docs/camera-extension-local-signing.md).
Self-signed system extensions require `csrutil enable --without kext --without debug`
and `sudo systemextensionsctl developer on` once.

App icons are **real launcher icons**: the companion (`v5`) serves 96×96 PNGs for
launchable apps, cached under `~/Library/Application Support/AndroLaunch/AppIcons`.
Without the companion, the UI keeps its SF Symbol fallbacks. Installing the
companion over ADB pre-grants notification, media/storage and notification-listener
access; phone/call permissions remain opt-in in the companion UI.

**Device Dashboard** (`⌘D`) opens the same compact dashboard from the menu bar,
with five tabs:

- **Apps:** search by name/package, app grid, “Copy to Android” for typed text or
  links, companion install helper, and one-tap app windows.
- **Notifications:** Showing / Hidden / **Recently Canceled** groups with real app
  icons, sender/subject shaping, Delete / Mark as read / Reply / Open, and
  per-device sync.
- **Storage:** file management plus an inline Storage Analytics donut; when
  Android hides folder access, an **Allow storage access** card opens the grant.
- **Device:** every connected phone is listed and expandable; the selected phone
  shows model/battery/transport, mirror/camera/screenshot/ring/storage actions,
  Wi-Fi pairing, AVDs, saved commands, trackpad/glance and every action that used to require the old menu.
- **Settings:** device-scoped audio, clipboard, quality and Frame Mode preferences.

**Storage Analytics** shows internal and SD-card capacity as donut charts with
Apps / User files / System & Others categories, folder drill-down, and the largest
media files. **Mount**/Open materializes a local **Finder mirror** under
`~/Library/Application Support/AndroLaunch/Finder` and reveals it in Finder (a
sidebar link is created at `~/AndroLaunch`).

**Mirror Controls** is a floating panel for the active mirror: audio forwarding,
always-on-top (Pin), screen off, clipboard, screenshot, recording, Mac keyboard,
frame toggle and Back/Home/Recents. Option changes restart that device’s mirror;
screenshots save to the Desktop and recordings to Movies.

**Copy to Android** is available as a macOS Services item for selected text/URLs
and from the dashboard search. The menu-bar **Tools** sheet exposes it alongside
the mirror, storage and Finder surfaces.

Also in this milestone: a redesigned onboarding flow, a floating call banner and
media controls, notification inline reply, camera preview, trackpad gesture panel,
and the Glance desktop board.

**Honest limits.** There is no relay cloud (use a LAN/VPN `adb connect` endpoint), no
cellular call audio on the Mac, and this unsigned build does not ship signed
extension targets (CMIO camera, File Provider, Quick Look, Share). The working
alternatives are the camera preview, the Finder mirror, Finder Services and the
Services “Copy to Android” item; the signed-extension packaging remains separate.
Plans for these surfaces are in
[`docs/feature-expansion-plan.md`](docs/feature-expansion-plan.md).

### Clipboard sharing

**Mirror-session forwarding** belongs to scrcpy and applies while its session runs. It is separate from any background clipboard bridge.

On Windows, the optional **Background clipboard bridge** checks for the third-party [ADB Clipboard app](https://play.google.com/store/apps/details?id=ch.pete.adbclipboard) before enabling PC-to-Android delivery. Its enabled indicator records the requested state, not verified delivery or helper-process health. Pause it explicitly to stop background sharing for that device.

On macOS, enable **Share clipboard** per device from the Clipboard section or a device's Configuration submenu.

The KDE console provides explicit **Send desktop text** and **Read last Android export** actions through the companion. Reading an export is not live synchronization: Android restrictions may require opening/tapping the companion first, and access to its exported file may be restricted.

Clipboard contents may contain passwords or other sensitive text. Enable sharing only for a trusted device. See each platform's controls for its scope and companion requirements.

-----

## 📸 Screenshots

<p>
  <img src="https://github.com/user-attachments/assets/542a6e2b-d7f3-450b-89a3-cd5e110a765e" width="48%" />
  <img alt="menu" src="https://github.com/user-attachments/assets/5d19767c-a3fe-4790-935f-6de1f6fd462f" width="20%"/>
  <img alt="Device menu" src="https://github.com/user-attachments/assets/6de31106-9c8a-4594-b929-c131dc12c584" width="18%" />
  <img src="https://github.com/user-attachments/assets/679d98b6-05d9-4802-a987-4afe14720e22" width="18%" />
  <img alt="" src="https://github.com/user-attachments/assets/33a38462-e46e-4afc-886d-32cdefe4f2b3" width="18%"/>
  <img alt="" src="https://github.com/user-attachments/assets/6aed1028-4f55-4a5c-bea0-19e30b1b0419" width="18%"/>
  <img alt="Manage Commands" src="https://github.com/user-attachments/assets/6390befe-24b6-4fa7-8409-99fe612f72a6" width="25%"/>
</p>

## License 📄

This project is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**. See [LICENSE](LICENSE).

-----

**Powered by [scrcpy](https://github.com/Genymobile/scrcpy)**

<a href="https://github.com/Genymobile/scrcpy"><img src="https://raw.githubusercontent.com/Genymobile/scrcpy/master/app/data/scrcpy.png" alt="scrcpy" width="32" height="32"></a>
