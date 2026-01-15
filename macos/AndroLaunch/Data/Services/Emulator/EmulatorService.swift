//
//  EmulatorService.swift
//  AndroLaunch
//
//  Created by AndroLaunch on 16/1/26.
//

import Combine
import Foundation

final class EmulatorService: EmulatorServiceProtocol {
    private let imagesSubject = PassthroughSubject<[SystemImage], Never>()
    private let avdsSubject = PassthroughSubject<[AVD], Never>()
    private let downloadProgressSubject = PassthroughSubject<(String, Double), Never>()
    private let errorSubject = PassthroughSubject<String?, Never>()
    
    var imagesPublisher: AnyPublisher<[SystemImage], Never> { imagesSubject.eraseToAnyPublisher() }
    var avdsPublisher: AnyPublisher<[AVD], Never> { avdsSubject.eraseToAnyPublisher() }
    var downloadProgress: AnyPublisher<(String, Double), Never> { downloadProgressSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<String?, Never> { errorSubject.eraseToAnyPublisher() }
    
    private var cancellables = Set<AnyCancellable>()
    private var startingAVDs = Set<String>()
    private var downloadProcesses: [String: Process] = [:]
    private let downloadQueue = DispatchQueue(label: "com.androlaunch.downloadQueue")
    
    // MARK: - List Available Images
    func listAvailableImages(toolsPath: String) {
        let sdkManagerPath = (toolsPath as NSString).appendingPathComponent("sdkmanager")
        let sdkRoot = getSDKRoot(from: toolsPath)
        
        print("[EmulatorService] listAvailableImages: sdkManagerPath=\(sdkManagerPath), sdkRoot=\(sdkRoot)")
        
        executeCommand(executable: sdkManagerPath, arguments: ["--list", "--sdk_root=\(sdkRoot)"]) { [weak self] success, output, errorOutput in
            guard let self = self else { return }
            print("[EmulatorService] listAvailableImages completed: success=\(success), outputLength=\(output?.count ?? 0), errorLength=\(errorOutput?.count ?? 0)")
            if success {
                let images = self.parseImages(from: output ?? "", sdkRoot: sdkRoot)
                print("[EmulatorService] parsed \(images.count) images")
                if images.isEmpty && !(output ?? "").isEmpty {
                     self.errorSubject.send("No compatible images found. Check if your architecture (\(self.getSystemArchitecture())) is supported by available images.")
                }
                self.imagesSubject.send(images)
            } else {
                print("[EmulatorService] ERROR: \(errorOutput ?? "unknown")")
                self.errorSubject.send(errorOutput ?? "Failed to list images")
                // Send empty to stop the spinner
                self.imagesSubject.send([])
            }
        }
    }
    
    // MARK: - List AVDs
    func listAVDs(toolsPath: String) {
        let avdManagerPath = (toolsPath as NSString).appendingPathComponent("avdmanager")
        
        // print("[EmulatorService] listAVDs: avdManagerPath=\(avdManagerPath)")
        
        executeCommand(executable: avdManagerPath, arguments: ["list", "avd"]) { [weak self] success, output, errorOutput in
            // print("[EmulatorService] listAVDs callback: success=\(success), output=\(output?.prefix(200) ?? "nil"), error=\(errorOutput?.prefix(500) ?? "nil")")
            
            guard let self = self else {
                print("[EmulatorService] listAVDs: self is nil!")
                return
            }
            
            if success {
                let avds = self.parseAVDs(from: output ?? "")
                
                // Now check which ones are running
                self.detectRunningAVDs(toolsPath: toolsPath, avds: avds) { updatedAVDs in
                    self.avdsSubject.send(updatedAVDs)
                }
            } else {
                // avdmanager returns status=1 when there are no AVDs, but also on real errors
                // Check if output suggests "no avds" vs a real error
                let out = output ?? ""
                let err = errorOutput ?? ""
                
                if err.contains("Exception") || err.contains("Error") {
                    print("[EmulatorService] listAVDs REAL ERROR: \(err)")
                    // Don't send this to UI yet as it might be transient or noise
                }
                
                // Parse anyway - might have partial output
                let avds = self.parseAVDs(from: out)
                self.avdsSubject.send(avds)
            }
        }
    }
    
    // MARK: - Directory Size Calculation
    private func calculateDirectorySize(path: String) -> Int64? {
        guard let url = URL(string: path) else { return nil }
        
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Hardware Profiles
    func listHardwareProfiles(toolsPath: String, completion: @escaping ([HardwareProfile]) -> Void) {
        let avdManagerPath = (toolsPath as NSString).appendingPathComponent("avdmanager")
        executeCommand(executable: avdManagerPath, arguments: ["list", "device"]) { success, output, _ in
            guard success, let output = output else {
                completion([])
                return
            }
            
            let profiles = self.parseHardwareProfiles(output: output)
            completion(profiles)
        }
    }
    
    private func parseHardwareProfiles(output: String) -> [HardwareProfile] {
        var profiles = [HardwareProfile]()
        let blocks = output.components(separatedBy: "---------")
        
        // Regex to match: id: 45 or "pixel_9"
        let idRegex = try? NSRegularExpression(pattern: #"id: \d+ or "([^"]+)""#)
        // Regex to match: Name: Pixel 9
        let nameRegex = try? NSRegularExpression(pattern: #"Name: (.+)$"#)
        // Regex to match: OEM : Google
        let oemRegex = try? NSRegularExpression(pattern: #"OEM\s+:\s+(.+)$"#)
        // Regex to match: Resolution: 1080x2400
        let resRegex = try? NSRegularExpression(pattern: #"Resolution\s*:\s*(\d+)x(\d+)"#)
        // Regex to match: Density: 420
        let densityRegex = try? NSRegularExpression(pattern: #"Density\s*:\s*(\d+)"#)
        
        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            var id: String?
            var name: String?
            var oem: String?
            var width: Int?
            var height: Int?
            var density: Int?
            
            let lines = trimmed.components(separatedBy: .newlines)
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                
                if let match = idRegex?.firstMatch(in: line, range: range),
                   let r = Range(match.range(at: 1), in: line) {
                    id = String(line[r])
                } else if let match = nameRegex?.firstMatch(in: line, range: range),
                   let r = Range(match.range(at: 1), in: line) {
                    name = String(line[r])
                } else if let match = oemRegex?.firstMatch(in: line, range: range),
                   let r = Range(match.range(at: 1), in: line) {
                    oem = String(line[r])
                } else if let match = resRegex?.firstMatch(in: line, range: range),
                          let wRange = Range(match.range(at: 1), in: line),
                          let hRange = Range(match.range(at: 2), in: line) {
                    width = Int(String(line[wRange]))
                    height = Int(String(line[hRange]))
                } else if let match = densityRegex?.firstMatch(in: line, range: range),
                          let r = Range(match.range(at: 1), in: line) {
                    density = Int(String(line[r]))
                }
            }
            
            if let id = id, let name = name {
                profiles.append(HardwareProfile(id: id, name: name, oem: oem, width: width, height: height, density: density))
            }
        }
        
        return profiles.sorted { $0.name < $1.name }
    }

    // MARK: - Create AVD
    func createAVD(toolsPath: String, name: String, imagePath: String, device: String?, options: AVDOptions) {
        let avdManagerPath = (toolsPath as NSString).appendingPathComponent("avdmanager")
        var args = ["create", "avd", "--name", name, "--package", imagePath, "--force"]
        if let device = device {
            args.append("--device")
            args.append(device)
        }
        
        // Handle SD Card during creation
        if let sdCardMB = options.sdCardMB {
            args.append("-c")
            args.append("\(sdCardMB)M")
        }
        
        print("[EmulatorService] createAVD: \(args.joined(separator: " "))")
        
        // We need to handle the "Do you wish to create a custom hardware profile? [no]" prompt
        executeCommandWithInput(executable: avdManagerPath, arguments: args, input: "no\n") { [weak self] success, output, errorOutput in
            guard let self = self else { return }
            print("[EmulatorService] createAVD baseline completed: success=\(success)")
            
            if success {
                // Apply hardware overrides
                self.updateAVDConfig(avdName: name, options: options)
                self.listAVDs(toolsPath: toolsPath)
            } else {
                print("[EmulatorService] createAVD ERROR: \(errorOutput ?? "unknown")")
                self.errorSubject.send(errorOutput ?? "Failed to create AVD")
                self.avdsSubject.send(self.parseAVDs(from: "")) // Trigger update to stop spinner
            }
        }
    }
    
    private func updateAVDConfig(avdName: String, options: AVDOptions) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let avdDirName = avdName.replacingOccurrences(of: " ", with: "_") + ".avd"
        let configPath = homeDir.appendingPathComponent(".android/avd/\(avdDirName)/config.ini")
        
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("[EmulatorService] updateAVDConfig: config.ini not found at \(configPath.path)")
            return
        }
        
        do {
            var content = try String(contentsOf: configPath, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)
            
            if let ram = options.ramMB {
                self.updateOrAdd(key: "hw.ramSize", value: "\(ram)", in: &lines)
            }
            if let heap = options.heapMB {
                self.updateOrAdd(key: "vm.heapSize", value: "\(heap)", in: &lines)
            }
            if let storage = options.storageMB {
                self.updateOrAdd(key: "disk.dataPartition.size", value: "\(storage)M", in: &lines)
            }
            if let width = options.width {
                self.updateOrAdd(key: "hw.lcd.width", value: "\(width)", in: &lines)
            }
            if let height = options.height {
                self.updateOrAdd(key: "hw.lcd.height", value: "\(height)", in: &lines)
            }
            if let density = options.density {
                self.updateOrAdd(key: "hw.lcd.density", value: "\(density)", in: &lines)
            }
            if let gps = options.gps {
                self.updateOrAdd(key: "hw.gps", value: gps ? "yes" : "no", in: &lines)
            }
            if let keyboard = options.keyboard {
                self.updateOrAdd(key: "hw.keyboard", value: keyboard ? "yes" : "no", in: &lines)
            }
            if let coldBoot = options.coldBoot {
                self.updateOrAdd(key: "fastboot.forceCold", value: coldBoot ? "yes" : "no", in: &lines)
            }
            if let gpu = options.gpuMode {
                self.updateOrAdd(key: "gpu.mode", value: gpu, in: &lines)
            }
            if let showFrame = options.showDeviceFrame {
                self.updateOrAdd(key: "showDeviceFrame", value: showFrame ? "yes" : "no", in: &lines)
            }
            if let camera = options.cameraBack {
                self.updateOrAdd(key: "hw.camera.back", value: camera, in: &lines)
                // Also set front to match or be none
                self.updateOrAdd(key: "hw.camera.front", value: camera == "none" ? "none" : "emulated", in: &lines)
            }
            
            content = lines.joined(separator: "\n")
            try content.write(to: configPath, atomically: true, encoding: .utf8)
            print("[EmulatorService] updateAVDConfig: Applied hardware overrides to \(configPath.path)")
        } catch {
            print("[EmulatorService] updateAVDConfig failed: \(error)")
        }
    }
    
    private func updateOrAdd(key: String, value: String, in lines: inout [String]) {
        if let index = lines.firstIndex(where: { $0.starts(with: "\(key)=") }) {
            lines[index] = "\(key)=\(value)"
        } else {
            lines.append("\(key)=\(value)")
        }
    }
    
    // MARK: - Delete AVD
    func deleteAVD(toolsPath: String, name: String) {
        let avdManagerPath = (toolsPath as NSString).appendingPathComponent("avdmanager")
        executeCommand(executable: avdManagerPath, arguments: ["delete", "avd", "--name", name]) { [weak self] success, _, errorOutput in
            guard let self = self else { return }
            if success {
                self.listAVDs(toolsPath: toolsPath)
            } else {
                self.errorSubject.send(errorOutput ?? "Failed to delete AVD")
            }
        }
    }

    // MARK: - Rename AVD
    func renameAVD(toolsPath: String, oldName: String, newName: String) {
        let avdManagerPath = (toolsPath as NSString).appendingPathComponent("avdmanager")
        print("[EmulatorService] renameAVD: \(oldName) -> \(newName)")
        executeCommand(executable: avdManagerPath, arguments: ["move", "avd", "-n", oldName, "-r", newName]) { [weak self] success, _, errorOutput in
            guard let self = self else { return }
            print("[EmulatorService] renameAVD completed: success=\(success)")
            if success {
                self.listAVDs(toolsPath: toolsPath)
            } else {
                print("[EmulatorService] renameAVD ERROR: \(errorOutput ?? "unknown")")
                self.errorSubject.send(errorOutput ?? "Failed to rename AVD")
                self.listAVDs(toolsPath: toolsPath) // Stop spinner even on error
            }
        }
    }
    
    // MARK: - Download Image
    func downloadImage(toolsPath: String, imagePath: String) {
        let sdkManagerPath = (toolsPath as NSString).appendingPathComponent("sdkmanager")
        
        // Immediate feedback: send 0% progress
        DispatchQueue.main.async {
            self.downloadProgressSubject.send((imagePath, 0.0))
        }
        
        // Use a dedicated queue to manage process lifecycle safely
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            let sdkRoot = self.getSDKRoot(from: toolsPath)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: sdkManagerPath)
            task.arguments = ["--sdk_root=\(sdkRoot)", "--install", imagePath]
            
            let inputPipe = Pipe()
            let outputPipe = Pipe() // Capturing both stdout and stderr for progress
            
            task.standardInput = inputPipe
            task.standardOutput = outputPipe
            task.standardError = outputPipe // Combine pipes
            
            // Track the process
            DispatchQueue.main.async {
                self.downloadProcesses[imagePath] = task
            }
            
            do {
                try task.run()
                
                // Send "y" for license more aggressively
                let writeHandle = inputPipe.fileHandleForWriting
                DispatchQueue.global().async {
                    for _ in 0..<10 {
                        if !task.isRunning { break }
                        try? writeHandle.write(contentsOf: "y\n".data(using: .utf8) ?? Data())
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                }
                
                // Parse output on the fly for progress
                let outputHandle = outputPipe.fileHandleForReading
                while task.isRunning {
                    if let data = try? outputHandle.read(upToCount: 4096), let str = String(data: data, encoding: .utf8) {
                        // print("[SDKMANAGER RAW]: \(str)") // Uncomment for deep debugging
                        
                        // Look for progress like [===            ] 10%
                        if let progress = self.extractProgress(from: str) {
                            DispatchQueue.main.async {
                                self.downloadProgressSubject.send((imagePath, progress))
                            }
                        }
                    }
                }
                
                task.waitUntilExit()
                
                // Cleanup process tracking
                DispatchQueue.main.async {
                    self.downloadProcesses.removeValue(forKey: imagePath)
                
                    if task.terminationStatus == 0 {
                        self.downloadProgressSubject.send((imagePath, 1.0))
                         // Add slight delay to allow filesystem to settle before listing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.listAvailableImages(toolsPath: toolsPath)
                        }
                    } else {
                        // If terminated by signal 15 (SIGTERM) or 9 (SIGKILL), it might be user initiated cancel
                        if task.terminationStatus == 15 || task.terminationStatus == 9 {
                             print("[EmulatorService] download cancelled by user")
                             // We don't send error, just maybe reset progress or let UI handle removal
                        } else {
                            // Log technical error
                            print("[EmulatorService] download failed with code \(task.terminationStatus)")
                            self.errorSubject.send("Failed to download image \(imagePath). Exit code: \(task.terminationStatus)")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.downloadProcesses.removeValue(forKey: imagePath)
                    self.errorSubject.send("Failed to start download: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Cancel Download
    func cancelDownload(imagePath: String) {
        print("[EmulatorService] cancelDownload requesting cancel for: \(imagePath)")
        if let process = downloadProcesses[imagePath] {
            process.terminate()
            downloadProcesses.removeValue(forKey: imagePath)
            print("[EmulatorService] cancelDownload: Terminated process for \(imagePath)")
        } else {
            print("[EmulatorService] cancelDownload: No active process found for \(imagePath)")
        }
    }
    
    // MARK: - Delete Image
    func deleteImage(toolsPath: String, imagePath: String) {
        let sdkManagerPath = (toolsPath as NSString).appendingPathComponent("sdkmanager")
        let sdkRoot = getSDKRoot(from: toolsPath)
        
        print("[EmulatorService] deleteImage: \(imagePath)")
        
        executeCommand(executable: sdkManagerPath, arguments: ["--uninstall", imagePath, "--sdk_root=\(sdkRoot)"]) { [weak self] success, _, errorOutput in
            guard let self = self else { return }
            print("[EmulatorService] deleteImage completed: success=\(success)")
            if success {
                // Add slight delay to allow filesystem to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.listAvailableImages(toolsPath: toolsPath)
                }
            } else {
                print("[EmulatorService] deleteImage ERROR: \(errorOutput ?? "unknown")")
                self.errorSubject.send(errorOutput ?? "Failed to delete image")
            }
        }
    }
    
    private func extractProgress(from output: String) -> Double? {
        // Look for any 1-3 digit number followed by %
        // This is ultra-permissive to catch "10%", " 10 %", "100%"
        let pattern = #"(\d{1,3})\s*%"#
        
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
            if let lastMatch = matches.last,
               let range = Range(lastMatch.range(at: 1), in: output),
               let percent = Double(output[range]) {
                return percent / 100.0
            }
        }
        return nil
    }
    
    // MARK: - Start Emulator
    func startEmulator(toolsPath: String, avdName: String) {
        let sdkRoot = getSDKRoot(from: toolsPath)
        let emulatorPath = (sdkRoot as NSString).appendingPathComponent("emulator/emulator")
        
        print("[EmulatorService] startEmulator: \(emulatorPath) -avd \(avdName) -no-window")
        
        startingAVDs.insert(avdName)
        self.listAVDs(toolsPath: toolsPath) // Propagate starting state
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: emulatorPath)
        let safeAvdName = avdName.replacingOccurrences(of: " ", with: "_")
        task.arguments = ["-avd", avdName, "-no-window", "-no-audio", "-prop", "ro.product.model=\(safeAvdName)"]
        
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_SDK_ROOT"] = sdkRoot
        env["ANDROID_HOME"] = sdkRoot
        task.environment = env
        
        // We don't want the app to wait for the emulator
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            print("[EmulatorService] Emulator started in background")
        } catch {
            print("[EmulatorService] Failed to start emulator: \(error)")
            self.errorSubject.send("Failed to start emulator: \(error.localizedDescription)")
        }
    }
    
    func stopEmulator(toolsPath: String, avdName: String) {
        let sdkRoot = getSDKRoot(from: toolsPath)
        let adbPath = (sdkRoot as NSString).appendingPathComponent("platform-tools/adb")
        
        // Find serial for this AVD
        detectRunningAVDs(toolsPath: toolsPath, avds: []) { runningAVDs in
            if let serial = runningAVDs.first(where: { $0.name == avdName })?.serial {
                print("[EmulatorService] stopEmulator: killing \(serial) (\(avdName))")
                self.executeCommand(executable: adbPath, arguments: ["-s", serial, "emu", "kill"]) { success, _, _ in
                    print("[EmulatorService] stopEmulator completed: \(success)")
                    self.listAVDs(toolsPath: toolsPath)
                }
            } else {
                print("[EmulatorService] stopEmulator: could not find running serial for \(avdName)")
            }
        }
    }
    
    // MARK: - Status Detection Logic
    private func detectRunningAVDs(toolsPath: String, avds: [AVD], completion: @escaping ([AVD]) -> Void) {
        let sdkRoot = getSDKRoot(from: toolsPath)
        let adbPath = (sdkRoot as NSString).appendingPathComponent("platform-tools/adb")
        
        executeCommand(executable: adbPath, arguments: ["devices"]) { success, output, _ in
            guard success, let output = output else {
                completion(avds)
                return
            }
            
            let lines = output.components(separatedBy: .newlines)
            let serials = lines.compactMap { line -> String? in
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 && parts[1] == "device" && parts[0].hasPrefix("emulator-") {
                    return parts[0]
                }
                return nil
            }
            
            if serials.isEmpty {
                completion(avds)
                return
            }
            
            var updatedAVDs = avds
            if updatedAVDs.isEmpty {
                 // If avds is empty, we are just looking for running ones (for stopEmulator)
                 // We'll create dummy AVD objects with names
            }
            
            let group = DispatchGroup()
            var runningMap = [String: String]() // Name: Serial
            
            for serial in serials {
                group.enter()
                // Try method 1: adb emu avd name
                self.executeCommand(executable: adbPath, arguments: ["-s", serial, "emu", "avd", "name"]) { success, output, _ in
                    if success, var name = output?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        // Clean up "OK" suffix and newlines from telnet response
                        if name.hasSuffix("OK") {
                            name = name.replacingOccurrences(of: "OK", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        runningMap[name] = serial
                        group.leave()
                    } else {
                        // Try method 2: shell getprop ro.boot.qemu.avd_name
                        self.executeCommand(executable: adbPath, arguments: ["-s", serial, "shell", "getprop", "ro.boot.qemu.avd_name"]) { success2, output2, _ in
                            if success2, let name = output2?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                                runningMap[name] = serial
                            }
                            group.leave()
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                if !runningMap.isEmpty {
                    // print("[EmulatorService] runningMap found: \(runningMap)")
                }
                if updatedAVDs.isEmpty {
                    let result = runningMap.map { (name, serial) in
                        AVD(name: name, device: nil, path: nil, target: nil, isRunning: true, isStarting: false, serial: serial)
                    }
                    completion(result)
                } else {
                    for i in 0..<updatedAVDs.count {
                        let avdName = updatedAVDs[i].name
                        
                        // Robust matching: case-insensitive, normalize underscores to spaces
                        let match = runningMap.first { (foundName, serial) in
                            let n1 = avdName.lowercased().replacingOccurrences(of: " ", with: "_")
                            let n2 = foundName.lowercased().replacingOccurrences(of: " ", with: "_")
                            return n1 == n2 || foundName.lowercased() == avdName.lowercased() || foundName.lowercased().contains(avdName.lowercased()) || avdName.lowercased().contains(foundName.lowercased())
                        }
                        
                        if let found = match {
                            // print("[EmulatorService] Matched \(avdName) to serial \(found.value)")
                            updatedAVDs[i].isRunning = true
                            updatedAVDs[i].serial = found.value
                            self.startingAVDs.remove(avdName)
                        } else if self.startingAVDs.contains(avdName) {
                            // print("[EmulatorService] \(avdName) is still starting...")
                            updatedAVDs[i].isStarting = true
                        }
                    }
                    completion(updatedAVDs)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func executeCommand(executable: String, arguments: [String], completion: @escaping (Bool, String?, String?) -> Void) {
        // print("[EmulatorService] executeCommand: \(executable) \(arguments.joined(separator: " "))")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        
        let sdkRoot = getSDKRoot(from: (executable as NSString).deletingLastPathComponent)
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_SDK_ROOT"] = sdkRoot
        env["ANDROID_HOME"] = sdkRoot
        task.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        // Read output asynchronously to avoid blocking on large outputs
        var outputData = Data()
        var errorData = Data()
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                // Stop handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                // Read any remaining data
                outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                
                let output = String(data: outputData, encoding: .utf8)
                let errorOutput = String(data: errorData, encoding: .utf8)
                
                /*
                if task.terminationStatus != 0 {
                    print("[EmulatorService] executeCommand finished with error status: \(task.terminationStatus)")
                }
                */
                
                DispatchQueue.main.async {
                    completion(task.terminationStatus == 0, output, errorOutput)
                }
            } catch {
                print("[EmulatorService] executeCommand failed: \(error)")
                DispatchQueue.main.async {
                    completion(false, nil, error.localizedDescription)
                }
            }
        }
    }
    
    private func executeCommandWithInput(executable: String, arguments: [String], input: String, completion: @escaping (Bool, String?, String?) -> Void) {
        print("[EmulatorService] executeCommandWithInput: \(executable) \(arguments.joined(separator: " "))")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        
        let sdkRoot = getSDKRoot(from: (executable as NSString).deletingLastPathComponent)
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_SDK_ROOT"] = sdkRoot
        env["ANDROID_HOME"] = sdkRoot
        task.environment = env
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        // Async reading to prevent blocking
        var outputData = Data()
        var errorData = Data()
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                
                // Send input
                if let data = input.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                inputPipe.fileHandleForWriting.closeFile()
                
                task.waitUntilExit()
                
                // Stop handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                // Read remaining
                outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                
                let output = String(data: outputData, encoding: .utf8)
                let errorOutput = String(data: errorData, encoding: .utf8)
                
                print("[EmulatorService] executeCommandWithInput finished: status=\(task.terminationStatus)")
                
                DispatchQueue.main.async {
                    completion(task.terminationStatus == 0, output, errorOutput)
                }
            } catch {
                print("[EmulatorService] executeCommandWithInput failed: \(error)")
                DispatchQueue.main.async {
                    completion(false, nil, error.localizedDescription)
                }
            }
        }
    }
    
    private func parseImages(from output: String, sdkRoot: String = "") -> [SystemImage] {
        var availableImages = [SystemImage]()
        var installedIds = Set<String>()
        
        let lines = output.components(separatedBy: .newlines)
        var currentSection: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("-") { continue }
            
            let lowercased = trimmed.lowercased()
            if lowercased.contains("installed packages:") || lowercased.contains("installed:") {
                currentSection = "installed"
                continue
            } else if lowercased.contains("available packages:") || lowercased.contains("available:") {
                currentSection = "available"
                continue
            } else if lowercased.contains("available updates:") || lowercased.contains("updates:") {
                currentSection = "updates"
                continue
            }
            
            if trimmed.contains("system-images") {
                let parts = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 1 {
                    let id = parts[0]
                    
                    if currentSection == "installed" {
                        installedIds.insert(id)
                    } else {
                        // In many cases, sdkmanager output is a single table or we missed the header
                        let description = parts.count >= 3 ? parts[2] : id
                        
                        // Smart Filtering:
                        // 1. Check architecture compatibility
                        let isCompatible = self.isImageCompatible(id: id)
                        
                        // 2. Only show Google APIs or Play Store images for better UX
                        let isPreferred = id.contains("google_apis") || id.contains("google_apis_playstore")
                        
                        // 3. If it's already installed, we probably want to see it too
                        let isInstalled = installedIds.contains(id)
                        
                        if (isCompatible && isPreferred) || isInstalled {
                            availableImages.append(SystemImage(id: id, description: description, isDownloaded: isInstalled, sizeBytes: nil))
                        }
                    }
                }
            }
        }
        
        // Mark as downloaded if they are in installedIds and calculate size
        var finalImages = [SystemImage]()
        for img in availableImages {
            let isDownloaded = installedIds.contains(img.id)
            var sizeBytes: Int64? = nil
            
            if isDownloaded && !sdkRoot.isEmpty {
                // Convert ID to path: system-images;android-33;google_apis;arm64-v8a -> system-images/android-33/google_apis/arm64-v8a
                let relPath = img.id.replacingOccurrences(of: ";", with: "/")
                let fullPath = (sdkRoot as NSString).appendingPathComponent(relPath)
                sizeBytes = self.calculateDirectorySize(path: "file://" + fullPath)
            }
            
            finalImages.append(SystemImage(id: img.id, description: img.description, isDownloaded: isDownloaded, sizeBytes: sizeBytes))
        }
        
        // Add any installed images that weren't in the available list (e.g. legacy or custom)
        for id in installedIds {
            if !availableImages.contains(where: { $0.id == id }) {
                // Try to make a nice description from ID if possible
                let description = id.replacingOccurrences(of: "system-images;", with: "").replacingOccurrences(of: ";", with: " ")
                
                var sizeBytes: Int64? = nil
                if !sdkRoot.isEmpty {
                    let relPath = id.replacingOccurrences(of: ";", with: "/")
                    let fullPath = (sdkRoot as NSString).appendingPathComponent(relPath)
                    sizeBytes = self.calculateDirectorySize(path: "file://" + fullPath)
                }
                
                finalImages.append(SystemImage(id: id, description: description, isDownloaded: true, sizeBytes: sizeBytes))
            }
        }
        
        return finalImages.sorted { $0.id > $1.id }
    }
    
    private func parseAVDs(from output: String) -> [AVD] {
        var avds = [AVD]()
        let sections = output.components(separatedBy: "---------")
        
        for section in sections {
            let lines = section.components(separatedBy: .newlines)
            var name = ""
            var device = ""
            var path = ""
            var target = ""
            
            for line in lines {
                if line.contains("Name:") {
                    name = line.components(separatedBy: "Name:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                } else if line.contains("Device:") {
                    device = line.components(separatedBy: "Device:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                } else if line.contains("Path:") {
                    path = line.components(separatedBy: "Path:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                } else if line.contains("Target:") {
                    target = line.components(separatedBy: "Target:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                }
            }
            
            if !name.isEmpty {
                avds.append(AVD(name: name, device: device, path: path, target: target))
            }
        }
        
        return avds
    }
    
    private func getSDKRoot(from toolsPath: String) -> String {
        // Expected: .../sdk/cmdline-tools/latest/bin
        // 1. bin -> latest
        // 2. latest -> cmdline-tools
        // 3. cmdline-tools -> sdk (SDK Root)
        let path1 = (toolsPath as NSString).deletingLastPathComponent
        let path2 = (path1 as NSString).deletingLastPathComponent
        let path3 = (path2 as NSString).deletingLastPathComponent
        return path3
    }

    private func isImageCompatible(id: String) -> Bool {
        let arch = getSystemArchitecture()
        if arch == "arm64" {
            // For Apple Silicon, prefer arm64
            return id.contains("arm64-v8a") || id.contains("aarch64")
        } else {
            // For Intel, prefer x86_64
            return id.contains("x86_64") || id.contains("x86")
        }
    }
    
    private func getSystemArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: Int8.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }
}
