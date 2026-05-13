import Foundation

// MARK: - Scrcpy Service

public final class ScrcpyService {
    private var runningProcesses: [String: Process] = [:]
    public var errorHandler: ((String) -> Void)?

    private var scrcpyPaths: [String] {
        [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(NSHomeDirectory())/.local/bin/scrcpy",
            "/Applications/scrcpy.app/Contents/MacOS/scrcpy",
        ]
    }

    public init() {}

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

    // MARK: - Helpers

    /// Validate render-fit values. Only `contain`, `cover`, `fit-width`, `fit-height` are accepted.
    /// Returns the value if valid, nil otherwise.
    private func validRenderFit(_ value: String) -> String? {
        let valid = ["contain", "cover", "fit-width", "fit-height"]
        return valid.contains(value) ? value : nil
    }

    /// Validate hex color string. Accepts 3 or 6 hex digits, optionally prefixed with `#`.
    /// Returns the value as-is if valid, nil otherwise. scrcpy handles the actual parsing.
    private func validBackgroundColor(_ value: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")
        let range = NSRange(location: 0, length: value.utf16.count)
        return pattern.firstMatch(in: value, options: [], range: range) != nil ? value : nil
    }

    // MARK: - Mirror Device

    /// Launch scrcpy to mirror a device screen
    /// - Parameters:
    ///   - deviceID: Device serial
    ///   - adbPath: Path to ADB executable
    ///   - audioEnabled: Whether to forward audio
    ///   - clipboardEnabled: Whether to sync clipboard
    ///   - maxSize: Max resolution (e.g. 1024)
    ///   - maxFPS: Max FPS
    ///   - bitRate: Video bitrate in Mbps
    ///   - orientation: Lock orientation (e.g. "0", "90", "180", "270")
    ///   - borderless: Remove window decorations
    ///   - stayAwake: Keep device awake (opt-in)
    ///   - keepActive: Keep device active (default on, replaces --stay-awake as default)
    ///   - backgroundColor: Window background color (3 or 6 digit hex, optional #)
    ///   - renderFit: Window rendering fit mode (contain|cover|fit-width|fit-height)
    ///   - lockAspectRatio: Lock window aspect ratio (set false to disable)
    ///   - minSizeAlignment: Minimum size alignment
    public func mirrorDevice(
        deviceID: String,
        adbPath: String? = nil,
        audioEnabled: Bool = true,
        clipboardEnabled: Bool = true,
        maxSize: Int? = nil,
        maxFPS: Int? = nil,
        bitRate: Int? = nil,
        orientation: String? = nil,
        borderless: Bool = false,
        flexDisplay: Bool = false,
        stayAwake: Bool = false,
        keepActive: Bool = true,
        backgroundColor: String? = nil,
        renderFit: String? = nil,
        lockAspectRatio: Bool = true,
        minSizeAlignment: Int? = nil
    ) throws -> Process {
        guard let scrcpyPath = findScrcpyPath() else {
            throw ADBError.unknown("SCRCPY not found. Install with: brew install scrcpy")
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
            "--window-title", "AndroLaunch - \(cleanDeviceID)",
        ]

        if stayAwake {
            args.append("--stay-awake")
        }

        if keepActive {
            args.append("--keep-active")
        }

        if let backgroundColor = backgroundColor.flatMap({ validBackgroundColor($0) }) {
            args.append(contentsOf: ["--background-color", backgroundColor])
        }

        if let renderFit = renderFit.flatMap({ validRenderFit($0) }) {
            args.append(contentsOf: ["--render-fit", renderFit])
        }

        if !lockAspectRatio {
            args.append("--no-window-aspect-ratio-lock")
        }

        if let minSizeAlignment = minSizeAlignment {
            args.append(contentsOf: ["--min-size-alignment", "\(minSizeAlignment)"])
        }

        if flexDisplay {
            // Flex mode: no size constraint, let the window resize freely
        } else if let maxSize = maxSize {
            args.append(contentsOf: ["-m", "\(maxSize)"])
        }

        if let maxFPS = maxFPS {
            args.append(contentsOf: ["--max-fps", "\(maxFPS)"])
        }

        if let bitRate = bitRate {
            args.append(contentsOf: ["--bit-rate", "\(bitRate)M"])
        }

        if let orientation = orientation {
            args.append(contentsOf: ["--lock-video-orientation", orientation])
        }

        if !audioEnabled {
            args.append("--no-audio")
        }

        if !clipboardEnabled {
            args.append("--no-clipboard-autosync")
        }

        if borderless {
            args.append("--window-borderless")
        }

        // Set ADB path if provided
        if let adbPath = adbPath {
            args.append(contentsOf: ["--adb", adbPath])
        }

        task.arguments = args

        // Run in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                self.runningProcesses.removeValue(forKey: deviceID)
            } catch {
                self.errorHandler?("Failed to start scrcpy: \(error.localizedDescription)")
            }
        }

        runningProcesses[deviceID] = task
        return task
    }

    // MARK: - Mirror Camera

    public func mirrorCamera(
        deviceID: String,
        adbPath: String? = nil,
        audioEnabled: Bool = false,
        facing: String? = nil,
        fps: Int? = nil,
        size: Int? = nil,
        bitRate: Int? = nil,
        orientation: String? = nil,
        aspectRatio: String? = nil,
        cameraTorch: Bool = false,
        cameraZoom: Double? = nil
    ) throws -> Process {
        guard let scrcpyPath = findScrcpyPath() else {
            throw ADBError.unknown("SCRCPY not found. Install with: brew install scrcpy")
        }

        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)

        var args = [
            "--serial", cleanDeviceID,
            "--video-source=camera",
            "--window-title", "AndroLaunch Camera - \(cleanDeviceID)",
        ]

        if cameraTorch {
            args.append("--camera-torch")
            // --video-source=camera is already set above, per contract rule #3
        }

        if let cameraZoom = cameraZoom {
            args.append(contentsOf: ["--camera-zoom", "\(cameraZoom)"])
        }

        if let facing = facing {
            args.append(contentsOf: ["--camera-facing", facing])
        }

        if let fps = fps {
            args.append(contentsOf: ["--max-fps", "\(fps)"])
        }

        if let size = size {
            args.append(contentsOf: ["-m", "\(size)"])
        }

        if let bitRate = bitRate {
            args.append(contentsOf: ["--bit-rate", "\(bitRate)M"])
        }

        if let orientation = orientation {
            args.append(contentsOf: ["--lock-video-orientation", orientation])
        }

        if let aspectRatio = aspectRatio {
            args.append(contentsOf: ["--camera-ar", aspectRatio])
        }

        if !audioEnabled {
            args.append("--no-audio")
        } else {
            args.append("--audio-source=playback")
        }

        if let adbPath = adbPath {
            args.append(contentsOf: ["--adb", adbPath])
        }

        task.arguments = args

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                self.runningProcesses.removeValue(forKey: "camera-\(deviceID)")
            } catch {
                self.errorHandler?(
                    "Failed to start camera mirroring: \(error.localizedDescription)")
            }
        }

        runningProcesses["camera-\(deviceID)"] = task
        return task
    }

    // MARK: - Launch App via Scrcpy

    public func launchApp(
        packageID: String,
        deviceID: String,
        adbPath: String? = nil,
        audioEnabled: Bool = true,
        resolution: Int = 1024,
        keepActive: Bool = true,
        flexDisplay: Bool = false,
        backgroundColor: String? = nil,
        renderFit: String? = nil,
        lockAspectRatio: Bool = true,
        bitRate: Int? = nil,
        clipboardEnabled: Bool = true
    ) throws -> Process {
        guard let scrcpyPath = findScrcpyPath() else {
            throw ADBError.unknown("SCRCPY not found. Install with: brew install scrcpy")
        }

        var cleanDeviceID = deviceID
        if cleanDeviceID.contains(".:") {
            cleanDeviceID = cleanDeviceID.replacingOccurrences(of: ".:", with: ":")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)

        var args = [
            "--serial", cleanDeviceID,
            "--window-title", "AndroLaunch - \(packageID)",
            "--new-display",
            "--start-app", packageID,
            "--audio-output-buffer=10",
        ]

        if flexDisplay {
            args.append("--flex-display")
        } else {
            // Without flex, constrain to the requested resolution
            args.append(contentsOf: ["-m", "\(resolution)"])
        }

        if keepActive {
            args.append("--keep-active")
        }

        // Audio bit-rate: explicit param wins, then flexDisplay default, then legacy fallback
        if let bitRate = bitRate {
            args.append("--audio-bit-rate=\(bitRate)M")
        } else if flexDisplay {
            args.append("--audio-bit-rate=16M")
        } else {
            args.append("--audio-bit-rate=10000")
        }

        if let backgroundColor = backgroundColor.flatMap({ validBackgroundColor($0) }) {
            args.append(contentsOf: ["--background-color", backgroundColor])
        }

        if let renderFit = renderFit.flatMap({ validRenderFit($0) }) {
            args.append(contentsOf: ["--render-fit", renderFit])
        }

        if !lockAspectRatio {
            args.append("--no-window-aspect-ratio-lock")
        }

        if !audioEnabled {
            args.append("--no-audio")
        }

        if !clipboardEnabled {
            args.append("--no-clipboard-autosync")
        }

        if let adbPath = adbPath {
            args.append(contentsOf: ["--adb", adbPath])
        }

        task.arguments = args

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                self.runningProcesses.removeValue(forKey: "app-\(deviceID)-\(packageID)")
            } catch {
                self.errorHandler?(
                    "Failed to launch app with scrcpy: \(error.localizedDescription)")
            }
        }

        runningProcesses["app-\(deviceID)-\(packageID)"] = task
        return task
    }

    // MARK: - Stop Mirroring

    public func stopMirroring(deviceID: String) {
        if let process = runningProcesses[deviceID] {
            process.terminate()
            runningProcesses.removeValue(forKey: deviceID)
        }
        if let process = runningProcesses["camera-\(deviceID)"] {
            process.terminate()
            runningProcesses.removeValue(forKey: "camera-\(deviceID)")
        }
    }

    public func stopAll() {
        for (_, process) in runningProcesses {
            process.terminate()
        }
        runningProcesses.removeAll()
    }
}
