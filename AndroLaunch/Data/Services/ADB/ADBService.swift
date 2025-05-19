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
    let apps = PassthroughSubject<[AndroidApp], Never>()
    let error = PassthroughSubject<String?, Never>()

    // MARK: - Internal State
    private var currentADBPath: String?
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
        print("ADBService: Initializing...")
    }

    // MARK: - Private Helper: Execute Shell Command (For ADB commands like list, start-server, fetch packages)
    private func executeADBCommand(arguments: [String], path: String? = nil, completion: @escaping (Bool, String?, String?) -> Void) {
        guard let adbPath = path ?? currentADBPath else {
            print("ExecuteADBCommand failed: ADB executable path not set.")
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
                    print("Executed ADB Command: \(adbPath) \(arguments.joined(separator: " "))")
                    print("Output: \(output ?? "nil")")
                    print("Error: \(errorOutput ?? "nil")")
                    print("Termination Status: \(task.terminationStatus)")

                    let success = task.terminationStatus == 0

                    completion(success, output, errorOutput)
                }
            } catch {
                DispatchQueue.main.async {
                    print("Process execution error for \(adbPath) \(arguments.joined(separator: " ")): \(error.localizedDescription)")
                    completion(false, nil, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private Helper: Find SCRCPY Executable
    private func findScrcpyPath() -> String? {
         print("Attempting to find scrcpy...")
         for path in scrcpyPaths {
             print("Checking scrcpy path: \(path)")
             if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                 print("SCRCPY found at: \(path)")
                 return path
             }
         }
         print("SCRCPY not found in any specified paths.")
         return nil
     }


    // MARK: - ADB Path Discovery
    func findADB() {
        print("Attempting to find ADB...")
        for path in systemADBPaths {
            print("Checking path: \(path)")
            if FileManager.default.isExecutableFile(atPath: path) {
                print("ADB found at: \(path)")
                currentADBPath = path
                error.send(nil)
                startADBDaemon()
                return
            }
        }
        print("ADB not found in any specified paths.")
        let notFoundError = "ADB not found. Install Android Platform Tools."
        error.send(notFoundError)
        devices.send([])
        currentADBPath = nil
    }

    func startADBDaemon() {
        guard let adbPath = currentADBPath else {
             print("Cannot start daemon, ADB path not set.")
            return
        }
        print("Starting ADB daemon...")
        // Use executeADBCommand for the standard ADB start-server command
        executeADBCommand(arguments: ["start-server"], path: adbPath) { [weak self] success, _, errorOutput in
            guard let self else { return }
            if success {
                print("ADB daemon started successfully.")
                // Daemon might take a moment, add a small delay before listing devices
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                     self.listDevices()
                }
            } else {
                print("ADB daemon failed to start. Error: \(errorOutput ?? "Unknown error")")
                self.error.send(errorOutput ?? "ADB daemon failed to start")
                self.devices.send([])
            }
        }
    }

    // MARK: - Device Listing
    func listDevices() {
        guard currentADBPath != nil else {
            print("ADB path not set, cannot list devices.")
            return
        }
        print("Executing 'adb devices -l'...")
         // Use executeADBCommand for the standard ADB devices command
        executeADBCommand(arguments: ["devices", "-l"]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            if success {
                print("Raw ADB devices output: \(output ?? "nil")")
                let devices = self.parseDevices(from: output ?? "")
                print("Parsed devices: \(devices)")
                self.devices.send(devices)
                self.error.send(nil)
            } else {
                print("ADB devices command failed. Error: \(errorOutput ?? "Unknown error")")
                self.error.send(errorOutput ?? "Device listing failed")
                self.devices.send([])
          }
        }
    }

    // MARK: - Private Helper: Parse ADB Devices Output
    private func parseDevices(from output: String) -> [AndroidDevice] {
        let pattern = #"^(\S+)\s+(device|unauthorized|offline|no permissions)\s*(.*)$"# // Adjusted regex slightly for end of line
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
             print("Failed to create regex for device parsing.")
            return []
        }
        var devices = [AndroidDevice]()

        output.enumerateLines { line, _ in
            guard !line.lowercased().contains("list of devices attached") && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges >= 3 else {
                 print("Line did not match device pattern: \(line)")
                return
            }

            let idRange = match.range(at: 1)
            let stateRange = match.range(at: 2)
            let detailsRange = match.range(at: 3)

            guard let id = Range(idRange, in: line),
                  let state = Range(stateRange, in: line) else {
                 print("Could not extract ID or state from line: \(line)")
                return
            }

            let deviceID = String(line[id])
            let deviceState = String(line[state])
            var modelName = "Android Device"

            if let detailsRng = Range(detailsRange, in: line) {
                let details = String(line[detailsRng])
                let modelPattern = #"model:([^\s]+)"#
                if let modelMatch = try? NSRegularExpression(pattern: modelPattern)
                    .firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
                    let modelRng = Range(modelMatch.range(at: 1), in: details) {
                    modelName = String(details[modelRng]).replacingOccurrences(of: "_", with: " ")
                }
            }

            // Only add devices that are successfully connected
            if deviceState == "device" {
                devices.append(AndroidDevice(
                    id: deviceID,
                    name: modelName,
                    isConnected: true
                ))
                 print("Found connected device: \(deviceID) (\(modelName))")
            } else {
                print("Found device in state \(deviceState): \(deviceID)")
            }
        }

        return devices
    }


    // MARK: - App Listing
    func fetchApps(for deviceID: String) {
        guard let adbPath = currentADBPath else {
            print("ADB path not set, cannot fetch apps.")
            return
        }
        
        print("Fetching apps for device: \(deviceID)")
        // List all apps including system and user-installed
        executeADBCommand(arguments: ["-s", deviceID, "shell", "pm", "list", "packages"]) { [weak self] success, output, errorOutput in
            guard let self else { return }
            
            if success {
                print("Raw app list output: \(output ?? "nil")")
                let apps = self.parseApps(from: output ?? "", deviceID: deviceID)
                print("Parsed apps: \(apps)")
                self.apps.send(apps)
                self.error.send(nil)
            } else {
                print("App listing failed. Error: \(errorOutput ?? "Unknown error")")
                self.error.send(errorOutput ?? "App listing failed")
                self.apps.send([])
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
            print("❌ Could not find package_names_mapping.json in bundle")
            packageMapping = [:]
            return []
        }
        
        print("🔍 Looking for package mapping file at: \(jsonPath)")
        
        if fileManager.fileExists(atPath: jsonPath) {
            print("📂 Found package mapping file")
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                print("📄 Successfully read file data: \(data.count) bytes")
                if let mapping = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    packageMapping = mapping
                    print("✅ Successfully parsed JSON with \(mapping.count) entries")
                } else {
                    print("❌ Failed to parse JSON data")
                    packageMapping = [:]
                }
            } catch {
                print("❌ Failed to read file data: \(error.localizedDescription)")
                packageMapping = [:]
            }
        } else {
            print("❌ Could not find package mapping file at path: \(jsonPath)")
            packageMapping = [:]
        }
        
        print("📱 Processing \(lines.count) package names from device")
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Parse the output format: package:com.example.app
            let components = line.components(separatedBy: ":")
            guard components.count == 2 else { continue }
            
            // Extract package name from the right side of the colon
            let packageName = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Debug logging for each package
            if let appInfo = packageMapping[packageName] {
                print("📦 Found mapping for \(packageName): \(appInfo)")
            } else {
                print("⚠️ No mapping found for package: \(packageName)")
            }
            
            // Only include if in mapping and not background
            guard let appInfo = packageMapping[packageName],
                  let isBackground = appInfo["is_background"] as? Bool,
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
        }
        
        print("🎯 Final app list contains \(apps.count) apps")
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

    // MARK: - App Launching & Mirroring (using SCRCPY)
    func launchApp(packageID: String, deviceID: String) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot launch app with scrcpy."
            print("LaunchApp failed: \(errorMessage)")
            self.error.send(errorMessage)
            self.findADB()
            return
        }

        guard let scrcpyPath = findScrcpyPath() else {
            let errorMessage = """
            SCRCPY executable not found.
            Please install scrcpy (e.g., `brew install scrcpy` on macOS).
            """
            print("LaunchApp failed: \(errorMessage)")
            self.error.send(errorMessage)
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

        print("Attempting to launch app \(packageID) on device \(deviceID) using scrcpy...")




        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = [
            "--serial", deviceID,
            "--stay-awake",
            "-S",
            "--window-title", "\(packageID)",
            "--new-display",
            "-m 900",
            "--no-audio",
            "--keyboard=aoa",
            "--start-app", packageID
        ]

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
                 // End of file - scrcpy process likely terminated
                 print("End of SCRCPY error output for \(deviceID).")
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
            print("✅ SCRCPY process launched successfully for device \(deviceID) to launch app \(packageID).")


        } catch {
            // Error launching the process itself (e.g., scrcpy path invalid, permissions)
            let errorMessage = "Failed to launch SCRCPY process for \(deviceID): \(error.localizedDescription)"
            print("❌ \(errorMessage)")
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

    // MARK: - Optional Mirroring Function
     // Mirrors the entire device screen using scrcpy (without launching a specific app)
     func mirrorDevice(deviceID: String) {
         guard let adbPath = currentADBPath else {
             let errorMessage = "ADB executable path not set. Cannot mirror device with scrcpy."
             print("MirrorDevice failed: \(errorMessage)")
             self.error.send(errorMessage)
             self.findADB() // Attempt to find ADB
             return
         }

         guard let scrcpyPath = findScrcpyPath() else {
             let errorMessage = """
             SCRCPY executable not found.
             Please install scrcpy (e.g., `brew install scrcpy` on macOS).
             """
             print("MirrorDevice failed: \(errorMessage)")
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

         print("Attempting to mirror device \(deviceID) using scrcpy...")


         let task = Process()
         task.executableURL = URL(fileURLWithPath: scrcpyPath)

         // scrcpy arguments for mirroring
         task.arguments = ["--serial", deviceID, "--window-title", "\(deviceID)"]

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
                      // print("SCRCPY Error Output (\(deviceID)): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                  }
                  errorFileHandle.readInBackgroundAndNotify()
              } else {
                  print("End of SCRCPY error output for \(deviceID).")
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
                 print("SCRCPY process for \(deviceID) terminated with status \(exitCode)")

                 let collectedErrorOutput = self.scrcpyErrorOutputs[deviceID] ?? "No error output captured."

                 self.runningScrcpyProcesses[deviceID] = nil
                 self.scrcpyErrorOutputs[deviceID] = nil

                 if exitCode != 0 {
                     let errorMessage = "SCRCPY mirroring failed for device \(deviceID) (Exit code: \(exitCode)).\nError Output:\n\(collectedErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                     print("❌ \(errorMessage)")
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
                 } else {
                     print("SCRCPY mirroring for \(deviceID) exited cleanly.")
                 }
                 if let obs = self.scrcpyErrorPipeHandlers.removeValue(forKey: deviceID) as? NSObjectProtocol {
                     NotificationCenter.default.removeObserver(obs)
                 }
             }
         }

         do {
             try task.run()
             runningScrcpyProcesses[deviceID] = task
             print("✅ SCRCPY mirroring process launched successfully for device \(deviceID).")

         } catch {
             let errorMessage = "Failed to launch SCRCPY mirroring process for \(deviceID): \(error.localizedDescription)"
             print("❌ \(errorMessage)")
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
            print("Attempting to terminate SCRCPY process for device \(deviceID)...")
            task.terminate() // Request termination
            // The terminationHandler will handle cleanup
        } else {
            print("No running SCRCPY process found for device \(deviceID).")
        }
    }
}
