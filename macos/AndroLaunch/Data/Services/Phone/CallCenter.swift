//
//  CallCenter.swift
//  AndroLaunch
//
//  Coarse call awareness + best-effort answer/decline over the companion
//  protocol. Owned by the phone-companion feature.
//
//  What this is
//  ------------
//  A 1.5 s poll of `call.state` on every connected device whose companion is
//  ready. The result drives three surfaces that share one snapshot: the
//  floating banner, the status-menu rows, and a macOS notification with
//  Answer/Decline while the phone rings.
//
//  What this is not
//  ----------------
//  There is no call audio on the Mac: Android exposes call capture to system
//  apps only, and macOS has no public third-party cellular call API. Every row
//  and banner says "Audio stays on your phone" instead of implying otherwise.
//  Answer/Decline are best-effort: they need `ANSWER_PHONE_CALLS` on the phone,
//  and a call that already ended (or a refused Telecom request) simply reports
//  "not ringing" rather than faking success.
//
//  Polling is deliberately cheap: only devices whose forward is already verified
//  are polled, never more than one request per device per tick, and a device that
//  disappears takes its snapshot with it.
//

import Combine
import Foundation
import UserNotifications

final class CallCenter: ObservableObject {

    // MARK: - Snapshot

    struct Snapshot: Equatable {
        var deviceID: String
        var deviceName: String
        var state: String
        var incoming: Bool
        var since: Date
        var controlAvailable: Bool
        var displayName: String?

        var isRinging: Bool { state == "ringing" }
        var isInCall: Bool { state == "offhook" }
        var isIdle: Bool { state == "idle" }

        /// One sentence for the banner and menu; never promises call audio.
        var detailText: String {
            if isRinging {
                return incoming
                    ? "Incoming call on \(deviceName). Audio stays on your phone."
                    : "Ringing on \(deviceName)."
            }
            if isInCall {
                return "In a call on \(deviceName). Audio stays on your phone."
            }
            return "No call on \(deviceName)."
        }

        var titleText: String {
            if isRinging { return "Incoming call" }
            if isInCall { return "In call" }
            return "No call"
        }
    }

    static let shared = CallCenter()

    // MARK: - Published state

    @Published private(set) var active: Snapshot?
    @Published private(set) var lastError: String?
    /// Coarse capability per device, used by the menu to explain a missing
    /// Answer button instead of silently hiding it.
    @Published private(set) var support: [String: CompanionCallState] = [:]

    // MARK: - Private state

    private let companion: CompanionClient
    private let devicesProvider: () -> [AndroidDevice]
    private let center = UNUserNotificationCenter.current()

    private var timer: Timer?
    private var isRunning = false
    private var pollsInFlight: Set<String> = []
    private var establishAttemptedAt: [String: Date] = [:]
    private var callAlertIdentifiers: Set<String> = []
    /// Epoch millis of the snapshot currently shown, so a banner is not
    /// re-posted for the same ringing session on every poll.
    private var alertedCallKey: String?
    private var cancellables = Set<AnyCancellable>()

    /// 1.5 s is fast enough to catch a ringing window and cheap over the ADB tunnel.
    private static let pollInterval: TimeInterval = 1.5
    private static let establishRetryInterval: TimeInterval = 20
    private static let maxPolledDevices = 3
    private static let categoryIdentifier = "ANDROLAUNCH_CALL"

    init(
        companion: CompanionClient = .shared,
        devicesProvider: @escaping () -> [AndroidDevice] = {
            DependencyContainer.shared.menuViewModel.devices
        }
    ) {
        self.companion = companion
        self.devicesProvider = devicesProvider
    }

    // MARK: - Lifecycle

    /// Starts the poll loop. Idempotent; safe to call from the app delegate.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        NotificationCategories.registerIfNeeded()
        scheduleTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        pollsInFlight.removeAll()
        active = nil
        clearDeliveredCallAlerts()
        CallBannerController.shared.update(nil)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common mode keeps polling alive while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Polling

    private func tick() {
        guard isRunning else { return }
        let devices = devicesProvider().filter { $0.isConnected }
        guard !devices.isEmpty else {
            if active != nil { clearActive(reason: nil) }
            return
        }
        // Drop snapshots for devices that are no longer attached.
        if let snapshot = active, !devices.contains(where: { $0.id == snapshot.deviceID }) {
            clearActive(reason: nil)
        }

        var polled = 0
        for device in devices {
            if companion.isReady(device.id) {
                guard polled < Self.maxPolledDevices else { break }
                polled += 1
                poll(device)
            } else {
                establishChannelIfDue(for: device)
            }
        }
        if polled == 0, active == nil {
            // Nothing ready yet; nothing to show. Silence is correct, not an error.
            if lastError != nil { lastError = nil }
        }
    }

    private func establishChannelIfDue(for device: AndroidDevice) {
        let now = Date()
        if let last = establishAttemptedAt[device.id],
            now.timeIntervalSince(last) < Self.establishRetryInterval
        {
            return
        }
        establishAttemptedAt[device.id] = now
        // Preparing starts the companion service and verifies the forward. It is
        // harmless when the app is not installed (state becomes .notInstalled).
        companion.prepare(deviceID: device.id)
    }

    private func poll(_ device: AndroidDevice) {
        guard !pollsInFlight.contains(device.id) else { return }
        pollsInFlight.insert(device.id)

        companion.callState(deviceID: device.id) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.pollsInFlight.remove(device.id)
                guard self.isRunning else { return }
                switch result {
                case .success(let state):
                    self.support[device.id] = state
                    self.apply(state, for: device)
                case .failure(let error):
                    // A dropped forward is normal (unplug, sleep). Forget readiness
                    // so the next tick can rebuild the channel.
                    self.companion.invalidate(device.id)
                    self.support[device.id] = nil
                    self.lastError = error.localizedDescription
                    if let snapshot = self.active, snapshot.deviceID == device.id {
                        self.clearActive(reason: nil)
                    }
                }
            }
        }
    }

    private func apply(_ state: CompanionCallState, for device: AndroidDevice) {
        guard state.supported, state.permission, state.enabled else {
            // Call awareness is switched off (or the permission was revoked) on the
            // phone. Say nothing rather than showing a permanent "unavailable" row.
            if let snapshot = active, snapshot.deviceID == device.id {
                clearActive(reason: nil)
            }
            return
        }
        guard !state.isIdle else {
            if let snapshot = active, snapshot.deviceID == device.id {
                clearActive(reason: nil)
            }
            return
        }

        let snapshot = Snapshot(
            deviceID: device.id,
            deviceName: device.name,
            state: state.state,
            incoming: state.incoming,
            since: state.sinceMillis > 0
                ? Date(timeIntervalSince1970: Double(state.sinceMillis) / 1000)
                : Date(),
            controlAvailable: state.controlAvailable,
            displayName: device.name)

        // Ringing wins over an in-call snapshot on another device; otherwise the
        // most recently changed state wins.
        if let current = active, current.deviceID != device.id,
            current.isRinging && !snapshot.isRinging
        {
            return
        }
        active = snapshot
        CallBannerController.shared.update(snapshot)
        lastError = nil
        if snapshot.isRinging {
            postCallAlertIfNeeded(for: snapshot)
        } else {
            clearDeliveredCallAlerts()
        }
    }

    private func clearActive(reason: String?) {
        active = nil
        alertedCallKey = nil
        clearDeliveredCallAlerts()
        CallBannerController.shared.update(nil)
        if let reason { lastError = reason }
    }

    // MARK: - Actions

    /// Refreshes one device immediately (used after Answer/Decline so the UI does
    /// not wait for the next tick).
    func refresh(deviceID: String) {
        guard let device = devicesProvider().first(where: { $0.id == deviceID }) else { return }
        guard companion.isReady(deviceID) else {
            companion.prepare(deviceID: deviceID)
            return
        }
        poll(device)
    }

    /// Answers the ringing call. Best-effort: needs `ANSWER_PHONE_CALLS` and a call
    /// that is still ringing.
    func answer() {
        guard let snapshot = active, snapshot.isRinging else { return }
        guard companion.isReady(snapshot.deviceID) else {
            lastError = "Reconnect the device to answer from the Mac."
            return
        }
        companion.answerCall(deviceID: snapshot.deviceID) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                if success {
                    self.lastError = nil
                    self.refresh(deviceID: snapshot.deviceID)
                } else {
                    self.lastError = Self.friendlyMessage(
                        message, fallback: "The phone did not answer the call.")
                    self.refresh(deviceID: snapshot.deviceID)
                }
            }
        }
    }

    /// Declines a ringing call or ends an active one.
    func decline() {
        guard let snapshot = active else { return }
        guard companion.isReady(snapshot.deviceID) else {
            lastError = "Reconnect the device to end the call from the Mac."
            return
        }
        companion.endCall(deviceID: snapshot.deviceID) { [weak self] success, message in
            guard let self else { return }
            DispatchQueue.main.async {
                if success {
                    self.lastError = nil
                } else {
                    self.lastError = Self.friendlyMessage(
                        message, fallback: "The phone did not end the call.")
                }
                self.refresh(deviceID: snapshot.deviceID)
            }
        }
    }

    private static func friendlyMessage(_ raw: String?, fallback: String) -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        switch raw {
        case "permission_required":
            return "Allow call control in AndroLaunch Comp on the phone (Calls → Allow)."
        case "not_ringing":
            return "The call already ended on the phone."
        case "unsupported":
            return "This phone does not expose telephony to apps."
        case "failed":
            return fallback
        default:
            return raw
        }
    }

    // MARK: - macOS notification

    private func postCallAlertIfNeeded(for snapshot: Snapshot) {
        // One alert per ringing session: the since timestamp identifies the call.
        let key = "\(snapshot.deviceID)|\(Int(snapshot.since.timeIntervalSince1970))"
        guard alertedCallKey != key else { return }
        alertedCallKey = key

        let content = UNMutableNotificationContent()
        content.title = snapshot.incoming ? "Incoming call" : "Call ringing"
        content.subtitle = snapshot.deviceName
        content.body = "Answer or decline from the Mac. Audio stays on your phone."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "deviceID": snapshot.deviceID,
            "kind": "call",
        ]

        let identifier = "androlaunch.call.\(snapshot.deviceID).\(Int(snapshot.since.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.lastError = error.localizedDescription
                } else {
                    self.callAlertIdentifiers.insert(identifier)
                    self.lastError = nil
                }
            }
        }
    }

    private func clearDeliveredCallAlerts() {
        let identifiers = Array(callAlertIdentifiers)
        callAlertIdentifiers.removeAll()
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Called by the notification delegate when an Answer/Decline action is used.
    func handleNotificationAction(_ identifier: String) {
        switch identifier {
        case "ANDROLAUNCH_CALL_ANSWER": answer()
        case "ANDROLAUNCH_CALL_DECLINE": decline()
        default: break
        }
    }
}
