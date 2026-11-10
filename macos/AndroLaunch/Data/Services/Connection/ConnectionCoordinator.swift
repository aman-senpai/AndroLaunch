//
//  ConnectionCoordinator.swift
//  AndroLaunch
//
//  Transport-agnostic connection layer. A phone is one device that keeps working
//  when it moves between USB, Wi-Fi, Bonjour and user-added network addresses:
//  the coordinator watches the ADB device list, records every transport in
//  `EndpointStore`, races the remembered wireless addresses of a disconnected
//  device (first success wins, the rest are abandoned), and fails over when a
//  live transport disappears.
//
//  Everything in here is deliberately quiet. Transient connect failures never
//  reach `AlertPresenter`; they are recorded as endpoint health and retried with
//  backoff. The only visible effects are the menu rows this feeds
//  (`ConnectionMenuSection`) and the normal device list refresh.
//

import AppKit
import Combine
import Foundation

extension Notification.Name {
    /// Posted by `ADBService.disconnectDevice(deviceID:)` when the user (or a
    /// feature acting for them) explicitly drops a transport. The coordinator
    /// stops racing that identity until the device reappears, so automatic
    /// reconnection never fights an intentional disconnect.
    static let adbIntentionalDisconnect = Notification.Name(
        "com.senpai.AndroLaunch.adbIntentionalDisconnect")
}

/// A device the coordinator remembers even while no transport is live.
struct RememberedDevice: Identifiable, Equatable {
    let identity: String
    let name: String
    let isReconnecting: Bool

    var id: String { identity }
}

/// Owns presence polling, endpoint racing, failover and wake recovery.
///
/// State is main-queue confined: the timer, ADB callbacks, Combine sinks and menu
/// actions all run on the main queue, so the race bookkeeping below needs no locks.
final class ConnectionCoordinator: ObservableObject {
    static let shared = ConnectionCoordinator()

    // MARK: - UI state (published on the main queue)

    /// Known devices that are currently offline and have at least one remembered
    /// wireless transport. `ConnectionMenuSection` turns these into quiet
    /// "Reconnect" rows; the list is intentionally capped at the menu layer.
    @Published private(set) var rememberedDisconnectedDevices: [RememberedDevice] = []

    /// Identities with a transport race currently in flight.
    @Published private(set) var reconnectingIdentities: Set<String> = []

    // MARK: - Tuning

    private enum Tuning {
        /// Lightweight `adb devices` presence poll. Slow enough to stay invisible.
        static let refreshInterval: TimeInterval = 9
        /// Never race the same identity more often than this.
        static let raceCooldown: TimeInterval = 10
        /// Grace period after a live transport disappears (cable unplugged,
        /// Wi-Fi dropped) before its other endpoints are tried.
        static let failoverDelay: TimeInterval = 2.5
        /// Small stagger between candidate attempts so a winning endpoint that is
        /// better-ranked can settle before the next address is dialled.
        static let raceStagger: TimeInterval = 0.15
        /// Per-endpoint exponential backoff after failures.
        static let endpointBaseBackoff: TimeInterval = 30
        static let endpointMaxBackoff: TimeInterval = 10 * 60
        static let maxEndpointFailures = 8
        /// Upper bound on simultaneously dialled addresses for one device.
        static let maxRaceEndpoints = 4
        /// Safety valve so a lost ADB callback can never wedge the refresh guard.
        static let refreshTimeout: TimeInterval = 15
    }

    // MARK: - Dependencies

    private let adb: ADBService
    private let endpoints: EndpointStore
    private let deviceRepository: any DeviceRepositoryProtocol

    // MARK: - State (main queue only)

    /// identity -> display name, for remembered-but-offline devices.
    private var knownIdentities: [String: String] = [:]
    /// Identities currently listed by "Previous Devices".
    private var persistedIdentities: Set<String> = []
    private var connectedIdentities: Set<String> = []
    /// identity -> live transport ID (the ADB serial: IP:port or the USB serial).
    private var liveTransportIDs: [String: String] = [:]
    /// Reverse of `liveTransportIDs`, used to resolve a disconnect notification.
    private var transportIdentities: [String: String] = [:]
    /// Every transport ID currently live, so an already-reachable address is never raced.
    private var liveTransportSet: Set<String> = []
    /// identity -> addresses already recorded in `EndpointStore` this session.
    private var recordedTransports: [String: Set<String>] = [:]
    /// Identities the user explicitly disconnected; racing stays off until the
    /// device reappears or the user asks to reconnect.
    private var intentionalDisconnects: [String: Date] = [:]
    private var lastRaceAt: [String: Date] = [:]
    private var racingIdentities: Set<String> = []
    private var pendingRaces: [String: PendingRace] = [:]
    private var endpointBackoff: [String: EndpointBackoff] = [:]
    private var failoverWorkItems: [String: DispatchWorkItem] = [:]

    private var refreshTimer: Timer?
    private var refreshWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var lastPresenceCheck = Date.distantPast

    private var cancellables = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var isStarted = false

    private struct PendingRace {
        var remaining: Int
    }

    private struct EndpointBackoff {
        var failures: Int
        var retryAfter: Date
    }

    // MARK: - Init

    init(
        adb: ADBService = DependencyContainer.shared.adb,
        endpoints: EndpointStore = .shared,
        deviceRepository: any DeviceRepositoryProtocol = DependencyContainer.shared.deviceRepository
    ) {
        self.adb = adb
        self.endpoints = endpoints
        self.deviceRepository = deviceRepository
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshWorkItem?.cancel()
        for workItem in failoverWorkItems.values {
            workItem.cancel()
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
    }

    // MARK: - Lifecycle

    /// Starts presence polling and attaches to the ADB device feed. Idempotent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        bindPublishers()
        installObservers()
        updateTimerState()
        refreshPresence(force: true)
    }

    /// Stops all background work and drops live state. The remembered endpoint
    /// history lives in `EndpointStore`, so nothing is lost.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        stopRefreshTimer()
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isRefreshing = false
        for workItem in failoverWorkItems.values {
            workItem.cancel()
        }
        failoverWorkItems.removeAll()
        pendingRaces.removeAll()
        racingIdentities.removeAll()
        reconnectingIdentities.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
        cancellables.removeAll()
        recomputeRemembered()
    }

    /// Called when the status menu opens: resume monitoring on demand and refresh
    /// if the last presence check is getting stale.
    func menuWillAppear() {
        guard isStarted else { return }
        updateTimerState()
        if Date().timeIntervalSince(lastPresenceCheck) >= Tuning.refreshInterval * 0.8 {
            refreshPresence()
        }
    }

    // MARK: - Presence

    /// Requests a fresh `adb devices` pass. Coalesced: overlapping refreshes are
    /// never stacked, and a stale in-flight pass is abandoned by the timeout.
    func refreshPresence(force: Bool = false) {
        guard isStarted, adb.adbPath != nil else { return }
        guard !isRefreshing else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastPresenceCheck) < 2 { return }

        isRefreshing = true
        lastPresenceCheck = now
        scheduleRefreshTimeout()
        adb.listDevices()
    }

    private func scheduleRefreshTimeout() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishRefresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Tuning.refreshTimeout, execute: workItem)
    }

    private func finishRefresh() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isRefreshing = false
    }

    // MARK: - Observers

    private func bindPublishers() {
        adb.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.handleDevices(devices)
            }
            .store(in: &cancellables)

        deviceRepository.previousDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] previousDevices in
                self?.handlePreviousDevices(previousDevices)
            }
            .store(in: &cancellables)
    }

    private func installObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .adbIntentionalDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let transportID = notification.userInfo?["deviceID"] as? String else { return }
            self?.handleIntentionalDisconnect(transportID: transportID)
        }
    }

    /// After sleep, endpoints that failed before the Mac suspended are usually
    /// reachable again (Wi-Fi rejoined, VPN came back up), so clear all cooldowns
    /// and take a fresh look immediately instead of waiting out the backoff.
    private func handleWake() {
        guard isStarted else { return }
        lastRaceAt.removeAll()
        endpointBackoff.removeAll()
        for workItem in failoverWorkItems.values {
            workItem.cancel()
        }
        failoverWorkItems.removeAll()
        pendingRaces.removeAll()
        racingIdentities.removeAll()
        reconnectingIdentities.removeAll()
        updateTimerState()
        refreshPresence(force: true)

        // Network-change monitoring (`NWPathMonitor`) would let us react the
        // moment Wi-Fi rejoins instead of waiting for the next poll. It needs no
        // extra entitlement, but it is intentionally out of scope for this slice:
        // the 9 s presence refresh and wake handling cover the same cases, and
        // reading the path adds a second source of truth for a menu-bar utility.
    }

    // MARK: - Device feed

    private func handleDevices(_ devices: [AndroidDevice]) {
        finishRefresh()

        let previouslyConnected = connectedIdentities
        var newConnected = Set<String>()
        var newTransportIDs: [String: String] = [:]
        var newTransportIdentities: [String: String] = [:]
        var newTransportSet = Set<String>()
        var justDisconnected = Set<String>()

        for device in devices {
            let identity = device.stableID
            guard !identity.isEmpty else { continue }
            newConnected.insert(identity)
            knownIdentities[identity] = device.name
            newTransportIDs[identity] = device.id
            newTransportIdentities[device.id] = identity
            newTransportSet.insert(device.id)

            // Keep the endpoint history current: a transport that appears while an
            // identity is connected (USB plugged in, Wi-Fi re-established) is a
            // successful endpoint for that phone.
            if recordedTransports[identity] == nil {
                recordedTransports[identity] = Set(endpoints.endpoints(for: identity).map(\.address))
            }
            if recordedTransports[identity, default: []].insert(device.id).inserted {
                endpoints.recordSuccess(address: device.id, for: identity)
            }

            // The device is back: forget any explicit disconnect and any pending
            // failover, and start its cooldown window fresh.
            intentionalDisconnects.removeValue(forKey: identity)
            failoverWorkItems[identity]?.cancel()
            failoverWorkItems.removeValue(forKey: identity)
            pendingRaces.removeValue(forKey: identity)
            racingIdentities.remove(identity)
            reconnectingIdentities.remove(identity)
            lastRaceAt.removeValue(forKey: identity)
        }

        connectedIdentities = newConnected
        liveTransportIDs = newTransportIDs
        transportIdentities = newTransportIdentities
        liveTransportSet = newTransportSet

        for identity in previouslyConnected.subtracting(newConnected) {
            justDisconnected.insert(identity)
            scheduleFailoverRace(for: identity)
        }

        updateTimerState()
        recomputeRemembered()

        // Race the other remembered devices right away; the one that just dropped
        // waits out `failoverDelay` so a transport swap is not mistaken for a
        // disconnect.
        raceDisconnectedKnownDevices(excluding: justDisconnected)
    }

    private func handlePreviousDevices(_ previousDevices: [PreviousDevice]) {
        var changed = false
        let current = Set(previousDevices.map(\.serialNumber))

        for record in previousDevices where !record.serialNumber.isEmpty {
            // Import the last known host into the endpoint history so a device
            // remembered by an older release is still raceable.
            endpoints.migrate(legacyHost: record.lastKnownHost, for: record.serialNumber)
            if knownIdentities[record.serialNumber] == nil {
                knownIdentities[record.serialNumber] = record.name
                changed = true
            }
        }

        // A previous device the user removed from the menu should stop coming
        // back automatically.
        for identity in persistedIdentities.subtracting(current)
        where !connectedIdentities.contains(identity) {
            knownIdentities.removeValue(forKey: identity)
            failoverWorkItems[identity]?.cancel()
            failoverWorkItems.removeValue(forKey: identity)
            pendingRaces.removeValue(forKey: identity)
            racingIdentities.remove(identity)
            reconnectingIdentities.remove(identity)
            changed = true
        }

        persistedIdentities = current
        if changed {
            updateTimerState()
        }
        recomputeRemembered()
    }

    // MARK: - Racing

    private func scheduleFailoverRace(for identity: String) {
        guard knownIdentities[identity] != nil else { return }
        failoverWorkItems[identity]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.failoverWorkItems.removeValue(forKey: identity)
            self.race(identity: identity)
        }
        failoverWorkItems[identity] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Tuning.failoverDelay, execute: workItem)
    }

    private func raceDisconnectedKnownDevices(excluding excluded: Set<String> = []) {
        let identities = knownIdentities.keys
            .filter { !connectedIdentities.contains($0) && !excluded.contains($0) }
            .sorted()
        for (offset, identity) in identities.enumerated() {
            guard !failoverWorkItems.keys.contains(identity) else { continue }
            if offset == 0 {
                race(identity: identity)
            } else {
                // Stagger so a laptop with several remembered phones does not
                // spawn a burst of adb processes on the same run-loop turn.
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(offset) * 0.25) {
                    [weak self] in
                    self?.race(identity: identity)
                }
            }
        }
    }

    /// Starts a race for a known-but-offline identity. All candidates are dialled
    /// concurrently (in `EndpointStore` preference order, lightly staggered); the
    /// first success wins and every other completion is ignored. Never connects to
    /// USB endpoints — the cable is the only way to reach those.
    private func race(identity: String, isExplicit: Bool = false) {
        guard isStarted, knownIdentities[identity] != nil else { return }
        guard !connectedIdentities.contains(identity) else { return }
        guard !racingIdentities.contains(identity) else { return }

        let now = Date()
        if !isExplicit {
            if failoverWorkItems[identity] != nil { return }
            if intentionalDisconnects[identity] != nil { return }
            if let lastRace = lastRaceAt[identity],
                now.timeIntervalSince(lastRace) < Tuning.raceCooldown
            {
                return
            }
        }

        var candidates = endpoints.candidates(for: identity).filter { $0.kind.isWireless }
        candidates.removeAll { liveTransportSet.contains($0.address) }
        if !isExplicit {
            candidates.removeAll { endpoint in
                guard let backoff = endpointBackoff[backoffKey(identity, endpoint.address)] else {
                    return false
                }
                return backoff.retryAfter > now
            }
        }
        let accepted = Array(candidates.prefix(Tuning.maxRaceEndpoints))
        guard !accepted.isEmpty else { return }

        lastRaceAt[identity] = now
        racingIdentities.insert(identity)
        pendingRaces[identity] = PendingRace(remaining: accepted.count)
        reconnectingIdentities.insert(identity)
        recomputeRemembered()

        startCandidate(accepted[0], identity: identity)
        for (index, endpoint) in accepted.enumerated().dropFirst() {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * Tuning.raceStagger
            ) { [weak self] in
                self?.startCandidate(endpoint, identity: identity)
            }
        }
    }

    private func startCandidate(_ endpoint: DeviceEndpoint, identity: String) {
        guard pendingRaces[identity] != nil else { return }  // a winner was already found
        adb.connectToHost(endpoint.address) { [weak self] success in
            self?.handleRaceResult(identity: identity, endpoint: endpoint, success: success)
        }
    }

    private func handleRaceResult(identity: String, endpoint: DeviceEndpoint, success: Bool) {
        guard var pending = pendingRaces[identity] else { return }  // race already decided

        if success {
            pendingRaces.removeValue(forKey: identity)
            racingIdentities.remove(identity)
            reconnectingIdentities.remove(identity)
            recordedTransports[identity, default: []].insert(endpoint.address)
            endpoints.recordSuccess(address: endpoint.address, for: identity)
            endpointBackoff.removeValue(forKey: backoffKey(identity, endpoint.address))
            lastRaceAt[identity] = Date()
            recomputeRemembered()
            // `connectToHost` already asked ADB for a fresh device list; the next
            // feed update flips this identity to connected. No extra poll needed.
            return
        }

        endpoints.recordFailure(address: endpoint.address, for: identity)
        recordBackoff(identity: identity, address: endpoint.address)

        pending.remaining -= 1
        if pending.remaining <= 0 {
            pendingRaces.removeValue(forKey: identity)
            racingIdentities.remove(identity)
            reconnectingIdentities.remove(identity)
            recomputeRemembered()
        } else {
            pendingRaces[identity] = pending
        }
    }

    private func recordBackoff(identity: String, address: String) {
        let key = backoffKey(identity, address)
        var entry = endpointBackoff[key] ?? EndpointBackoff(failures: 0, retryAfter: .distantPast)
        entry.failures = min(entry.failures + 1, Tuning.maxEndpointFailures)
        let exponent = Double(max(0, entry.failures - 1))
        let delay = min(
            Tuning.endpointBaseBackoff * pow(2, exponent), Tuning.endpointMaxBackoff)
        entry.retryAfter = Date().addingTimeInterval(delay)
        endpointBackoff[key] = entry
    }

    private func backoffKey(_ identity: String, _ address: String) -> String {
        identity + "|" + address
    }

    private func handleIntentionalDisconnect(transportID: String) {
        let identity =
            transportIdentities[transportID]
            ?? DeviceScopedPreferences.shared.identity(forTransportID: transportID)
        guard !identity.isEmpty else { return }

        intentionalDisconnects[identity] = Date()
        failoverWorkItems[identity]?.cancel()
        failoverWorkItems.removeValue(forKey: identity)
        pendingRaces.removeValue(forKey: identity)
        racingIdentities.remove(identity)
        reconnectingIdentities.remove(identity)
        recomputeRemembered()
    }

    // MARK: - Public actions (menu)

    /// Explicit user request to bring a remembered device back.
    func reconnect(identity: String) {
        guard knownIdentities[identity] != nil, !connectedIdentities.contains(identity) else {
            return
        }
        intentionalDisconnects.removeValue(forKey: identity)
        lastRaceAt.removeValue(forKey: identity)
        failoverWorkItems[identity]?.cancel()
        failoverWorkItems.removeValue(forKey: identity)
        for endpoint in endpoints.candidates(for: identity) {
            endpointBackoff.removeValue(forKey: backoffKey(identity, endpoint.address))
        }
        race(identity: identity, isExplicit: true)
    }

    /// Explicitly connect one remembered address ("Change Connection" row).
    func connect(identity: String, address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard knownIdentities[identity] != nil || !connectedIdentities.contains(identity) else {
            return
        }
        intentionalDisconnects.removeValue(forKey: identity)
        endpointBackoff.removeValue(forKey: backoffKey(identity, trimmed))
        adb.connectToHost(trimmed) { [weak self] success in
            guard let self else { return }
            if success {
                self.recordedTransports[identity, default: []].insert(trimmed)
                self.endpoints.recordSuccess(address: trimmed, for: identity)
            } else {
                self.endpoints.recordFailure(address: trimmed, for: identity)
                self.recordBackoff(identity: identity, address: trimmed)
            }
            self.recomputeRemembered()
        }
    }

    /// P2 remote endpoints: stores a validated `host:port` and dials it. Hostnames,
    /// IPv4/IPv6 literals and VPN addresses (Tailscale, ZeroTier, SSH forwards) are
    /// all just `adb connect` targets, so `TransportKind.isHostAndPort` is the only
    /// validation needed.
    ///
    /// - Returns: `false` when the address is not `host:port`; nothing is stored.
    @discardableResult
    func addManualEndpoint(_ address: String, for identity: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, TransportKind.isHostAndPort(trimmed) else { return false }

        endpoints.upsert(
            DeviceEndpoint(address: trimmed, kind: .manual, isUserAdded: true), for: identity)
        if knownIdentities[identity] == nil {
            knownIdentities[identity] = displayName(for: identity)
        }
        updateTimerState()
        connect(identity: identity, address: trimmed)
        recomputeRemembered()
        return true
    }

    private func displayName(for identity: String) -> String {
        knownIdentities[identity] ?? "Android Device"
    }

    // MARK: - Timer

    private func updateTimerState() {
        let shouldRun = isStarted && (!knownIdentities.isEmpty || !connectedIdentities.isEmpty)
        if shouldRun {
            startRefreshTimer()
        } else {
            stopRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: Tuning.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshPresence()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - UI derivation

    private func recomputeRemembered() {
        var remembered: [RememberedDevice] = []
        for (identity, name) in knownIdentities where !connectedIdentities.contains(identity) {
            // An offline USB-only device (or one whose wireless endpoints have gone
            // stale after repeated failures) has nothing to reconnect to; stay quiet.
            guard endpoints.candidates(for: identity).contains(where: { $0.kind.isWireless })
            else { continue }
            remembered.append(
                RememberedDevice(
                    identity: identity,
                    name: name,
                    isReconnecting: reconnectingIdentities.contains(identity)))
        }
        remembered.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard remembered != rememberedDisconnectedDevices else { return }
        rememberedDisconnectedDevices = remembered
    }
}
