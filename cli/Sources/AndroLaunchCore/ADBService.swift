import Foundation

#if canImport(AppKit)
    import AppKit
#endif

// MARK: - ADB Service

public final class ADBService {
    public private(set) var currentADBPath: String?
    public var adbPath: String? { currentADBPath }

    public var errorHandler: ((String) -> Void)?

    private var systemADBPaths: [String] {
        [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(NSHomeDirectory())/Documents/android/platform-tools/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Library/Android/sdk/platform-tools/adb",
        ]
    }

    private var scrcpyPaths: [String] {
        [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(NSHomeDirectory())/.local/bin/scrcpy",
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy",
        ]
    }

    public init() {}

    // MARK: - ADB Path Discovery

    @discardableResult
    public func findADB() -> Bool {
        for path in systemADBPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                currentADBPath = path
                return true
            }
        }
        errorHandler?(
            "ADB not found. Install Android Platform Tools (`brew install android-platform-tools`)."
        )
        currentADBPath = nil
        return false
    }

    public func startADBDaemon() throws {
        guard currentADBPath != nil else {
            throw ADBError.adbNotFound
        }
        let (success, _, errorOutput) = executeADBCommandSync(arguments: ["start-server"])
        if !success {
            throw ADBError.commandFailed(errorOutput ?? "Failed to start ADB daemon")
        }
        // Small delay to let daemon stabilize
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Device Listing

    public func listDevices() throws -> [AndroidDevice] {
        guard currentADBPath != nil else {
            throw ADBError.adbNotFound
        }
        let (success, output, errorOutput) = executeADBCommandSync(arguments: ["devices", "-l"])
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Device listing failed")
        }
        return parseDevices(from: output)
    }

    // MARK: - Fetch Apps

    public func fetchApps(for deviceID: String) throws -> [AndroidApp] {
        let (success, output, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "pm", "list", "packages", "-f", "-3",
        ])
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to fetch apps")
        }
        return parseApps(from: output)
    }

    // MARK: - Device Info

    public func fetchAndroidVersion(deviceID: String) -> String? {
        let (_, output, _) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "getprop", "ro.build.version.release",
        ])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func fetchAPILevel(deviceID: String) -> String? {
        let (_, output, _) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "getprop", "ro.build.version.sdk",
        ])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func fetchBatteryLevel(deviceID: String) -> Int? {
        let (_, output, _) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "dumpsys", "battery",
        ])
        guard let output = output else { return nil }
        for line in output.components(separatedBy: .newlines) {
            if line.contains("level:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return Int(parts[1].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    public func fetchIsCharging(deviceID: String) -> Bool? {
        let (_, output, _) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "dumpsys", "battery",
        ])
        guard let output = output else { return nil }
        for line in output.components(separatedBy: .newlines) {
            if line.contains("AC powered:") || line.contains("USB powered:")
                || line.contains("Wireless powered:")
            {
                if line.contains("true") { return true }
            }
        }
        return false
    }

    // MARK: - Device Model

    public func fetchDeviceModel(deviceID: String) -> String? {
        let (_, output, _) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "getprop", "ro.product.model",
        ])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    // MARK: - Quick Actions

    public func reboot(deviceID: String, mode: RebootMode) throws {
        var args = ["-s", deviceID, "reboot"]
        if !mode.rawValue.isEmpty {
            args.append(mode.rawValue)
        }
        let (success, _, errorOutput) = executeADBCommandSync(arguments: args)
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to reboot device")
        }
    }

    public func toggleWiFi(deviceID: String, enable: Bool) throws {
        let state = enable ? "enable" : "disable"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "svc", "wifi", state,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Wi-Fi")
        }
    }

    public func toggleBluetooth(deviceID: String, enable: Bool) throws {
        let state = enable ? "enable" : "disable"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "svc", "bluetooth", state,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Bluetooth")
        }
    }

    public func toggleDarkMode(deviceID: String, enable: Bool) throws {
        let mode = enable ? "yes" : "no"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "cmd", "uimode", "night", mode,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Dark Mode")
        }
    }

    public func toggleAirplaneMode(deviceID: String, enable: Bool) throws {
        let value = enable ? "1" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "settings", "put", "global", "airplane_mode_on", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Airplane Mode")
        }
        // Broadcast for immediate effect
        _ = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "am", "broadcast", "-a", "android.intent.action.AIRPLANE_MODE",
        ])
    }

    public func toggleMobileData(deviceID: String, enable: Bool) throws {
        let value = enable ? "1" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "settings", "put", "global", "mobile_data", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Mobile Data")
        }
    }

    public func toggleLocation(deviceID: String, enable: Bool) throws {
        let value = enable ? "3" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "settings", "put", "secure", "location_mode", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Location")
        }
    }

    public func toggleDoNotDisturb(deviceID: String, enable: Bool) throws {
        let value = enable ? "1" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "cmd", "settings", "put", "global", "zen_mode", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Do Not Disturb")
        }
    }

    public func toggleAutoRotate(deviceID: String, enable: Bool) throws {
        let value = enable ? "1" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "settings", "put", "system", "accelerometer_rotation", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Auto-Rotate")
        }
    }

    public func setRingerMode(deviceID: String, mode: RingerMode) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "cmd", "media_session", "set_volume_mode", mode.rawValue,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to set Ringer Mode")
        }
    }

    public func toggleAdaptiveBrightness(deviceID: String, enable: Bool) throws {
        let value = enable ? "1" : "0"
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "settings", "put", "system", "screen_brightness_mode", value,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to toggle Adaptive Brightness")
        }
    }

    public func fetchQuickActionsState(deviceID: String) -> QuickActionsState {
        let cmd = """
            echo "WIFI:$(settings get global wifi_on)";
            echo "BT:$(settings get global bluetooth_on)";
            echo "DARK:$(cmd uimode night)";
            echo "AIR:$(settings get global airplane_mode_on)";
            echo "DATA:$(settings get global mobile_data)";
            echo "LOC:$(settings get secure location_mode)";
            echo "DND:$(cmd settings get global zen_mode)";
            echo "ROT:$(settings get system accelerometer_rotation)";
            echo "BRI:$(settings get system screen_brightness_mode)";
            echo "RINGER:$(cmd media_session volume_mode_for_stream 2)"
            """

        let (success, output, _) = executeADBCommandSync(arguments: ["-s", deviceID, "shell", cmd])
        var state = QuickActionsState()
        guard success, let output = output else { return state }

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("WIFI:") {
                state.isWifiEnabled = line.contains("1")
            } else if line.hasPrefix("BT:") {
                state.isBluetoothEnabled = line.contains("1")
            } else if line.hasPrefix("DARK:") {
                state.isDarkModeEnabled = line.contains("yes")
            } else if line.hasPrefix("AIR:") {
                state.isAirplaneModeEnabled = line.contains("1")
            } else if line.hasPrefix("DATA:") {
                state.isMobileDataEnabled = line.contains("1")
            } else if line.hasPrefix("LOC:") {
                if let val = Int(
                    line.replacingOccurrences(of: "LOC:", with: "").trimmingCharacters(
                        in: .whitespaces)), val > 0
                {
                    state.isLocationEnabled = true
                }
            } else if line.hasPrefix("DND:") {
                if let val = Int(
                    line.replacingOccurrences(of: "DND:zen_mode =", with: "").trimmingCharacters(
                        in: .whitespaces)), val > 0
                {
                    state.isDoNotDisturbEnabled = true
                } else if line.contains("1") || line.contains("2") || line.contains("3") {
                    state.isDoNotDisturbEnabled = true
                }
            } else if line.hasPrefix("ROT:") {
                state.isAutoRotateEnabled = line.contains("1")
            } else if line.hasPrefix("BRI:") {
                state.isAdaptiveBrightnessEnabled = line.contains("1")
            }
        }
        return state
    }

    // MARK: - App Management

    public func launchApp(packageID: String, deviceID: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "monkey", "-p", packageID, "-c",
            "android.intent.category.LAUNCHER", "1",
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to launch app")
        }
    }

    public func uninstallApp(deviceID: String, packageID: String) throws {
        let (success, output, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "uninstall", packageID,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? output ?? "Failed to uninstall app")
        }
    }

    public func clearAppData(deviceID: String, packageID: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "pm", "clear", packageID,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to clear app data")
        }
    }

    public func installAPK(deviceID: String, apkPath: String) throws {
        let (success, output, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "install", apkPath,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? output ?? "Failed to install APK")
        }
    }

    // MARK: - File Management

    public func listFiles(for deviceID: String, at path: String) throws -> [AndroidFile] {
        let (success, output, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "ls", "-la", path,
        ])
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to list files")
        }
        return parseFiles(output, at: path)
    }

    public func pushFile(deviceID: String, localPath: String, remotePath: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "push", localPath, remotePath,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to push file")
        }
    }

    public func pullFile(deviceID: String, remotePath: String, localPath: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "pull", remotePath, localPath,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to pull file")
        }
    }

    public func deleteFile(deviceID: String, path: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "rm", "-rf", path,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to delete file")
        }
    }

    public func createDirectory(deviceID: String, path: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", "mkdir", "-p", path,
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to create directory")
        }
    }

    // MARK: - Disconnect

    public func disconnectDevice(deviceID: String) throws {
        let (success, _, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "disconnect",
        ])
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to disconnect device")
        }
    }

    // MARK: - Shell Command

    public func executeShell(deviceID: String, command: String) throws -> String {
        let (success, output, errorOutput) = executeADBCommandSync(arguments: [
            "-s", deviceID, "shell", command,
        ])
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Shell command failed")
        }
        return output
    }

    // MARK: - Find Scrcpy

    public func findScrcpyPath() -> String? {
        for path in scrcpyPaths {
            if FileManager.default.fileExists(atPath: path)
                && FileManager.default.isExecutableFile(atPath: path)
            {
                return path
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    private func executeADBCommandSync(arguments: [String]) -> (
        success: Bool, output: String?, errorOutput: String?
    ) {
        guard let adbPath = currentADBPath else {
            return (false, nil, "ADB executable path not set.")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        task.standardOutput = standardOutputPipe
        task.standardError = standardErrorPipe

        do {
            var env = ProcessInfo.processInfo.environment
            // Resolve JAVA_HOME if available
            let javaHome = resolveJavaHome()
            if let javaHome = javaHome {
                env["JAVA_HOME"] = javaHome
                env["PATH"] = "\(javaHome)/bin:\(env["PATH"] ?? "")"
            }
            task.environment = env

            try task.run()
            task.waitUntilExit()

            let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)

            let success = task.terminationStatus == 0
            return (success, output, errorOutput)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    private func resolveJavaHome() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines), !output.isEmpty
            {
                return output
            }
        } catch {
            // Ignore
        }
        return nil
    }

    // MARK: - Parsing

    private func parseDevices(from output: String) -> [AndroidDevice] {
        let pattern = #"^(\S+)\s+(device|unauthorized|offline|no permissions)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        else {
            return []
        }
        var devices = [AndroidDevice]()
        var seenDeviceNames = Set<String>()

        output.enumerateLines { line, _ in
            guard
                !line.lowercased().contains("list of devices attached")
                    && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range) {
                let serial = String(line[Range(match.range(at: 1), in: line)!])
                let status = String(line[Range(match.range(at: 2), in: line)!])
                let info =
                    match.numberOfRanges > 3
                    ? String(line[Range(match.range(at: 3), in: line)!]) : ""

                let isConnected = status == "device"
                var model: String? = nil
                let infoParts = info.components(separatedBy: .whitespaces)
                for part in infoParts {
                    if part.hasPrefix("model:") {
                        model = String(part.dropFirst(6))
                    }
                }

                let deviceName: String
                if let model = model {
                    deviceName = model
                } else if serial.contains(":") {
                    // Wireless device - use serial
                    deviceName = serial
                } else {
                    deviceName = serial
                }

                // For duplicate device names, use serial as suffix
                var displayName = deviceName
                if seenDeviceNames.contains(displayName) {
                    displayName = "\(deviceName) (\(serial))"
                }
                seenDeviceNames.insert(displayName)

                let device = AndroidDevice(
                    id: serial,
                    name: displayName,
                    model: model,
                    isConnected: isConnected,
                    serialNumber: serial
                )
                devices.append(device)
            }
        }
        return devices
    }

    private func parseApps(from output: String) -> [AndroidApp] {
        var apps = [AndroidApp]()
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            guard line.hasPrefix("package:") else { continue }
            // Format: package:/path/to/apk=com.example.app
            let clean = String(line.dropFirst("package:".count))
            let parts = clean.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let apkPath = parts[0]
            let packageName = parts[1]
            let appName = (apkPath as NSString).lastPathComponent.replacingOccurrences(
                of: ".apk", with: "")
            let displayName = appName.replacingOccurrences(of: "_", with: " ").capitalized

            let app = AndroidApp(
                id: packageName,
                name: displayName,
                iconName: "android",
                packageName: packageName
            )
            apps.append(app)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseFiles(_ output: String, at parentPath: String) -> [AndroidFile] {
        var files = [AndroidFile]()
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            guard !line.isEmpty, !line.hasPrefix("total ") else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }
            let permissions = parts[0]
            let sizeStr = parts[4]
            let dateStr = parts[5]
            let name = parts.dropFirst(6).joined(separator: " ")
            guard name != "." && name != ".." else { continue }

            let isDirectory = permissions.hasPrefix("d")
            let size = Int64(sizeStr) ?? 0
            let fullPath =
                parentPath.hasSuffix("/") ? "\(parentPath)\(name)" : "\(parentPath)/\(name)"

            let file = AndroidFile(
                name: name,
                path: fullPath,
                size: size,
                modificationDate: dateStr,
                isDirectory: isDirectory,
                permissions: permissions
            )
            files.append(file)
        }
        return files
    }
}

// MARK: - String Extension

extension String {
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
}
