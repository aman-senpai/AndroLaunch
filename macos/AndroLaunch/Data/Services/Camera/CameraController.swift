//
//  CameraController.swift
//  AndroLaunch
//
//  Phone camera preview via scrcpy plus honest status for the Mac camera
//  extension. Owned by the platform-extras feature.
//
//  What is real in this build:
//  - A live camera preview in its own scrcpy window (front/back lens, torch,
//    zoom, aspect ratio) driven by the selected Hub device.
//  - State reflects the actual scrcpy process: it is cleared when the window is
//    closed or the device disappears.
//
//  What is limited (stated plainly in the UI, never faked):
//  - The CoreMediaIO system extension that would let Zoom/QuickTime pick the
//    phone as a webcam needs a signed, notarised extension target. This build
//    cannot ship or install one, so the status stays "Not available" unless a
//    future signed extension is genuinely present on the Mac.
//

import AppKit
import Combine
import Foundation
import SystemExtensions

final class CameraController: ObservableObject {
    static let shared = CameraController()

    // MARK: - Published state

    /// Single source of truth for the camera card. Rebuilt whenever settings,
    /// device state or the preview process change.
    @Published private(set) var state = CameraPreviewState()

    // MARK: - Preview settings (apply to the next launch)

    private var lens: CameraLens = .back
    private var aspect: CameraAspect = .wide
    private var torchEnabled = false
    private var zoom: Double = CameraZoom.minimum
    private var message: String?
    private var needsRestart = false

    // MARK: - Preview process tracking

    private var previewDeviceID: String?
    private var isStarting = false
    private var previewActive = false
    private var monitor: Timer?
    private var startToken = UUID()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let scrcpy: any ScrcpyServiceProtocol
    private let adbPathProvider: () -> String?

    // MARK: - Init

    init(
        scrcpyService: any ScrcpyServiceProtocol = DependencyContainer.shared.scrcpyService,
        adbPath: @escaping () -> String? = { DependencyContainer.shared.deviceRepository.adbPath }
    ) {
        self.scrcpy = scrcpyService
        self.adbPathProvider = adbPath
        observeDevices()
        observeScrcpyErrors()
        refreshExtensionStatus()
        syncState()
    }

    // MARK: - Public read access

    /// True while a preview window is starting or running.
    var isPreviewing: Bool { previewActive || isStarting }

    var actions: CameraSettingsActions {
        CameraSettingsActions(
            startPreview: { [weak self] in self?.preview() },
            stopPreview: { [weak self] in self?.stopPreview() },
            restartPreview: { [weak self] in self?.applyPendingChanges() },
            setLens: { [weak self] in self?.setLens($0) },
            setAspect: { [weak self] in self?.setAspect($0) },
            setTorch: { [weak self] in self?.setTorch($0) },
            setZoom: { [weak self] in self?.setZoom($0) },
            refreshExtensionStatus: { [weak self] in self?.refreshExtensionStatus() },
            openExtensionSettings: { [weak self] in self?.openExtensionSettings() },
            installExtension: { [weak self] in self?.installExtension() },
            clearMessage: { [weak self] in self?.clearMessage() }
        )
    }

    func canPreview(deviceID: String) -> Bool {
        guard HubStore.shared.devices.contains(where: { $0.id == deviceID && $0.isConnected })
        else { return false }
        return scrcpyAvailable
    }

    private var scrcpyAvailable: Bool {
        scrcpy.scrcpyPath != nil || scrcpy.detectScrcpyPath() != nil
    }

    // MARK: - Preview lifecycle

    /// Start (or keep) the camera preview for `deviceID`, defaulting to the
    /// selected Hub device.
    func preview(deviceID: String? = nil) {
        guard let device = resolveDevice(deviceID) else {
            setMessage("Connect an Android device in the Hub to preview its camera.")
            return
        }
        guard device.isConnected else {
            setMessage("\(device.name) is not connected.")
            return
        }
        guard scrcpyAvailable else {
            setMessage(
                "scrcpy isn't installed. Install it with Homebrew (`brew install scrcpy`) to preview the camera."
            )
            return
        }
        if isPreviewing {
            if previewDeviceID == device.id { return }
            stopPreview(silently: true)
        }
        // Do not block the launch on a dumpsys preflight: on some Xiaomi builds
        // `dumpsys media.camera` can stall the shared ADB queue indefinitely.
        // scrcpy's stderr already carries the useful CAMERA_IN_USE reason.
        launchPreview(device: device)
    }

    func stopPreview() {
        stopPreview(silently: false)
    }

    func switchCamera() {
        setLens(lens == .back ? .front : .back)
    }

    func toggleTorch() {
        setTorch(!torchEnabled)
    }

    func applyPendingChanges() {
        restartPreview()
    }

    func clearMessage() {
        message = nil
        syncState()
    }

    // MARK: - Settings

    func setLens(_ newLens: CameraLens) {
        guard newLens != lens else { return }
        lens = newLens
        if !newLens.supportsTorch { torchEnabled = false }
        if isPreviewing {
            restartPreview()
        } else {
            needsRestart = false
            syncState()
        }
    }

    func setAspect(_ newAspect: CameraAspect) {
        guard newAspect != aspect else { return }
        aspect = newAspect
        markNeedsRestartIfPreviewing()
    }

    func setTorch(_ enabled: Bool) {
        let effective = enabled && lens.supportsTorch
        guard effective != torchEnabled else { return }
        torchEnabled = effective
        markNeedsRestartIfPreviewing()
    }

    func setZoom(_ newZoom: Double) {
        let clamped = CameraZoom.clamp(newZoom)
        guard abs(clamped - zoom) > 0.001 else { return }
        zoom = clamped
        markNeedsRestartIfPreviewing()
    }

    private func markNeedsRestartIfPreviewing() {
        needsRestart = isPreviewing
        if isPreviewing {
            message = "Restart the preview to apply the new setting."
        }
        syncState()
    }

    // MARK: - Extension

    func refreshExtensionStatus() {
        state.extensionStatus = .querying
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = Self.probeExtensionStatus()
            DispatchQueue.main.async {
                self?.state.extensionStatus = status
                self?.syncState()
            }
        }
    }

    /// Opens System Settings where system extensions are managed and explains,
    /// plainly, that this build has nothing to install.
    func openExtensionSettings() {
        setMessage(
            "Camera extensions live in System Settings › General › Login Items & Extensions. For the local test extension, run scripts/install-local-camera-extension.sh and follow its SIP/developer-mode steps."
        )
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security?LoginItems",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { break }
        }
    }

    func installExtension() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            setMessage(
                "Install the app in /Applications first, then run scripts/install-local-camera-extension.sh. macOS won't activate a system extension from a DerivedData build.")
            return
        }
        setMessage("Requesting camera-extension activation…")
        CameraExtensionInstaller.shared.activate { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let detail):
                self.setMessage(detail)
                self.refreshExtensionStatus()
            case .failure(let error):
                self.setMessage(
                    "Camera extension activation failed: \(error.localizedDescription). Run `sudo systemextensionsctl developer on` (requires the SIP developer-mode reduction) and try again."
                )
            }
        }
    }

    // MARK: - scrcpy errors

    private func observeScrcpyErrors() {
        scrcpy.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self, let error, error.hasPrefix("Camera: ") else { return }
                self.isStarting = false
                self.previewActive = false
                self.previewDeviceID = nil
                self.message = String(error.dropFirst("Camera: ".count))
                self.syncState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Device observation

    private func observeDevices() {
        HubStore.shared.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                if let deviceID = self.previewDeviceID,
                    !devices.contains(where: { $0.id == deviceID && $0.isConnected })
                {
                    self.stopPreview(silently: true)
                    self.message = "Device disconnected — camera preview stopped."
                }
                self.syncState()
            }
            .store(in: &cancellables)
    }

    private func resolveDevice(_ deviceID: String?) -> AndroidDevice? {
        let store = HubStore.shared
        let devices = store.devices
        if let deviceID, let requested = devices.first(where: { $0.id == deviceID }) {
            if requested.isConnected { return requested }
            // ADB can leave a stale Wi-Fi transport visible as "offline" while the
            // same phone is online under its mDNS/another endpoint. Prefer the
            // live transport instead of failing the camera on the stale id.
            if let serial = requested.serialNumber,
                let alternate = devices.first(where: {
                    $0.isConnected && $0.id != requested.id && $0.serialNumber == serial
                })
            {
                return alternate
            }
            if let model = requested.model,
                let alternate = devices.first(where: {
                    $0.isConnected && $0.id != requested.id && $0.model == model
                })
            {
                return alternate
            }
            return requested
        }
        if let selected = store.selectedDevice, selected.isConnected {
            return selected
        }
        return devices.first(where: \.isConnected)
    }

    // MARK: - Launch

    private func launchPreview(device: AndroidDevice) {
        message = nil
        needsRestart = false
        isStarting = true
        previewActive = false
        previewDeviceID = device.id

        // `ScrcpyService` builds and owns the scrcpy invocation for the camera
        // window. Torch and zoom are scrcpy launch options, so changing them
        // while previewing restarts the process (see `needsRestart`).
        scrcpy.mirrorCamera(
            deviceID: device.id,
            adbPath: adbPathProvider(),
            audioEnabled: false,
            facing: lens.scrcpyValue,
            fps: 30,
            size: 1280,
            bitRate: 12,
            orientation: nil,
            aspectRatio: aspect.scrcpyValue,
            cameraTorch: torchEnabled && lens.supportsTorch,
            cameraZoom: CameraZoom.scrcpyValue(zoom)
        )

        let token = UUID()
        startToken = token
        syncState()

        // scrcpy reports startup problems asynchronously. Verify the real process
        // shortly after launch instead of trusting the request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.startToken == token else { return }
            self.verifyStart(deviceID: device.id, token: token)
        }
    }

    private func verifyStart(deviceID: String, token: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let running = CameraScrcpyProcess.isRunning(deviceID: deviceID)
            DispatchQueue.main.async {
                guard let self, self.startToken == token else { return }
                self.isStarting = false
                if running {
                    self.previewActive = true
                    self.message = nil
                    self.startMonitor(deviceID: deviceID)
                } else {
                    self.previewActive = false
                    self.previewDeviceID = nil
                    if self.message == nil {
                        self.message =
                            "scrcpy couldn't start the camera. Unlock the phone and close any other camera app, then try again."
                    }
                }
                self.syncState()
            }
        }
    }

    private func restartPreview() {
        guard let deviceID = previewDeviceID else {
            needsRestart = false
            syncState()
            return
        }
        stopPreview(silently: true)
        guard let device = resolveDevice(deviceID) else {
            setMessage("Device disconnected — camera preview stopped.")
            return
        }
        launchPreview(device: device)
    }

    private func stopPreview(silently: Bool) {
        let deviceID = previewDeviceID
        startToken = UUID()
        stopMonitor()
        previewActive = false
        isStarting = false
        previewDeviceID = nil
        needsRestart = false

        if let deviceID {
            // Terminate only the camera window for this device. `ScrcpyService`
            // keys camera and mirror processes separately, and a user's mirror
            // window should survive stopping the camera preview.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                if !CameraScrcpyProcess.terminate(deviceID: deviceID) {
                    DispatchQueue.main.async { self.scrcpy.stopMirroring(deviceID: deviceID) }
                }
            }
        }
        if !silently { message = "Camera preview stopped." }
        syncState()
    }

    // MARK: - Process monitoring

    private func startMonitor(deviceID: String) {
        monitor?.invalidate()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let running = CameraScrcpyProcess.isRunning(deviceID: deviceID)
                guard !running else { return }
                DispatchQueue.main.async {
                    guard let self, self.previewDeviceID == deviceID, self.previewActive
                    else { return }
                    self.previewActive = false
                    self.previewDeviceID = nil
                    self.message = "Camera preview closed."
                    self.stopMonitor()
                    self.syncState()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
    }

    private func stopMonitor() {
        monitor?.invalidate()
        monitor = nil
    }

    // MARK: - State

    private func setMessage(_ text: String?) {
        message = text
        syncState()
    }

    private func syncState() {
        let store = HubStore.shared
        let selected = store.selectedDevice
        let device: AndroidDevice? = {
            if let id = previewDeviceID {
                return store.devices.first(where: { $0.id == id }) ?? selected
            }
            return selected
        }()

        var next = CameraPreviewState()
        next.deviceID = device?.id
        next.deviceName = device?.name
        next.isDeviceConnected = device?.isConnected ?? false
        next.isScrcpyAvailable = scrcpyAvailable
        next.lens = lens
        next.aspect = aspect
        next.torchEnabled = torchEnabled
        next.zoom = zoom
        next.isPreviewing = previewActive
        next.isStarting = isStarting
        next.needsRestart = needsRestart
        next.extensionStatus = state.extensionStatus
        next.message = message
        state = next
    }

    // MARK: - Extension probe

    private static func probeExtensionStatus() -> CameraExtensionStatus {
        let bundleURL = Bundle.main.bundleURL
        let directories: [URL?] = [
            bundleURL.appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true),
            bundleURL.appendingPathComponent("Contents/PlugIns", isDirectory: true),
            Bundle.main.builtInPlugInsURL,
        ]
        if let output = runTool(
            "/usr/bin/systemextensionsctl", ["list"], timeout: 2.0),
            let label = CameraExtensionProbe.extensionLabel(fromSystemExtensionList: output)
        {
            return .installed(label)
        }
        if let bundled = CameraExtensionProbe.bundledCameraExtensionName(in: directories) {
            return .installable(bundled)
        }
        return .unavailable("No camera extension is bundled in this build.")
    }

    /// Runs a small read-only tool with a hard timeout. Always call off the main
    /// queue: `systemextensionsctl` can take a moment under load.
    private static func runTool(
        _ path: String, _ arguments: [String], timeout: TimeInterval
    ) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if task.isRunning {
            task.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Camera process tracking

/// Finds and stops the exact scrcpy process that renders the camera preview.
///
/// `ScrcpyService` keeps its process table private and its `stopMirroring`
/// terminates both the mirror and the camera process for a device. The camera
/// window's title is unique ("AndroLaunch Camera - <device>"), so matching on the
/// command line lets the preview stop without closing the user's mirror window.
private enum CameraScrcpyProcess {
    static func isRunning(deviceID: String) -> Bool {
        !pids(deviceID: deviceID).isEmpty
    }

    @discardableResult
    static func terminate(deviceID: String) -> Bool {
        let matches = pids(deviceID: deviceID)
        guard !matches.isEmpty else { return false }
        for pid in matches {
            kill(pid, SIGTERM)
        }
        return true
    }

    static func windowTitleFragment(deviceID: String) -> String {
        "AndroLaunch Camera - \(deviceID)"
    }

    private static func pids(deviceID: String) -> [pid_t] {
        guard let output = run("/usr/bin/pgrep", ["-f", windowTitleFragment(deviceID: deviceID)])
        else { return [] }
        return output.split(whereSeparator: \.isNewline).compactMap {
            pid_t($0.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}


// MARK: - System extension activation

/// Local-signing friendly activation. Works with an Apple Development / Developer
/// ID signature in normal builds, and with a self-signed certificate when
/// `systemextensionsctl developer on` is enabled.
final class CameraExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    static let shared = CameraExtensionInstaller()
    static let extensionIdentifier = "com.senpai.AndroLaunch.CameraExtension"

    private var completion: ((Result<String, Error>) -> Void)?

    func activate(completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier,
            queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            completion?(.success("AndroLaunch Camera extension activated. Pick it in FaceTime, Zoom or QuickTime."))
        case .willCompleteAfterReboot:
            completion?(.success("Camera extension activated; restart the Mac to finish."))
        @unknown default:
            completion?(.success("Camera extension request finished."))
        }
        completion = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // The system shows its own approval prompt; the app stays out of the way.
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension extension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}
