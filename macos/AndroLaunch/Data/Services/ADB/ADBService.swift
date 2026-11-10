//
//  ADBService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import Foundation

#if canImport(AppKit)
    import AppKit
#endif

// MARK: - ADB Service Implementation

final class ADBService: ADBServiceProtocol {
    // MARK: - Protocol Requirements (Publishers)
    let devices = PassthroughSubject<[AndroidDevice], Never>()
    // Updated apps publisher to emit deviceID along with apps
    let apps = PassthroughSubject<(String, [AndroidApp]), Never>()
    let error = PassthroughSubject<String?, Never>()

    // MARK: - Internal State
    // MARK: - Internal State
    private var currentADBPath: String?
    var adbPath: String? { currentADBPath }
    private var cancellables = Set<AnyCancellable>()

    // State for managing scrcpy processes and error reporting
    private var scrcpyErrorPipeHandlers: [String: Any] = [:]
    private var scrcpyErrorOutputs: [String: String] = [:]
    private var runningScrcpyProcesses: [String: Process] = [:]
    private var clipboardSyncProcesses: [String: Process] = [:]  // Dedicated clipboard sync processes

    // MARK: - Clipboard Sync State
    private var clipboardSyncDevices: Set<String> = []  // Mac -> Android enabled devices
    private var clipboardReusingMirrorDevices: Set<String> = []  // Android -> Mac via an existing mirror
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = -1
    private var lastClipboardText: String?
    private var clipboardCompanionInstalled: [String: Bool] = [:]
    private var clipboardCompanionCheckedAt: [String: Date] = [:]
    private var clipboardCompanionChecksInFlight: Set<String> = []
    /// Emits health events so `ClipboardBridge` can surface bridge state in the UI.
    let clipboardEvents = PassthroughSubject<ClipboardSyncEvent, Never>()

    // Store last published device list so disconnect can find all connection paths
    private var lastPublishedDevices: [AndroidDevice] = []

    // MARK: - Executable Path Discovery

    // Common system paths for ADB
    private var systemADBPaths: [String] {
        let bundled = Bundle.main.url(forResource: "adb", withExtension: nil)?.path
        var paths: [String] = []
        if let bundled { paths.append(bundled) }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(NSHomeDirectory())/Documents/android/platform-tools/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Library/Android/sdk/platform-tools/adb",
        ])
        return paths
    }

    // Common system paths for SCRCPY
    private var scrcpyPaths: [String] {
        [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(NSHomeDirectory())/.local/bin/scrcpy",
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy",
        ]
    }

    // MARK: - Initialization
    init() {
    }

    // MARK: - Private Helper: Execute Shell Command (For ADB commands like list, start-server, fetch packages)
    /// Shared for feature extensions (clipboard, notifications, transfers).
    func executeADBCommand(
        arguments: [String], path: String? = nil,
        completion: @escaping (Bool, String?, String?) -> Void
    ) {
        guard let adbPath = path ?? currentADBPath else {
            completion(false, nil, "ADB executable path not set.")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        task.standardOutput = standardOutputPipe
        task.standardError = standardErrorPipe

        // Use a background queue for the potentially long-running process
        DispatchQueue.global(qos: .background).async {
            do {
                var env = ProcessInfo.processInfo.environment
                if let javaHome = EnvironmentManager.shared.javaHome {
                    env["JAVA_HOME"] = javaHome
                    env["PATH"] = "\(javaHome)/bin:\(env["PATH"] ?? "")"
                }
                task.environment = env

                try task.run()
                task.waitUntilExit()

                let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8)
                let errorOutput = String(data: errorData, encoding: .utf8)

                // Deliver the result back to the main thread
                DispatchQueue.main.async {
                    let success = task.terminationStatus == 0

                    completion(success, output, errorOutput)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, nil, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private Helper: Find SCRCPY Executable
    func findScrcpyPath() -> String? {
        for path in scrcpyPaths {
            if FileManager.default.fileExists(atPath: path)
                && FileManager.default.isExecutableFile(atPath: path)
            {
                return path
            }
        }
        return nil
    }

    // MARK: - ADB Path Discovery

    func detectADBPath() -> String? {
        for path in systemADBPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func findADB() {
        if let path = detectADBPath() {
            currentADBPath = path
            error.send(nil)
            startADBDaemon()
            return
        }
        let notFoundError = "ADB not found. Install Android Platform Tools."
        error.send(notFoundError)
        devices.send([])
        currentADBPath = nil
    }

    func startADBDaemon() {
        guard let adbPath = currentADBPath else {
            error.send("Cannot start daemon, ADB path not set.")
            return
        }
        // Use executeADBCommand for the standard ADB start-server command
        executeADBCommand(arguments: ["start-server"], path: adbPath) {
            [weak self] success, _, errorOutput in
            guard let self else { return }
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.listDevices()
                }
            } else {
                self.error.send(errorOutput ?? "ADB daemon failed to start")
                self.devices.send([])
            }
        }
    }

    // MARK: - Device Listing
    func listDevices() {
        guard currentADBPath != nil else {
            error.send("ADB path not set, cannot list devices.")
            devices.send([])
            return
        }
        // Use executeADBCommand for the standard ADB devices command
        executeADBCommand(arguments: ["devices", "-l"]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Move parsing to background to avoid blocking main thread with sync ADB calls
                DispatchQueue.global(qos: .userInitiated).async {
                    let devices = self.parseDevices(from: output ?? "")

                    DispatchQueue.main.async {
                        self.lastPublishedDevices = devices
                        self.devices.send(devices)
                    }
                }
            } else {
                self.error.send(errorOutput ?? "Device listing failed")
                self.devices.send([])
            }
        }
    }

    // MARK: - Private Helper: Parse ADB Devices Output
    private func parseDevices(from output: String) -> [AndroidDevice] {
        let states = [
            "device", "unauthorized", "offline", "no permissions", "authorizing",
            "connecting", "recovery", "sideload", "bootloader", "host", "rescue",
        ]

        struct ParsedEntry {
            let deviceID: String
            let modelName: String
            let rawModel: String?
        }

        var allEntries = [ParsedEntry]()

        // --- Pass 1: Parse all lines (no ADB calls yet) ---
        output.enumerateLines { line, _ in
            guard
                !line.lowercased().contains("list of devices attached")
                    && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }

            guard let (deviceID, state, details) = Self.splitDeviceLine(line, states: states)
            else {
                print("[ADBService] Line did not match device pattern: \(line)")
                return
            }

            var cleanDeviceID = deviceID
            if cleanDeviceID.contains(".:") {
                cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
            }

            var modelName = "Android Device"
            var rawModel: String?

            if let details = details {
                let modelPattern = #"model:([^\s]+)"#
                if let modelMatch = try? NSRegularExpression(pattern: modelPattern)
                    .firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
                    let modelRng = Range(modelMatch.range(at: 1), in: details)
                {
                    rawModel = String(details[modelRng])
                    modelName = rawModel!.replacingOccurrences(of: "_", with: " ")
                }
            }

            if state == "device" {
                allEntries.append(
                    ParsedEntry(deviceID: cleanDeviceID, modelName: modelName, rawModel: rawModel))
            } else {
                print("Found device in state \(state): \(cleanDeviceID)")
            }
        }

        // --- Pass 2: Deduplicate by serial number, prefer IP-based connections ---
        // Sort: IP-based IDs first (shorter, more reliable), mDNS last
        let sortedEntries = allEntries.sorted { lhs, rhs in
            let lhsIsMDNS =
                lhs.deviceID.contains("_tcp") || lhs.deviceID.contains("_udp")
            let rhsIsMDNS =
                rhs.deviceID.contains("_tcp") || rhs.deviceID.contains("_udp")
            if lhsIsMDNS != rhsIsMDNS { return !lhsIsMDNS }
            return false
        }

        var seenSerials = Set<String>()
        var devices = [AndroidDevice]()

        // Only fetch properties for the winning entry per serial
        for entry in sortedEntries {
            let props = fetchDeviceProperties(deviceID: entry.deviceID)

            let dedupKey = props.serialNumber ?? entry.modelName
            if seenSerials.contains(dedupKey) {
                continue
            }
            seenSerials.insert(dedupKey)

            let newDevice = AndroidDevice(
                id: entry.deviceID,
                name: entry.modelName,
                model: entry.rawModel,
                isConnected: true,
                serialNumber: props.serialNumber,
                androidVersion: props.androidVersion,
                apiLevel: props.apiLevel,
                batteryLevel: props.batteryLevel,
                isCharging: props.isCharging
            )
            devices.append(newDevice)
        }

        // No need to disconnect redundant entries — both point to the same physical
        // device and disconnecting one can destabilize the other. Since all ADB
        // commands use `-s <deviceID>`, duplicates don't cause ambiguity errors.

        return devices
    }

    /// Split an `adb devices -l` line into (serial, state, details?).
    /// Serial may contain spaces for mDNS/bonjour-discovered devices.
    private static func splitDeviceLine(
        _ line: String,
        states: [String]
    ) -> (String, String, String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first occurrence of any state keyword as a whole word
        var bestMatch: (range: Range<String.Index>, state: String)?
        for state in states {
            let escaped = NSRegularExpression.escapedPattern(for: state)
            let pattern = "(?:^|\\s)(\(escaped))(?:$|\\s)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: nsRange),
                match.numberOfRanges >= 2,
                let stateRange = Range(match.range(at: 1), in: trimmed)
            {
                if bestMatch == nil || stateRange.lowerBound < bestMatch!.range.lowerBound {
                    bestMatch = (stateRange, state)
                }
            }
        }
        guard let match = bestMatch else { return nil }

        let deviceID = String(trimmed[trimmed.startIndex..<match.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detailsStart = trimmed.index(after: match.range.upperBound)
        let details: String?
        if detailsStart < trimmed.endIndex {
            details = String(trimmed[detailsStart...]).trimmingCharacters(
                in: .whitespacesAndNewlines)
        } else {
            details = nil
        }
        return (deviceID, match.state, details)
    }

    // MARK: - App Listing
    func fetchApps(for deviceID: String) {
        guard let scrcpyPath = findScrcpyPath() else {
            error.send("SCRCPY executable not found. Please install scrcpy.")
            return
        }

        // Sanitize deviceID
        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = ["--serial", cleanDeviceID, "--list-apps"]

        if let adbPath = currentADBPath {
            var env = ProcessInfo.processInfo.environment
            env["ADB"] = adbPath

            if let javaHome = EnvironmentManager.shared.javaHome {
                env["JAVA_HOME"] = javaHome
                env["PATH"] =
                    "\(javaHome)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
            } else {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
            }

            task.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let maxRetries = 3
            var lastOutput = ""
            var lastExitCode: Int32 = 0

            for attempt in 1...maxRetries {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: scrcpyPath)
                task.arguments = ["--serial", cleanDeviceID, "--list-apps"]

                if let adbPath = self.currentADBPath {
                    var env = ProcessInfo.processInfo.environment
                    env["ADB"] = adbPath
                    if let javaHome = EnvironmentManager.shared.javaHome {
                        env["JAVA_HOME"] = javaHome
                        env["PATH"] =
                            "\(javaHome)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
                    } else {
                        env["PATH"] =
                            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
                    }
                    task.environment = env
                }

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                task.standardOutput = outputPipe
                task.standardError = errorPipe

                do {
                    // Timeout watchdog
                    let timeoutWorkItem = DispatchWorkItem { task.terminate() }
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + 30, execute: timeoutWorkItem)

                    try task.run()
                    task.waitUntilExit()
                    timeoutWorkItem.cancel()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    let combinedOutput = output + "\n" + errorOutput
                    lastOutput = combinedOutput
                    lastExitCode = task.terminationStatus

                    if task.terminationStatus == 0 {
                        let apps = self.parseScrcpyApps(from: combinedOutput)
                        DispatchQueue.main.async {
                            self.apps.send((deviceID, apps))
                        }
                        if apps.isEmpty
                            && !combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        {
                            print(
                                "[ADBService] fetchApps: No apps found in output: \(combinedOutput)"
                            )
                        }
                        return
                    }

                    if task.terminationStatus == 15 {
                        print("[ADBService] fetchApps timed out (attempt \(attempt)/\(maxRetries))")
                    } else {
                        print(
                            "[ADBService] fetchApps failed (attempt \(attempt)/\(maxRetries), code \(task.terminationStatus)). Output:\n\(combinedOutput)"
                        )
                    }

                    if attempt < maxRetries {
                        Thread.sleep(forTimeInterval: 2.0)
                    }
                } catch {
                    print(
                        "[ADBService] fetchApps error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)"
                    )
                    if attempt < maxRetries {
                        Thread.sleep(forTimeInterval: 2.0)
                    }
                }
            }

            // All retries exhausted
            DispatchQueue.main.async {
                self.error.send(
                    "Failed to fetch apps for \(deviceID). Scrcpy exited with code \(lastExitCode) after \(maxRetries) attempts."
                )
                self.apps.send((deviceID, []))
            }
        }
    }

    private func parseScrcpyApps(from output: String) -> [AndroidApp] {
        var apps: [AndroidApp] = []
        let lines = output.components(separatedBy: .newlines)

        // Regex to match: * App Name package.name
        // Capture Group 1: App Name (lazy match until last space)
        // Capture Group 2: Package Name (non-whitespace)
        let pattern = #"^\s*[\*\-]\s+(.+?)\s+(\S+)$"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex?.firstMatch(in: trimmed, options: [], range: range),
                match.numberOfRanges == 3
            {

                if let nameRange = Range(match.range(at: 1), in: trimmed),
                    let pkgRange = Range(match.range(at: 2), in: trimmed)
                {

                    let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
                    let packageName = String(trimmed[pkgRange]).trimmingCharacters(in: .whitespaces)

                    let app = AndroidApp(
                        id: packageName,
                        name: name,
                        iconName: "android",
                        packageName: packageName
                    )
                    apps.append(app)
                }
            }
        }

        return apps.sorted { $0.name < $1.name }
    }

    private func executeADBCommandSync(arguments: [String]) throws -> String {
        guard let adbPath = currentADBPath else {
            throw NSError(
                domain: "ADBService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ADB path not set"])
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let outputPipe = Pipe()
        task.standardOutput = outputPipe

        try task.run()
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    /// Fetch serial, android version, API level, battery level, and charging status
    /// in a single ADB shell call to avoid spawning multiple processes.
    private struct DeviceProperties {
        var serialNumber: String?
        var androidVersion: String?
        var apiLevel: String?
        var batteryLevel: Int?
        var isCharging: Bool?
    }

    private func fetchDeviceProperties(deviceID: String) -> DeviceProperties {
        var props = DeviceProperties()
        do {
            let cmd =
                "getprop ro.serialno; getprop ro.build.version.release; getprop ro.build.version.sdk; dumpsys battery"
            let output = try executeADBCommandSync(arguments: [
                "-s", deviceID, "shell", cmd,
            ])
            let lines = output.components(separatedBy: .newlines)

            // Line 0: serial number
            if lines.indices.contains(0) {
                let s = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { props.serialNumber = s }
            }
            // Line 1: android version
            if lines.indices.contains(1) {
                let v = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { props.androidVersion = v }
            }
            // Line 2: API level
            if lines.indices.contains(2) {
                let a = lines[2].trimmingCharacters(in: .whitespacesAndNewlines)
                if !a.isEmpty { props.apiLevel = a }
            }
            // Lines 3+: dumpsys battery output
            for line in lines.dropFirst(3) {
                if line.contains("level:") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count == 2 {
                        props.batteryLevel = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                if line.contains("AC powered")
                    || line.contains("USB powered")
                    || line.contains("Wireless powered")
                {
                    let parts = line.components(separatedBy: ":")
                    if parts.count == 2,
                        parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                    {
                        props.isCharging = true
                    }
                }
            }
        } catch {
            print("[ADBService] fetchDeviceProperties error for \(deviceID): \(error)")
        }
        return props
    }

    // MARK: - App Launching & Mirroring (using SCRCPY)
    func launchApp(
        packageID: String, deviceID: String, appName: String?, deviceName: String?,
        audioEnabled: Bool, resolution: Int, clipboardEnabled: Bool, flexDisplay: Bool,
        useVirtualDisplay: Bool
    ) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot launch app with scrcpy."
            error.send(errorMessage)
            findADB()
            return
        }

        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = """
                SCRCPY executable not found.
                Please install scrcpy (e.g., `brew install scrcpy` on macOS).
                """
            error.send(errorMessage)
            #if canImport(AppKit)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "SCRCPY Not Found"
                    alert.informativeText =
                        errorMessage
                        + "\n\nCommon installation method on macOS:\nOpen Terminal and run: `brew install scrcpy`"
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Install with Homebrew")
                    alert.alertStyle = .warning
                    let response = alert.runModal()
                    if response == .alertSecondButtonReturn {
                        let command =
                            "clear; echo 'Installing scrcpy via Homebrew...'; brew install scrcpy; echo 'Done! Close this window and try again.'"
                        let scriptSource =
                            "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(command)\""
                        if let script = NSAppleScript(source: scriptSource) {
                            var error: NSDictionary?
                            script.executeAndReturnError(&error)
                        }
                    }
                }
            #endif
            return
        }

        // Sanitize deviceID (remove trailing dot from hostname if present)
        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        var args = [
            "--serial", cleanDeviceID,
            "--window-title", "\(deviceName ?? deviceID) - \(appName ?? packageID)",
            "--start-app", packageID,
            "--audio-output-buffer=10",
        ]

        if useVirtualDisplay {
            // An app gets a window of its own on a scrcpy virtual display. Avoided on
            // Android 12-13, where that crashes SystemUI and locks the device.
            args.append("--new-display")
            if flexDisplay {
                args.append("--flex-display")
                args.append("--audio-bit-rate=16M")
            } else {
                args.append("-m")
                args.append("\(resolution)")
                args.append("--audio-bit-rate=10000")
            }
        } else {
            // Mirror the main display with the app in the foreground instead
            args.append("-m")
            args.append("\(resolution)")
            args.append("--audio-bit-rate=10000")
        }

        if !audioEnabled {
            args.append("--no-audio")
        }

        if !clipboardEnabled {
            args.append("--no-clipboard-autosync")
        }

        // --keyboard=aoa only works over USB
        // Check for IP:Port format OR mDNS service names (containing _tcp or _udp)
        let isWireless =
            cleanDeviceID.contains(":") || cleanDeviceID.contains("_tcp")
            || cleanDeviceID.contains("_udp")

        let isEmulator = cleanDeviceID.lowercased().hasPrefix("emulator-")

        if !isWireless && !isEmulator {
            args.append("--keyboard=aoa")
        }

        task.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath

        if let javaHome = EnvironmentManager.shared.javaHome {
            env["JAVA_HOME"] = javaHome
            env["PATH"] =
                "\(javaHome)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        } else {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        }

        task.environment = env

        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = ""  // Initialize error output storage for this device

        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(obs)
        }

        // Add an observer for data available on the error pipe
        let observer = NotificationCenter.default.addObserver(
            forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data,
                !data.isEmpty
            {
                if let output = String(data: data, encoding: .utf8) {
                    // Append collected output
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else {
                // Clean up the observer for this device
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                    as? NSObjectProtocol
                {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        scrcpyErrorPipeHandlers[deviceID] = observer
        errorFileHandle.readInBackgroundAndNotify()  // Start the first read

        // --- Run the Process ---
        do {
            try task.run()
            // Store the process reference
            runningScrcpyProcesses[deviceID] = task

        } catch {
            // Error launching the process itself (e.g., scrcpy path invalid, permissions)
            let errorMessage =
                "Failed to launch SCRCPY process for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)

            // Clean up error pipe reader if the process didn't even start
            if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                as? NSObjectProtocol
            {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil  // Clear collected output

            #if canImport(AppKit)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Launch Failed"
                    alert.informativeText = errorMessage
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .critical
                    alert.runModal()
                }

            #endif
        }
    }

    func launchCamera(deviceID: String, facing: CameraFacing) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot launch camera with scrcpy."
            error.send(errorMessage)
            findADB()
            return
        }

        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = "SCRCPY executable not found. Please install scrcpy."
            error.send(errorMessage)
            showScrcpyErrorAlert(errorMessage: errorMessage)
            return
        }

        // Sanitize deviceID
        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)

        var args = [
            "--serial", cleanDeviceID,
            "--video-source=camera",
            "--camera-facing=\(facing.rawValue)",
            "--camera-size=1280x720",
            "--window-title", "\(facing.rawValue.capitalized) Camera - \(cleanDeviceID)",
        ]

        args.append("--no-audio")

        task.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath

        if let javaHome = EnvironmentManager.shared.javaHome {
            env["JAVA_HOME"] = javaHome
            env["PATH"] =
                "\(javaHome)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        } else {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        }

        task.environment = env

        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = ""

        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(obs)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data,
                !data.isEmpty
            {
                if let output = String(data: data, encoding: .utf8) {
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else {
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                    as? NSObjectProtocol
                {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        scrcpyErrorPipeHandlers[deviceID] = observer
        errorFileHandle.readInBackgroundAndNotify()

        do {
            try task.run()
            runningScrcpyProcesses[deviceID] = task
        } catch {
            let errorMessage =
                "Failed to launch camera for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
            if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                as? NSObjectProtocol
            {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil
            showScrcpyErrorAlert(errorMessage: errorMessage)
        }
    }

    // MARK: - Optional Mirroring Function
    // Mirrors the entire device screen using scrcpy (without launching a specific app)
    func mirrorDevice(
        deviceID: String, deviceName: String?, audioEnabled: Bool, clipboardEnabled: Bool,
        maxSize: Int?, maxFPS: Int?, bitRate: Int?, orientation: String?, borderless: Bool,
        flexDisplay: Bool
    ) {
        let options = MirrorOptions(
            audioForwarding: audioEnabled,
            alwaysOnTop: false,
            screenOff: false,
            borderless: borderless,
            clipboard: clipboardEnabled,
            recording: false,
            macKeyboard: true)
        let quality = MirrorQuality(
            maxSize: maxSize,
            maxFPS: maxFPS,
            bitRate: bitRate,
            orientation: orientation,
            flexDisplay: flexDisplay)
        let resolvedName =
            deviceName ?? lastPublishedDevices.first(where: { $0.id == deviceID })?.name
        _ = startMirrorSession(
            deviceID: deviceID,
            deviceName: resolvedName,
            quality: quality,
            options: options,
            recordPath: nil)
    }

    // MARK: - Mirror Session (Mirror Controls)

    /// Session lifecycle for the floating mirror panel. The panel must describe
    /// what actually launched, not what the switches wish had launched.
    let mirrorSessionEvents = PassthroughSubject<MirrorSessionEvent, Never>()

    private var mirrorSessions: [String: MirrorSessionSnapshot] = [:]
    private var mirrorSessionTasks: [String: Process] = [:]
    /// scrcpy processes being stopped on purpose (restart/close), so the shared
    /// termination handler does not report a failure for a deliberate stop. Keyed
    /// by process identity so a slow, stale handler can never clear a newer
    /// session's flag.
    private var intentionallyStoppedScrcpy: Set<ObjectIdentifier> = []

    /// What was actually launched for this device, if a mirror session is live.
    func mirrorSession(for deviceID: String) -> MirrorSessionSnapshot? {
        guard runningScrcpyProcesses[deviceID]?.isRunning == true else { return nil }
        return mirrorSessions[deviceID]
    }

    func isMirrorSessionActive(deviceID: String) -> Bool {
        runningScrcpyProcesses[deviceID]?.isRunning == true && mirrorSessions[deviceID] != nil
    }

    /// Restart (or start) the mirror for one device with `options`, preserving the
    /// caller's quality preset. Only the previous mirror process for that device
    /// is retired — app windows and camera sessions are not killed.
    @discardableResult
    func restartMirror(
        deviceID: String,
        options: MirrorOptions,
        quality: MirrorQuality,
        recordPath: String? = nil
    ) -> Bool {
        let name = lastPublishedDevices.first(where: { $0.id == deviceID })?.name
        return startMirrorSession(
            deviceID: deviceID,
            deviceName: name,
            quality: quality,
            options: options,
            recordPath: recordPath)
    }

    /// The single place that builds and launches a scrcpy mirror process. Both
    /// `mirrorDevice` and `restartMirror` go through here so the argument list
    /// cannot drift between call sites.
    @discardableResult
    func startMirrorSession(
        deviceID: String,
        deviceName: String?,
        quality: MirrorQuality,
        options: MirrorOptions,
        recordPath: String?
    ) -> Bool {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot mirror device with scrcpy."
            self.error.send(errorMessage)
            findADB()
            return false
        }

        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = """
                SCRCPY executable not found.
                Please install scrcpy (e.g., `brew install scrcpy` on macOS).
                """
            self.error.send(errorMessage)
            showScrcpyErrorAlert(errorMessage: errorMessage)
            mirrorSessionEvents.send(
                .failed(deviceID: deviceID, message: errorMessage))
            return false
        }

        // Fast restarts: retire the previous mirror (intentional stop, not a
        // failure) before this session takes ownership of the per-device keys.
        retireMirrorSessionIfNeeded(deviceID: deviceID)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = MirrorScrcpyArguments.build(
            deviceID: deviceID,
            deviceName: deviceName,
            quality: quality,
            options: options,
            recordPath: recordPath)
        task.environment = scrcpyLaunchEnvironment(adbPath: adbPath)

        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = ""

        // Remove any existing observer for this device before adding a new one.
        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
            as? NSObjectProtocol
        {
            NotificationCenter.default.removeObserver(obs)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data,
                !data.isEmpty
            {
                if let output = String(data: data, encoding: .utf8) {
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                as? NSObjectProtocol
            {
                NotificationCenter.default.removeObserver(obs)
            }
        }
        scrcpyErrorPipeHandlers[deviceID] = observer
        errorFileHandle.readInBackgroundAndNotify()

        task.terminationHandler = { [weak self] terminatedTask in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // A restarted session owns the per-device keys now; the stale
                // handler must not clear the new process, observer or error text.
                guard self.runningScrcpyProcesses[deviceID] === terminatedTask else {
                    return
                }

                let exitCode = terminatedTask.terminationStatus
                let intentional =
                    self.intentionallyStoppedScrcpy.remove(ObjectIdentifier(terminatedTask))
                    != nil
                let collectedErrorOutput =
                    self.scrcpyErrorOutputs[deviceID] ?? "No error output captured."

                self.runningScrcpyProcesses[deviceID] = nil
                self.scrcpyErrorOutputs[deviceID] = nil

                if self.mirrorSessionTasks[deviceID] === terminatedTask {
                    self.mirrorSessionTasks[deviceID] = nil
                    self.mirrorSessions[deviceID] = nil
                    self.mirrorSessionEvents.send(.stopped(deviceID: deviceID))
                }

                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                    as? NSObjectProtocol
                {
                    NotificationCenter.default.removeObserver(obs)
                }

                guard exitCode != 0, !intentional else { return }

                let errorMessage =
                    "SCRCPY mirroring failed for device \(deviceID) (Exit code: \(exitCode)).\nError Output:\n\(collectedErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                self.error.send(errorMessage)
                self.mirrorSessionEvents.send(
                    .failed(deviceID: deviceID, message: errorMessage))
                self.showScrcpyErrorAlert(errorMessage: errorMessage)
            }
        }

        do {
            try task.run()
            runningScrcpyProcesses[deviceID] = task
            mirrorSessionTasks[deviceID] = task
            let snapshot = MirrorSessionSnapshot(
                deviceID: deviceID,
                deviceName: deviceName,
                options: options,
                quality: quality,
                recordPath: recordPath,
                startedAt: Date())
            mirrorSessions[deviceID] = snapshot
            mirrorSessionEvents.send(.started(snapshot))
            return true
        } catch {
            let errorMessage =
                "Failed to launch SCRCPY mirroring process for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
            if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                as? NSObjectProtocol
            {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil
            mirrorSessionTasks[deviceID] = nil
            mirrorSessions[deviceID] = nil
            mirrorSessionEvents.send(
                .failed(deviceID: deviceID, message: errorMessage))
            showScrcpyErrorAlert(errorMessage: errorMessage)
            return false
        }
    }

    /// Stops the mirror session for one device on purpose. App windows and the
    /// camera session are not affected because they are not mirror sessions.
    func stopMirrorSession(deviceID: String) {
        guard let task = mirrorSessionTasks[deviceID]
            ?? (isMirrorSessionActive(deviceID: deviceID)
                ? runningScrcpyProcesses[deviceID] : nil)
        else {
            return
        }
        intentionallyStoppedScrcpy.insert(ObjectIdentifier(task))
        if task.isRunning { task.terminate() }
        mirrorSessionTasks[deviceID] = nil
        mirrorSessions[deviceID] = nil
        mirrorSessionEvents.send(.stopped(deviceID: deviceID))
    }

    private func retireMirrorSessionIfNeeded(deviceID: String) {
        guard let task = mirrorSessionTasks[deviceID] else { return }
        intentionallyStoppedScrcpy.insert(ObjectIdentifier(task))
        if task.isRunning { task.terminate() }
        mirrorSessionTasks[deviceID] = nil
        mirrorSessions[deviceID] = nil
        if runningScrcpyProcesses[deviceID] === task {
            runningScrcpyProcesses[deviceID] = nil
            if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID)
                as? NSObjectProtocol
            {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil
        }
    }

    /// The environment `mirrorDevice` has always given scrcpy: an explicit `ADB`
    /// path plus the user's Java/Homebrew search path.
    private func scrcpyLaunchEnvironment(adbPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath
        if let javaHome = EnvironmentManager.shared.javaHome {
            env["JAVA_HOME"] = javaHome
            env["PATH"] =
                "\(javaHome)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        } else {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        }
        return env
    }

    // MARK: - Camera Mirroring
    func mirrorCamera(
        deviceID: String, deviceName: String?, audioEnabled: Bool, facing: String?, fps: Int?,
        size: Int?, bitRate: Int?, orientation: String?, aspectRatio: String?
    ) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot mirror camera."
            self.error.send(errorMessage)
            self.findADB()
            return
        }

        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = "SCRCPY executable not found."
            self.error.send(errorMessage)
            return
        }

        // Sanitize deviceID
        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        var args = [
            "--serial", cleanDeviceID, "--window-title", "\(deviceName ?? deviceID) (Camera)",
        ]
        args.append("--video-source=camera")

        if let facing = facing, !facing.isEmpty, facing != "Auto" {
            args.append("--camera-facing")
            args.append(facing.lowercased())
        }

        if let fps = fps, fps > 0 {
            args.append("--camera-fps")
            args.append("\(fps)")
        }

        // Note: If size is specified, --camera-ar is forbidden according to docs?
        // User request: "If --camera-size is specified, then -m/--max-size and --camera-ar are forbidden"
        // But our "size" parameter maps to "-m" (max size) in the previous implementation?
        // Let's check previous implementation:
        // if let size = size, size > 0 { args.append("-m"); args.append("\(size)") }
        // Wait, for camera, -m is supported.
        // But --camera-size is explicit size.
        // The user request says: "Two constraints are supported: -m/--max-size ... ; --camera-ar ..."
        // "If --camera-size is specified, then -m/--max-size and --camera-ar are forbidden"
        // In our UI, "Camera Size" currently maps to `-m` (max size) based on my previous edit?
        // Let's re-read my previous edit to ADBService.swift.
        // Previous edit:
        // if let size = size, size > 0 { args.append("-m"); args.append("\(size)") }
        // So we are using max-size, not explicit camera-size.
        // So we CAN use --camera-ar with -m.

        if let size = size, size > 0 {
            args.append("-m")
            args.append("\(size)")
        }

        if let aspectRatio = aspectRatio, !aspectRatio.isEmpty, aspectRatio != "Auto" {
            args.append("--camera-ar")
            args.append(aspectRatio)
        }

        if let bitRate = bitRate, bitRate > 0 {
            args.append("--video-bit-rate")
            args.append("\(bitRate)M")
        }

        if let orientation = orientation, !orientation.isEmpty, orientation != "Auto" {
            args.append("--orientation")
            args.append(orientation)
        }

        if !audioEnabled {
            args.append("--no-audio")
        }

        // Run scrcpy
        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        task.environment = env

        do {
            try task.run()
            runningScrcpyProcesses[deviceID] = task
        } catch {
            let errorMessage =
                "Failed to launch SCRCPY camera mirroring for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
        }
    }

    // MARK: - Clipboard Sync Service
    // MARK: - Clipboard Sync Service

    /// Android package that receives Mac clipboard text via the WRITE broadcast.
    private static let clipboardCompanionPackage = CompanionClient.packageName
    /// Missing companions are re-checked after this interval; installed ones stay cached.
    private static let clipboardCompanionRecheckInterval: TimeInterval = 30

    func startClipboardSync(deviceID: String) {
        // Mac -> Android: opt this device into the shared pasteboard watcher.
        clipboardSyncDevices.insert(deviceID)
        startMacClipboardObserver()

        // Android -> Mac: reuse the mirror session scrcpy already runs for this device
        // when it forwards the clipboard; only otherwise spawn the hidden session.
        startAndroidToMacClipboardSync(deviceID: deviceID)

        // Learn whether the companion exists so the UI never promises delivery it cannot do.
        checkClipboardCompanion(deviceID: deviceID)
    }

    // MARK: - Android -> Mac

    private func startAndroidToMacClipboardSync(deviceID: String) {
        if clipboardSyncSessionCanReuseMirror(deviceID: deviceID) {
            adoptRunningMirrorForClipboard(deviceID: deviceID)
            return
        }

        clipboardReusingMirrorDevices.remove(deviceID)
        guard clipboardSyncProcesses[deviceID] == nil else { return }
        startScrcpyClipboardSync(deviceID: deviceID)
    }

    /// A running scrcpy session forwards clipboard changes unless it was started with
    /// `--no-clipboard-autosync`; only that case still needs its own hidden session.
    private func clipboardSyncSessionCanReuseMirror(deviceID: String) -> Bool {
        guard let mirror = runningScrcpyProcesses[deviceID], mirror.isRunning else { return false }
        return mirror.arguments?.contains("--no-clipboard-autosync") != true
    }

    /// Marks the device as handled by an existing mirror and retires a dedicated hidden
    /// session if one is still running, so two scrcpy sessions never compete for it.
    private func adoptRunningMirrorForClipboard(deviceID: String) {
        clipboardReusingMirrorDevices.insert(deviceID)
        if let dedicated = clipboardSyncProcesses.removeValue(forKey: deviceID) {
            dedicated.terminate()
        }
    }

    /// Keeps Android -> Mac sync correct while sharing is enabled: follow a mirror that
    /// scrcpy starts or stops, without ever running two sessions when one will do.
    private func reconcileAndroidToMacClipboardSessions() {
        for deviceID in clipboardSyncDevices {
            if clipboardSyncSessionCanReuseMirror(deviceID: deviceID) {
                adoptRunningMirrorForClipboard(deviceID: deviceID)
                continue
            }
            guard clipboardReusingMirrorDevices.contains(deviceID) else { continue }
            // The mirror ended (or stopped forwarding); fall back to the hidden session.
            clipboardReusingMirrorDevices.remove(deviceID)
            if clipboardSyncProcesses[deviceID] == nil {
                startScrcpyClipboardSync(deviceID: deviceID)
            }
        }
    }

    func stopAllClipboardSync() {
        let ids = Array(clipboardSyncDevices)
        for id in ids { stopClipboardSync(deviceID: id) }
    }

    func stopClipboardSync(deviceID: String) {
        clipboardSyncDevices.remove(deviceID)
        clipboardReusingMirrorDevices.remove(deviceID)

        // Only the dedicated hidden session is ours to terminate; a reused mirror stays.
        if let task = clipboardSyncProcesses.removeValue(forKey: deviceID) {
            task.terminate()
            print("Stopped scrcpy clipboard sync for \(deviceID)")
        }

        if clipboardSyncDevices.isEmpty {
            stopMacClipboardObserver()
        }
    }

    private func startScrcpyClipboardSync(deviceID: String) {
        // Never run two hidden sessions for the same device.
        if let existing = clipboardSyncProcesses[deviceID], existing.isRunning {
            return
        }

        guard let adbPath = currentADBPath else {
            error.send("ADB executable path not set. Cannot start clipboard sync.")
            findADB()
            return
        }

        guard let scrcpyPath = findScrcpyPath() else {
            error.send("SCRCPY executable not found. Please install scrcpy.")
            return
        }

        // Sanitize deviceID
        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)

        // Arguments: --serial deviceID --no-video --no-audio --no-window
        // This starts scrcpy in background just for clipboard
        let args = [
            "--serial", cleanDeviceID,
            "--no-video",
            "--no-audio",
            "--no-window",
        ]

        task.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        task.environment = env

        // We don't necessarily need to capture output unless for debugging errors
        // But let's capture error output just in case
        let errorPipe = Pipe()
        task.standardError = errorPipe

        task.terminationHandler = { [weak self] terminatedTask in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Remove from processes list if it terminated
                if self.clipboardSyncProcesses[deviceID] == terminatedTask {
                    self.clipboardSyncProcesses[deviceID] = nil
                    if terminatedTask.terminationStatus != 0 {
                        self.clipboardEvents.send(
                            .failed(
                                deviceID: deviceID,
                                message: "The hidden scrcpy clipboard session exited unexpectedly."))
                    }
                }
            }
        }

        do {
            try task.run()
            clipboardSyncProcesses[deviceID] = task
            print("Started scrcpy clipboard sync for \(deviceID)")
        } catch {
            self.error.send(
                "Failed to start clipboard sync for \(deviceID): \(error.localizedDescription)")
        }
    }

    // MARK: - Mac -> Android Clipboard Sync

    private func startMacClipboardObserver() {
        guard clipboardTimer == nil else { return }

        // Seed from the current pasteboard so enabling sharing does not replay stale text.
        let pasteboard = NSPasteboard.general
        lastClipboardChangeCount = pasteboard.changeCount
        lastClipboardText = pasteboard.string(forType: .string)

        // A light timer is enough: reading changeCount is cheap, and the full string is
        // only read (and synced) when the pasteboard actually changed.
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.checkMacClipboard()
        }
        clipboardTimer?.tolerance = 0.25
    }

    private func stopMacClipboardObserver() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        lastClipboardChangeCount = -1
        lastClipboardText = nil
    }

    private func checkMacClipboard() {
        // Follow a mirror that starts or stops while sharing is enabled.
        reconcileAndroidToMacClipboardSessions()

        #if canImport(AppKit)
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != lastClipboardChangeCount else { return }
            lastClipboardChangeCount = pasteboard.changeCount

            guard let content = pasteboard.string(forType: .string), !content.isEmpty else {
                lastClipboardText = nil
                return
            }

            // scrcpy mirrors the text we just pushed back onto the pasteboard; do not
            // bounce that echo to the devices again.
            guard content != lastClipboardText else { return }
            lastClipboardText = content

            for deviceID in clipboardSyncDevices {
                // Deliberately not gated on `clipboardCompanionInstalled`: the user can
                // install the companion at any time, and a "missing" result cached before
                // that would silently disable delivery until the toggle was cycled.
                // Delivery itself is cheap when the channel is already up.
                sendClipboardToDevice(deviceID: deviceID, text: content)
            }
        #endif
    }

    func sendClipboardToDevice(
        deviceID: String, text: String, completion: ((Bool) -> Void)? = nil
    ) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }

        // The first-party companion owns clipboard writes. It is reached over the
        // ADB tunnel (forwarded abstract socket), so there is no third-party app to
        // install and no shell quoting to get wrong.
        CompanionClient.shared.pushClipboard(text, deviceID: deviceID) {
            [weak self] delivered in
            guard let self else {
                completion?(false)
                return
            }
            if delivered {
                self.lastClipboardText = text
                self.clipboardEvents.send(.sent(deviceID: deviceID, at: Date()))
                completion?(true)
                return
            }

            self.clipboardEvents.send(
                .failed(
                    deviceID: deviceID,
                    message: "AndroLaunch Comp could not receive the text."))
            // Delivery failed; the app may have been uninstalled, so re-check quietly.
            self.checkClipboardCompanion(deviceID: deviceID, forceRefresh: true)
            completion?(false)
        }
    }

    // MARK: - Companion App Detection

    /// Verifies that the AndroLaunch companion is installed, caching positives and
    /// re-checking missing apps after a short interval. Results are published on
    /// `clipboardEvents` so `ClipboardBridge` can surface them.
    func checkClipboardCompanion(deviceID: String, forceRefresh: Bool = false) {
        if !forceRefresh, let cached = clipboardCompanionInstalled[deviceID] {
            let checkedAt = clipboardCompanionCheckedAt[deviceID] ?? .distantPast
            if cached || Date().timeIntervalSince(checkedAt) < Self.clipboardCompanionRecheckInterval
            {
                return
            }
        }

        // Menu builds can ask several times before the first result arrives.
        guard !clipboardCompanionChecksInFlight.contains(deviceID) else { return }
        clipboardCompanionChecksInFlight.insert(deviceID)

        executeADBCommand(
            arguments: ["-s", deviceID, "shell", "pm", "path", Self.clipboardCompanionPackage]
        ) { [weak self] success, output, _ in
            guard let self else { return }
            // `pm path` exits 0 for a missing package and simply prints nothing.
            let installed = success && (output?.contains("package:") == true)
            DispatchQueue.main.async {
                self.clipboardCompanionChecksInFlight.remove(deviceID)
                self.clipboardCompanionInstalled[deviceID] = installed
                self.clipboardCompanionCheckedAt[deviceID] = Date()
                self.clipboardEvents.send(
                    .companionChecked(deviceID: deviceID, installed: installed))
            }
        }
    }

    /// Last known companion state, `nil` before the first check completes.
    func cachedClipboardCompanionStatus(deviceID: String) -> Bool? {
        clipboardCompanionInstalled[deviceID]
    }

    /// Whether Mac -> Android delivery is currently opted in for this device.
    func isClipboardSyncActive(deviceID: String) -> Bool {
        clipboardSyncDevices.contains(deviceID)
    }

    func uninstallApp(deviceID: String, packageID: String) {
        executeADBCommand(arguments: ["-s", deviceID, "uninstall", packageID]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Refresh apps list after successful uninstall
                self.fetchApps(for: deviceID)
            } else {
                self.error.send(
                    "Failed to uninstall \(packageID): \(errorOutput ?? "Unknown error")")
            }
        }
    }

    func clearAppData(deviceID: String, packageID: String) {
        executeADBCommand(arguments: ["-s", deviceID, "shell", "pm", "clear", packageID]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Success usually returns "Success"
            } else {
                self.error.send(
                    "Failed to clear app data for \(packageID): \(errorOutput ?? "Unknown error")")
            }
        }
    }

    private func showScrcpyErrorAlert(errorMessage: String) {
        #if canImport(AppKit)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Action Failed"
                alert.informativeText = """
                    \(errorMessage)

                    Ensure scrcpy is installed and accessible in your system's PATH.
                    Common installation method on macOS:
                    Open Terminal and run: `brew install scrcpy`
                    """
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Install with Homebrew")
                alert.alertStyle = .warning
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    let command =
                        "clear; echo 'Installing scrcpy via Homebrew...'; brew install scrcpy; echo 'Done! Close this window and try again.'"
                    let scriptSource =
                        "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(command)\""
                    if let script = NSAppleScript(source: scriptSource) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
                }
            }
        #endif
    }
    // MARK: - Optional Stop Mirroring Function
    func stopMirroring(deviceID: String) {
        if let task = runningScrcpyProcesses[deviceID] {
            // A deliberate stop is not a mirror failure.
            intentionallyStoppedScrcpy.insert(ObjectIdentifier(task))
            task.terminate()  // The terminationHandler handles cleanup
            if mirrorSessionTasks[deviceID] === task {
                mirrorSessionTasks[deviceID] = nil
                mirrorSessions[deviceID] = nil
                mirrorSessionEvents.send(.stopped(deviceID: deviceID))
            }
        } else {
            self.error.send("No running SCRCPY process found for device \(deviceID).")
        }
    }

    // MARK: - Install APK
    func installAPK(deviceID: String, apkPath: String) {
        guard currentADBPath != nil else {
            self.error.send("ADB path not set, cannot install APK.")
            return
        }

        executeADBCommand(arguments: ["-s", deviceID, "install", "-r", apkPath]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                self.error.send(nil)  // Clear any previous errors
                // Optionally refresh apps after install
                self.fetchApps(for: deviceID)
            } else {
                self.error.send(errorOutput ?? "Failed to install APK")
            }
        }
    }

    // MARK: - Disconnect Device
    func disconnectDevice(deviceID: String) {
        guard currentADBPath != nil else {
            self.error.send("ADB path not set, cannot disconnect device.")
            return
        }

        // Tell the connection layer this was a deliberate disconnect, so it does not
        // immediately race the device's remembered endpoints and undo the action.
        NotificationCenter.default.post(
            name: .adbIntentionalDisconnect,
            object: nil,
            userInfo: ["deviceID": deviceID])

        // Find all device IDs sharing the same serial number (e.g. IP + mDNS paths)
        let serial = lastPublishedDevices.first(where: { $0.id == deviceID })?.serialNumber
        let idsToDisconnect: [String]
        if let serial {
            idsToDisconnect = lastPublishedDevices
                .filter { $0.serialNumber == serial }
                .map { $0.id }
        } else {
            idsToDisconnect = [deviceID]
        }

        let group = DispatchGroup()
        for id in idsToDisconnect {
            group.enter()
            executeADBCommand(arguments: ["disconnect", id]) { _, _, _ in group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.listDevices()
        }
    }

    func connectToHost(_ hostPort: String, completion: @escaping (Bool) -> Void) {
        // `adb connect` is how the connection coordinator races endpoints. Some ADB
        // versions exit 0 while printing a failure, so success needs a clean exit
        // status *and* no failure text in the output.
        executeADBCommand(arguments: ["connect", hostPort]) {
            [weak self] success, output, errorOutput in
            let combined = ((output ?? "") + "\n" + (errorOutput ?? "")).lowercased()
            let reportedFailure =
                combined.contains("failed to connect")
                || combined.contains("failed to authenticate")
                || combined.contains("cannot connect")
                || combined.contains("unable to connect")
            let connected = success && !reportedFailure
            if connected {
                self?.listDevices()
            }
            completion(connected)
        }
    }

    // MARK: - Quick Actions
    func reboot(deviceID: String, mode: RebootMode) {
        var args = ["-s", deviceID, "reboot"]
        if !mode.rawValue.isEmpty {
            args.append(mode.rawValue)
        }

        executeADBCommand(arguments: args) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to reboot device")
            }
        }
    }

    func toggleWiFi(deviceID: String, enable: Bool) {
        let state = enable ? "enable" : "disable"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "svc", "wifi", state]) {
            [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Wi-Fi")
            }
        }
    }

    func toggleBluetooth(deviceID: String, enable: Bool) {
        let state = enable ? "enable" : "disable"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "svc", "bluetooth", state]) {
            [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Bluetooth")
            }
        }
    }

    func toggleDarkMode(deviceID: String, enable: Bool) {
        let mode = enable ? "yes" : "no"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "cmd", "uimode", "night", mode]) {
            [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Dark Mode")
            }
        }
    }

    func toggleAirplaneMode(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "settings", "put", "global", "airplane_mode_on", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Airplane Mode")
            } else {
                // Broadcast intent is often needed for Airplane mode to take effect immediately
                self?.executeADBCommand(arguments: [
                    "-s", deviceID, "shell", "am", "broadcast", "-a",
                    "android.intent.action.AIRPLANE_MODE",
                ]) { _, _, _ in }
            }
        }
    }

    func toggleMobileData(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "settings", "put", "global", "mobile_data", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Mobile Data")
            }
        }
    }

    func toggleLocation(deviceID: String, enable: Bool) {
        // 3 = High Accuracy, 0 = Off
        let value = enable ? "3" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "settings", "put", "secure", "location_mode", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Location")
            }
        }
    }

    func toggleDoNotDisturb(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "cmd", "settings", "put", "global", "zen_mode", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Do Not Disturb")
            }
        }
    }

    func toggleAutoRotate(deviceID: String, enable: Bool) {
        // 0 = Disable Auto-Rotate (Portrait/Landscape locked), 1 = Enable Auto-Rotate
        // The user request says: "adb shell settings put system accelerometer_rotation 0 (Disable Auto-Rotate)"
        // So enable=true means accelerometer_rotation=1
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "settings", "put", "system", "accelerometer_rotation", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Auto-Rotate")
            }
        }
    }

    func setRingerMode(deviceID: String, mode: RingerMode) {
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "cmd", "media_session", "set_volume_mode", mode.rawValue,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to set Ringer Mode")
            }
        }
    }

    func toggleAdaptiveBrightness(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: [
            "-s", deviceID, "shell", "settings", "put", "system", "screen_brightness_mode", value,
        ]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Adaptive Brightness")
            }
        }
    }

    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void)
    {
        // Construct a single command to fetch all states
        // We use echo to separate values for easier parsing
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

        executeADBCommand(arguments: ["-s", deviceID, "shell", cmd]) { success, output, _ in
            var state = QuickActionsState()
            guard success, let output = output else {
                completion(state)
                return
            }

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
                    // 0 = Off, others (1, 2, 3) are On
                    if let val = Int(
                        line.replacingOccurrences(of: "LOC:", with: "").trimmingCharacters(
                            in: .whitespaces)), val > 0
                    {
                        state.isLocationEnabled = true
                    }
                } else if line.hasPrefix("DND:") {
                    // zen_mode: 0 = Off, 1+ = On
                    if let val = Int(
                        line.replacingOccurrences(of: "DND:zen_mode =", with: "")
                            .trimmingCharacters(in: .whitespaces)), val > 0
                    {
                        state.isDoNotDisturbEnabled = true
                    } else if line.contains("1") || line.contains("2") || line.contains("3") {
                        // Fallback parsing if format differs
                        state.isDoNotDisturbEnabled = true
                    }
                } else if line.hasPrefix("ROT:") {
                    // accelerometer_rotation: 0 = Locked (Portrait/Landscape), 1 = Auto-Rotate
                    state.isAutoRotateEnabled = line.contains("1")
                } else if line.hasPrefix("BRI:") {
                    state.isAdaptiveBrightnessEnabled = line.contains("1")
                }
                // Ringer mode is tricky to get via simple command across versions.
                // We'll skip it for now or default to normal, as `mode_ringer` is unreliable.
            }

            completion(state)
        }
    }

    // MARK: - File Management
    func listFiles(
        for deviceID: String, at path: String,
        completion: @escaping (Result<[AndroidFile], Error>) -> Void
    ) {
        // ls -la: Permissions, Links, Owner, Group, Size, Date, Name
        let targetPath = path.hasSuffix("/") ? path : "\(path)/"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "ls", "-la", targetPath]) {
            success, output, errorOutput in
            if success, let output = output {
                let files = self.parseFiles(output, at: path)
                completion(.success(files))
            } else {
                let error = NSError(
                    domain: "ADBService", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: errorOutput ?? "Failed to list files"])
                completion(.failure(error))
            }
        }
    }

    private func parseFiles(_ output: String, at parentPath: String) -> [AndroidFile] {
        var files: [AndroidFile] = []

        // Multiple patterns to handle different ls output formats
        // 1. Standard Toybox: drwxrwx--x 13 root sdcard_rw 4096 2026-04-12 17:00 name
        // 2. Toolbox/Busybox: drwxrwx--x root sdcard_rw 4096 Apr 12 17:00 name
        // 3. Simple: drwxrwx--x 4096 Apr 12 17:00 name
        let patterns = [
            #"^([a-zA-Z-]{10,11})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s+(.+)$"#,
            #"^([a-zA-Z-]{10,11})\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2}\s+\d+\s+[\d:]{4,5})\s+(.+)$"#,
            #"^([a-zA-Z-]{10,11})\s+(\d+)\s+([A-Z][a-z]{2}\s+\d+\s+[\d:]{4,5})\s+(.+)$"#,
        ]

        let regexes = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines)
        }
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let nsLine = line.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
            if nsLine.length == 0 || nsLine.hasPrefix("total") { continue }

            var matchFound = false
            for regex in regexes {
                let matches = regex.matches(
                    in: nsLine as String, options: [],
                    range: NSRange(location: 0, length: nsLine.length))
                guard let match = matches.first else { continue }

                if match.numberOfRanges >= 4 {
                    let perms = nsLine.substring(with: match.range(at: 1))
                    let sizeStr = nsLine.substring(with: match.range(at: 2))
                    let dateStr = nsLine.substring(with: match.range(at: 3))
                    var name = nsLine.substring(with: match.range(at: match.numberOfRanges - 1))

                    if let arrowRange = name.range(of: " -> ") {
                        name = String(name[..<arrowRange.lowerBound])
                    }

                    if name == "./" || name == "../" || name == "." || name == ".." {
                        matchFound = true
                        continue
                    }

                    let isDirectory =
                        perms.hasPrefix("d") || perms.hasPrefix("l") || name.hasSuffix("/")
                    if name.hasSuffix("/") {
                        name.removeLast()
                    }

                    let size = Int64(sizeStr) ?? 0
                    let fullPath =
                        parentPath.hasSuffix("/") ? "\(parentPath)\(name)" : "\(parentPath)/\(name)"

                    let file = AndroidFile(
                        name: name,
                        path: fullPath,
                        size: size,
                        modificationDate: dateStr,
                        isDirectory: isDirectory,
                        permissions: perms
                    )
                    files.append(file)
                    matchFound = true
                    break
                }
            }

            // Fallback for very simple ls if everything else fails
            if !matchFound {
                let parts = nsLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 1 {
                    let namePart = parts.last!
                    if namePart != "." && namePart != ".." && namePart != "./" && namePart != "../"
                    {
                        let isDirectory =
                            nsLine.hasPrefix("d") || namePart.hasSuffix("/")
                            || nsLine.hasPrefix("l")
                        var name = namePart
                        if let arrowIndex = parts.firstIndex(of: "->"), arrowIndex > 0 {
                            name = parts[arrowIndex - 1]
                        }
                        if name.hasSuffix("/") { name.removeLast() }

                        // Only add if it doesn't look like a metadata line
                        if !name.contains(":") && !name.hasPrefix("d") {
                            let fullPath =
                                parentPath.hasSuffix("/")
                                ? "\(parentPath)\(name)" : "\(parentPath)/\(name)"
                            files.append(
                                AndroidFile(
                                    name: name,
                                    path: fullPath,
                                    size: 0,
                                    modificationDate: nil,
                                    isDirectory: isDirectory,
                                    permissions: isDirectory ? "drwxr-xr-x" : "-rw-r--r--"
                                ))
                        }
                    }
                }
            }
        }
        return files.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    func pushFile(
        deviceID: String, localPath: String, remotePath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        executeADBCommand(arguments: ["-s", deviceID, "push", localPath, remotePath]) {
            success, _, errorOutput in
            if success {
                completion(.success(()))
            } else {
                let error = NSError(
                    domain: "ADBService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: errorOutput ?? "Failed to push file"])
                completion(.failure(error))
            }
        }
    }

    func pullFile(
        deviceID: String, remotePath: String, localPath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        executeADBCommand(arguments: ["-s", deviceID, "pull", remotePath, localPath]) {
            success, _, errorOutput in
            if success {
                completion(.success(()))
            } else {
                let error = NSError(
                    domain: "ADBService", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: errorOutput ?? "Failed to pull file"])
                completion(.failure(error))
            }
        }
    }

    func deleteFile(
        deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        executeADBCommand(arguments: ["-s", deviceID, "shell", "rm", "-rf", path]) {
            success, _, errorOutput in
            if success {
                completion(.success(()))
            } else {
                let error = NSError(
                    domain: "ADBService", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: errorOutput ?? "Failed to delete file"])
                completion(.failure(error))
            }
        }
    }

    func createDirectory(
        deviceID: String, path: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        executeADBCommand(arguments: ["-s", deviceID, "shell", "mkdir", "-p", path]) {
            success, _, errorOutput in
            if success {
                completion(.success(()))
            } else {
                let error = NSError(
                    domain: "ADBService", code: 6,
                    userInfo: [
                        NSLocalizedDescriptionKey: errorOutput ?? "Failed to create directory"
                    ])
                completion(.failure(error))
            }
        }
    }
}
