# AndroLaunch for Linux (Caelestia Desktop Shell)

Native widget suite and background service bringing the full power of **AndroLaunch** to Linux desktops running the [Caelestia Shell](https://github.com/caelestia-dots/shell).

---

## ✨ Features

- **📱 Device Management**: Auto-detects USB, Wi-Fi, and emulator devices with real-time battery and connection telemetry.
- **🖥️ Screen & Camera Mirroring**: One-click Scrcpy screen mirroring with flexible resizing, audio forwarding, stay-awake, and custom bitrate/FPS limits.
- **📷 Camera Preview**: Mirror front or rear Android camera with flash torch, zoom, and FPS controls.
- **📷 Wireless QR Pairing**: Connect seamlessly using Android 11+ Wireless Debugging by scanning the built-in dynamic QR code.
- **⚡ Quick Controls**: Toggle Wi-Fi, Bluetooth, Mobile Data, Airplane Mode, Location, Do Not Disturb, Auto-Rotate, and Dark Mode.
- **🚀 App Manager**: Search, launch on-device, launch mirrored in Scrcpy, clear app data, uninstall, or install APKs.
- **📁 File Explorer**: Browse Android internal storage, upload local files, and download remote items.
- **💻 ADB Shell & Terminal**: Interactive PTY terminal emulator launcher and saved custom command runner.
- **🤖 AVD Emulator Control**: List and launch Android Virtual Devices with a single click.
- **⌨️ IPC / CLI Interface**: Full command-line and Hyprland keybind control via `caelestia shell androlaunch <command>`.

---

## 🛠️ Prerequisites

- **ADB** (`android-tools` package on Fedora/Arch/Debian)
- **Scrcpy** (`scrcpy` package)
- **Caelestia Shell** installed at `~/.config/quickshell/caelestia`

---

## 🚀 Installation

Run the installation script from the `linux` directory:

```bash
chmod +x install.sh
./install.sh
```

---

## ⌨️ CLI / IPC Usage

Control your devices via terminal or bind them in your `hyprland.conf`:

```bash
# Check service availability and list connected devices
caelestia shell androlaunch isAvailable
caelestia shell androlaunch listDevices
caelestia shell androlaunch getActiveDevice

# Screen & Camera Mirroring
caelestia shell androlaunch mirror
caelestia shell androlaunch camera

# Quick Settings Toggles
caelestia shell androlaunch toggle wifi
caelestia shell androlaunch toggle darkmode
caelestia shell androlaunch toggle data

# Launch App or Open Shell
caelestia shell androlaunch launchApp com.spotify.music
caelestia shell androlaunch openTerminal

# Power Management
caelestia shell androlaunch reboot normal
caelestia shell androlaunch reboot recovery
```
