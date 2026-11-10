//
//  AppWindowController.swift
//  AndroLaunch
//
//  Per-app phone windows ("Frame Mode"). One scrcpy process per window:
//  Android 14+ gets its own virtual display, Android 12–13 mirrors the main
//  display with the app in front. The controller owns the window registry,
//  honest failure reporting.
//

import AppKit
import Combine
import Foundation

struct OpenAppWindow: Identifiable, Equatable {
    var id: String { "\(deviceID)-\(packageID)" }
    let deviceID: String
    let packageID: String
    let appName: String
    let mode: AppLaunchMode
    var openedAt: Date
    /// `true` when the window is backed by a scrcpy virtual display (Android 14+).
    var isVirtualDisplay: Bool = false
    var processIdentifier: Int32? = nil

    var displayName: String { appName.isEmpty ? packageID : appName }
}

final class AppWindowController: ObservableObject {
    static let shared = AppWindowController()

    @Published private(set) var openWindows: [OpenAppWindow] = []
    /// Last launch failure, already phrased for people.
    @Published private(set) var lastError: String?
    /// A non-fatal explanation (e.g. Frame Mode falling back to a mirrored display).
    @Published private(set) var lastNotice: String?
    @Published private(set) var isOpening = false

    private var processes: [String: Process] = [:]
    private var terminationObservers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        terminationObservers.append(
            center.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.closeAll()
            })
    }

    deinit {
        for observer in terminationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Queries

    var mostRecent: OpenAppWindow? {
        openWindows.max { $0.openedAt < $1.openedAt }
    }

    func isOpen(packageID: String, deviceID: String) -> Bool {
        openWindows.contains { $0.packageID == packageID && $0.deviceID == deviceID }
    }

    func window(packageID: String, deviceID: String) -> OpenAppWindow? {
        openWindows.first { $0.packageID == packageID && $0.deviceID == deviceID }
    }

    func openWindowCount(forDeviceID deviceID: String) -> Int {
        openWindows.filter { $0.deviceID == deviceID }.count
    }

    /// What Frame Mode will actually do for a phone, for the Apps tab copy.
    func behavior(for device: AndroidDevice?) -> MeldWindowBehavior {
        guard let device else {
            return .mainDisplayFallback(
                reason: "Connect a phone to open app windows.")
        }
        // `virtualDisplayIsUnsafe` already protects Android 12–13; MeldModeSupport
        // additionally requires Android 14 so lower versions never attempt it.
        if device.virtualDisplayIsUnsafe {
            return .mainDisplayFallback(
                reason:
                    "Frame Mode windows need Android 14 or later. This phone mirrors its main display instead.")
        }
        return MeldModeSupport.behavior(apiLevel: device.apiLevel)
    }

    // MARK: - Open

    @discardableResult
    func openApp(_ app: AndroidApp, deviceID: String, mode: AppLaunchMode) -> Bool {
        openApp(
            packageID: app.packageName, appName: app.name, deviceID: deviceID, mode: mode)
    }

    @discardableResult
    func openApp(
        packageID: String,
        appName: String,
        deviceID: String,
        mode: AppLaunchMode
    ) -> Bool {
        let packageID = packageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageID.isEmpty else {
            lastError = "This app has no package name to launch."
            return false
        }

        let store = HubStore.shared
        guard !store.isPreview else {
            lastError = "Snapshot mode does not launch windows."
            return false
        }

        guard let device = store.devices.first(where: { $0.id == deviceID || $0.stableID == deviceID })
        else {
            lastError = "That phone is no longer connected."
            return false
        }
        guard device.isConnected else {
            lastError = "\(device.name) is offline. Reconnect it and try again."
            return false
        }
        if isOpen(packageID: packageID, deviceID: device.id) {
            lastError = "\(appName.isEmpty ? packageID : appName) already has a window open on \(device.name)."
            return false
        }

        // Settings → Fusion mode → Frame Mode is a real preference. Turning it off
        // makes every app open as a normal screen mirror, including deep links.
        let requestedMode = mode
        let effectiveMode: AppLaunchMode =
            (mode == .meldWindow && !AppPreferences.shared.meldModeEnabled) ? .mirror : mode
        var settingNotice: String?
        if effectiveMode != requestedMode {
            settingNotice = "Frame Mode is off in Settings; opened as Screen Mirroring."
        }

        let scrcpyPath = resolveScrcpyPath()
        guard let scrcpyPath else {
            lastError = "scrcpy isn't installed. Install it with `brew install scrcpy`, then try again."
            return false
        }

        let behavior = self.behavior(for: device)
        // Screen mirroring always uses the main display; only Frame Mode can ask
        // for a dedicated virtual display.
        let useVirtualDisplay = effectiveMode == .meldWindow && behavior.isVirtualDisplay
        let adbPath = DependencyContainer.shared.adb.adbPath
        let resolution = DependencyContainer.shared.deviceRepository.getResolution(for: device.id)
        let audioEnabled = DependencyContainer.shared.deviceRepository.isAudioEnabled(for: device.id)

        var arguments: [String] = [
            "--serial", sanitizedSerial(device.id),
            "--window-title", "\(appName.isEmpty ? packageID : appName) — \(device.name)",
        ]
        if useVirtualDisplay {
            arguments.append("--new-display")
            if resolution > 0 {
                arguments.append(contentsOf: ["-m", "\(resolution)"])
            }
            arguments.append("--start-app=\(packageID)")
        } else {
            arguments.append("--start-app=\(packageID)")
            if resolution > 0 {
                arguments.append(contentsOf: ["-m", "\(resolution)"])
            }
        }
        if !audioEnabled { arguments.append("--no-audio") }
        if !DependencyContainer.shared.deviceRepository.isClipboardEnabled(for: device.id) {
            arguments.append("--no-clipboard-autosync")
        }
        if let adbPath { arguments.append(contentsOf: ["--adb", adbPath]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        let windowID = "\(device.id)-\(packageID)"
        process.terminationHandler = { [weak self] process in
            // scrcpy can fail immediately (old version, unknown option, phone
            // busy). Read what it said before deciding how to report it.
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.handleTermination(
                    windowID: windowID, status: process.terminationStatus, rawOutput: raw)
            }
        }

        do {
            try process.run()
        } catch {
            lastError = "Couldn't start scrcpy: \(error.localizedDescription)"
            return false
        }

        processes[windowID] = process
        openWindows.append(
            OpenAppWindow(
                deviceID: device.id,
                packageID: packageID,
                appName: appName,
                mode: effectiveMode,
                openedAt: Date(),
                isVirtualDisplay: useVirtualDisplay,
                processIdentifier: process.processIdentifier))

        lastError = nil
        if effectiveMode == .meldWindow, case .mainDisplayFallback(let reason) = behavior {
            lastNotice = settingNotice ?? reason
            // Feature alerts → Frame Mode: the app is opening on the phone screen
            // instead of its own window.
            FeatureAlertCenter.shared.post(
                .meldMode,
                title: "Frame Mode",
                body: reason)
        } else if let settingNotice {
            lastNotice = settingNotice
        } else {
            lastNotice = nil
        }

        return true
    }

    /// Brings an existing app window to the front (handoff row).
    func activate(_ window: OpenAppWindow) {
        guard let identifier = window.processIdentifier else { return }
        NSRunningApplication(processIdentifier: pid_t(identifier))?.activate(options: [])
    }

    // MARK: - Close

    func closeApp(_ window: OpenAppWindow) {
        if let process = processes.removeValue(forKey: window.id) {
            process.terminate()
        }
        openWindows.removeAll { $0.id == window.id }
    }

    func closeApp(packageID: String, deviceID: String) {
        guard let window = window(packageID: packageID, deviceID: deviceID) else { return }
        closeApp(window)
    }

    func closeWindows(forDeviceID deviceID: String) {
        for window in openWindows where window.deviceID == deviceID {
            closeApp(window)
        }
    }

    func closeAll() {
        let active = processes
        processes.removeAll()
        openWindows.removeAll()
        for (_, process) in active where process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Messages

    func clearError() { lastError = nil }
    func clearNotice() { lastNotice = nil }

    // MARK: - Internals

    private func handleTermination(windowID: String, status: Int32, rawOutput: String) {
        let wasTracked = openWindows.contains { $0.id == windowID }
        guard wasTracked || processes[windowID] != nil else { return }
        processes.removeValue(forKey: windowID)
        openWindows.removeAll { $0.id == windowID }

        guard status != 0 else { return }
        let detail = rawOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("INFO:") }
        let reason = detail ?? rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError =
            reason.isEmpty
            ? "The app window closed unexpectedly (scrcpy exited with code \(status))."
            : "The app window couldn't open: \(reason)"
    }

    private func resolveScrcpyPath() -> String? {
        let service = DependencyContainer.shared.scrcpyService
        if let path = service.scrcpyPath, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let detected = service.detectScrcpyPath(),
            FileManager.default.isExecutableFile(atPath: detected)
        {
            return detected
        }
        return AppConstants.scrcpyPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func sanitizedSerial(_ serial: String) -> String {
        // Bonjour services sometimes expose a trailing-dot hostname.
        serial.replacingOccurrences(of: ".:", with: ":")
    }
}
