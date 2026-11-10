//
//  WirelessPairingService.swift
//  AndroLaunch
//
//  The Wi-Fi pairing brain behind the Hub's four wireless tabs. It owns exactly
//  one kind of work at a time (QR pairing, pairing-code discovery, or the
//  connect scan that follows a successful pair) so two flows can never compete
//  for the single ADB server.
//
//  Everything here is real ADB + Bonjour: `adb pair`, `adb connect`, and
//  `_adb-tls-pairing._tcp` / `_adb-tls-connect._tcp`. There is no simulated
//  success path; a phase only reaches `.connected` after adb accepted the
//  connection.
//

import Combine
import Darwin
import Foundation

final class WirelessPairingService: NSObject, ObservableObject {

    // MARK: - State

    enum QRPhase: Equatable {
        case idle
        case waitingForScan
        case pairing(endpoint: String)
        case pairedWaiting(endpoint: String)
        case connected(endpoint: String)
        case failed(message: String)
    }

    enum DiscoveryPhase: Equatable {
        case idle
        case searching
        case found
        case failed(message: String)
    }

    enum ActionPhase: Equatable {
        case idle
        case working(message: String)
        case success(message: String)
        case failure(message: String)
    }

    struct DiscoveredDevice: Identifiable, Equatable {
        let id: String
        var name: String
        var endpoint: String

        var title: String { "Device at \(endpoint)" }
    }

    /// QR pairing state, including the generated payload.
    @Published private(set) var qrPhase: QRPhase = .idle
    @Published private(set) var qrPassword: String = ""
    @Published private(set) var qrPayload: String = ""
    @Published private(set) var qrServiceName: String = ""

    /// Pairing-code tab discovery.
    @Published private(set) var discoveryPhase: DiscoveryPhase = .idle
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// Pair-and-connect action on the pairing-code tab.
    @Published private(set) var pairPhase: ActionPhase = .idle

    /// Manual IP connect action on the IP-address tab.
    @Published private(set) var connectPhase: ActionPhase = .idle

    /// Bumped whenever adb reports a new transport, so the Hub can refresh its
    /// device list without the service knowing about `HubStore`.
    @Published private(set) var connectionGeneration = 0

    // MARK: - Private state

    private enum ConnectPurpose { case qr, manualPair }

    private let adb: ADBService?
    private let preview: Bool

    private var pairingBrowser: NetServiceBrowser?
    private var connectBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var processedPairingEndpoints = Set<String>()
    private var processedConnectEndpoints = Set<String>()

    private var qrSessionActive = false
    private var pairingCodeSessionActive = false
    private var connectPurpose: ConnectPurpose?
    private var connectTimeoutWorkItem: DispatchWorkItem?

    private static let connectDiscoveryTimeout: TimeInterval = 18

    // MARK: - Init

    init(adb: ADBService? = nil, preview: Bool = false) {
        self.preview = preview
        self.adb = preview ? nil : (adb ?? DependencyContainer.shared.adb)
        super.init()
        if preview {
            // Deterministic stand-in for ImageRenderer snapshots. No ADB, no
            // Bonjour and no permission prompt is touched in preview mode.
            self.qrPassword = "482915"
            self.qrServiceName = "studio-PreviewQR"
            self.qrPayload = ADBQRCode.payload(
                password: "482915", serviceName: self.qrServiceName)
            self.qrPhase = .waitingForScan
            self.discoveryPhase = .searching
        }
    }

    deinit {
        pairingBrowser?.stop()
        connectBrowser?.stop()
        resolvingServices.forEach { $0.stop() }
        connectTimeoutWorkItem?.cancel()
    }

    // MARK: - Lifecycle

    /// Stops all discovery. Called when the Wi-Fi card collapses or the view
    /// leaves the window so no browser or permission prompt outlives the UI.
    func stop() {
        teardownDiscovery()
        if case .waitingForScan = qrPhase { qrPhase = .idle }
        if case .pairing = qrPhase { qrPhase = .idle }
        if case .pairedWaiting = qrPhase { qrPhase = .idle }
        if discoveryPhase == .searching { discoveryPhase = .idle }
        if case .working = pairPhase { pairPhase = .idle }
        if case .working = connectPhase { connectPhase = .idle }
    }

    // MARK: - QR pairing

    /// Generates a fresh six-digit code and waits for the phone's scanner.
    func startQRPairing() {
        if preview {
            if qrPayload.isEmpty {
                qrPassword = "482915"
                qrServiceName = "studio-PreviewQR"
                qrPayload = ADBQRCode.payload(
                    password: qrPassword, serviceName: qrServiceName)
            }
            qrPhase = .waitingForScan
            return
        }
        teardownDiscovery()
        guard adb?.adbPath != nil else {
            qrPhase = .failed(message: Self.adbMissingMessage)
            return
        }

        let password = ADBQRCode.randomPassword()
        let serviceName = ADBQRCode.randomServiceName()
        qrPassword = password
        qrServiceName = serviceName
        qrPayload = ADBQRCode.payload(password: password, serviceName: serviceName)
        qrPhase = .waitingForScan
        qrSessionActive = true
        startPairingBrowser()
    }

    func regenerateQR() {
        startQRPairing()
    }

    /// Clears a wedged ADB server and starts a fresh QR session. This is the
    /// in-app equivalent of `adb kill-server && adb start-server`, which
    /// resolves most persistent "protocol fault" pairing failures.
    func resetADBAndRegenerateQR() {
        guard let adb, adb.adbPath != nil else {
            qrPhase = .failed(message: Self.adbMissingMessage)
            return
        }
        teardownDiscovery()
        qrPhase = .waitingForScan
        adb.executeADBCommand(arguments: ["kill-server"]) { [weak self] _, _, _ in
            adb.executeADBCommand(arguments: ["start-server"]) { [weak self] _, _, _ in
                DispatchQueue.main.async {
                    guard self != nil else { return }
                    self?.startQRPairing()
                }
            }
        }
    }

    // MARK: - Pairing code

    /// Browses for phones showing the "Pair device with pairing code" dialog.
    func startPairingCodeDiscovery() {
        if preview {
            discoveryPhase = .searching
            discoveredDevices = []
            return
        }
        teardownDiscovery()
        guard adb?.adbPath != nil else {
            discoveryPhase = .failed(message: Self.adbMissingMessage)
            return
        }
        pairingCodeSessionActive = true
        discoveryPhase = .searching
        discoveredDevices = []
        if case .success = pairPhase { pairPhase = .idle }
        if case .failure = pairPhase { pairPhase = .idle }
        startPairingBrowser()
    }

    func retryDiscovery() {
        startPairingCodeDiscovery()
    }

    /// Pairs with a discovered or manually entered endpoint and then resolves the
    /// phone's wireless-debugging port to bring it online.
    func pair(endpoint: String, code: String) {
        guard WirelessPairingCode.isValid(code) else {
            pairPhase = .failure(
                message: "Enter the 6-digit pairing code shown on the phone.")
            return
        }
        let parsed: WirelessEndpoint
        switch WirelessEndpoint.parse(endpoint) {
        case .success(let value):
            parsed = value
        case .failure(let error):
            pairPhase = .failure(
                message: [error.message, error.guidance].compactMap { $0 }.joined(separator: " "))
            return
        }
        guard let adb, adb.adbPath != nil else {
            pairPhase = .failure(message: Self.adbMissingMessage)
            return
        }
        if case .working = pairPhase { return }
        pairPhase = .working(message: "Pairing with \(parsed.displayValue)…")
        runPair(parsed.displayValue, code: WirelessPairingCode.normalized(code))
    }

    // MARK: - IP address

    /// Manual `adb connect`. The address is validated before adb is invoked so
    /// the UI can show the exact correction instead of a generic adb error.
    func connect(address raw: String) {
        let parsed: WirelessEndpoint
        switch WirelessEndpoint.parse(raw) {
        case .success(let value):
            parsed = value
        case .failure(let error):
            connectPhase = .failure(
                message: [error.message, error.guidance].compactMap { $0 }.joined(separator: " "))
            return
        }
        guard let adb, adb.adbPath != nil else {
            connectPhase = .failure(message: Self.adbMissingMessage)
            return
        }
        if case .working = connectPhase { return }

        connectPhase = .working(message: "Connecting to \(parsed.displayValue)…")
        adb.executeADBCommand(arguments: ["connect", parsed.displayValue]) {
            [weak self] _, output, errorOutput in
            guard let self else { return }
            let combined = Self.combined(output, errorOutput)
            if ADBCommandInterpreter.connectSucceeded(combined) {
                adb.listDevices()
                self.connectPhase = .success(
                    message: "Connected to \(parsed.displayValue).")
                self.connectionGeneration += 1
            } else {
                self.connectPhase = .failure(
                    message: ADBCommandInterpreter.connectFailureMessage(output: combined))
            }
        }
    }

    /// Drops one wireless transport from adb. Used by the "connected over Wi-Fi"
    /// rows in the IP-address tab.
    func disconnect(deviceID: String) {
        guard let adb, adb.adbPath != nil else {
            connectPhase = .failure(message: Self.adbMissingMessage)
            return
        }
        adb.executeADBCommand(arguments: ["disconnect", deviceID]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            adb.listDevices()
            self.connectionGeneration += 1
            let combined = Self.combined(output, errorOutput).lowercased()
            if success || combined.contains("disconnected") {
                self.connectPhase = .success(message: "Disconnected \(deviceID).")
            } else {
                self.connectPhase = .failure(
                    message: ADBCommandInterpreter.connectFailureMessage(output: combined))
            }
        }
    }

    // MARK: - Pairing

    private func runPair(_ endpoint: String, code: String) {
        guard let adb else {
            pairPhase = .failure(message: Self.adbMissingMessage)
            return
        }
        adb.executeADBCommand(arguments: ["pair", endpoint, code]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            let combined = Self.combined(output, errorOutput)
            if success && ADBCommandInterpreter.pairSucceeded(combined) {
                adb.listDevices()
                self.connectionGeneration += 1
                self.stopPairingBrowser()
                self.pairPhase = .working(
                    message: "Paired. Waiting for the device to come online…")
                self.startConnectBrowser(purpose: .manualPair)
            } else {
                self.pairPhase = .failure(
                    message: ADBCommandInterpreter.pairFailureMessage(output: combined))
            }
        }
    }

    private func pairFromQR(endpoint: String) {
        guard let adb else {
            qrPhase = .failed(message: Self.adbMissingMessage)
            return
        }
        qrPhase = .pairing(endpoint: endpoint)
        adb.executeADBCommand(arguments: ["pair", endpoint, qrPassword]) {
            [weak self] success, output, errorOutput in
            guard let self else { return }
            let combined = Self.combined(output, errorOutput)
            if success && ADBCommandInterpreter.pairSucceeded(combined) {
                adb.listDevices()
                self.connectionGeneration += 1
                self.stopPairingBrowser()
                self.qrPhase = .pairedWaiting(endpoint: endpoint)
                self.startConnectBrowser(purpose: .qr)
            } else {
                self.stopPairingBrowser()
                self.qrPhase = .failed(
                    message: ADBCommandInterpreter.pairFailureMessage(output: combined))
            }
        }
    }

    // MARK: - Bonjour discovery

    private func startPairingBrowser() {
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_adb-tls-pairing._tcp", inDomain: "local.")
        pairingBrowser = browser
    }

    private func stopPairingBrowser() {
        pairingBrowser?.stop()
        pairingBrowser = nil
    }

    private func startConnectBrowser(purpose: ConnectPurpose) {
        stopConnectBrowser()
        connectPurpose = purpose
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_adb-tls-connect._tcp", inDomain: "local.")
        connectBrowser = browser
        scheduleConnectTimeout(for: purpose)
    }

    private func stopConnectBrowser() {
        connectBrowser?.stop()
        connectBrowser = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        connectPurpose = nil
    }

    private func scheduleConnectTimeout(for purpose: ConnectPurpose) {
        connectTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.connectPurpose == purpose else { return }
            self.stopConnectBrowser()
            let message =
                "Paired, but the device didn't come online. Turn Wireless debugging off and on again on the phone, then retry."
            switch purpose {
            case .qr:
                self.qrPhase = .failed(message: message)
            case .manualPair:
                self.pairPhase = .failure(message: message)
            }
        }
        connectTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.connectDiscoveryTimeout, execute: workItem)
    }

    private func teardownDiscovery() {
        stopPairingBrowser()
        stopConnectBrowser()
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        processedPairingEndpoints.removeAll()
        processedConnectEndpoints.removeAll()
        qrSessionActive = false
        pairingCodeSessionActive = false
    }

    // MARK: - Service resolution

    private func handleResolvedService(_ service: NetService) {
        if service.type.hasPrefix("_adb-tls-pairing") {
            handlePairingService(service)
        } else if service.type.hasPrefix("_adb-tls-connect") {
            handleConnectService(service)
        }
    }

    private func handlePairingService(_ service: NetService) {
        guard let endpoint = Self.preferredEndpoint(of: service) else { return }
        if qrSessionActive {
            // The phone advertises the exact service name embedded in our QR.
            // Ignoring every other pairing service avoids stale/previous QR
            // sessions and the confusing "protocol fault" they produce.
            guard service.name == qrServiceName else { return }
            guard processedPairingEndpoints.insert(endpoint).inserted else { return }
            stopPairingBrowser()
            pairFromQR(endpoint: endpoint)
            return
        }
        guard pairingCodeSessionActive else { return }
        guard processedPairingEndpoints.insert(endpoint).inserted else { return }
        let displayName = service.name
        if let index = discoveredDevices.firstIndex(where: { $0.endpoint == endpoint }) {
            discoveredDevices[index].name = displayName
        } else {
            discoveredDevices.append(
                DiscoveredDevice(id: endpoint, name: displayName, endpoint: endpoint))
            discoveredDevices.sort { $0.endpoint.localizedStandardCompare($1.endpoint) == .orderedAscending }
        }
        discoveryPhase = .found
    }

    private func handleConnectService(_ service: NetService) {
        guard let endpoint = Self.preferredEndpoint(of: service) else { return }
        guard let purpose = connectPurpose else { return }
        guard processedConnectEndpoints.insert(endpoint).inserted else { return }
        stopConnectBrowser()
        connectResolvedEndpoint(endpoint, purpose: purpose)
    }

    private func connectResolvedEndpoint(_ endpoint: String, purpose: ConnectPurpose) {
        guard let adb else {
            reportConnectFailure(Self.adbMissingMessage, purpose: purpose)
            return
        }
        adb.executeADBCommand(arguments: ["connect", endpoint]) {
            [weak self] _, output, errorOutput in
            guard let self else { return }
            let combined = Self.combined(output, errorOutput)
            if ADBCommandInterpreter.connectSucceeded(combined) {
                adb.listDevices()
                self.connectionGeneration += 1
                switch purpose {
                case .qr:
                    self.qrPhase = .connected(endpoint: endpoint)
                case .manualPair:
                    self.pairPhase = .success(message: "Connected to \(endpoint).")
                }
            } else {
                self.reportConnectFailure(
                    ADBCommandInterpreter.connectFailureMessage(output: combined),
                    purpose: purpose)
            }
        }
    }

    private func reportConnectFailure(_ message: String, purpose: ConnectPurpose) {
        switch purpose {
        case .qr:
            qrPhase = .failed(message: message)
        case .manualPair:
            pairPhase = .failure(message: message)
        }
    }

    // MARK: - Helpers

    private static let adbMissingMessage =
        "ADB was not found. Install Android platform-tools and try again."

    private static func combined(_ output: String?, _ errorOutput: String?) -> String {
        [output ?? "", errorOutput ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Resolves the routable endpoint advertised by an ADB mDNS service.
    /// A routable address is preferred over a link-local (169.254/fe80) one
    /// because peer-to-peer interfaces are not reachable from the phone.
    private static func preferredEndpoint(of service: NetService) -> String? {
        let port = service.port
        guard port > 0, port <= Int(UInt16.max), let addresses = service.addresses else {
            return nil
        }
        var ipv4: String?
        var linkLocalIPv4: String?
        var ipv6: String?
        var linkLocalIPv6: String?

        for address in addresses {
            address.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                switch Int32(family) {
                case AF_INET:
                    var addressValue = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    guard inet_ntop(AF_INET, &addressValue, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
                    else { return }
                    let value = String(cString: buffer)
                    if value.hasPrefix("169.254.") {
                        if linkLocalIPv4 == nil { linkLocalIPv4 = value }
                    } else if ipv4 == nil {
                        ipv4 = value
                    }
                case AF_INET6:
                    var addressValue = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    guard inet_ntop(AF_INET6, &addressValue, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil
                    else { return }
                    let value = String(cString: buffer)
                    let lowercased = value.lowercased()
                    if lowercased.hasPrefix("fe80:") {
                        if linkLocalIPv6 == nil { linkLocalIPv6 = value }
                    } else if ipv6 == nil {
                        ipv6 = value
                    }
                default:
                    return
                }
            }
        }

        if let ipv4 { return "\(ipv4):\(port)" }
        if let ipv6 { return "[\(ipv6)]:\(port)" }
        if let linkLocalIPv4 { return "\(linkLocalIPv4):\(port)" }
        if let linkLocalIPv6 { return "[\(linkLocalIPv6)]:\(port)" }
        return nil
    }
}

// MARK: - NetService delegates

extension WirelessPairingService: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
    ) {
        guard browser === pairingBrowser || browser === connectBrowser else { return }
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 8)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]
    ) {
        guard browser === pairingBrowser else { return }
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        let message =
            "Could not search for devices (code \(code)). Check Local Network permission and the Wi-Fi connection."
        if qrSessionActive {
            stopPairingBrowser()
            qrPhase = .failed(message: message)
        } else if pairingCodeSessionActive {
            stopPairingBrowser()
            discoveryPhase = .failed(message: message)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        resolvingServices.removeAll { $0 === sender }
        handleResolvedService(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 === sender }
    }
}
