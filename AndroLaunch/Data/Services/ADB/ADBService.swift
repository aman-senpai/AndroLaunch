//
//  ADBService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import Foundation
#if canImport(AppKit)
import AppKit // Needed for NSAlert and NSWorkspace
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
    private var scrcpyErrorPipeHandlers: [String: Any] = [:] // Dictionary to hold observation tokens/handlers keyed by device ID
    private var scrcpyErrorOutputs: [String: String] = [:] // Dictionary to collect error output keyed by device ID
    private var runningScrcpyProcesses: [String: Process] = [:] // To keep track of running scrcpy processes

    // MARK: - Executable Path Discovery

    // Common system paths for ADB
    private var systemADBPaths: [String] {
        [
            "/opt/homebrew/bin/adb", // Homebrew default
            "/usr/local/bin/adb",    // Older Homebrew or manual install
            "/usr/bin/adb",          // Sometimes in system path (less common for adb)
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb", // Android Studio SDK default
            "/Library/Android/sdk/platform-tools/adb" // System-wide SDK? (less common)
        ]
    }

    // Common system paths for SCRCPY
    private var scrcpyPaths: [String] {
        [
            "/opt/homebrew/bin/scrcpy", // Homebrew default
            "/usr/local/bin/scrcpy",    // Older Homebrew or manual install
            "\(NSHomeDirectory())/.local/bin/scrcpy", // User bin
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy" // App bundle location
        ]
    }

    // MARK: - Initialization
    init() {
        print("ADBService: Initializing...")
        // Initial ADB discovery can be triggered here or externally.
        // For this setup, it's assumed to be called by refreshDevices() or similar.
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
                // Wait for ADB commands to finish. This is appropriate for non-interactive commands.
                task.waitUntilExit()

                let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8)
                let errorOutput = String(data: errorData, encoding: .utf8)

                // Deliver the result back to the main thread
                DispatchQueue.main.async {
                    print("Executed ADB Command: \(adbPath) \(arguments.joined(separator: " "))") // Debug print
                    print("Output: \(output ?? "nil")") // Debug print
                    print("Error: \(errorOutput ?? "nil")") // Debug print
                    print("Termination Status: \(task.terminationStatus)") // Debug print

                    let success = task.terminationStatus == 0 // Basic check

                    completion(success, output, errorOutput)
                }
            } catch {
                DispatchQueue.main.async {
                    print("Process execution error for \(adbPath) \(arguments.joined(separator: " ")): \(error.localizedDescription)") // Debug print
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
        for path in systemADBPaths { // Use system paths from this service
            print("Checking path: \(path)")
            if FileManager.default.isExecutableFile(atPath: path) {
                print("ADB found at: \(path)")
                currentADBPath = path
                error.send(nil) // Clear previous ADB not found error
                startADBDaemon() // Start daemon once found
                return
            }
        }
        print("ADB not found in any specified paths.")
        let notFoundError = "ADB not found. Install Android Platform Tools."
        error.send(notFoundError)
        devices.send([]) // Ensure device list is empty if ADB not found
        currentADBPath = nil
    }

    func startADBDaemon() {
        guard let adbPath = currentADBPath else {
             print("Cannot start daemon, ADB path not set.") // Debug print
            return // Should not happen if findADB was successful
        }
        print("Starting ADB daemon...")
        // Use executeADBCommand for the standard ADB start-server command
        executeADBCommand(arguments: ["start-server"], path: adbPath) { [weak self] success, _, errorOutput in
            guard let self else { return }
            if success {
                print("ADB daemon started successfully.")
                // Daemon might take a moment, add a small delay before listing devices
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Add a small delay
                     self.listDevices() // Proceed to list devices if daemon starts
                }
            } else {
                print("ADB daemon failed to start. Error: \(errorOutput ?? "Unknown error")")
                self.error.send(errorOutput ?? "ADB daemon failed to start")
                self.devices.send([]) // Send empty devices on error
            }
        }
    }

    // MARK: - Device Listing
    func listDevices() {
        guard currentADBPath != nil else {
            print("ADB path not set, cannot list devices.")
            // Error already sent by findADB or startADBDaemon
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
                self.error.send(nil) // Clear any previous errors on success
            } else {
                print("ADB devices command failed. Error: \(errorOutput ?? "Unknown error")")
                self.error.send(errorOutput ?? "Device listing failed")
                self.devices.send([]) // Send empty devices list on error
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
            guard !line.lowercased().contains("list of devices attached") && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return } // Skip header and empty lines

            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges >= 3 else {
                 print("Line did not match device pattern: \(line)") // Debug unmatched lines
                return
            }

            let idRange = match.range(at: 1)
            let stateRange = match.range(at: 2)
            let detailsRange = match.range(at: 3) // Optional details range

            guard let id = Range(idRange, in: line),
                  let state = Range(stateRange, in: line) else {
                 print("Could not extract ID or state from line: \(line)")
                return
            }

            let deviceID = String(line[id])
            let deviceState = String(line[state])
            var modelName = "Android Device" // Default name

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
                    isConnected: true // State is "device"
                ))
                 print("Found connected device: \(deviceID) (\(modelName))") // Debug found device
            } else {
                print("Found device in state \(deviceState): \(deviceID)") // Debug non-connected states
                // You could add devices in 'unauthorized' state with isConnected: false
                // devices.append(AndroidDevice(id: deviceID, name: modelName, isConnected: false))
            }
        }

        return devices // Returning all parsed devices, filter in VM/Repo if only 'device' state is needed
    }


    // MARK: - App Listing
    func fetchApps(for deviceID: String) {
         guard currentADBPath != nil else {
             self.error.send("ADB not found or not set.")
             self.apps.send([])
             return
         }
         print("Fetching apps for device: \(deviceID)")
         // Clear previous apps immediately on the main thread
         DispatchQueue.main.async {
             self.apps.send([])
         }

         // Use executeADBCommand for the standard ADB shell command
         // Added -3 to list only third-party apps, like in the DeviceManager example
         executeADBCommand(arguments: ["-s", deviceID, "shell", "pm", "list", "packages", "-3"], completion: { [weak self] success, output, errorOutput in
             guard let self else { return }
             if success {
                 // Basic parsing: extract package names
                 let packageLines = output?.split(separator: "\n") ?? []
                 let apps = packageLines.compactMap { line -> AndroidApp? in
                     let lineString = String(line) // Ensure it's a String
                     if lineString.starts(with: "package:") {
                         let packageName = String(lineString.dropFirst("package:".count)).trimmingCharacters(in: .whitespacesAndNewlines) // Trim whitespace
                         // Use package name as the app name for now
                         return AndroidApp(id: packageName, name: packageName)
                     }
                     return nil
                 }
                 print("Fetched and parsed \(apps.count) apps.")
                 self.apps.send(apps)
                 self.error.send(nil) // Clear any previous errors on success
             } else {
                 print("Fetching apps failed. Error: \(errorOutput ?? "Unknown error")")
                 self.error.send(errorOutput ?? "Failed to fetch apps for \(deviceID)")
                 self.apps.send([])
             }
         })
     }

    // MARK: - App Launching & Mirroring (using SCRCPY)
    func launchApp(packageID: String, deviceID: String) {
        guard let adbPath = currentADBPath else {
            let errorMessage = "ADB executable path not set. Cannot launch app with scrcpy."
            print("LaunchApp failed: \(errorMessage)")
            self.error.send(errorMessage)
            // Optionally attempt to find ADB again
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
            // Optionally show an alert directly from here if needed, or rely on UI observing the error publisher
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
            "--window-title", "Running: \(packageID)",
            "--new-display=720x1400", // Added resolution argument
            "--start-app", packageID
        ]

        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adbPath // Explicitly tell scrcpy where to find adb
        // Ensure common binary paths are in the PATH for scrcpy if it needs other tools
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
         task.arguments = ["--serial", deviceID, "--no-audio", "--window-title", "Mirroring \(deviceID)"]

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
