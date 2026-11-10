//
//  NotificationMirror.swift
//  AndroLaunch
//
//  Mirrors Android notifications into macOS Notification Center.
//
//  Design notes
//  ------------
//  - Opt-in is per device, stored through `DeviceScopedPreferences` under the
//    device's `stableID`, so moving a phone from USB to Wi-Fi does not silently
//    reset the choice. Nothing is polled, parsed or delivered until the user
//    turns mirroring on for that device *and* the global switch is armed.
//  - Polling is a single repeating `Timer` per enabled device (6 s). Timers are
//    created only for devices that are enabled, connected and authorized, and
//    every timer is invalidated on disable, disconnect, revoke and deinit.
//  - `dumpsys notification` output is not a stable API; see
//    `NotificationDumpParser` for the defensive, line-oriented parsing rules.
//  - Delivery uses `UNUserNotificationCenter`, which the app already uses in
//    `MenuViewModel.sendNotification(title:body:)`.
//  - Privacy: a built-in deny-list plus a "Hide sensitive apps" switch (default
//    on) keep finance, password-manager, authenticator and email text off the
//    Mac unless the user explicitly changes it.
//

import Combine
import Foundation
import UserNotifications

final class NotificationMirror: NSObject, ObservableObject {
    static let shared = NotificationMirror()

    // MARK: - Public types

    enum Status: String, Equatable {
        case off
        case needsPermission
        case mirroring
        case unsupported
        case error
    }

    /// Everything the menu is allowed to show for one device.
    struct DeviceState: Equatable {
        let stableID: String
        var transportID: String
        var name: String
        var enabled: Bool
        var status: Status
        var mirroredToday: Int
        var lastError: String?
    }

    // MARK: - Published state

    /// Keyed by `AndroidDevice.stableID`, so the row survives transport changes.
    @Published private(set) var deviceStates: [String: DeviceState] = [:]
    /// Global arm/pause switch. Defaults to off; enabling a device from the menu
    /// is an explicit opt-in and arms this switch too.
    @Published private(set) var masterEnabled: Bool
    /// Hide finance/password-manager/authenticator/email notifications.
    @Published private(set) var hideSensitiveApps: Bool

    // MARK: - Constants

    private static let masterDefaultsKey = "notifications.mirror.enabled"
    private static let hideSensitiveDefaultsKey = "notifications.hideSensitiveApps"
    private static let devicePreferenceKey = "notificationsEnabled"
    private static let pollInterval: TimeInterval = 6
    private static let firstPollDelay: TimeInterval = 1
    private static let maxConsecutiveUnparseablePolls = 2

    // MARK: - Private state

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let preferences = DeviceScopedPreferences.shared
    private let dayFormatter: DateFormatter

    /// Latest `AndroidDevice` snapshot per stable ID (transport ID, name, OS).
    private var activeDevices: [String: AndroidDevice] = [:]
    /// Repeating pollers, keyed by stable ID.
    private var timers: [String: Timer] = [:]
    /// Devices with an ADB read in flight; prevents overlapping polls.
    private var pollsInFlight: Set<String> = []
    /// "stableID|androidVersion|apiLevel" → does `--noredact` work on this OS?
    private var noredactSupport: [String: Bool] = [:]
    /// Devices whose current notification list has been captured as a baseline.
    /// Nothing from the baseline is mirrored; only later additions are.
    private var primedDevices: Set<String> = []
    /// Fingerprints (key + post time) from the previous successful poll.
    private var lastFingerprints: [String: Set<String>] = [:]
    /// Consecutive polls that returned no parseable notification section.
    private var unparseableCounts: [String: Int] = [:]
    /// Devices that proved unreadable; polling is stopped until the user
    /// toggles mirroring off and on again.
    private var unsupportedDevices: Set<String> = []
    /// Day stamp for the "mirrored today" counter.
    private var mirroredCountDay: [String: String] = [:]
    /// Latest notification list per stable ID, tracked so phone tools (verification
    /// code copy) can read it without another ADB round trip.
    private var latestRecords: [String: [AndroidNotificationRecord]] = [:]

    private var authorized = false
    private var authorizationCheckInFlight = false
    private var pendingAuthorizationCompletions: [(Bool) -> Void] = []

    /// Optional package → app label lookup, wired by the menu section from
    /// `MenuViewModel.deviceApps` (scrcpy's cached app list). This costs no
    /// extra ADB calls; when it has no answer the reverse-DNS fallback is used.
    var appLabelProvider: ((_ packageID: String) -> String?)?

    // MARK: - Init

    private override init() {
        defaults = .standard
        if defaults.object(forKey: Self.masterDefaultsKey) == nil {
            // The dashboard is the product's notification surface; default to on
            // so a fresh install can see notifications immediately. The user can
            // still turn it off per device or globally.
            masterEnabled = true
            defaults.set(true, forKey: Self.masterDefaultsKey)
        } else {
            masterEnabled = defaults.bool(forKey: Self.masterDefaultsKey)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        dayFormatter = formatter

        if let storedHideSensitive = defaults.object(forKey: Self.hideSensitiveDefaultsKey) as? Bool {
            hideSensitiveApps = storedHideSensitive
        } else {
            hideSensitiveApps = true
        }

        super.init()

        // Reply / dismiss / call categories must exist before the first delivery,
        // otherwise macOS drops the action buttons.
        NotificationCategories.registerIfNeeded()

        // MenuViewModel posts local notifications but installs no delegate. With
        // no delegate, macOS suppresses banners while AndroLaunch is frontmost.
        // We install ours only when the center has no delegate, so a future
        // app-wide delegate is never clobbered. Ours only presents banners and
        // handles a banner tap (open the posting app on the phone); it does not
        // change how MenuViewModel's requests are stored or delivered.
        if center.delegate == nil {
            center.delegate = self
        }
    }

    deinit {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
    }

    // MARK: - Queries used by the menu

    func state(for device: AndroidDevice) -> DeviceState {
        if let existing = deviceStates[device.stableID] {
            return existing
        }
        return DeviceState(
            stableID: device.stableID,
            transportID: device.id,
            name: device.name,
            enabled: preferences.bool(Self.devicePreferenceKey, for: device.stableID, default: true),
            status: .off,
            mirroredToday: 0,
            lastError: nil
        )
    }

    func isEnabled(for device: AndroidDevice) -> Bool {
        preferences.bool(Self.devicePreferenceKey, for: device.stableID, default: true)
    }

    /// Human-readable status line for the menu row.
    func statusText(for device: AndroidDevice) -> String {
        let deviceState = state(for: device)
        if !masterEnabled && deviceState.enabled {
            return "Off — enable in Preferences"
        }
        switch deviceState.status {
        case .off:
            return deviceState.enabled ? "Off" : "Off — not enabled"
        case .needsPermission:
            return "Not permitted — open System Settings"
        case .mirroring:
            if deviceState.mirroredToday > 0 {
                return "Mirroring — \(deviceState.mirroredToday) today"
            }
            return "Mirroring"
        case .unsupported:
            return "Unsupported on this device"
        case .error:
            if let error = deviceState.lastError, !error.isEmpty {
                return "Error — \(error)"
            }
            return "Error"
        }
    }

    /// True when the device's dump proved unreadable (status row explains it).
    func isUnsupported(_ device: AndroidDevice) -> Bool {
        unsupportedDevices.contains(device.stableID)
    }

    // MARK: - Device lifecycle

    /// Reconciles timers/state with the connected device list. Safe and cheap to
    /// call on every menu open; timers are only created while eligible.
    func syncDevices(_ devices: [AndroidDevice]) {
        var liveIDs: Set<String> = []
        for device in devices {
            let stableID = device.stableID
            liveIDs.insert(stableID)
            activeDevices[stableID] = device
            ensureStateExists(for: device)

            guard var next = deviceStates[stableID] else { continue }
            var changed = false
            if next.transportID != device.id {
                next.transportID = device.id
                changed = true
            }
            if next.name != device.name {
                next.name = device.name
                changed = true
            }
            let enabled = preferences.bool(
                Self.devicePreferenceKey, for: stableID, default: true)
            if next.enabled != enabled {
                next.enabled = enabled
                changed = true
            }
            let day = currentDay()
            if let countedDay = mirroredCountDay[stableID], countedDay != day {
                mirroredCountDay[stableID] = day
                next.mirroredToday = 0
                changed = true
            }
            if changed {
                deviceStates[stableID] = next
            }
        }

        for stableID in Array(deviceStates.keys) where !liveIDs.contains(stableID) {
            stopTimer(for: stableID)
            deviceStates[stableID] = nil
            activeDevices[stableID] = nil
            primedDevices.remove(stableID)
            lastFingerprints[stableID] = nil
            unparseableCounts[stableID] = 0
            pollsInFlight.remove(stableID)
        }

        reconcileTimers()
    }

    func setDeviceEnabled(_ enabled: Bool, for device: AndroidDevice) {
        let stableID = device.stableID
        activeDevices[stableID] = device
        preferences.setBool(enabled, Self.devicePreferenceKey, for: stableID)
        ensureStateExists(for: device)

        if enabled {
            unsupportedDevices.remove(stableID)
            unparseableCounts[stableID] = 0
            primedDevices.remove(stableID)
            lastFingerprints[stableID] = nil
            updateState(stableID) {
                $0.enabled = true
                $0.status = .off
                $0.lastError = nil
            }
            if masterEnabled {
                armDevice(device)
            } else {
                // Explicit per-device opt-in is a clear "yes"; arm the global
                // switch with it so the toggle does not look broken. This is the
                // only implicit path that turns the master switch on.
                setMasterEnabled(true)
            }
        } else {
            stopTimer(for: stableID)
            primedDevices.remove(stableID)
            lastFingerprints[stableID] = nil
            unparseableCounts[stableID] = 0
            unsupportedDevices.remove(stableID)
            updateState(stableID) {
                $0.enabled = false
                $0.status = .off
                $0.lastError = nil
            }
        }
    }

    func setMasterEnabled(_ enabled: Bool) {
        guard enabled != masterEnabled else {
            if enabled { reconcileTimers() }
            return
        }
        defaults.set(enabled, forKey: Self.masterDefaultsKey)
        masterEnabled = enabled

        if enabled {
            startEligibleTimers()
            requestAuthorizationIfNeeded { [weak self] granted in
                guard let self, self.masterEnabled else { return }
                self.authorized = granted
                if !granted {
                    self.markEnabledDevicesAsNeedsPermission()
                }
            }
        } else {
            stopAllTimers()
            for stableID in Array(deviceStates.keys) {
                updateState(stableID) {
                    $0.status = .off
                    $0.lastError = nil
                }
            }
            // Forget the previous baseline so re-enabling mirrors nothing that
            // arrived while mirroring was paused.
            primedDevices.removeAll()
            lastFingerprints.removeAll()
            pollsInFlight.removeAll()
        }
    }

    func setHideSensitiveApps(_ hide: Bool) {
        guard hide != hideSensitiveApps else { return }
        defaults.set(hide, forKey: Self.hideSensitiveDefaultsKey)
        hideSensitiveApps = hide
    }

    /// Invalidates every poller. Called on disable and from `deinit`.
    func stop() {
        stopAllTimers()
    }

    // MARK: - Timer management

    private func reconcileTimers() {
        guard masterEnabled else {
            stopAllTimers()
            return
        }
        // Polling feeds the in-panel list and must not wait on the macOS
        // notification authorization prompt. Start immediately, then refresh
        // the authorization state in the background for banner delivery.
        startEligibleTimers()
        refreshAuthorization { [weak self] granted in
            guard let self, self.masterEnabled else { return }
            self.authorized = granted
            if !granted {
                self.markEnabledDevicesAsNeedsPermission()
            }
        }
    }

    private func startEligibleTimers() {
        guard masterEnabled else {
            stopAllTimers()
            return
        }

        var eligible: Set<String> = []
        for stableID in Array(deviceStates.keys) {
            guard let state = deviceStates[stableID] else { continue }
            guard state.enabled else {
                updateState(stableID) {
                    $0.status = .off
                    $0.lastError = nil
                }
                continue
            }
            if unsupportedDevices.contains(stableID) {
                updateState(stableID) { $0.status = .unsupported }
                continue
            }
            guard let device = activeDevices[stableID] else { continue }
            eligible.insert(stableID)
            startTimer(for: device)
        }

        for stableID in Array(timers.keys) where !eligible.contains(stableID) {
            stopTimer(for: stableID)
        }
    }

    private func startTimer(for device: AndroidDevice) {
        let stableID = device.stableID
        if timers[stableID] != nil {
            updateState(stableID) {
                if $0.status == .off || $0.status == .needsPermission {
                    $0.status = .mirroring
                }
            }
            return
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollDevice(stableID: stableID)
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .common)
        timers[stableID] = timer

        updateState(stableID) {
            if $0.status != .unsupported {
                $0.status = .mirroring
            }
            $0.lastError = nil
        }

        // Prime the baseline shortly after enabling so a queue of existing
        // notifications is recorded silently instead of mirrored as a flood.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstPollDelay) { [weak self] in
            self?.pollDevice(stableID: stableID)
        }
    }

    private func stopTimer(for stableID: String) {
        timers[stableID]?.invalidate()
        timers[stableID] = nil
    }

    private func stopAllTimers() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
    }

    private func markEnabledDevicesAsNeedsPermission() {
        for stableID in Array(deviceStates.keys) {
            guard let state = deviceStates[stableID] else { continue }
            let status: Status
            if !state.enabled {
                status = .off
            } else if unsupportedDevices.contains(stableID) {
                status = .unsupported
            } else {
                status = .needsPermission
            }
            updateState(stableID) { $0.status = status }
        }
    }

    // MARK: - Polling

    private func pollDevice(stableID: String) {
        guard masterEnabled,
            let state = deviceStates[stableID], state.enabled,
            let device = activeDevices[stableID]
        else { return }
        guard !pollsInFlight.contains(stableID) else { return }

        pollsInFlight.insert(stableID)
        let supportKey = noredactKey(for: device)
        let rememberedSupport = noredactSupport[supportKey]
        performPoll(
            device: device,
            stableID: stableID,
            useNoredact: rememberedSupport ?? true,
            allowFallback: rememberedSupport == nil
        )
    }

    /// True while the poll result is still relevant (feature on, same device
    /// transport). Used after an asynchronous parse before touching state.
    private func stillPolling(stableID: String, device: AndroidDevice) -> Bool {
        guard masterEnabled,
            let state = deviceStates[stableID], state.enabled,
            activeDevices[stableID]?.id == device.id
        else { return false }
        return true
    }

    /// Latest notification list read for a device, or an empty list before the
    /// first successful poll. Exposed for phone-tool rows (verification codes).
    func latestRecords(for device: AndroidDevice) -> [AndroidNotificationRecord] {
        latestRecords[device.stableID] ?? []
    }

    private func performPoll(
        device: AndroidDevice, stableID: String, useNoredact: Bool, allowFallback: Bool
    ) {
        // The companion's notification listener gives real platform metadata —
        // flags, action buttons and direct-reply actions — with no shell scraping.
        // dumpsys stays as the fallback for devices without the companion (or with
        // a pre-v3 APK that answers unknown_command).
        if CompanionClient.shared.isReady(device.id) {
            pollViaCompanion(device: device, stableID: stableID)
            return
        }

        // The companion may still be starting. Poll its readiness quickly so
        // the panel fills in ~1–2 s, then fall back to dumpsys only after a
        // generous window for phones without Comp.
        func waitForCompanion(_ attempt: Int) {
            guard stillPolling(stableID: stableID, device: device) else {
                pollsInFlight.remove(stableID)
                return
            }
            if CompanionClient.shared.isReady(device.id) {
                pollViaCompanion(device: device, stableID: stableID)
                return
            }
            if attempt >= 12 {
                pollViaDumpsys(
                    device: device, stableID: stableID, useNoredact: useNoredact,
                    allowFallback: allowFallback)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                waitForCompanion(attempt + 1)
            }
        }
        waitForCompanion(0)
    }

    private func pollViaCompanion(device: AndroidDevice, stableID: String) {
        CompanionClient.shared.requestWhenReady(
            deviceID: device.id, command: "notif.list", timeout: 6
        ) { [weak self] result in
            guard let self else { return }
            guard self.masterEnabled,
                let state = self.deviceStates[stableID], state.enabled,
                self.activeDevices[stableID]?.id == device.id
            else {
                self.pollsInFlight.remove(stableID)
                return
            }
            switch result {
            case .success(let json):
                guard let items = CompanionNotification.decodeList(json) else {
                    // A v2 companion answers this command with unknown_command, so
                    // fall back instead of marking the device unsupported.
                    self.pollViaDumpsys(
                        device: device, stableID: stableID, useNoredact: true,
                        allowFallback: true)
                    return
                }
                self.noredactSupport[self.noredactKey(for: device)] = true
                self.pollsInFlight.remove(stableID)
                self.handlePollSuccess(items.map(Self.record(from:)), for: device)
            case .failure:
                self.pollViaDumpsys(
                    device: device, stableID: stableID, useNoredact: true,
                    allowFallback: true)
            }
        }
    }

    /// Companion payload → the mirror's shared record type.
    static func record(from item: CompanionNotification) -> AndroidNotificationRecord {
        // FLAG_ONGOING_EVENT (0x2) so the existing "hide ongoing" filter applies.
        let flags = item.isOngoing ? 0x0000_0002 : 0
        return AndroidNotificationRecord(
            packageName: item.packageName,
            key: item.key,
            postTime: Int64(item.postedAt.timeIntervalSince1970 * 1000),
            title: item.title.isEmpty ? nil : item.title,
            text: item.text.isEmpty ? nil : item.text,
            flags: flags,
            isMedia: false,
            actions: item.actions.map {
                AndroidNotificationAction(index: $0.index, title: $0.title, hasReply: $0.hasReply)
            },
            isSensitive: item.isSensitive)
    }

    private func pollViaDumpsys(
        device: AndroidDevice, stableID: String, useNoredact: Bool, allowFallback: Bool
    ) {
        DependencyContainer.shared.adb.fetchNotificationDump(
            deviceID: device.id, useNoredact: useNoredact
        ) { [weak self] outcome in
            guard let self else { return }

            // The menu can disable mirroring or the transport can change while
            // the ADB read is in flight; drop stale results instead of reviving
            // a timer or mirroring from a device the user just turned off.
            guard self.masterEnabled,
                let state = self.deviceStates[stableID], state.enabled,
                self.activeDevices[stableID]?.id == device.id
            else {
                self.pollsInFlight.remove(stableID)
                return
            }

            switch outcome {
            case .success(let output):
                // Parsing is line-oriented but can touch a large string; keep it
                // off the main thread so polls never hitch the menu bar.
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let records = NotificationDumpParser.parse(output)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard self.stillPolling(stableID: stableID, device: device) else {
                            self.pollsInFlight.remove(stableID)
                            return
                        }
                        if let records {
                            self.noredactSupport[self.noredactKey(for: device)] = useNoredact
                            self.pollsInFlight.remove(stableID)
                            self.handlePollSuccess(records, for: device)
                        } else if allowFallback {
                            self.pollViaDumpsys(
                                device: device, stableID: stableID, useNoredact: false,
                                allowFallback: false)
                        } else {
                            self.pollsInFlight.remove(stableID)
                            self.registerUnparseable(device: device)
                        }
                    }
                }
            case .unsupportedFlag:
                if allowFallback {
                    self.pollViaDumpsys(
                        device: device, stableID: stableID, useNoredact: false,
                        allowFallback: false)
                } else {
                    self.pollsInFlight.remove(stableID)
                    self.registerUnparseable(device: device)
                }
            case .failure(let message):
                self.pollsInFlight.remove(stableID)
                self.registerCommandFailure(device: device, message: message)
            }
        }
    }

    private func handlePollSuccess(
        _ records: [AndroidNotificationRecord], for device: AndroidDevice
    ) {
        let stableID = device.stableID
        unparseableCounts[stableID] = 0
        latestRecords[stableID] = records
        let fingerprints = Set(records.map { $0.fingerprint })

        guard primedDevices.contains(stableID) else {
            // First successful poll after enabling/connecting: remember what is
            // already on screen, mirror nothing.
            primedDevices.insert(stableID)
            lastFingerprints[stableID] = fingerprints
            updateState(stableID) {
                $0.status = .mirroring
                $0.lastError = nil
            }
            return
        }

        let previous = lastFingerprints[stableID] ?? []
        var seen: Set<String> = []
        for record in records {
            let fingerprint = record.fingerprint
            guard seen.insert(fingerprint).inserted else { continue }
            guard !previous.contains(fingerprint) else { continue }
            guard shouldMirror(record) else { continue }
            if authorized {
                deliver(record, for: device)
            }
        }
        lastFingerprints[stableID] = seen

        updateState(stableID) {
            $0.status = .mirroring
            $0.lastError = nil
        }
    }

    private func registerUnparseable(device: AndroidDevice) {
        let stableID = device.stableID
        let count = (unparseableCounts[stableID] ?? 0) + 1
        unparseableCounts[stableID] = count

        if count >= Self.maxConsecutiveUnparseablePolls {
            unsupportedDevices.insert(stableID)
            stopTimer(for: stableID)
            primedDevices.remove(stableID)
            lastFingerprints[stableID] = nil
            updateState(stableID) {
                $0.status = .unsupported
                $0.lastError = "dumpsys notification was not readable."
            }
        } else {
            updateState(stableID) {
                $0.status = .error
                $0.lastError = "Waiting for the next poll."
            }
        }
    }

    private func registerCommandFailure(device: AndroidDevice, message: String) {
        unparseableCounts[device.stableID] = 0
        updateState(device.stableID) {
            $0.status = .error
            $0.lastError = Self.shortError(message)
        }
    }

    // MARK: - Filtering

    private func shouldMirror(_ record: AndroidNotificationRecord) -> Bool {
        guard record.displayText != nil else {
            // No readable text usually means the phone is locked with content
            // hidden, the dump is redacted, or the notification is a media /
            // system placeholder. Never guess at hidden content.
            return false
        }
        if record.isOngoing { return false }
        if record.isGroupSummary { return false }
        if record.isMedia { return false }
        if hideSensitiveApps && Self.isSensitivePackage(record.packageName) { return false }
        // The phone app itself marked it secret (or the platform hid its content).
        if hideSensitiveApps && record.isSensitive { return false }
        return true
    }

    static func isSensitivePackage(_ packageName: String) -> Bool {
        NotificationPrivacy.isSensitivePackage(packageName)
    }

    // MARK: - Delivery

    private func deliver(_ record: AndroidNotificationRecord, for device: AndroidDevice) {
        let content = UNMutableNotificationContent()
        content.title = appLabel(for: record.packageName)

        let notificationTitle = record.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationText = record.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Banner layout: app name as the title, the notification title as the
        // subtitle, and the notification body as the body. A title-only
        // notification becomes the body so it is never shown twice.
        if let text = notificationText, !text.isEmpty {
            content.body = String(text.prefix(600))
            if let title = notificationTitle, !title.isEmpty {
                content.subtitle = String(title.prefix(200))
            }
        } else if let title = notificationTitle, !title.isEmpty {
            content.body = String(title.prefix(600))
        }
        content.sound = nil
        content.interruptionLevel = .active
        content.threadIdentifier = record.packageName
        content.userInfo = [
            "package": record.packageName,
            "deviceID": device.id,
            "stableID": device.stableID,
            // Reply/dismiss routing needs the phone notification key and the
            // action index; neither is sensitive on its own.
            "key": record.key,
            "replyAction": record.replyActionIndex,
        ]
        // A reply category only exists for apps that expose a direct-reply action;
        // everything else still gets "Dismiss on phone".
        content.categoryIdentifier =
            (record.hasReply && AppPreferences.shared.inlineReply)
            ? NotificationCategories.message
            : NotificationCategories.plain

        let identifier = "androlaunch.\(device.stableID).\(record.key).\(record.postTime)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let stableID = device.stableID

        center.add(request) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.updateState(stableID) {
                        $0.status = .error
                        $0.lastError = Self.shortError(error.localizedDescription)
                    }
                    return
                }
                self.updateState(stableID) { state in
                    let day = self.currentDay()
                    if self.mirroredCountDay[stableID] != day {
                        self.mirroredCountDay[stableID] = day
                        state.mirroredToday = 0
                    }
                    state.mirroredToday += 1
                    state.status = .mirroring
                    state.lastError = nil
                }
            }
        }
    }

    /// App label for the banner: the cached scrcpy app name when known, else a
    /// readable form of the last reverse-DNS package component.
    private func appLabel(for packageName: String) -> String {
        if let provided = appLabelProvider?(packageName) {
            let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let genericComponents: Set<String> = [
            "android", "app", "apps", "mobile", "client", "application",
        ]
        let components = packageName.split(separator: ".").map(String.init)
        for component in components.reversed() {
            let candidate = component.replacingOccurrences(of: "_", with: " ")
            let lowered = candidate.lowercased()
            guard !candidate.isEmpty, !genericComponents.contains(lowered) else { continue }
            guard candidate.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            else { continue }
            return candidate.prefix(1).uppercased() + String(candidate.dropFirst())
        }
        return packageName
    }

    // MARK: - Authorization

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    /// Reads the current authorization state without prompting. Repeated calls
    /// are coalesced, and the result is refreshed on every menu open so granting
    /// permission in System Settings is picked up without a relaunch.
    private func refreshAuthorization(completion: @escaping (Bool) -> Void) {
        if authorizationCheckInFlight {
            pendingAuthorizationCompletions.append(completion)
            return
        }
        authorizationCheckInFlight = true
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                let granted = Self.isAuthorized(settings.authorizationStatus)
                self.authorized = granted
                self.authorizationCheckInFlight = false
                completion(granted)
                let pending = self.pendingAuthorizationCompletions
                self.pendingAuthorizationCompletions.removeAll()
                for handler in pending {
                    handler(granted)
                }
            }
        }
    }

    /// Requests authorization lazily, only when the user enables the feature.
    /// Never called on launch.
    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                if Self.isAuthorized(settings.authorizationStatus) {
                    self.authorized = true
                    completion(true)
                    return
                }
                guard settings.authorizationStatus == .notDetermined else {
                    self.authorized = false
                    completion(false)
                    return
                }
                self.center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        self.authorized = granted
                        completion(granted)
                    }
                }
            }
        }
    }

    private func armDevice(_ device: AndroidDevice) {
        guard masterEnabled, deviceStates[device.stableID]?.enabled == true else { return }
        // Poll for the panel immediately; the macOS authorization prompt only
        // controls whether banners are delivered, not whether we can read.
        startTimer(for: device)
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            self.authorized = granted
            if !granted {
                self.updateState(device.stableID) {
                    if $0.status == .mirroring { $0.status = .needsPermission }
                    $0.lastError = nil
                }
            }
        }
    }

    // MARK: - State helpers

    private func ensureStateExists(for device: AndroidDevice) {
        let stableID = device.stableID
        guard deviceStates[stableID] == nil else { return }
        deviceStates[stableID] = DeviceState(
            stableID: stableID,
            transportID: device.id,
            name: device.name,
            enabled: preferences.bool(
                Self.devicePreferenceKey, for: stableID, default: true),
            status: .off,
            mirroredToday: 0,
            lastError: nil
        )
        if mirroredCountDay[stableID] == nil {
            mirroredCountDay[stableID] = currentDay()
        }
    }

    private func updateState(_ stableID: String, _ mutate: (inout DeviceState) -> Void) {
        guard var state = deviceStates[stableID] else { return }
        mutate(&state)
        guard state != deviceStates[stableID] else { return }
        deviceStates[stableID] = state
    }

    private func noredactKey(for device: AndroidDevice) -> String {
        let version = device.androidVersion ?? "unknown"
        let apiLevel = device.apiLevel ?? "unknown"
        return "\(device.stableID)|\(version)|\(apiLevel)"
    }

    private func currentDay() -> String {
        dayFormatter.string(from: Date())
    }

    private static func shortError(_ message: String) -> String {
        let collapsed = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(120))
    }
}

// MARK: - Notification interaction

extension NotificationMirror: UNUserNotificationCenterDelegate {
    /// Tap on a mirrored banner: open the posting app on the phone. Only the
    /// default action is handled; the package string is validated by
    /// `ADBService.launchPackageOnDevice` before any shell command is built.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        let deviceID = userInfo["deviceID"] as? String ?? ""

        switch response.actionIdentifier {
        case NotificationCategories.callAnswerAction,
            NotificationCategories.callDeclineAction:
            CallCenter.shared.handleNotificationAction(response.actionIdentifier)

        case NotificationCategories.replyAction:
            guard let textResponse = response as? UNTextInputNotificationResponse,
                let key = userInfo["key"] as? String, !key.isEmpty, !deviceID.isEmpty
            else { return }
            let actionIndex = (userInfo["replyAction"] as? Int) ?? -1
            let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            CompanionClient.shared.reply(
                toNotificationKey: key, actionIndex: actionIndex, text: text, deviceID: deviceID
            ) { [weak self] success, message in
                guard let self, !success else { return }
                self.postLocalNotice(
                    title: "Reply not delivered",
                    body: Self.replyFailureText(message))
            }

        case NotificationCategories.dismissAction:
            guard let key = userInfo["key"] as? String, !key.isEmpty, !deviceID.isEmpty else {
                return
            }
            CompanionClient.shared.dismissNotification(
                key: key, deviceID: deviceID
            ) { [weak self] success, message in
                guard let self, !success else { return }
                self.postLocalNotice(
                    title: "Could not dismiss on the phone",
                    body: message ?? "The notification may already be gone.")
            }

        case UNNotificationDefaultActionIdentifier:
            // Tapping the banner opens the posting app on the phone.
            guard let packageName = userInfo["package"] as? String,
                ADBService.isSafePackageIdentifier(packageName),
                !deviceID.isEmpty
            else { return }
            DependencyContainer.shared.adb.launchPackageOnDevice(
                deviceID: deviceID, packageID: packageName
            ) { _ in }

        default:
            break
        }
    }

    /// Honest, actionable copy for a failed reply.
    static func replyFailureText(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return "The phone did not accept the reply. Open the message on the phone to answer."
        }
        if raw.contains("unknown_command") {
            return "Update AndroLaunch Comp on the phone to reply from the Mac."
        }
        switch raw {
        case "no_action":
            return "This app replies with its own screen, not an inline reply. Open it on the phone."
        case "gone":
            return "The notification is no longer on the phone."
        case "permission_required":
            return "Allow notification access for AndroLaunch Comp on the phone."
        default:
            return raw
        }
    }

    /// Local failure feedback that does not pretend the phone did anything.
    private func postLocalNotice(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(300))
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: "androlaunch.action.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    /// With a delegate installed, macOS would otherwise suppress banners while
    /// AndroLaunch is frontmost. Presenting them as banners keeps mirroring
    /// useful, and makes MenuViewModel's existing notifications visible too.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
