# AndroLaunch - Your Android Device Management Hub for macOS, Windows & Linux

<p align="center">
  <img src="https://github.com/user-attachments/assets/1da15d00-ab8a-4afb-8d26-fd23ae3a3cda" alt="AndroLaunch" width="150">
</p>

**AndroLaunch** is a professional and powerful cross-platform application (macOS, Windows & Linux) designed to give you effortless control over your Android devices using the power of ADB (Android Debug Bridge) and Scrcpy. Manage quick settings, launch apps, install APKs, and even mirror your device screen—all from one convenient spot.

## 🚀 Key Features at a Glance

| Category                 | Features                                                                                        | New in Latest Release                                                                      |
| :----------------------- | :---------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------- |
| **Setup & Connectivity** | First-launch onboarding wizard, automatic device detection, ADB status monitoring.             | **Onboarding Wizard**, **Wireless Pairing via QR Code**, dedicated ADB Shell terminal.      |
| **Quick Controls**       | Toggle Wi-Fi, Bluetooth, Mobile Data, Location, DND, Auto-Rotate. Adjust volume and brightness. | **Uninstall Apps**, **Clear App Data**, install APKs from file.                            |
| **App & System**         | List and launch installed apps, system reboot (normal, bootloader, recovery).                   | Improved app search and native menu integration.                                           |
| **Screen Mirroring**     | Full device screen mirroring with custom resolution.                                            | **Flex Display**, **Camera Torch & Zoom**, **Aspect Ratio Lock**, **Custom Background**, **Keep Active**, **Render Fit**. |
| **Productivity**         | Clipboard sync, command execution, file management.                                           | **Bi-directional Clipboard Sync** (Mac/PC $leftrightarrow$ Android).                          |

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

> **Note**: the app is ad-hoc signed (not notarized), so macOS may refuse the first launch. Either right-click AndroLaunch in `/Applications` → **Open**, or run `xattr -dr com.apple.quarantine /Applications/AndroLaunch.app`.

**Option B — Manual download**

1.  **Launch**: Download the macOS build (`v<version>-macos.zip`) from [Releases](https://github.com/aman-senpai/AndroLaunch/releases), move AndroLaunch.app to Applications, and run.

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

1.  **Install ADB** (required): We recommend using **Scoop** or **Chocolatey**:
    - **Scoop**: `scoop install adb`
    - **Chocolatey**: `choco install adb`

2.  **Install scrcpy** (for screen mirroring): We recommend using **Scoop** or **Chocolatey**:
    - **Scoop**: `scoop install scrcpy`
    - **Chocolatey**: `choco install scrcpy`

    > **Note**: Requires scrcpy v4.0+ for all features.

3.  **Launch**: download the Windows build from [Releases](https://github.com/aman-senpai/AndroLaunch/releases). Windows artifacts are not attached to every release — the newest is `windows.v0.zip` on [v0.3.3](https://github.com/aman-senpai/AndroLaunch/releases/tag/v0.3.3).

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
  * **New! Wireless Pairing**: Connect your Android device wirelessly to your Mac using a simple **QR Code scan**—no cables required after the initial setup.
  * **New! ADB Shell**: Open a dedicated terminal for the selected device to execute custom ADB commands directly.

### 📂 App Control and Installation

Control your installed applications and manage APK files effortlessly:

  * **App List and Search**: Browse all installed apps with a quick search function.
  * **Launch Apps**: Open any app instantly from the menu.
  * **App Windows**: Open an app in its own resizable window on a scrcpy virtual display. On Android 12–13 the app is instead opened on the mirrored screen (foreground), because the platform SystemUI crashes on such virtual displays and locks the device.
  * **New! App Uninstall**: Remove unwanted apps with a confirmation dialog.
  * **New! Clear App Data**: Reset an application to its initial state by clearing all its saved data.
  * **New! Install APK**: Drag and drop or select an APK file to install it directly onto the connected device.

### 🖥️ Full Screen Mirroring (via Scrcpy)

Mirror your Android screen to your Mac with advanced options:

  * **Full Mirroring**: Launch a window showing your device's screen.
  * **Borderless Mode**: For a cleaner, more integrated view.
  * **Camera Mirroring**: Preview your device's camera (front or back) in a separate window with custom FPS and resolution settings.
  * **Audio Toggle**: Choose to mirror the audio from your device to your Mac.
  * **🔒 Aspect Ratio Lock**: Window automatically maintains device aspect ratio when resizing (disable with `--no-aspect-ratio-lock`).
  * **🎨 Custom Background**: Set any background color with hex code (e.g., `--background-color=#234567`). Default is now dark gray instead of black.
  * **🔋 Keep Active**: Prevent device sleep without changing global settings (`--keep-active`).
  * **📐 Flex Display**: Resize virtual display dynamically with the window (`--flex-display` / `-x`).
  * **📸 Camera Torch & Zoom**: Control camera flash (`--camera-torch`) and zoom level (`--camera-zoom=1.5`) for camera mirroring.
  * **📏 Render Fit**: Choose how content fits the window: `contain`, `cover`, `fit-width`, `fit-height`.
  * **🔌 Disconnected Indicator**: Shows a disconnect icon for 2 seconds before closing, so you know the connection dropped.

### 📋 Bi-directional Clipboard Sync

This is a massive productivity booster:

  * **Copy/Paste Mac $leftrightarrow$ Android**: Text copied on your Mac is instantly available on your Android device, and vice-versa.
  * **Note**: For **Android $rightarrow$ Mac** synchronization, you **must** install the companion app, [**AdbClipboard**](https://play.google.com/store/apps/details?id=ch.pete.adbclipboard), on your Android device.

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

This project is licensed under the MIT License.

-----

**Powered By**:
[<img src="https://github.com/Genymobile/scrcpy/raw/master/app/data/icon.svg" width=25>](https://github.com/Genymobile/scrcpy)
