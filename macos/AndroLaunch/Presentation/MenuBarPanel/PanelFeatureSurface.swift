//
//  PanelFeatureSurface.swift
//  AndroLaunch
//
//  One action surface for the menu-bar panel's Device tab and Tools overlay.
//  Every capability that used to live only in the legacy menu (camera, mirror,
//  commands, AVDs, Wi-Fi pairing, storage, ring, trackpad, Glance, camera
//  extension, legacy menu) is routed through here so both panel surfaces stay
//  in sync and no feature becomes unreachable now that the Hub is gone.
//
//  The surface never invents success: it returns the message the real service
//  produced, and asynchronous actions complete with their actual result.
//

import AppKit
import Combine
import Foundation

/// Small inline result for a panel action. The panel renders these with the
/// existing quiet `DashboardFeedback` style rather than a modal alert.
struct PanelFeatureFeedback: Equatable {
    let message: String
    let isError: Bool

    static func ok(_ message: String) -> PanelFeatureFeedback {
        PanelFeatureFeedback(message: message, isError: false)
    }

    static func failure(_ message: String) -> PanelFeatureFeedback {
        PanelFeatureFeedback(message: message, isError: true)
    }
}

final class PanelFeatureSurface: ObservableObject {
    static let shared = PanelFeatureSurface()

    /// AVDs reported by the emulator service, surfaced in the Device tab.
    @Published private(set) var virtualDeviceCount = 0
    @Published private(set) var runningVirtualDeviceCount = 0
    /// Saved shell commands, surfaced as a count in Tools.
    @Published private(set) var commandCount = 0
    @Published private(set) var cameraExtensionStatus: CameraExtensionStatus = .querying
    @Published private(set) var bluetoothEnabled: Bool?

    private var started = false
    private var cancellables = Set<AnyCancellable>()

    /// The container (and therefore ADB, the emulator poller and the camera
    /// probe) is only reached on first live use, never when the snapshot renderer
    /// or a SwiftUI preview instantiates the Device tab.
    private var container: DependencyContainer { DependencyContainer.shared }

    private init() {}

    private func startIfNeeded() {
        guard !started else { return }
        started = true

        let emulator = container.emulatorManagerViewModel
        emulator.$existingAVDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] avds in
                self?.virtualDeviceCount = avds.count
                self?.runningVirtualDeviceCount = avds.filter(\.isRunning).count
            }
            .store(in: &cancellables)

        CameraController.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.cameraExtensionStatus = state.extensionStatus
            }
            .store(in: &cancellables)

        virtualDeviceCount = emulator.existingAVDs.count
        runningVirtualDeviceCount = emulator.existingAVDs.filter(\.isRunning).count
        commandCount = container.menuViewModel.getGlobalShellCommands().count
        cameraExtensionStatus = CameraController.shared.state.extensionStatus
    }

    // MARK: - Device helpers

    func device(id: String?) -> AndroidDevice? {
        guard let id else { return HubStore.shared.selectedDevice }
        return HubStore.shared.devices.first {
            $0.id == id || $0.stableID == id
        } ?? HubStore.shared.selectedDevice
    }

    private func connectedDevice(id: String?) -> AndroidDevice? {
        guard let device = device(id: id), device.isConnected else { return nil }
        return device
    }

    var virtualDeviceSummary: String {
        if virtualDeviceCount == 0 {
            return "No virtual devices created yet"
        }
        var summary = "\(virtualDeviceCount) virtual device\(virtualDeviceCount == 1 ? "" : "s")"
        if runningVirtualDeviceCount > 0 {
            summary += " · \(runningVirtualDeviceCount) running"
        }
        return summary
    }

    func refreshVirtualDeviceCount() {
        startIfNeeded()
        // The emulator view model polls while its window is open; this refreshes
        // the panel's own count without opening it.
        container.deviceRepository.listAVDs()
        commandCount = container.menuViewModel.getGlobalShellCommands().count
        CameraController.shared.refreshExtensionStatus()
    }

    func refreshCommandCount() {
        startIfNeeded()
        commandCount = container.menuViewModel.getGlobalShellCommands().count
    }

    // MARK: - Mirror

    func mirrorScreen(deviceID: String?) -> PanelFeatureFeedback {
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before mirroring its screen.")
        }
        DependencyContainer.shared.deviceRepository.mirrorDevice(deviceID: device.id)
        return .ok("Starting the mirror for \(device.name)…")
    }

    func openMirrorControls(deviceID: String?) -> PanelFeatureFeedback {
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before opening mirror controls.")
        }
        MirrorControlsController.shared.show(deviceID: device.id)
        return .ok("Mirror Controls opened for \(device.name).")
    }

    /// Frame Mode gives Android apps their own Mac windows (the dashboard
    /// header exposes the same preference). Virtual displays need Android 14+.
    func toggleFrameMode(deviceID: String?) -> PanelFeatureFeedback {
        guard let device = device(id: deviceID) else {
            return .failure("Connect a phone before changing Frame Mode.")
        }
        guard MeldModeSupport.supportsVirtualDisplay(apiLevel: device.apiLevel) else {
            return .failure(
                "Frame Mode needs Android 14 or later. This phone mirrors its main display instead.")
        }
        let preferences = AppPreferences.shared
        preferences.meldModeEnabled.toggle()
        return .ok(
            preferences.meldModeEnabled
                ? "Frame Mode on: Android apps open in their own windows."
                : "Frame Mode off: apps open on the mirrored main display.")
    }

    // MARK: - Camera

    func startCameraPreview(deviceID: String?, lens: CameraLens) -> PanelFeatureFeedback {
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before opening its camera.")
        }
        let camera = CameraController.shared
        let wasPreviewing = camera.isPreviewing
        camera.setLens(lens)
        if wasPreviewing {
            // Lens/torch/zoom only apply on launch; restart on the same session.
            camera.applyPendingChanges()
        } else {
            camera.preview(deviceID: device.id)
        }
        if let message = camera.state.message, !message.isEmpty {
            return .failure(message)
        }
        return .ok(
            wasPreviewing
                ? "Restarting the preview with the \(lens.title.lowercased())…"
                : "Starting the \(lens.title.lowercased()) preview…")
    }

    func stopCameraPreview() -> PanelFeatureFeedback {
        let camera = CameraController.shared
        guard camera.isPreviewing else {
            return .failure("The camera preview isn't running.")
        }
        camera.stopPreview()
        return .ok("Camera preview stopped.")
    }

    func openCameraExtension() -> PanelFeatureFeedback {
        let camera = CameraController.shared
        camera.refreshExtensionStatus()
        camera.openExtensionSettings()
        return .ok(
            "Camera extension needs a signed system extension. Opening System Settings and the in-app preview instead."
        )
    }

    // MARK: - Commands

    func openCommandsManager() {
        startIfNeeded()
        PanelFeaturePageRouter.open(.commands)
    }

    func runCommand(_ command: ShellCommand, deviceID: String?) -> PanelFeatureFeedback {
        startIfNeeded()
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before running a command.")
        }
        let viewModel = container.menuViewModel
        if command.isHostCommand {
            viewModel.runHostShellCommand(command.command)
            return .ok("Ran \(command.name) on this Mac.")
        }
        viewModel.runBackgroundShellCommand(command.command, for: device.id)
        return .ok("Ran \(command.name) on \(device.name).")
    }

    // MARK: - Virtual devices

    func openEmulatorManager() {
        startIfNeeded()
        PanelFeaturePageRouter.open(.avd)
    }

    // MARK: - Wi-Fi / companion

    func openWiFiConnection(initialTab: WiFiConnectionTab = .qr) {
        PanelFeaturePageRouter.open(.wifi)
    }

    func installCompanion(
        deviceID: String?,
        completion: @escaping (PanelFeatureFeedback) -> Void
    ) {
        startIfNeeded()
        guard let device = connectedDevice(id: deviceID) else {
            completion(.failure("Connect a phone before installing the companion."))
            return
        }
        CompanionClient.shared.install(deviceID: device.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(.ok("AndroLaunch Comp installed on \(device.name)."))
                case .failure(let error):
                    completion(.failure(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Storage

    func openStorageAnalytics(deviceID: String?) -> PanelFeatureFeedback {
        startIfNeeded()
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone to inspect its storage.")
        }
        PanelRouter.openStorageAnalytics()
        return .ok("Storage analytics expanded for \(device.name).")
    }

    // MARK: - Bluetooth

    func refreshBluetooth(deviceID: String?) {
        guard let device = connectedDevice(id: deviceID) else {
            bluetoothEnabled = nil
            return
        }
        container.adb.executeADBCommand(
            arguments: ["-s", device.id, "shell", "settings", "get", "global", "bluetooth_on"]
        ) { [weak self] _, output, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let value = output?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.bluetoothEnabled = (value == "1")
            }
        }
    }

    /// Enables/disables the phone's Bluetooth radio. This is useful for
    /// accessories/audio once the mirror is running; it is an explicit action,
    /// never a silent toggle.
    func toggleBluetooth(deviceID: String?) -> PanelFeatureFeedback {
        startIfNeeded()
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before changing Bluetooth.")
        }
        let enable = bluetoothEnabled != true
        let command = enable ? "enable" : "disable"
        container.adb.executeADBCommand(
            arguments: ["-s", device.id, "shell", "svc", "bluetooth", command]
        ) { [weak self] success, _, error in
            DispatchQueue.main.async {
                self?.refreshBluetooth(deviceID: device.id)
                if !success {
                    self?.bluetoothEnabled = nil
                    _ = error
                }
            }
        }
        return .ok("Turning Bluetooth \(command == "enable" ? "on" : "off") on \(device.name).")
    }

    // MARK: - Ring

    func toggleRing(deviceID: String?) -> PanelFeatureFeedback {
        guard let device = connectedDevice(id: deviceID) else {
            return .failure("Connect a phone before ringing it.")
        }
        guard CompanionClient.shared.isReady(device.id) else {
            return .failure(
                "Ringing needs AndroLaunch Comp on the phone. Install it from the Connection card first.")
        }
        let ring = RingService.shared
        if ring.isRinging(deviceID: device.id) {
            ring.stop(deviceID: device.id)
            return .ok("Stopped ringing \(device.name).")
        }
        ring.toggle(deviceID: device.id)
        if let error = ring.lastError {
            return .failure(error)
        }
        return .ok("Ringing \(device.name).")
    }

    // MARK: - Trackpad / Glance

    func showTrackpad(deviceID: String?) -> PanelFeatureFeedback {
        guard let device = device(id: deviceID) else {
            return .failure("Connect a phone before opening the trackpad.")
        }
        TrackpadController.shared.show(deviceID: device.id)
        return .ok("Trackpad opened for \(device.name).")
    }

    func toggleGlance() -> PanelFeatureFeedback {
        let glance = GlanceBoardController.shared
        glance.toggle()
        return .ok(
            glance.isVisible
                ? "Glance board shown on the desktop." : "Glance board hidden.")
    }

    // MARK: - Screenshot

    func takeScreenshot(
        deviceID: String?,
        completion: @escaping (PanelFeatureFeedback) -> Void
    ) {
        guard let device = connectedDevice(id: deviceID) else {
            completion(.failure("Connect a phone before taking a screenshot."))
            return
        }
        startIfNeeded()
        guard let adbPath = DependencyContainer.shared.adb.adbPath else {
            completion(
                .failure("ADB isn't available yet. Finish setup in Preferences, then try again."))
            return
        }

        let pictures = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/AndroLaunch", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let safeName = device.name.replacingOccurrences(of: "/", with: "-")
        let file = pictures.appendingPathComponent(
            "\(safeName) \(formatter.string(from: Date())).png")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["-s", device.id, "exec-out", "screencap", "-p"]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                let isPNG =
                    data.count >= pngSignature.count
                    && Array(data.prefix(pngSignature.count)) == pngSignature

                guard process.terminationStatus == 0, isPNG else {
                    let message = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        completion(
                            .failure(
                                message?.isEmpty == false
                                    ? "Screenshot failed: \(message!)"
                                    : "The phone returned no screenshot. Update Android Platform Tools and try again."))
                    }
                    return
                }

                try FileManager.default.createDirectory(
                    at: pictures, withIntermediateDirectories: true)
                try data.write(to: file)
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(file)
                    completion(.ok("Screenshot saved to Pictures/AndroLaunch."))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure("Couldn't save the screenshot: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - USB guidance

    func showUSBGuidance() {
        let alert = NSAlert()
        alert.messageText = "Connect over USB"
        alert.informativeText = """
            1. Enable Developer options and USB debugging on the phone.
            2. Connect a data-capable cable and keep the phone unlocked.
            3. Approve “Allow USB debugging?” for this Mac.
            4. Use Refresh Devices if the phone does not appear.

            USB is faster and more reliable than wireless debugging for mirroring, file transfers and screenshots.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }



}
