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
    private var clipboardSyncProcesses: [String: Process] = [:] // Dedicated clipboard sync processes
    
    // MARK: - Clipboard Sync State
    private var clipboardSyncDevices: Set<String> = []
    private var clipboardTimer: Timer?
    private var lastClipboardContent: String?
    
    // MARK: - Executable Path Discovery
    
    // Common system paths for ADB
    private var systemADBPaths: [String] {
        [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Library/Android/sdk/platform-tools/adb"
        ]
    }
    
    // Common system paths for SCRCPY
    private var scrcpyPaths: [String] {
        [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(NSHomeDirectory())/.local/bin/scrcpy",
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy"
        ]
    }
    
    // MARK: - Initialization
    init() {
    }
    
    // MARK: - Private Helper: Execute Shell Command (For ADB commands like list, start-server, fetch packages)
    private func executeADBCommand(arguments: [String], path: String? = nil, completion: @escaping (Bool, String?, String?) -> Void) {
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
    private func findScrcpyPath() -> String? {
        for path in scrcpyPaths {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    
    // MARK: - ADB Path Discovery
    func findADB() {
        for path in systemADBPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                currentADBPath = path
                error.send(nil)
                startADBDaemon()
                return
            }
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
        executeADBCommand(arguments: ["start-server"], path: adbPath) { [weak self] success, _, errorOutput in
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
        executeADBCommand(arguments: ["devices", "-l"]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Move parsing to background to avoid blocking main thread with sync ADB calls
                DispatchQueue.global(qos: .userInitiated).async {
                    let devices = self.parseDevices(from: output ?? "")
                    
                    DispatchQueue.main.async {
                        self.devices.send(devices)
                        self.error.send(nil)
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
        let pattern = #"^(\S+)\s+(device|unauthorized|offline|no permissions)\s*(.*)$"# // Adjusted regex slightly for end of line
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            self.error.send("Failed to create regex for device parsing.")
            return []
        }
        var devices = [AndroidDevice]()
        var seenDeviceNames = Set<String>() // To track unique device names
        
        output.enumerateLines { line, _ in
            guard !line.lowercased().contains("list of devices attached") && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges >= 3 else {
                self.error.send("Line did not match device pattern: \(line)")
                return
            }
            
            let idRange = match.range(at: 1)
            let stateRange = match.range(at: 2)
            let detailsRange = match.range(at: 3)
            
            guard let id = Range(idRange, in: line),
                  let state = Range(stateRange, in: line) else {
                self.error.send("Could not extract ID or state from line: \(line)")
                return
            }
            
            let deviceID = String(line[id])
            var cleanDeviceID = deviceID
            if cleanDeviceID.contains(".:") {
                cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
            }
            
            // Fetch serial number for this device
            var serialNumber: String?
            do {
                let serialOutput = try self.executeADBCommandSync(arguments: ["-s", cleanDeviceID, "shell", "getprop", "ro.serialno"])
                serialNumber = serialOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if serialNumber?.isEmpty == true {
                    serialNumber = nil
                }
            } catch {
                self.error.send("Failed to get serial number for \(cleanDeviceID): \(error.localizedDescription)")
            }
            
            let deviceState = String(line[state])
            var modelName = "Android Device"
            var rawModel: String?
            
            if let detailsRng = Range(detailsRange, in: line) {
                let details = String(line[detailsRng])
                let modelPattern = #"model:([^\s]+)"#
                if let modelMatch = try? NSRegularExpression(pattern: modelPattern)
                    .firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
                   let modelRng = Range(modelMatch.range(at: 1), in: details) {
                    rawModel = String(details[modelRng])
                    modelName = rawModel!.replacingOccurrences(of: "_", with: " ")
                }
            }
            
            // Only add devices that are successfully connected
            if deviceState == "device" {
                // Check for duplicate names before adding
                if !seenDeviceNames.contains(modelName) {
                    let newDevice = AndroidDevice(
                        id: cleanDeviceID,
                        name: modelName,
                        model: rawModel,
                        isConnected: true,
                        serialNumber: serialNumber,
                        androidVersion: self.fetchAndroidVersion(deviceID: cleanDeviceID),
                        apiLevel: self.fetchAPILevel(deviceID: cleanDeviceID),
                        batteryLevel: self.fetchBatteryLevel(deviceID: cleanDeviceID),
                        isCharging: self.fetchIsCharging(deviceID: cleanDeviceID)
                    )
                    devices.append(newDevice)
                    seenDeviceNames.insert(modelName) // Add name to seen set
                } else {
                    self.error.send("Skipping duplicate device name: \(modelName) (ID: \(cleanDeviceID))")
                }
            } else {
                self.error.send("Found device in state \(deviceState): \(cleanDeviceID)")
            }
        }
        
        return devices
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
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
            task.environment = env
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try task.run()
                task.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let combinedOutput = output + "\n" + errorOutput
                
                if task.terminationStatus == 0 {
                    let apps = self.parseScrcpyApps(from: combinedOutput)
                    
                    if !apps.isEmpty {
                        DispatchQueue.main.async {
                            self.apps.send((deviceID, apps))
                            self.error.send(nil)
                        }
                    } else {
                        DispatchQueue.main.async {
                            // Send raw output for debugging if 0 apps found
                            self.error.send("No apps found via scrcpy. Output:\n\(combinedOutput)")
                            self.apps.send((deviceID, []))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error.send("Scrcpy failed (code \(task.terminationStatus)). Output:\n\(combinedOutput)")
                        self.apps.send((deviceID, []))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.error.send("Failed to execute scrcpy: \(error.localizedDescription)")
                    self.apps.send((deviceID, []))
                }
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
            if let match = regex?.firstMatch(in: trimmed, options: [], range: range), match.numberOfRanges == 3 {
                
                if let nameRange = Range(match.range(at: 1), in: trimmed),
                   let pkgRange = Range(match.range(at: 2), in: trimmed) {
                    
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
            throw NSError(domain: "ADBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB path not set"])
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

    private func fetchAndroidVersion(deviceID: String) -> String? {
        do {
            let output = try executeADBCommandSync(arguments: ["-s", deviceID, "shell", "getprop", "ro.build.version.release"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func fetchAPILevel(deviceID: String) -> String? {
        do {
            let output = try executeADBCommandSync(arguments: ["-s", deviceID, "shell", "getprop", "ro.build.version.sdk"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func fetchBatteryLevel(deviceID: String) -> Int? {
        do {
            let output = try executeADBCommandSync(arguments: ["-s", deviceID, "shell", "dumpsys", "battery"])
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("level") {
                    let components = line.components(separatedBy: ":")
                    if components.count == 2 {
                        return Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchIsCharging(deviceID: String) -> Bool? {
        do {
            let output = try executeADBCommandSync(arguments: ["-s", deviceID, "shell", "dumpsys", "battery"])
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("AC powered") || line.contains("USB powered") || line.contains("Wireless powered") {
                     let components = line.components(separatedBy: ":")
                     if components.count == 2 {
                         let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                         if value == "true" {
                             return true
                         }
                     }
                }
            }
            return false
        } catch {
            return nil
        }
    }
    
    // MARK: - App Launching & Mirroring (using SCRCPY)
    func launchApp(packageID: String, deviceID: String, appName: String?, deviceName: String?, audioEnabled: Bool, resolution: Int, clipboardEnabled: Bool) {
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
                alert.informativeText = errorMessage + "\n\nCommon installation method on macOS:\nOpen Terminal and run: `brew install scrcpy`"
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Open scrcpy GitHub")
                alert.alertStyle = .warning
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Genymobile/scrcpy")!)
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
            "--stay-awake",
            "--window-title", "\(deviceName ?? deviceID) - \(appName ?? packageID)",
            "--new-display",
            "-m", "\(resolution)",
            "--start-app", packageID,
            "--audio-bit-rate=10000",
            "--audio-output-buffer=10"
        ]
        
        if !audioEnabled {
            args.append("--no-audio")
        }
        
        if !clipboardEnabled {
            args.append("--no-clipboard-autosync")
        }
        
        // --keyboard=aoa only works over USB
        // Check for IP:Port format OR mDNS service names (containing _tcp or _udp)
        let isWireless = cleanDeviceID.contains(":") ||
        cleanDeviceID.contains("_tcp") ||
        cleanDeviceID.contains("_udp")
        
        let isEmulator = cleanDeviceID.lowercased().hasPrefix("emulator-")
        
        if !isWireless && !isEmulator {
            args.append("--keyboard=aoa")
        } else {
            self.error.send("Wireless or Emulator device detected (\(cleanDeviceID)), skipping --keyboard=aoa")
        }
        
        task.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        task.environment = env
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = "" // Initialize error output storage for this device
        
        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(obs)
        }
        
        // Add an observer for data available on the error pipe
        let observer = NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data, !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    // Append collected output
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else {
                // Clean up the observer for this device
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        scrcpyErrorPipeHandlers[deviceID] = observer
        errorFileHandle.readInBackgroundAndNotify() // Start the first read
        
        // --- Run the Process ---
        do {
            try task.run()
            // Store the process reference
            runningScrcpyProcesses[deviceID] = task
            
        } catch {
            // Error launching the process itself (e.g., scrcpy path invalid, permissions)
            let errorMessage = "Failed to launch SCRCPY process for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
            
            // Clean up error pipe reader if the process didn't even start
            if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil // Clear collected output
            
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
            "--window-title", "\(facing.rawValue.capitalized) Camera - \(cleanDeviceID)"
        ]
        
        args.append("--no-audio")
        
        task.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        task.environment = env
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = ""
        
        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(obs)
        }
        
        let observer = NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data, !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else {
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
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
            let errorMessage = "Failed to launch camera for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
            if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil
            showScrcpyErrorAlert(errorMessage: errorMessage)
        }
    }
    
    
    // MARK: - Optional Mirroring Function
    // Mirrors the entire device screen using scrcpy (without launching a specific app)
    // Mirrors the entire device screen using scrcpy (without launching a specific app)
    func mirrorDevice(deviceID: String, deviceName: String?, audioEnabled: Bool, clipboardEnabled: Bool, maxSize: Int?, maxFPS: Int?, bitRate: Int?, orientation: String?, borderless: Bool) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot mirror device with scrcpy."
            self.error.send(errorMessage)
            self.findADB() // Attempt to find ADB
            return
        }
        
        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = """
             SCRCPY executable not found.
             Please install scrcpy (e.g., `brew install scrcpy` on macOS).
             """
            self.error.send(errorMessage)
#if canImport(AppKit)
            DispatchQueue.main.async {
                // Show alert similar to launchApp
                let alert = NSAlert()
                alert.messageText = "SCRCPY Not Found"
                alert.informativeText = errorMessage + "\n\nCommon installation method on macOS:\nOpen Terminal and run: `brew install scrcpy`"
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Open scrcpy GitHub")
                alert.alertStyle = .warning
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Genymobile/scrcpy")!)
                }
            }
#endif
            return
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        
        // scrcpy arguments for mirroring
        var args = ["--serial", deviceID, "--window-title", "\(deviceName ?? deviceID)"]
        
        if let maxSize = maxSize, maxSize > 0 {
            args.append("-m")
            args.append("\(maxSize)")
        }
        
        if let maxFPS = maxFPS, maxFPS > 0 {
            args.append("--max-fps")
            args.append("\(maxFPS)")
        }
        
        if let bitRate = bitRate, bitRate > 0 {
            args.append("--video-bit-rate")
            args.append("\(bitRate)M")
        }
        
        if let orientation = orientation, !orientation.isEmpty, orientation != "Auto" {
            args.append("--capture-orientation")
            args.append(orientation)
        }
        
        if borderless {
            args.append("--window-borderless")
        }
        
        if !audioEnabled {
            args.append("--no-audio")
        }
        
        if !clipboardEnabled {
            args.append("--no-clipboard-autosync")
        }
        task.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath // Explicitly tell scrcpy where to find adb
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:\(env["PATH"] ?? "")"
        task.environment = env
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        let errorFileHandle = errorPipe.fileHandleForReading
        scrcpyErrorOutputs[deviceID] = ""
        
        // Remove any existing observer for this device before adding a new one
        if let obs = scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(obs)
        }
        
        let observer = NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: errorFileHandle, queue: nil) { [weak self] notification in
            guard let self else { return }
            if let data = notification.userInfo?[FileHandle.readCompletionNotification] as? Data, !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    self.scrcpyErrorOutputs[deviceID, default: ""] += output
                }
                errorFileHandle.readInBackgroundAndNotify()
            } else {
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        scrcpyErrorPipeHandlers[deviceID] = observer
        errorFileHandle.readInBackgroundAndNotify()
        
        task.terminationHandler = { [weak self] terminatedTask in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let exitCode = terminatedTask.terminationStatus
                
                let collectedErrorOutput = self.scrcpyErrorOutputs[deviceID] ?? "No error output captured."
                
                self.runningScrcpyProcesses[deviceID] = nil
                self.scrcpyErrorOutputs[deviceID] = nil
                
                if exitCode != 0 {
                    let errorMessage = "SCRCPY mirroring failed for device \(deviceID) (Exit code: \(exitCode)).\nError Output:\n\(collectedErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                    self.error.send(errorMessage)
#if canImport(AppKit)
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "SCRCPY Mirroring Failed"
                        alert.informativeText = errorMessage
                        alert.addButton(withTitle: "OK")
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
#endif
                }
                if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        
        do {
            try task.run()
            runningScrcpyProcesses[deviceID] = task
            
        } catch {
            let errorMessage = "Failed to launch SCRCPY mirroring process for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
            if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(obs)
            }
            scrcpyErrorOutputs[deviceID] = nil
#if canImport(AppKit)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Mirroring Failed"
                alert.informativeText = errorMessage
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .critical
                alert.runModal()
            }
#endif
        }
    }
    
    // MARK: - Camera Mirroring
    func mirrorCamera(deviceID: String, deviceName: String?, audioEnabled: Bool, facing: String?, fps: Int?, size: Int?, bitRate: Int?, orientation: String?, aspectRatio: String?) {
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
        
        var args = ["--serial", cleanDeviceID, "--window-title", "\(deviceName ?? deviceID) (Camera)"]
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
            let errorMessage = "Failed to launch SCRCPY camera mirroring for \(deviceID): \(error.localizedDescription)"
            self.error.send(errorMessage)
        }
    }
    
    // MARK: - Clipboard Sync Service
    // MARK: - Clipboard Sync Service
    
    func startClipboardSync(deviceID: String) {
        // 1. Start Android -> Mac sync (using scrcpy)
        if clipboardSyncProcesses[deviceID] == nil {
            startScrcpyClipboardSync(deviceID: deviceID)
        }
        
        // 2. Start Mac -> Android sync (using adb broadcast)
        clipboardSyncDevices.insert(deviceID)
        startMacClipboardObserver()
    }
    
    func stopClipboardSync(deviceID: String) {
        // 1. Stop Android -> Mac sync
        if let task = clipboardSyncProcesses[deviceID] {
            task.terminate()
            clipboardSyncProcesses[deviceID] = nil
            print("Stopped scrcpy clipboard sync for \(deviceID)")
        }
        
        // 2. Stop Mac -> Android sync
        clipboardSyncDevices.remove(deviceID)
        if clipboardSyncDevices.isEmpty {
            stopMacClipboardObserver()
        }
    }
    
    private func startScrcpyClipboardSync(deviceID: String) {
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
            "--no-window"
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
                }
            }
        }
        
        do {
            try task.run()
            clipboardSyncProcesses[deviceID] = task
            print("Started scrcpy clipboard sync for \(deviceID)")
        } catch {
            self.error.send("Failed to start clipboard sync for \(deviceID): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Mac -> Android Clipboard Sync
    
    private func startMacClipboardObserver() {
        guard clipboardTimer == nil else { return }
        
        // Poll clipboard every 1 second
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkMacClipboard()
        }
    }
    
    private func stopMacClipboardObserver() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        lastClipboardContent = nil
    }
    
    private func checkMacClipboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            // Only sync if content changed
            if content != lastClipboardContent {
                lastClipboardContent = content
                
                // Send to all syncing devices
                for deviceID in clipboardSyncDevices {
                    sendClipboardToDevice(deviceID: deviceID, text: content)
                }
            }
        }
        #endif
    }
    
    private func sendClipboardToDevice(deviceID: String, text: String) {
        // Robustly escape the text for adb shell using single quotes.
        // We replace every single quote ' with '\'' to close the quote, insert a literal quote, and reopen the quote.
        // This allows passing any character (including spaces, newlines, double quotes, shell metacharacters) safely.
        let escapedText = text.replacingOccurrences(of: "'", with: "'\\''")
        
        // Using ch.pete.adbclipboard as requested
        // Command: adb shell am broadcast -a ch.pete.adbclipboard.WRITE -n ch.pete.adbclipboard/.WriteReceiver -e text '...'
        let command = "am broadcast -a ch.pete.adbclipboard.WRITE -n ch.pete.adbclipboard/.WriteReceiver -e text '\(escapedText)'"
        
        executeADBCommand(arguments: ["-s", deviceID, "shell", command]) { success, _, errorOutput in
            if !success {
                print("Failed to sync clipboard to \(deviceID): \(errorOutput ?? "Unknown error")")
            }
        }
    }
    
    func uninstallApp(deviceID: String, packageID: String) {
        executeADBCommand(arguments: ["-s", deviceID, "uninstall", packageID]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Refresh apps list after successful uninstall
                self.fetchApps(for: deviceID)
            } else {
                self.error.send("Failed to uninstall \(packageID): \(errorOutput ?? "Unknown error")")
            }
        }
    }
    
    func clearAppData(deviceID: String, packageID: String) {
        executeADBCommand(arguments: ["-s", deviceID, "shell", "pm", "clear", packageID]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                // Success usually returns "Success"
            } else {
                self.error.send("Failed to clear app data for \(packageID): \(errorOutput ?? "Unknown error")")
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
            alert.addButton(withTitle: "Open scrcpy GitHub")
            alert.alertStyle = .warning
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://github.com/Genymobile/scrcpy")!)
            }
        }
#endif
    }
    // MARK: - Optional Stop Mirroring Function
    func stopMirroring(deviceID: String) {
        if let task = runningScrcpyProcesses[deviceID] {
            task.terminate() // Request termination
            // The terminationHandler will handle cleanup
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
        
        executeADBCommand(arguments: ["-s", deviceID, "install", "-r", apkPath]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                self.error.send(nil) // Clear any previous errors
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
        
        executeADBCommand(arguments: ["disconnect", deviceID]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                self.listDevices()
            } else {
                self.error.send(errorOutput ?? "Failed to disconnect device")
            }
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
        executeADBCommand(arguments: ["-s", deviceID, "shell", "svc", "wifi", state]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Wi-Fi")
            }
        }
    }
    
    func toggleBluetooth(deviceID: String, enable: Bool) {
        let state = enable ? "enable" : "disable"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "svc", "bluetooth", state]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Bluetooth")
            }
        }
    }
    
    func toggleDarkMode(deviceID: String, enable: Bool) {
        let mode = enable ? "yes" : "no"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "cmd", "uimode", "night", mode]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Dark Mode")
            }
        }
    }
    
    func toggleAirplaneMode(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "settings", "put", "global", "airplane_mode_on", value]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Airplane Mode")
            } else {
                // Broadcast intent is often needed for Airplane mode to take effect immediately
                self?.executeADBCommand(arguments: ["-s", deviceID, "shell", "am", "broadcast", "-a", "android.intent.action.AIRPLANE_MODE"]) { _, _, _ in }
            }
        }
    }
    
    func toggleMobileData(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "settings", "put", "global", "mobile_data", value]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Mobile Data")
            }
        }
    }
    
    func toggleLocation(deviceID: String, enable: Bool) {
        // 3 = High Accuracy, 0 = Off
        let value = enable ? "3" : "0"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "settings", "put", "secure", "location_mode", value]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Location")
            }
        }
    }
    
    func toggleDoNotDisturb(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "cmd", "settings", "put", "global", "zen_mode", value]) { [weak self] success, _, errorOutput in
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
        executeADBCommand(arguments: ["-s", deviceID, "shell", "settings", "put", "system", "accelerometer_rotation", value]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Auto-Rotate")
            }
        }
    }
    
    func setRingerMode(deviceID: String, mode: RingerMode) {
        executeADBCommand(arguments: ["-s", deviceID, "shell", "cmd", "media_session", "set_volume_mode", mode.rawValue]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to set Ringer Mode")
            }
        }
    }
    
    func toggleAdaptiveBrightness(deviceID: String, enable: Bool) {
        let value = enable ? "1" : "0"
        executeADBCommand(arguments: ["-s", deviceID, "shell", "settings", "put", "system", "screen_brightness_mode", value]) { [weak self] success, _, errorOutput in
            if !success {
                self?.error.send(errorOutput ?? "Failed to toggle Adaptive Brightness")
            }
        }
    }
    
    func fetchQuickActionsState(deviceID: String, completion: @escaping (QuickActionsState) -> Void) {
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
                    if let val = Int(line.replacingOccurrences(of: "LOC:", with: "").trimmingCharacters(in: .whitespaces)), val > 0 {
                        state.isLocationEnabled = true
                    }
                } else if line.hasPrefix("DND:") {
                    // zen_mode: 0 = Off, 1+ = On
                    if let val = Int(line.replacingOccurrences(of: "DND:zen_mode =", with: "").trimmingCharacters(in: .whitespaces)), val > 0 {
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
}
