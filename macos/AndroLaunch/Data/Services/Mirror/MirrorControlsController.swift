//
//  MirrorControlsController.swift
//  AndroLaunch
//
//  Floating mirror controls: audio forwarding, always-on-top, screen-off,
//  clipboard, screenshot, recording, keyboard mode, frame toggle and navigation.
//
//  Every action is real: option changes restart the scrcpy mirror with the new
//  flags (the panel says so), screenshots come from `adb exec-out screencap`,
//  recording is Android's own `screenrecord` pulled to ~/Movies, and navigation
//  sends `input keyevent` codes. No capability is simulated.
//

import AppKit
import Combine
import Foundation

enum MirrorControlsError: LocalizedError {
    case adbUnavailable
    case noDevice
    case deviceOffline(String)
    case desktopUnavailable
    case moviesUnavailable
    case invalidScreenshot(String)
    case screenshotFailed(String)
    case recordingFailed(String)
    case recordingPullFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbUnavailable:
            return "ADB isn't available. Install Android Platform Tools and try again."
        case .noDevice:
            return "Select a phone before using mirror controls."
        case .deviceOffline(let name):
            return "\(name) is offline. Reconnect it and try again."
        case .desktopUnavailable:
            return "The Desktop folder isn't available, so the screenshot couldn't be saved."
        case .moviesUnavailable:
            return "The Movies folder isn't available, so the recording couldn't be saved."
        case .invalidScreenshot(let detail):
            return "The screenshot wasn't a valid PNG. \(detail)"
        case .screenshotFailed(let detail):
            return "The screenshot failed: \(detail)"
        case .recordingFailed(let detail):
            return "Screen recording failed: \(detail)"
        case .recordingPullFailed(let detail):
            return "The recording finished on the phone but couldn't be pulled to this Mac. \(detail)"
        }
    }
}

/// The result of a successful screenshot capture.
struct MirrorCaptureOutcome {
    let url: URL
    let copiedToClipboard: Bool
    let warning: String?
}

final class MirrorControlsController: ObservableObject {
    static let shared = MirrorControlsController()

    // MARK: - Published state

    @Published private(set) var isPresented = false
    @Published private(set) var deviceID: String?
    @Published private(set) var deviceName = "No device"
    @Published private(set) var isDeviceConnected = false
    @Published private(set) var options = MirrorOptions.default
    /// Options per ADB device id, so switching devices does not lose switches.
    @Published private(set) var optionsByDevice: [String: MirrorOptions] = [:]
    @Published private(set) var isMirroring = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var isSavingRecording = false
    @Published private(set) var lastCapturePath: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var isApplying = false

    // MARK: - Dependencies

    private let adb: ADBService
    private let repository: any DeviceRepositoryProtocol
    private let preferences = DeviceScopedPreferences.shared
    private var cancellables = Set<AnyCancellable>()
    private var panel: MirrorControlsPanelWindowController?

    // MARK: - Recording state

    private var recordingProcess: Process?
    private var recordingRemotePath: String?
    private var recordingDeviceID: String?
    private var isFinalizingRecording = false

    // MARK: - Debounced restart

    private var applyWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    init(
        adb: ADBService = DependencyContainer.shared.adb,
        deviceRepository: any DeviceRepositoryProtocol = DependencyContainer.shared.deviceRepository
    ) {
        self.adb = adb
        self.repository = deviceRepository
        bind()
    }

    private func bind() {
        adb.mirrorSessionEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .started(let snapshot):
                    guard snapshot.deviceID == self.deviceID else { return }
                    self.isMirroring = true
                    self.options = snapshot.options
                    self.options.recording = self.recordingStartedAt != nil
                    self.publishOptions()
                    if self.statusMessage == nil || self.statusMessage?.hasPrefix("Restarting") == true
                        || self.statusMessage?.hasPrefix("Starting") == true
                    {
                        self.statusMessage = "Mirror running with the selected options."
                    }
                case .stopped(let stoppedID):
                    guard stoppedID == self.deviceID else { return }
                    self.isMirroring = false
                    self.statusMessage = "Mirror stopped."
                case .failed(let failedID, let message):
                    guard failedID == self.deviceID else { return }
                    self.isMirroring = false
                    self.lastError = message
                }
            }
            .store(in: &cancellables)

        repository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshDeviceState() }
            .store(in: &cancellables)
    }

    // MARK: - Presentation

    /// Attach this controller to a device without presenting the floating panel.
    /// Used by the in-panel Mirror Controls page.
    func select(deviceID: String) {
        if let recordingDeviceID, recordingDeviceID != deviceID {
            stopRecording()
        }
        self.deviceID = deviceID
        refreshDeviceState()
        loadOptions(for: deviceID)
        isMirroring = adb.isMirrorSessionActive(deviceID: deviceID)
        if let snapshot = adb.mirrorSession(for: deviceID) {
            options = snapshot.options
            options.recording = recordingStartedAt != nil
            publishOptions()
        }
        if !isMirroring, statusMessage == nil {
            statusMessage = "No mirror running. Start it from here or change an option."
        }
    }

    func show(deviceID: String) {
        select(deviceID: deviceID)
        isPresented = true
        presentPanel()
    }

    func hide() {
        isPresented = false
        panel?.hide()
    }

    private func presentPanel() {
        if panel == nil {
            panel = MirrorControlsPanelWindowController(controller: self)
        }
        panel?.show()
    }

    // MARK: - Device

    private func currentDevice() -> AndroidDevice? {
        guard let deviceID else { return nil }
        return repository.devices.first { $0.id == deviceID }
    }

    private func refreshDeviceState() {
        guard let deviceID else { return }
        if let device = repository.devices.first(where: { $0.id == deviceID }) {
            // Only publish real changes; the repository notifies on every poll.
            if deviceName != device.name { deviceName = device.name }
            if isDeviceConnected != device.isConnected {
                isDeviceConnected = device.isConnected
            }
        } else if isDeviceConnected {
            isDeviceConnected = false
        }
    }

    /// Keeps the per-device published map in sync with the visible options.
    private func publishOptions() {
        guard let deviceID else { return }
        optionsByDevice[deviceID] = options
    }

    private func identity(for deviceID: String) -> String {
        repository.devices.first(where: { $0.id == deviceID })?.stableID ?? deviceID
    }

    // MARK: - Options

    private func loadOptions(for deviceID: String) {
        let identity = identity(for: deviceID)
        options = MirrorOptions(
            audioForwarding: repository.isAudioEnabled(for: deviceID),
            alwaysOnTop: preferences.bool(
                "mirrorControls.alwaysOnTop", for: identity, default: false),
            screenOff: preferences.bool(
                "mirrorControls.screenOff", for: identity, default: false),
            borderless: repository.isBorderlessEnabled(for: deviceID),
            clipboard: repository.isClipboardEnabled(for: deviceID),
            recording: recordingStartedAt != nil,
            macKeyboard: preferences.bool(
                "mirrorControls.macKeyboard", for: identity, default: true))
        publishOptions()
    }

    func setAudioForwarding(_ enabled: Bool) {
        guard options.audioForwarding != enabled else { return }
        options.audioForwarding = enabled
        publishOptions()
        if repository.isAudioEnabled(for: deviceID ?? "") != enabled {
            repository.toggleAudio(for: deviceID ?? "")
        }
        scheduleApply()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        guard options.alwaysOnTop != enabled else { return }
        options.alwaysOnTop = enabled
        publishOptions()
        persistToggleOptions()
        scheduleApply()
    }

    func setScreenOff(_ enabled: Bool) {
        guard options.screenOff != enabled else { return }
        options.screenOff = enabled
        publishOptions()
        persistToggleOptions()
        scheduleApply()
    }

    func setFrameChoice(_ choice: MirrorFrameChoice) {
        setBorderless(choice.borderless)
    }

    func setBorderless(_ enabled: Bool) {
        guard options.borderless != enabled else { return }
        options.borderless = enabled
        publishOptions()
        if repository.isBorderlessEnabled(for: deviceID ?? "") != enabled {
            repository.toggleBorderless(for: deviceID ?? "")
        }
        scheduleApply()
    }

    /// Real clipboard-bridge toggle (starts/stops the watcher); the mirror is
    /// restarted so scrcpy's autosync flag matches.
    func toggleClipboard() {
        setClipboard(!options.clipboard)
    }

    func setClipboard(_ enabled: Bool) {
        guard options.clipboard != enabled else { return }
        options.clipboard = enabled
        publishOptions()
        if repository.isClipboardEnabled(for: deviceID ?? "") != enabled {
            repository.toggleClipboard(for: deviceID ?? "")
        }
        scheduleApply()
    }

    func setMacKeyboard(_ enabled: Bool) {
        guard options.macKeyboard != enabled else { return }
        options.macKeyboard = enabled
        publishOptions()
        persistToggleOptions()
        scheduleApply()
    }

    private func persistToggleOptions() {
        guard let deviceID else { return }
        let identity = identity(for: deviceID)
        preferences.setBool(options.alwaysOnTop, "mirrorControls.alwaysOnTop", for: identity)
        preferences.setBool(options.screenOff, "mirrorControls.screenOff", for: identity)
        preferences.setBool(options.macKeyboard, "mirrorControls.macKeyboard", for: identity)
    }

    /// Only the option toggles restart the mirror; the restart is debounced so
    /// flipping two switches in a row produces one process, not two.
    private func scheduleApply() {
        guard isPresented else { return }
        applyWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.applyMirrorOptions() }
        applyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    // MARK: - Apply

    /// Restarts (or starts) the mirror with the current options, reusing the
    /// user's existing quality preset from the repository.
    func applyMirrorOptions() {
        applyWorkItem?.cancel()
        applyWorkItem = nil

        guard let deviceID else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard let device = currentDevice() else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard device.isConnected else {
            lastError = MirrorControlsError.deviceOffline(device.name).errorDescription
            return
        }

        let quality = MirrorQuality(
            maxSize: repository.getMaxSize(for: deviceID),
            maxFPS: repository.getMaxFPS(for: deviceID),
            bitRate: repository.getBitRate(for: deviceID),
            orientation: repository.getOrientation(for: deviceID),
            flexDisplay: repository.isFlexDisplayEnabled(for: deviceID))
        let wasMirroring = adb.isMirrorSessionActive(deviceID: deviceID)

        isApplying = true
        lastError = nil
        statusMessage = wasMirroring ? "Restarting the mirror…" : "Starting the mirror…"

        let started = adb.startMirrorSession(
            deviceID: deviceID,
            deviceName: device.name,
            quality: quality,
            options: options,
            recordPath: nil)

        isApplying = false
        if started {
            isMirroring = true
            statusMessage =
                wasMirroring
                ? "Mirror restarted. The new options are live."
                : "Mirror started with the selected options."
        } else {
            isMirroring = adb.isMirrorSessionActive(deviceID: deviceID)
            lastError = "The mirror could not start. Check the error alert for details."
        }
    }

    // MARK: - Screenshot

    func screenshot() {
        guard let deviceID else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard let device = currentDevice() else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard device.isConnected else {
            lastError = MirrorControlsError.deviceOffline(device.name).errorDescription
            return
        }
        guard let adbPath = adb.adbPath else {
            lastError = MirrorControlsError.adbUnavailable.errorDescription
            return
        }

        statusMessage = "Capturing a screenshot…"
        lastError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.captureScreenshot(adbPath: adbPath, deviceID: deviceID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let outcome):
                    self.lastCapturePath = MirrorCaptureNaming.displayPath(outcome.url)
                    self.statusMessage = outcome.copiedToClipboard
                        ? "Screenshot saved to \(MirrorCaptureNaming.displayPath(outcome.url)) and copied to the clipboard."
                        : "Screenshot saved to \(MirrorCaptureNaming.displayPath(outcome.url))."
                    self.lastError = outcome.copiedToClipboard ? nil : outcome.warning
                case .failure(let error):
                    self.statusMessage = nil
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Recording

    func startOrStopRecording() {
        guard !isSavingRecording else { return }
        if recordingStartedAt != nil {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard recordingStartedAt == nil else { return }
        guard let deviceID else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard let device = currentDevice() else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard device.isConnected else {
            lastError = MirrorControlsError.deviceOffline(device.name).errorDescription
            return
        }
        guard let adbPath = adb.adbPath else {
            lastError = MirrorControlsError.adbUnavailable.errorDescription
            return
        }

        let stamp = MirrorCaptureNaming.timestamp(Date())
        let remotePath = "/sdcard/AndroLaunch-record-\(stamp).mp4"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = [
            "-s", deviceID, "shell", "screenrecord", "--time-limit", "180", remotePath,
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.finalizeRecording(
                    exitStatus: process.terminationStatus, output: output)
            }
        }

        do {
            try task.run()
        } catch {
            lastError = "Screen recording could not start: \(error.localizedDescription)"
            return
        }

        recordingProcess = task
        recordingRemotePath = remotePath
        recordingDeviceID = deviceID
        recordingStartedAt = Date()
        options.recording = true
        publishOptions()
        lastError = nil
        statusMessage = "Recording on \(device.name). It stops automatically after 3 minutes."
    }

    private func stopRecording() {
        guard !isSavingRecording else { return }
        guard let deviceID = recordingDeviceID else { return }
        guard let adbPath = adb.adbPath else {
            lastError = MirrorControlsError.adbUnavailable.errorDescription
            return
        }
        statusMessage = "Stopping the recording…"
        // Android finalizes the MP4 on SIGINT; `pkill` is the reliable way to
        // reach the phone-side screenrecord from a local adb shell process.
        Self.runADBAndWait(
            adbPath: adbPath,
            arguments: ["-s", deviceID, "shell", "pkill", "-INT", "screenrecord"]
        ) { [weak self] _ in
            guard let self else { return }
            // Some Android builds report success from `pkill` while refusing the
            // signal (EPERM). If the local session is still alive a second later,
            // try the PID-based signal too; the 3-minute screenrecord limit is the
            // last resort.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let process = self.recordingProcess, process.isRunning else {
                    return
                }
                Self.runADBAndWait(
                    adbPath: adbPath,
                    arguments: [
                        "-s", deviceID, "shell", "kill", "-2", "$(pidof screenrecord)",
                    ]) { _ in }
            }
            // If the local adb shell still never notices, terminate it after a
            // grace period; the phone-side limit still finalizes the file and the
            // pull below retries briefly while it settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, let process = self.recordingProcess, process.isRunning else {
                    return
                }
                process.terminate()
            }
        }
    }

    private func finalizeRecording(exitStatus: Int32, output: String) {
        guard !isFinalizingRecording,
            let remotePath = recordingRemotePath,
            let deviceID = recordingDeviceID,
            let adbPath = adb.adbPath
        else { return }
        isFinalizingRecording = true
        isSavingRecording = true
        let startedAt = recordingStartedAt ?? Date()

        recordingProcess = nil
        recordingRemotePath = nil
        recordingDeviceID = nil
        recordingStartedAt = nil
        options.recording = false
        statusMessage = "Saving the recording…"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.pullRecording(
                adbPath: adbPath,
                deviceID: deviceID,
                remotePath: remotePath,
                startedAt: startedAt)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isFinalizingRecording = false
                self.isSavingRecording = false
                switch result {
                case .success(let url):
                    self.lastCapturePath = MirrorCaptureNaming.displayPath(url)
                    self.statusMessage =
                        "Recording saved to \(MirrorCaptureNaming.displayPath(url))."
                    self.lastError = nil
                    self.options.recording = false
                case .failure(let error):
                    self.statusMessage = nil
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Navigation

    func press(_ key: MirrorNavKey) {
        guard let deviceID else {
            lastError = MirrorControlsError.noDevice.errorDescription
            return
        }
        guard isDeviceConnected else {
            lastError = MirrorControlsError.deviceOffline(deviceName).errorDescription
            return
        }
        adb.executeADBCommand(
            arguments: ["-s", deviceID, "shell", "input", "keyevent", "\(key.keycode)"]
        ) { [weak self] success, _, errorOutput in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.statusMessage = "Sent \(key.title)."
                    self.lastError = nil
                } else {
                    self.lastError =
                        errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "The \(key.title.lowercased()) key could not be sent."
                }
            }
        }
    }

    // MARK: - Recording cleanup

    deinit {
        applyWorkItem?.cancel()
    }

    // MARK: - Process helpers

    /// Captures a PNG with `adb exec-out screencap -p`, saves it to the Desktop
    /// under a unique timestamped name and copies it to the pasteboard.
    private static func captureScreenshot(
        adbPath: String, deviceID: String
    ) -> Result<MirrorCaptureOutcome, MirrorControlsError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", deviceID, "exec-out", "screencap", "-p"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .failure(.screenshotFailed(error.localizedDescription))
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail =
                String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.screenshotFailed(detail?.isEmpty == false ? detail! : "adb exited with \(process.terminationStatus)."))
        }
        guard data.count > 8 else {
            return .failure(.invalidScreenshot("adb returned no image data."))
        }
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard Array(data.prefix(8)) == pngMagic else {
            // Known cause: Android 12+ screenshots can be HEIC/raw when a
            // non-PNG format is forced; tell the user rather than saving junk.
            return .failure(
                .invalidScreenshot(
                    "The phone returned data that isn't PNG. Update the phone or use screen recording instead."))
        }

        let fileManager = FileManager.default
        guard let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fileManager.fileExists(atPath: desktop.path)
        else {
            return .failure(.desktopUnavailable)
        }
        let existing = (try? fileManager.contentsOfDirectory(atPath: desktop.path)) ?? []
        let name = MirrorCaptureNaming.fileName(
            prefix: "AndroLaunch", date: Date(), fileExtension: "png", existingNames: existing)
        let url = desktop.appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            return .failure(.screenshotFailed(error.localizedDescription))
        }

        // Clipboard copy is a convenience, not a requirement.
        var copied = false
        if let image = NSImage(data: data), image.size.width > 0 {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            copied = pasteboard.setData(data, forType: .png)
        }
        return .success(
            MirrorCaptureOutcome(
                url: url,
                copiedToClipboard: copied,
                warning: copied ? nil : "Saved the screenshot, but the clipboard copy failed."))
    }

    private static func pullRecording(
        adbPath: String, deviceID: String, remotePath: String, startedAt: Date
    ) -> Result<URL, MirrorControlsError> {
        let fileManager = FileManager.default
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("AndroLaunch-record-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        func pull() -> Int32 {
            runAndWait(
                executable: adbPath,
                arguments: ["-s", deviceID, "pull", remotePath, temporaryURL.path])
        }

        var pullStatus = pull()
        var fileSize =
            (try? fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber)?
            .intValue ?? 0
        // A just-stopped screenrecord may still be finalizing the MP4; one short
        // retry avoids saving a header-only file when the signal lands late.
        if pullStatus == 0, fileSize < 10_000 {
            Thread.sleep(forTimeInterval: 1.5)
            pullStatus = pull()
            fileSize =
                (try? fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber)?
                .intValue ?? 0
        }
        guard pullStatus == 0, fileSize > 0 else {
            return .failure(
                .recordingPullFailed(
                    "The file is still on the phone at \(remotePath)."))
        }

        let moviesDirectory: URL
        if let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first {
            moviesDirectory = movies
        } else {
            moviesDirectory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Movies")
        }
        do {
            try fileManager.createDirectory(
                at: moviesDirectory, withIntermediateDirectories: true)
        } catch {
            return .failure(.moviesUnavailable)
        }

        let existing = (try? fileManager.contentsOfDirectory(atPath: moviesDirectory.path)) ?? []
        let name = MirrorCaptureNaming.fileName(
            prefix: "AndroLaunch", date: startedAt, fileExtension: "mp4",
            existingNames: existing)
        let destination = moviesDirectory.appendingPathComponent(name)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
        } catch {
            // Cross-volume moves can fail; fall back to copy + remove.
            do {
                try fileManager.copyItem(at: temporaryURL, to: destination)
            } catch {
                return .failure(.recordingPullFailed(error.localizedDescription))
            }
        }

        // Best-effort cleanup of the phone-side file.
        _ = runAndWait(
            executable: adbPath, arguments: ["-s", deviceID, "shell", "rm", "-f", remotePath])
        return .success(destination)
    }

    private static func runAndWait(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func runADBAndWait(
        adbPath: String, arguments: [String], completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = runAndWait(executable: adbPath, arguments: arguments)
            DispatchQueue.main.async { completion(status == 0) }
        }
    }
}
