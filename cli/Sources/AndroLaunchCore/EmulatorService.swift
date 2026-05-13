import Foundation

// MARK: - Emulator Service

public final class EmulatorService {
    public var errorHandler: ((String) -> Void)?
    private var runningEmulatorProcesses: [String: Process] = [:]
    private var downloadProcesses: [String: Process] = [:]

    public init() {}

    // MARK: - SDK Tools Path Resolution

    public func resolveCommandLineToolsPath() -> String? {
        // Common Android SDK paths
        let candidates = [
            "\(NSHomeDirectory())/Library/Android/sdk",
            "/usr/local/share/android-sdk",
            "/opt/android-sdk",
            "\(NSHomeDirectory())/Android/Sdk",
        ]

        for path in candidates {
            let emulatorPath = "\(path)/emulator/emulator"
            if FileManager.default.fileExists(atPath: emulatorPath) {
                return path
            }
        }

        // Try to find via ANDROID_HOME or ANDROID_SDK_ROOT
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            let emulatorPath = "\(androidHome)/emulator/emulator"
            if FileManager.default.fileExists(atPath: emulatorPath) {
                return androidHome
            }
        }

        if let sdkRoot = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let emulatorPath = "\(sdkRoot)/emulator/emulator"
            if FileManager.default.fileExists(atPath: emulatorPath) {
                return sdkRoot
            }
        }

        return nil
    }

    private func resolveEmulatorPath(toolsPath: String) -> String {
        return "\(toolsPath)/emulator/emulator"
    }

    private func resolveAvdManagerPath(toolsPath: String) -> String {
        return "\(toolsPath)/cmdline-tools/latest/bin/avdmanager"
    }

    private func resolveSdkManagerPath(toolsPath: String) -> String {
        return "\(toolsPath)/cmdline-tools/latest/bin/sdkmanager"
    }

    // MARK: - List System Images

    public func listAvailableImages(toolsPath: String) throws -> [SystemImage] {
        let sdkManager = resolveSdkManagerPath(toolsPath: toolsPath)
        let (success, output, errorOutput) = executeCommand(
            executable: sdkManager,
            arguments: ["--list"]
        )
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to list system images")
        }
        return parseImages(from: output, sdkRoot: toolsPath)
    }

    // MARK: - List AVDs

    public func listAVDs(toolsPath: String) throws -> [AVD] {
        let avdManager = resolveAvdManagerPath(toolsPath: toolsPath)
        let (success, output, errorOutput) = executeCommand(
            executable: avdManager,
            arguments: ["list", "avd"]
        )
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to list AVDs")
        }
        return parseAVDs(from: output)
    }

    // MARK: - List Hardware Profiles

    public func listHardwareProfiles(toolsPath: String) throws -> [HardwareProfile] {
        let avdManager = resolveAvdManagerPath(toolsPath: toolsPath)
        let (success, output, errorOutput) = executeCommand(
            executable: avdManager,
            arguments: ["list", "device"]
        )
        guard success, let output = output else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to list hardware profiles")
        }
        return parseHardwareProfiles(output: output)
    }

    // MARK: - Create AVD

    public func createAVD(
        toolsPath: String, name: String, imagePath: String, device: String?, options: AVDOptions
    ) throws {
        let avdManager = resolveAvdManagerPath(toolsPath: toolsPath)
        var args = ["create", "avd", "-n", name, "-k", imagePath, "-f"]

        if let device = device {
            args.append(contentsOf: ["-d", device])
        }

        let input = buildAVDConfigInput(options: options)
        let (success, _, errorOutput) = executeCommandWithInput(
            executable: avdManager,
            arguments: args,
            input: input
        )
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to create AVD")
        }

        // Update config.ini with additional options
        updateAVDConfig(avdName: name, options: options)
    }

    // MARK: - Delete AVD

    public func deleteAVD(toolsPath: String, name: String) throws {
        let avdManager = resolveAvdManagerPath(toolsPath: toolsPath)
        let (success, _, errorOutput) = executeCommand(
            executable: avdManager,
            arguments: ["delete", "avd", "-n", name]
        )
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to delete AVD")
        }
    }

    // MARK: - Rename AVD

    public func renameAVD(toolsPath: String, oldName: String, newName: String) throws {
        let avdManager = resolveAvdManagerPath(toolsPath: toolsPath)
        let (success, _, errorOutput) = executeCommand(
            executable: avdManager,
            arguments: ["move", "avd", "-n", oldName, "-r", newName]
        )
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to rename AVD")
        }
    }

    // MARK: - Start Emulator

    public func startEmulator(
        toolsPath: String, avdName: String, noSkin: Bool = true, qtHideWindow: Bool = false
    ) throws
        -> Process
    {
        let emulatorPath = resolveEmulatorPath(toolsPath: toolsPath)

        var args = ["-avd", avdName]

        // Display
        if noSkin { args.append("-no-skin") }
        if qtHideWindow { args.append("-qt-hide-window") }

        // Check for GPU mode
        let gpuMode = getGpuMode(avdName: avdName)
        if let gpu = gpuMode {
            args.append(contentsOf: ["-gpu", gpu])
        } else {
            args.append(contentsOf: ["-gpu", "auto"])
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: emulatorPath)
        task.arguments = args

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                self.runningEmulatorProcesses.removeValue(forKey: avdName)
            } catch {
                self.errorHandler?("Failed to start emulator: \(error.localizedDescription)")
            }
        }

        runningEmulatorProcesses[avdName] = task
        return task
    }

    // MARK: - Stop Emulator

    public func stopEmulator(toolsPath: String, avdName: String) throws {
        let adbPath = "\(toolsPath)/platform-tools/adb"

        // Find the serial of the running emulator
        let (success, output, _) = executeCommand(
            executable: adbPath,
            arguments: ["devices"]
        )
        guard success, let output = output else { return }

        var targetSerial: String?
        for line in output.components(separatedBy: .newlines) {
            if line.contains("emulator") && line.contains("device") {
                let serial = line.components(separatedBy: .whitespaces).first ?? ""
                // Check if this emulator matches the AVD name
                let (_, avdOutput, _) = executeCommand(
                    executable: adbPath,
                    arguments: ["-s", serial, "emu", "avd", "name"]
                )
                if avdOutput?.trimmingCharacters(in: .whitespacesAndNewlines) == avdName {
                    targetSerial = serial
                    break
                }
            }
        }

        if let serial = targetSerial {
            _ = executeCommand(executable: adbPath, arguments: ["-s", serial, "emu", "kill"])
        }

        // Also terminate local process if running
        if let process = runningEmulatorProcesses[avdName] {
            process.terminate()
            runningEmulatorProcesses.removeValue(forKey: avdName)
        }
    }

    // MARK: - Download Image

    public func downloadImage(toolsPath: String, imagePath: String) throws -> Process {
        let sdkManager = resolveSdkManagerPath(toolsPath: toolsPath)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: sdkManager)
        task.arguments = [imagePath]

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                self.downloadProcesses.removeValue(forKey: imagePath)
            } catch {
                self.errorHandler?("Download failed: \(error.localizedDescription)")
            }
        }

        downloadProcesses[imagePath] = task
        return task
    }

    public func cancelDownload(imagePath: String) {
        if let process = downloadProcesses[imagePath] {
            process.terminate()
            downloadProcesses.removeValue(forKey: imagePath)
        }
    }

    // MARK: - Delete Image

    public func deleteImage(toolsPath: String, imagePath: String) throws {
        let sdkManager = resolveSdkManagerPath(toolsPath: toolsPath)
        let (success, _, errorOutput) = executeCommand(
            executable: sdkManager,
            arguments: ["--uninstall", imagePath]
        )
        guard success else {
            throw ADBError.commandFailed(errorOutput ?? "Failed to delete image")
        }
    }

    // MARK: - Private Helpers

    private func executeCommand(executable: String, arguments: [String]) -> (
        success: Bool, output: String?, errorOutput: String?
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)

            return (task.terminationStatus == 0, output, errorOutput)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    private func executeCommandWithInput(executable: String, arguments: [String], input: String)
        -> (success: Bool, output: String?, errorOutput: String?)
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.standardInput = inputPipe

        do {
            try task.run()

            // Write input
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                inputPipe.fileHandleForWriting.closeFile()
            }

            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)

            return (task.terminationStatus == 0, output, errorOutput)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    // MARK: - Parsing

    private func parseImages(from output: String, sdkRoot: String) -> [SystemImage] {
        var images = [SystemImage]()
        var currentId: String?
        var currentDescription: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("system-images") {
                currentId = trimmed
                currentDescription = nil
            } else if let id = currentId, trimmed.hasPrefix("Description:") {
                currentDescription = String(trimmed.dropFirst("Description:".count))
                    .trimmingCharacters(in: .whitespaces)
                let imagePath =
                    "\(sdkRoot)/system-images/\(id.replacingOccurrences(of: "system-images;", with: "").replacingOccurrences(of: ";", with: "/"))"
                let isDownloaded = FileManager.default.fileExists(atPath: imagePath)
                images.append(
                    SystemImage(
                        id: id, description: currentDescription ?? id, isDownloaded: isDownloaded,
                        sizeBytes: nil))
                currentId = nil
            }
        }
        return images
    }

    private func parseAVDs(from output: String) -> [AVD] {
        var avds = [AVD]()
        var currentName: String?
        var currentDevice: String?
        var currentPath: String?
        var currentTarget: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Name:") {
                if let name = currentName {
                    avds.append(
                        AVD(
                            name: name, device: currentDevice, path: currentPath,
                            target: currentTarget))
                }
                currentName = String(trimmed.dropFirst("Name:".count)).trimmingCharacters(
                    in: .whitespaces)
                currentDevice = nil
                currentPath = nil
                currentTarget = nil
            } else if trimmed.hasPrefix("Device:") {
                currentDevice = String(trimmed.dropFirst("Device:".count)).trimmingCharacters(
                    in: .whitespaces)
            } else if trimmed.hasPrefix("Path:") {
                currentPath = String(trimmed.dropFirst("Path:".count)).trimmingCharacters(
                    in: .whitespaces)
            } else if trimmed.hasPrefix("Target:") {
                currentTarget = String(trimmed.dropFirst("Target:".count)).trimmingCharacters(
                    in: .whitespaces)
            }
        }

        if let name = currentName {
            avds.append(
                AVD(name: name, device: currentDevice, path: currentPath, target: currentTarget))
        }

        return avds
    }

    private func parseHardwareProfiles(output: String) -> [HardwareProfile] {
        var profiles = [HardwareProfile]()
        var currentId: String?
        var currentName: String?
        var currentOem: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("id:") || trimmed.hasPrefix("ID:") {
                if let id = currentId {
                    profiles.append(
                        HardwareProfile(
                            id: id, name: currentName ?? id, oem: currentOem, width: nil,
                            height: nil, density: nil))
                }
                let val = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
                // Extract number after "or" if present
                currentId = val.components(separatedBy: " ").first ?? val
                currentName = val.contains("\"") ? val : nil
                currentOem = nil
            } else if trimmed.hasPrefix("Name:") {
                currentName = String(trimmed.dropFirst("Name:".count)).trimmingCharacters(
                    in: .whitespaces)
            } else if trimmed.hasPrefix("OEM:") {
                currentOem = String(trimmed.dropFirst("OEM:".count)).trimmingCharacters(
                    in: .whitespaces)
            }
        }

        if let id = currentId {
            profiles.append(
                HardwareProfile(
                    id: id, name: currentName ?? id, oem: currentOem, width: nil, height: nil,
                    density: nil))
        }

        return profiles
    }

    // MARK: - AVD Config

    private func buildAVDConfigInput(options: AVDOptions) -> String {
        // The avdmanager may ask for custom hardware profile
        // We answer "no" by default (use the selected device profile)
        return "no\n"
    }

    private func updateAVDConfig(avdName: String, options: AVDOptions) {
        let homeDir = NSHomeDirectory()
        let configPath = "\(homeDir)/.android/avd/\(avdName).avd/config.ini"

        guard FileManager.default.fileExists(atPath: configPath),
            var lines = try? String(contentsOfFile: configPath, encoding: .utf8).components(
                separatedBy: .newlines)
        else { return }

        func updateOrAdd(key: String, value: String) {
            var found = false
            for i in 0..<lines.count {
                if lines[i].hasPrefix("\(key)=") {
                    lines[i] = "\(key)=\(value)"
                    found = true
                    break
                }
            }
            if !found {
                lines.append("\(key)=\(value)")
            }
        }

        if let ram = options.ramMB { updateOrAdd(key: "hw.ramSize", value: "\(ram)") }
        if let heap = options.heapMB { updateOrAdd(key: "vm.heapSize", value: "\(heap)") }
        if let storage = options.storageMB {
            updateOrAdd(key: "disk.dataPartition.size", value: "\(storage)M")
        }
        if let width = options.width { updateOrAdd(key: "hw.lcd.width", value: "\(width)") }
        if let height = options.height { updateOrAdd(key: "hw.lcd.height", value: "\(height)") }
        if let density = options.density { updateOrAdd(key: "hw.lcd.density", value: "\(density)") }
        if let sdCard = options.sdCardMB { updateOrAdd(key: "hw.sdCard.size", value: "\(sdCard)M") }
        if let camera = options.cameraBack { updateOrAdd(key: "hw.camera.back", value: camera) }
        if let gps = options.gps { updateOrAdd(key: "hw.gps", value: gps ? "yes" : "no") }
        if let keyboard = options.keyboard {
            updateOrAdd(key: "hw.keyboard", value: keyboard ? "yes" : "no")
        }
        if let gpu = options.gpuMode { updateOrAdd(key: "hw.gpu.mode", value: gpu) }

        try? lines.joined(separator: "\n").write(
            toFile: configPath, atomically: true, encoding: .utf8)
    }

    private func getGpuMode(avdName: String) -> String? {
        let homeDir = NSHomeDirectory()
        let configPath = "\(homeDir)/.android/avd/\(avdName).avd/config.ini"

        guard FileManager.default.fileExists(atPath: configPath),
            let content = try? String(contentsOfFile: configPath, encoding: .utf8)
        else { return nil }

        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix("hw.gpu.mode=") {
                return String(line.dropFirst("hw.gpu.mode=".count))
            }
        }
        return nil
    }
}
