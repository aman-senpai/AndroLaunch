import AndroLaunchCore
import ArgumentParser
import Foundation

// MARK: - Main Entry Point

@main
struct AndroLaunchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "androlaunch",
        abstract: "Android Device Management Hub for macOS — CLI",
        discussion: """
            AndroLaunch CLI gives you full control over your Android devices from the terminal.
            Manage devices, apps, quick settings, screen mirroring, file transfers, and emulators.
            """,
        version: "1.0.0",
        subcommands: [
            Devices.self,
            DeviceInfo.self,
            Apps.self,
            Launch.self,
            Uninstall.self,
            ClearData.self,
            Install.self,
            Mirror.self,
            Camera.self,
            Reboot.self,
            Wifi.self,
            Bluetooth.self,
            DarkMode.self,
            AirplaneMode.self,
            MobileData.self,
            Location.self,
            DoNotDisturb.self,
            AutoRotate.self,
            AdaptiveBrightness.self,
            Ringer.self,
            QuickState.self,
            Shell.self,
            Files.self,
            Push.self,
            Pull.self,
            DeleteFile.self,
            Mkdir.self,
            Pair.self,
            Disconnect.self,
            EmulatorImages.self,
            EmulatorAVDs.self,
            EmulatorProfiles.self,
            EmulatorCreate.self,
            EmulatorDelete.self,
            EmulatorRename.self,
            EmulatorStart.self,
            EmulatorStop.self,
            ScrcpyApp.self,
        ]
    )
}

// MARK: - Shared Service Helpers

private func makeADBService() -> ADBService {
    let service = ADBService()
    guard service.findADB() else {
        fputs("Error: ADB not found. Install with: brew install android-platform-tools\n", stderr)
        Foundation.exit(1)
    }
    do {
        try service.startADBDaemon()
    } catch {
        fputs("Warning: Could not start ADB daemon: \(error.localizedDescription)\n", stderr)
    }
    return service
}

private func resolveDeviceID(_ adb: ADBService, _ specified: String?) -> String {
    if let id = specified { return id }
    guard let devices = try? adb.listDevices(), let first = devices.first(where: { $0.isConnected })
    else {
        fputs("Error: No connected device found. Specify a device ID.\n", stderr)
        Foundation.exit(1)
    }
    return first.id
}

private func requireToolsPath(_ path: String?) -> String {
    if let path = path { return path }
    let emulator = EmulatorService()
    if let resolved = emulator.resolveCommandLineToolsPath() {
        return resolved
    }
    fputs("Error: Android SDK not found. Specify --tools-path or set ANDROID_HOME.\n", stderr)
    Foundation.exit(1)
}

// MARK: - Device Commands

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List connected Android devices"
    )

    func run() throws {
        let adb = makeADBService()
        let devices = try adb.listDevices()
        if devices.isEmpty {
            print("No devices connected.")
        } else {
            print("Connected devices:")
            for device in devices {
                let status = device.isConnected ? "🟢 connected" : "🔴 \(device.id)"
                print("  \(device.name)  [\(status)]")
                if let model = device.model { print("    Model: \(model)") }
                if let version = device.androidVersion { print("    Android: \(version)") }
                if let battery = device.batteryLevel {
                    let charging = device.isCharging == true ? " ⚡️" : ""
                    print("    Battery: \(battery)%\(charging)")
                }
            }
        }
    }
}

struct DeviceInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show detailed info about a device"
    )

    @Argument(help: "Device serial ID (optional, uses first connected device)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)

        let version = adb.fetchAndroidVersion(deviceID: id) ?? "unknown"
        let apiLevel = adb.fetchAPILevel(deviceID: id) ?? "unknown"
        let model = adb.fetchDeviceModel(deviceID: id) ?? "unknown"
        let battery = adb.fetchBatteryLevel(deviceID: id)
        let charging = adb.fetchIsCharging(deviceID: id)

        print("Device: \(id)")
        print("  Model: \(model)")
        print("  Android Version: \(version) (API \(apiLevel))")
        if let battery = battery {
            let chargingStr = charging == true ? " (charging)" : ""
            print("  Battery: \(battery)%\(chargingStr)")
        }
    }
}

// MARK: - App Commands

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List installed apps on a device"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    @Flag(name: .shortAndLong, help: "Show package names only")
    var packagesOnly = false

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let apps = try adb.fetchApps(for: id)

        if apps.isEmpty {
            print("No apps found.")
        } else {
            print("Installed apps (\(apps.count)):")
            for app in apps {
                if packagesOnly {
                    print("  \(app.packageName)")
                } else {
                    print("  \(app.name)  [\(app.packageName)]")
                }
            }
        }
    }
}

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch an app on a device"
    )

    @Argument(help: "Package ID of the app to launch")
    var packageID: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.launchApp(packageID: packageID, deviceID: id)
        print("Launched \(packageID) on \(id)")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uninstall an app from a device"
    )

    @Argument(help: "Package ID of the app to uninstall")
    var packageID: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.uninstallApp(deviceID: id, packageID: packageID)
        print("Uninstalled \(packageID) from \(id)")
    }
}

struct ClearData: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clear app data on a device"
    )

    @Argument(help: "Package ID of the app")
    var packageID: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.clearAppData(deviceID: id, packageID: packageID)
        print("Cleared data for \(packageID) on \(id)")
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install an APK on a device"
    )

    @Argument(help: "Path to the APK file")
    var apkPath: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.installAPK(deviceID: id, apkPath: apkPath)
        print("Installed \(apkPath) on \(id)")
    }
}

// MARK: - Screen Mirroring

struct Mirror: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mirror device screen via Scrcpy"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    @Flag(name: .long, help: "Disable audio forwarding")
    var noAudio = false

    @Flag(name: .long, help: "Disable clipboard sync")
    var noClipboard = false

    @Flag(name: .long, help: "Borderless window")
    var borderless = false

    @Option(name: .long, help: "Max resolution (e.g. 1024)")
    var maxSize: Int?

    @Option(name: .long, help: "Max FPS")
    var maxFPS: Int?

    @Option(name: .long, help: "Video bitrate in Mbps")
    var bitRate: Int?

    @Option(name: .long, help: "Lock orientation (0, 90, 180, 270)")
    var orientation: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let scrcpy = ScrcpyService()

        print("Mirroring \(id)... (Press Ctrl+C to stop)")
        _ = try scrcpy.mirrorDevice(
            deviceID: id,
            adbPath: adb.adbPath,
            audioEnabled: !noAudio,
            clipboardEnabled: !noClipboard,
            maxSize: maxSize,
            maxFPS: maxFPS,
            bitRate: bitRate,
            orientation: orientation,
            borderless: borderless
        )

        // Keep the CLI running while scrcpy is active
        RunLoop.main.run()
    }
}

struct Camera: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mirror device camera via Scrcpy"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    @Option(name: .long, help: "Camera facing: front or back")
    var facing: String?

    @Option(name: .long, help: "Max FPS")
    var fps: Int?

    @Option(name: .long, help: "Max resolution")
    var size: Int?

    @Option(name: .long, help: "Aspect ratio (e.g. 4:3)")
    var aspectRatio: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let scrcpy = ScrcpyService()

        print("Mirroring camera for \(id)... (Press Ctrl+C to stop)")
        _ = try scrcpy.mirrorCamera(
            deviceID: id,
            adbPath: adb.adbPath,
            facing: facing,
            fps: fps,
            size: size,
            aspectRatio: aspectRatio
        )

        RunLoop.main.run()
    }
}

struct ScrcpyApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scrcpy-app",
        abstract: "Launch an app in a scrcpy window with its own display"
    )

    @Argument(help: "Package ID of the app")
    var packageID: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    @Flag(name: .long, help: "Disable audio")
    var noAudio = false

    @Option(name: .long, help: "Display resolution (default: 1024)")
    var resolution: Int = 1024

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let scrcpy = ScrcpyService()

        print("Launching \(packageID) in scrcpy window... (Press Ctrl+C to stop)")
        _ = try scrcpy.launchApp(
            packageID: packageID,
            deviceID: id,
            adbPath: adb.adbPath,
            audioEnabled: !noAudio,
            resolution: resolution
        )

        RunLoop.main.run()
    }
}

// MARK: - System Controls

struct Reboot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reboot a device"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    @Flag(name: .long, help: "Reboot to bootloader")
    var bootloader = false

    @Flag(name: .long, help: "Reboot to recovery")
    var recovery = false

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let mode: RebootMode = bootloader ? .bootloader : (recovery ? .recovery : .normal)
        try adb.reboot(deviceID: id, mode: mode)
        print("Rebooting \(id)\(mode.rawValue.isEmpty ? "" : " to \(mode.rawValue)")...")
    }
}

struct Wifi: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Wi-Fi on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleWiFi(deviceID: id, enable: enable)
        print("Wi-Fi \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct Bluetooth: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Bluetooth on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleBluetooth(deviceID: id, enable: enable)
        print("Bluetooth \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct DarkMode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Dark Mode on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleDarkMode(deviceID: id, enable: enable)
        print("Dark Mode \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct AirplaneMode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Airplane Mode on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleAirplaneMode(deviceID: id, enable: enable)
        print("Airplane Mode \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct MobileData: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Mobile Data on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleMobileData(deviceID: id, enable: enable)
        print("Mobile Data \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct Location: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Location services on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleLocation(deviceID: id, enable: enable)
        print("Location \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct DoNotDisturb: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Do Not Disturb on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleDoNotDisturb(deviceID: id, enable: enable)
        print("Do Not Disturb \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct AutoRotate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Auto-Rotate on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleAutoRotate(deviceID: id, enable: enable)
        print("Auto-Rotate \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct AdaptiveBrightness: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Toggle Adaptive Brightness on a device"
    )

    @Argument(help: "on or off")
    var state: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let enable = try parseOnOff(state)
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.toggleAdaptiveBrightness(deviceID: id, enable: enable)
        print("Adaptive Brightness \(enable ? "enabled" : "disabled") on \(id)")
    }
}

struct Ringer: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set ringer mode on a device"
    )

    @Argument(help: "Mode: normal, vibrate, or silent")
    var mode: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let ringerMode: RingerMode
        switch mode.lowercased() {
        case "normal": ringerMode = .normal
        case "vibrate": ringerMode = .vibrate
        case "silent": ringerMode = .silent
        default: throw ValidationError("Invalid ringer mode. Use: normal, vibrate, or silent")
        }
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.setRingerMode(deviceID: id, mode: ringerMode)
        print("Ringer mode set to \(mode) on \(id)")
    }
}

struct QuickState: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show quick actions state for a device"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let state = adb.fetchQuickActionsState(deviceID: id)

        print("Quick Settings State for \(id):")
        print("  Wi-Fi: \(state.isWifiEnabled ? "✅" : "❌")")
        print("  Bluetooth: \(state.isBluetoothEnabled ? "✅" : "❌")")
        print("  Dark Mode: \(state.isDarkModeEnabled ? "✅" : "❌")")
        print("  Airplane Mode: \(state.isAirplaneModeEnabled ? "✅" : "❌")")
        print("  Mobile Data: \(state.isMobileDataEnabled ? "✅" : "❌")")
        print("  Location: \(state.isLocationEnabled ? "✅" : "❌")")
        print("  Do Not Disturb: \(state.isDoNotDisturbEnabled ? "✅" : "❌")")
        print("  Auto-Rotate: \(state.isAutoRotateEnabled ? "✅" : "❌")")
        print("  Adaptive Brightness: \(state.isAdaptiveBrightnessEnabled ? "✅" : "❌")")
        print("  Ringer Mode: \(state.ringerMode.rawValue)")
    }
}

// MARK: - Shell

struct Shell: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a shell command on a device"
    )

    @Argument(help: "The shell command to execute")
    var command: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let output = try adb.executeShell(deviceID: id, command: command)
        if !output.isEmpty {
            print(output)
        }
    }
}

// MARK: - File Management

struct Files: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List files on a device"
    )

    @Argument(help: "Remote path on device (default: /sdcard)")
    var path: String = "/sdcard"

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        let files = try adb.listFiles(for: id, at: path)

        if files.isEmpty {
            print("No files found at \(path)")
        } else {
            print("Contents of \(path):")
            for file in files {
                let type = file.isDirectory ? "📁" : "📄"
                let size = file.formattedSize
                print("  \(type) \(file.name)  \(size)  \(file.permissions)")
            }
        }
    }
}

struct Push: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Push a file to a device"
    )

    @Argument(help: "Local file path")
    var localPath: String

    @Argument(help: "Remote path on device")
    var remotePath: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.pushFile(deviceID: id, localPath: localPath, remotePath: remotePath)
        print("Pushed \(localPath) -> \(remotePath) on \(id)")
    }
}

struct Pull: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pull a file from a device"
    )

    @Argument(help: "Remote path on device")
    var remotePath: String

    @Argument(help: "Local file path")
    var localPath: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.pullFile(deviceID: id, remotePath: remotePath, localPath: localPath)
        print("Pulled \(remotePath) -> \(localPath) from \(id)")
    }
}

struct DeleteFile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Delete a file or directory on a device"
    )

    @Argument(help: "Remote path on device")
    var path: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.deleteFile(deviceID: id, path: path)
        print("Deleted \(path) on \(id)")
    }
}

struct Mkdir: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a directory on a device"
    )

    @Argument(help: "Remote path on device")
    var path: String

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.createDirectory(deviceID: id, path: path)
        print("Created directory \(path) on \(id)")
    }
}

// MARK: - Pairing & Disconnect

struct Pair: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Wirelessly pair a device using ADB pairing"
    )

    @Option(name: .long, help: "Pairing IP address")
    var ip: String?

    @Option(name: .long, help: "Pairing port (default: 41111)")
    var port: Int = 41111

    @Option(name: .long, help: "Pairing code (6 digits)")
    var code: String?

    func run() throws {
        let adb = makeADBService()

        if let ip = ip, let code = code {
            // Manual pairing
            let command = "\(adb.adbPath!) pair \(ip):\(port) \(code)"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", command]
            try task.run()
            task.waitUntilExit()
            print("Pairing request sent to \(ip):\(port)")
        } else {
            print("Usage: androlaunch pair --ip <ip> --code <6-digit-code>")
            print("Note: Use the AndroLaunch GUI app for QR code-based pairing.")
        }
    }
}

struct Disconnect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Disconnect a device"
    )

    @Argument(help: "Device serial ID (optional)")
    var deviceID: String?

    func run() throws {
        let adb = makeADBService()
        let id = resolveDeviceID(adb, deviceID)
        try adb.disconnectDevice(deviceID: id)
        print("Disconnected \(id)")
    }
}

// MARK: - Emulator Commands

struct EmulatorImages: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available system images"
    )

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        let images = try emulator.listAvailableImages(toolsPath: path)
        if images.isEmpty {
            print("No system images found.")
        } else {
            print("Available system images:")
            for image in images {
                let status = image.isDownloaded ? "📦 downloaded" : "☁️  available"
                print("  \(image.id)")
                print("    \(image.description) [\(status)]")
            }
        }
    }
}

struct EmulatorAVDs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List Android Virtual Devices (AVDs)"
    )

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        let avds = try emulator.listAVDs(toolsPath: path)
        if avds.isEmpty {
            print("No AVDs found.")
        } else {
            print("AVDs:")
            for avd in avds {
                let status = avd.isRunning ? "🟢 running" : "⚫ stopped"
                print("  \(avd.name) [\(status)]")
                if let device = avd.device { print("    Device: \(device)") }
                if let target = avd.target { print("    Target: \(target)") }
            }
        }
    }
}

struct EmulatorProfiles: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available hardware profiles"
    )

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        let profiles = try emulator.listHardwareProfiles(toolsPath: path)
        if profiles.isEmpty {
            print("No hardware profiles found.")
        } else {
            print("Hardware profiles:")
            for profile in profiles {
                print("  \(profile.id) - \(profile.name)")
            }
        }
    }
}

struct EmulatorCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new AVD"
    )

    @Argument(help: "Name for the new AVD")
    var name: String

    @Argument(help: "System image path (e.g. system-images;android-33;google_apis;arm64-v8a)")
    var imagePath: String

    @Option(name: .long, help: "Device profile ID")
    var device: String?

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        try emulator.createAVD(
            toolsPath: path, name: name, imagePath: imagePath, device: device, options: .default)
        print("Created AVD: \(name)")
    }
}

struct EmulatorDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete an AVD"
    )

    @Argument(help: "Name of the AVD to delete")
    var name: String

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        try emulator.deleteAVD(toolsPath: path, name: name)
        print("Deleted AVD: \(name)")
    }
}

struct EmulatorRename: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Rename an AVD"
    )

    @Argument(help: "Current AVD name")
    var oldName: String

    @Argument(help: "New AVD name")
    var newName: String

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        try emulator.renameAVD(toolsPath: path, oldName: oldName, newName: newName)
        print("Renamed AVD \(oldName) -> \(newName)")
    }
}

struct EmulatorStart: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start an emulator"
    )

    @Argument(help: "AVD name")
    var avdName: String

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        _ = try emulator.startEmulator(toolsPath: path, avdName: avdName)
        print("Starting emulator: \(avdName)... (Press Ctrl+C to stop)")
        RunLoop.main.run()
    }
}

struct EmulatorStop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop a running emulator"
    )

    @Argument(help: "AVD name")
    var avdName: String

    @Option(name: .long, help: "Path to Android SDK")
    var toolsPath: String?

    func run() throws {
        let path = requireToolsPath(toolsPath)
        let emulator = EmulatorService()
        try emulator.stopEmulator(toolsPath: path, avdName: avdName)
        print("Stopped emulator: \(avdName)")
    }
}

// MARK: - Helpers

private func parseOnOff(_ state: String) throws -> Bool {
    switch state.lowercased() {
    case "on", "true", "1", "enable", "enabled":
        return true
    case "off", "false", "0", "disable", "disabled":
        return false
    default:
        throw ValidationError("Invalid state: \(state). Use 'on' or 'off'.")
    }
}
