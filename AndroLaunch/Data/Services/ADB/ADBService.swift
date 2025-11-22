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
                let devices = self.parseDevices(from: output ?? "")
                self.devices.send(devices)
                self.error.send(nil)
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
            if let range = cleanDeviceID.range(of: ".:") {
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
                        serialNumber: serialNumber
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
        guard let adbPath = currentADBPath else {
            error.send("ADB path not set, cannot fetch apps.")
            return
        }
        
        // List all apps including system and user-installed
        executeADBCommand(arguments: ["-s", deviceID, "shell", "pm", "list", "packages"]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            
            if success {
                let apps = self.parseApps(from: output ?? "", deviceID: deviceID)
                // Emit deviceID along with the app list
                self.apps.send((deviceID, apps))
                self.error.send(nil)
            } else {
                self.error.send(errorOutput ?? "App listing failed")
                self.apps.send((deviceID, [])) // Emit empty array with deviceID on failure
            }
        }
    }
    
    private func parseApps(from output: String, deviceID: String) -> [AndroidApp] {
        var apps: [AndroidApp] = []
        let lines = output.components(separatedBy: .newlines)
        
        // Read package names mapping from Data/Resources directory
        let packageMapping: [String: [String: Any]]
        let fileManager = FileManager.default
        
        // Use bundle path for the JSON file
        let bundle = Bundle.main
        guard let jsonPath = bundle.path(forResource: "package_names_mapping", ofType: "json") else {
            packageMapping = [:]
            return []
        }
                
        if fileManager.fileExists(atPath: jsonPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                if let mapping = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    packageMapping = mapping
                } else {
                    packageMapping = [:]
                }
            } catch {
                packageMapping = [:]
            }
        } else {
            packageMapping = [:]
        }
        
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Parse the output format: package:com.example.app
            let components = line.components(separatedBy: ":")
            guard components.count == 2 else { continue }
            
            // Extract package name from the right side of the colon
            let packageName = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Debug logging for each package
            if let appInfo = packageMapping[packageName] {
                
                // Only include if in mapping and not background
                guard let isBackground = appInfo["is_background"] as? Bool,
                      isBackground == false,
                      let appName = appInfo["name"] as? String else {
                    continue
                }
                
                let app = AndroidApp(
                    id: packageName,
                    name: appName,
                    iconName: "android",
                    packageName: packageName
                )
                apps.append(app)
                
            } else {
                self.error.send("⚠️ No mapping found for package: \(packageName), using formatted name")
                
                // Fallback for unmapped apps
                let appName = formatPackageName(packageName)
                let app = AndroidApp(
                    id: packageName,
                    name: appName,
                    iconName: "android",
                    packageName: packageName
                )
                apps.append(app)
            }
        }
        
        return apps.sorted { $0.name < $1.name }
    }
    
    private func formatPackageName(_ packageName: String) -> String {
        var name = packageName
        
        // Remove common prefixes
        if name.hasPrefix("com.") {
            name = String(name.dropFirst(4))
        } else if name.hasPrefix("org.") {
            name = String(name.dropFirst(4))
        }
        
        // Replace dots and underscores with spaces
        name = name.replacingOccurrences(of: ".", with: " ")
                   .replacingOccurrences(of: "_", with: " ")
        
        // Capitalize each word
        return name.capitalized
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

    // MARK: - App Launching & Mirroring (using SCRCPY)
    func launchApp(packageID: String, deviceID: String, audioEnabled: Bool, resolution: Int) {
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
        if let range = cleanDeviceID.range(of: ".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        var args = [
            "--serial", cleanDeviceID,
            "--stay-awake",
            "--window-title", "\(packageID)",
            "--new-display",
            "-m \(resolution)",
            "--start-app", packageID,
            "--audio-bit-rate=10000",
            "--audio-output-buffer=10"
        ]
        
        if !audioEnabled {
            args.append("--no-audio")
        }
        
        // --keyboard=aoa only works over USB
        // Check for IP:Port format OR mDNS service names (containing _tcp or _udp)
        let isWireless = cleanDeviceID.contains(":") || 
                        cleanDeviceID.contains("_tcp") || 
                        cleanDeviceID.contains("_udp")
        
        if !isWireless {
            args.append("--keyboard=aoa")
        } else {
            self.error.send("Wireless device detected (\(cleanDeviceID)), skipping --keyboard=aoa")
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
        if let range = cleanDeviceID.range(of: ".:") {
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
     func mirrorDevice(deviceID: String, audioEnabled: Bool) {
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
         var args = ["--serial", deviceID, "--window-title", "\(deviceID)"]
         if !audioEnabled {
             args.append("--no-audio")
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

}
