//
//  ScrcpyService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 21/4/25.
//

import Combine
import Foundation

final class ScrcpyService: ScrcpyServiceProtocol {
    private var scrcpyPath: String?
    private var runningProcesses: [String: Process] = [:]
    private let processLock = NSLock()
    let error = PassthroughSubject<String?, Never>()

    private let scrcpyPaths = [
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy",
        "\(NSHomeDirectory())/.local/bin/scrcpy",
        "/Applications/scrcpy.app/Contents/MacOS/scrcpy",
    ]

    init() {
        scrcpyPath = findScrcpyPath()
    }

    private func findScrcpyPath() -> String? {
        for path in scrcpyPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Mirror Device

    func mirrorDevice(
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        clipboardEnabled: Bool,
        maxSize: Int?,
        maxFPS: Int?,
        bitRate: Int?,
        orientation: String?,
        borderless: Bool,
        flexDisplay: Bool,
        keepActive: Bool,
        backgroundColor: String?,
        renderFit: String?,
        lockAspectRatio: Bool,
        minSizeAlignment: Int?
    ) {
        guard let scrcpyPath = scrcpyPath else {
            error.send("SCRCPY not installed. Use `brew install scrcpy`.")
            return
        }

        var args: [String] = []
        args.append("--serial")
        args.append(deviceID)
        args.append("--window-title")
        args.append("AndroLaunch - \(deviceID)")

        if keepActive { args.append("--keep-active") }
        if borderless { args.append("--window-borderless") }
        if !audioEnabled { args.append("--no-audio") }
        if !clipboardEnabled { args.append("--no-clipboard-autosync") }
        if let backgroundColor = backgroundColor {
            args.append("--background-color=\(backgroundColor)")
        }
        if let renderFit = renderFit { args.append("--render-fit=\(renderFit)") }
        if !lockAspectRatio { args.append("--no-window-aspect-ratio-lock") }
        if let minSizeAlignment = minSizeAlignment {
            args.append("--min-size-alignment=\(minSizeAlignment)")
        }
        if flexDisplay {
            // Flex mode: no size constraint
        } else if let maxSize = maxSize {
            args.append(contentsOf: ["-m", "\(maxSize)"])
        }
        if let maxFPS = maxFPS { args.append(contentsOf: ["--max-fps", "\(maxFPS)"]) }
        if let bitRate = bitRate { args.append(contentsOf: ["--bit-rate", "\(bitRate)M"]) }
        if let orientation = orientation {
            args.append(contentsOf: ["--lock-video-orientation", orientation])
        }
        if let adbPath = adbPath { args.append(contentsOf: ["--adb", adbPath]) }

        launchProcess(scrcpyPath: scrcpyPath, args: args, key: deviceID)
    }

    // MARK: - Mirror Camera

    func mirrorCamera(
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        facing: String?,
        fps: Int?,
        size: Int?,
        bitRate: Int?,
        orientation: String?,
        aspectRatio: String?,
        cameraTorch: Bool,
        cameraZoom: Double?
    ) {
        guard let scrcpyPath = scrcpyPath else {
            error.send("SCRCPY not installed. Use `brew install scrcpy`.")
            return
        }

        var args: [String] = []
        args.append("--serial")
        args.append(deviceID)
        args.append("--video-source=camera")
        args.append("--window-title")
        args.append("AndroLaunch Camera - \(deviceID)")

        if cameraTorch { args.append("--camera-torch") }
        if let cameraZoom = cameraZoom { args.append("--camera-zoom=\(cameraZoom)") }
        if let facing = facing { args.append(contentsOf: ["--camera-facing", facing]) }
        if let fps = fps { args.append(contentsOf: ["--max-fps", "\(fps)"]) }
        if let size = size { args.append(contentsOf: ["-m", "\(size)"]) }
        if let bitRate = bitRate { args.append(contentsOf: ["--bit-rate", "\(bitRate)M"]) }
        if let orientation = orientation {
            args.append(contentsOf: ["--lock-video-orientation", orientation])
        }
        if let aspectRatio = aspectRatio { args.append(contentsOf: ["--camera-ar", aspectRatio]) }
        if audioEnabled {
            args.append("--audio-source=playback")
        } else {
            args.append("--no-audio")
        }
        if let adbPath = adbPath { args.append(contentsOf: ["--adb", adbPath]) }

        launchProcess(scrcpyPath: scrcpyPath, args: args, key: "camera-\(deviceID)")
    }

    // MARK: - Launch App

    func launchApp(
        packageID: String,
        deviceID: String,
        adbPath: String?,
        audioEnabled: Bool,
        resolution: Int,
        keepActive: Bool,
        flexDisplay: Bool,
        backgroundColor: String?,
        renderFit: String?,
        lockAspectRatio: Bool,
        bitRate: Int?
    ) {
        guard let scrcpyPath = scrcpyPath else {
            error.send("SCRCPY not installed. Use `brew install scrcpy`.")
            return
        }

        var args: [String] = []
        args.append("--serial")
        args.append(deviceID)
        args.append("--window-title")
        args.append("AndroLaunch - \(packageID)")
        args.append("--new-display")
        args.append("--start-app")
        args.append(packageID)

        if flexDisplay {
            args.append("--flex-display")
        } else {
            args.append(contentsOf: ["-m", "\(resolution)"])
        }

        if keepActive { args.append("--keep-active") }
        if !audioEnabled { args.append("--no-audio") }
        if let backgroundColor = backgroundColor {
            args.append("--background-color=\(backgroundColor)")
        }
        if let renderFit = renderFit { args.append("--render-fit=\(renderFit)") }
        if !lockAspectRatio { args.append("--no-window-aspect-ratio-lock") }
        if let bitRate = bitRate {
            args.append("--audio-bit-rate=\(bitRate)M")
        } else {
            args.append("--audio-bit-rate=10000")
        }
        if let adbPath = adbPath { args.append(contentsOf: ["--adb", adbPath]) }

        launchProcess(scrcpyPath: scrcpyPath, args: args, key: "app-\(deviceID)-\(packageID)")
    }

    // MARK: - Process Management

    private func launchProcess(scrcpyPath: String, args: [String], key: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = args

        processLock.lock()
        runningProcesses[key] = task
        processLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try task.run()
                task.waitUntilExit()
                self?.processLock.lock()
                self?.runningProcesses.removeValue(forKey: key)
                self?.processLock.unlock()
            } catch {
                self?.error.send("Failed: \(error.localizedDescription)")
            }
        }
    }

    func stopMirroring(deviceID: String) {
        processLock.lock()
        let mirror = runningProcesses.removeValue(forKey: deviceID)
        let camera = runningProcesses.removeValue(forKey: "camera-\(deviceID)")
        processLock.unlock()

        mirror?.terminate()
        camera?.terminate()
    }

    func stopAll() {
        processLock.lock()
        let processes = Array(runningProcesses.values)
        runningProcesses.removeAll()
        processLock.unlock()

        for p in processes {
            p.terminate()
        }
    }
}
