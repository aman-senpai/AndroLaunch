//
//  ClipboardBridge.swift
//  AndroLaunch
//
//  Observable health for the opt-in clipboard bridge. `ADBService` owns the actual
//  sync (scrcpy session + pasteboard watcher + broadcast) and reports events here;
//  this object only owns what the UI needs to know per device.
//

import AppKit
import Combine
import Foundation

/// Direction of the last successful clipboard delivery.
enum ClipboardSyncDirection: Equatable {
    case macToAndroid
    case androidToMac

    var label: String {
        switch self {
        case .macToAndroid: return "Mac → Android"
        case .androidToMac: return "Android → Mac"
        }
    }
}

/// Events reported by `ADBService`'s clipboard implementation.
enum ClipboardSyncEvent {
    case sent(deviceID: String, at: Date)
    case failed(deviceID: String, message: String)
    case companionChecked(deviceID: String, installed: Bool)
}

/// Per-device clipboard bridge state surfaced in the menu.
struct ClipboardBridgeState: Equatable {
    /// Opt-in flag from `DeviceRepository`.
    var enabled: Bool = false
    /// `nil` while the first companion check is still running.
    var companionInstalled: Bool?
    var lastSyncedAt: Date?
    var lastDirection: ClipboardSyncDirection?
    var lastError: String?

    /// Enabled, companion present and no delivery error since the last success.
    var healthy: Bool {
        enabled && companionInstalled == true && lastError == nil
    }
}

/// Owns the clipboard feature's UI state and exposes the explicit user actions.
/// It never duplicates sync logic: every action is delegated to `ADBService`.
final class ClipboardBridge: ObservableObject {
    static let shared = ClipboardBridge()

    /// The companion is shipped with the app and installed over ADB.
    var canInstallCompanion: Bool { CompanionClient.shared.bundledAPKURL != nil }

    @Published private(set) var states: [String: ClipboardBridgeState] = [:]

    private let adb: ADBService
    private let repository: any DeviceRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(
        adb: ADBService = DependencyContainer.shared.adb,
        deviceRepository: any DeviceRepositoryProtocol = DependencyContainer.shared.deviceRepository
    ) {
        self.adb = adb
        self.repository = deviceRepository

        adb.clipboardEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.apply(event) }
            .store(in: &cancellables)

        // The opt-in flag lives in the repository; mirror it into the menu state.
        repository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshEnabledStates() }
            .store(in: &cancellables)
    }

    // MARK: - Reading state

    func state(for deviceID: String) -> ClipboardBridgeState {
        states[deviceID] ?? ClipboardBridgeState()
    }

    /// One-line bridge status for the Clipboard submenu (specifically short).
    func statusText(for deviceID: String) -> String {
        let state = state(for: deviceID)
        guard state.enabled else { return "Off" }
        if state.companionInstalled == false { return "AndroLaunch Comp not installed" }
        if state.companionInstalled == nil { return "Checking AndroLaunch Comp…" }
        if state.lastError != nil { return "Delivery failed" }
        if let lastSyncedAt = state.lastSyncedAt {
            return "Synced \(relativeAge(of: lastSyncedAt)) ago"
        }
        return "On · waiting for clipboard activity"
    }

    /// Tooltip for the Configuration menu toggle: the real companion state, not a promise.
    func tooltip(for deviceID: String) -> String {
        let state = state(for: deviceID)
        let privacy =
            "Clipboard text may include sensitive data; sharing stays opt-in per device until AndroLaunch quits."
        let summary: String
        switch state.companionInstalled {
        case true:
            summary =
                "AndroLaunch Comp is installed. Mac → Android text goes through it; Android → Mac uses the mirrored session."
        case false:
            summary =
                "AndroLaunch Comp is not installed on this device, so Mac → Android clipboard delivery will not work. Install it from the Clipboard menu — no Play Store, no third-party app."
        case nil:
            summary =
                "Checking for AndroLaunch Comp… Android → Mac sharing works through scrcpy; Mac → Android needs AndroLaunch Comp."
        }
        guard let error = state.lastError, !error.isEmpty else {
            return "\(summary) \(privacy)"
        }
        let firstLine = error.components(separatedBy: .newlines).first ?? error
        return "\(summary) Last error: \(firstLine). \(privacy)"
    }

    // MARK: - Actions

    /// Turns the bridge on or off for one device, delegating to the repository/ADBService.
    func setEnabled(_ enabled: Bool, for deviceID: String) {
        if repository.isClipboardEnabled(for: deviceID) != enabled {
            repository.toggleClipboard(for: deviceID)
        }

        updateState(for: deviceID) {
            $0.enabled = enabled
            if !enabled {
                $0.lastSyncedAt = nil
                $0.lastDirection = nil
                $0.lastError = nil
            }
        }

        if enabled {
            adb.checkClipboardCompanion(deviceID: deviceID)
        }
    }

    /// Sends the text currently on this Mac's clipboard to one device (explicit action).
    func sendCurrentClipboard(to deviceID: String) {
        guard
            let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            AlertPresenter.showWarning(
                message:
                    "There is no text on this Mac's clipboard to send. Copy some text first, then choose Send Clipboard to Device.",
                title: "Nothing to Send")
            return
        }

        guard state(for: deviceID).companionInstalled != false else {
            presentCompanionMissingWarning()
            return
        }

        adb.sendClipboardToDevice(deviceID: deviceID, text: text) { [weak self] success in
            guard let self, !success else { return }
            // The failure event already recorded `lastError`; make the explicit action visible.
            if self.state(for: deviceID).companionInstalled == false {
                self.presentCompanionMissingWarning()
            } else {
                AlertPresenter.showWarning(
                    message:
                        "The clipboard text could not be delivered to this device. Make sure it is still connected and AndroLaunch Comp is installed.",
                    title: "Clipboard Delivery Failed")
            }
        }
    }

    // MARK: - Images

    /// True when the Mac clipboard currently holds something the phone can paste
    /// as an image (image data or an image file copied in Finder).
    var pasteboardHasImage: Bool { ClipboardImageService.pasteboardContainsImage() }

    /// Sends the image on the Mac clipboard to one device. Images are a one-shot
    /// action rather than a sync toggle: they are large, rarely repeated, and
    /// pushing every screenshot automatically would be noise.
    func sendCurrentImage(to deviceID: String) {
        guard pasteboardHasImage else {
            AlertPresenter.showWarning(
                message:
                    "There is no image on this Mac's clipboard. Copy a screenshot or image first, then choose Send Clipboard Image.",
                title: "Nothing to Send")
            return
        }
        guard state(for: deviceID).companionInstalled != false else {
            presentCompanionMissingWarning()
            return
        }

        ClipboardImageService.shared.pushPasteboardImage(to: deviceID) { [weak self] success, message in
            guard let self else { return }
            if success {
                self.updateState(for: deviceID) {
                    $0.lastSyncedAt = Date()
                    $0.lastDirection = .macToAndroid
                    $0.lastError = nil
                }
            } else {
                let reason = message ?? "The image could not be delivered."
                self.updateState(for: deviceID) { $0.lastError = reason }
                AlertPresenter.showWarning(
                    message: reason, title: "Image Delivery Failed")
            }
        }
    }

    /// Copies an image from the phone clipboard onto the Mac clipboard.
    ///
    /// Android 10+ only allows clipboard reads while the companion is in front, so
    /// a failure here is a platform rule, not a bug — the alert says so.
    func pullImage(from deviceID: String) {
        guard state(for: deviceID).companionInstalled != false else {
            presentCompanionMissingWarning()
            return
        }
        ClipboardImageService.shared.pullPhoneImage(from: deviceID) { [weak self] success, message in
            guard let self else { return }
            if success {
                self.updateState(for: deviceID) {
                    $0.lastSyncedAt = Date()
                    $0.lastDirection = .androidToMac
                    $0.lastError = nil
                }
            } else {
                let reason = message ?? "No image could be read from the phone clipboard."
                self.updateState(for: deviceID) { $0.lastError = reason }
                AlertPresenter.showWarning(
                    message: reason, title: "No Image on the Phone")
            }
        }
    }

    /// Asks ADBService to verify the companion app (cached; missing apps are re-checked).
    func refreshCompanionStatus(for deviceID: String, force: Bool = false) {
        adb.checkClipboardCompanion(deviceID: deviceID, forceRefresh: force)
    }

    /// Reconciles state with the current device list. Called when the menu is built/opened.
    func refresh(devices: [AndroidDevice]) {
        for device in devices {
            refreshState(for: device.id)
            adb.checkClipboardCompanion(deviceID: device.id)
        }
    }

    // MARK: - Event handling

    private func apply(_ event: ClipboardSyncEvent) {
        switch event {
        case .sent(let deviceID, let at):
            updateState(for: deviceID) {
                $0.lastSyncedAt = at
                $0.lastDirection = .macToAndroid
                $0.lastError = nil
            }
        case .failed(let deviceID, let message):
            updateState(for: deviceID) { $0.lastError = message }
            // A failed broadcast often means the companion disappeared; verify quietly.
            adb.checkClipboardCompanion(deviceID: deviceID, forceRefresh: true)
            // The Feature alerts → Clipboard switch is a real gate. The body is
            // deliberately generic: clipboard content never enters a notification.
            let deviceName =
                DependencyContainer.shared.menuViewModel.devices
                .first(where: { $0.id == deviceID })?.name
            FeatureAlertCenter.shared.post(
                .clipboard,
                title: "Clipboard sync",
                body: deviceName.map { "Couldn’t sync the clipboard with \($0)." }
                    ?? "Couldn’t sync the clipboard with your phone.")
        case .companionChecked(let deviceID, let installed):
            updateState(for: deviceID) { $0.companionInstalled = installed }
        }
    }

    // MARK: - State helpers

    private func updateState(for deviceID: String, _ mutate: (inout ClipboardBridgeState) -> Void) {
        var state = states[deviceID] ?? ClipboardBridgeState()
        state.enabled = repository.isClipboardEnabled(for: deviceID)
        mutate(&state)
        states[deviceID] = state
    }

    private func refreshState(for deviceID: String) {
        var state = states[deviceID] ?? ClipboardBridgeState()
        state.enabled = repository.isClipboardEnabled(for: deviceID)
        if state.companionInstalled == nil {
            state.companionInstalled = adb.cachedClipboardCompanionStatus(deviceID: deviceID)
        }
        states[deviceID] = state
    }

    private func refreshEnabledStates() {
        for deviceID in Array(states.keys) {
            let enabled = repository.isClipboardEnabled(for: deviceID)
            guard states[deviceID]?.enabled != enabled else { continue }
            var state = states[deviceID] ?? ClipboardBridgeState()
            state.enabled = enabled
            states[deviceID] = state
        }
    }

    private func presentCompanionMissingWarning() {
        AlertPresenter.showWarning(
            message:
                "Mac → Android clipboard delivery needs AndroLaunch Comp on the device. Install it from the Clipboard menu, then try again.",
            title: "AndroLaunch Comp Missing")
    }

    private func relativeAge(of date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
