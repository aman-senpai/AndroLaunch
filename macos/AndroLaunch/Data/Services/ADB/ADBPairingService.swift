//
//  ADBPairingService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/11/25.
//

import Foundation
import Combine

protocol ADBPairingServiceProtocol {
    var pairingStatus: PassthroughSubject<String, Never> { get }
    var isPairing: CurrentValueSubject<Bool, Never> { get }
    var pairingComplete: PassthroughSubject<Void, Never> { get } // NEW: Signal for completion
    
    func startPairing() -> (qrCode: String, password: String)
    func stopPairing()
}

final class ADBPairingService: NSObject, ADBPairingServiceProtocol, NetServiceBrowserDelegate, NetServiceDelegate {
    private let commandExecutor: CommandExecutorProtocol
    private let adbService: ADBServiceProtocol
    
    // Networking
    private var pairingBrowser: NetServiceBrowser?
    private var connectBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    
    // State
    private var password: String = ""
    private var isPairingAttemptInFlight = false
    
    // Deduplication
    private var processedPairingEndpoints = Set<String>()
    private var processedConnectHosts = Set<String>()
    
    let pairingStatus = PassthroughSubject<String, Never>()
    let isPairing = CurrentValueSubject<Bool, Never>(false)
    let pairingComplete = PassthroughSubject<Void, Never>() // NEW
    
    private var cancellables = Set<AnyCancellable>()
    
    init(commandExecutor: CommandExecutorProtocol, adbService: ADBServiceProtocol) {
        self.commandExecutor = commandExecutor
        self.adbService = adbService
        super.init()
    }
    
    func startPairing() -> (qrCode: String, password: String) {
        stopPairing() // Ensure clean slate

        // 1. Generate Password
        let randomCode = Int.random(in: 100000...999999)
        self.password = String(randomCode)
        
        // 2. Generate QR String
        let qrString = "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:\(self.password);;"
        
        // 3. Start Discovery
        print("ADBPairingService: Starting browsing for pairing service...")
        startPairingDiscovery()
        
        isPairing.send(true)
        pairingStatus.send("Waiting for device to scan QR code...")
        
        return (qrString, self.password)
    }
    
    func stopPairing() {
        print("ADBPairingService: stopPairing() called.")
        
        pairingBrowser?.stop()
        pairingBrowser = nil
        
        connectBrowser?.stop()
        connectBrowser = nil
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        
        processedPairingEndpoints.removeAll()
        processedConnectHosts.removeAll()
        isPairingAttemptInFlight = false
        
        cancellables.removeAll()
        
        isPairing.send(false)
        pairingStatus.send("Pairing stopped.")
    }
    
    // MARK: - Pairing Discovery
    
    private func startPairingDiscovery() {
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_adb-tls-pairing._tcp", inDomain: "local.")
        self.pairingBrowser = browser
    }
    
    private func restartPairingDiscovery() {
        pairingBrowser?.stop()
        pairingBrowser = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.isPairing.value else { return }
            self.startPairingDiscovery()
        }
    }
    
    /// Resolved `_adb-tls-pairing._tcp` service -> `adb pair`.
    ///
    /// The IP must come from the Bonjour resolution itself. Connecting to the pairing
    /// port to read it back (as this used to do) races with the actual `adb pair`
    /// handshake against the phone's pairing server and can stall indefinitely: a
    /// `NWConnection` that never reaches `.ready` or `.failed` left the UI stuck on
    /// "Resolving IP" forever, because every other state was ignored.
    private func handleResolvedPairingService(_ service: NetService) {
        guard let ip = Self.preferredIPv4Address(of: service),
              service.port > 0, service.port <= Int(UInt16.max) else {
            return
        }
        
        let endpoint = "\(ip):\(service.port)"
        guard !processedPairingEndpoints.contains(endpoint), !isPairingAttemptInFlight else { return }
        processedPairingEndpoints.insert(endpoint)
        
        pairingStatus.send("Pairing with \(endpoint)...")
        pairDevice(ip: ip, port: UInt16(service.port), endpoint: endpoint)
    }
    
    private func pairDevice(ip: String, port: UInt16, endpoint: String) {
        guard let adbPath = adbService.adbPath else {
            pairingStatus.send("ADB not found. Cannot pair.")
            return
        }
        isPairingAttemptInFlight = true
        let command = "\(adbPath) pair \"\(ip):\(port)\" \(self.password)"
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                self.isPairingAttemptInFlight = false
                if case .failure(let error) = completion {
                    self.pairingStatus.send("Pairing error: \(Self.message(for: error)) Retrying...")
                    self.processedPairingEndpoints.remove(endpoint)
                    self.restartPairingDiscovery()
                }
            } receiveValue: { [weak self] output in
                guard let self = self else { return }
                if output.contains("Successfully paired to") || output.contains("already paired") {
                    self.pairingStatus.send("Paired with \(ip). Connecting...")
                    self.pairingBrowser?.stop() // Stop pairing scan
                    self.pairingBrowser = nil
                    self.startConnectDiscovery() // Start connect scan
                } else {
                    self.pairingStatus.send("Pairing rejected. Retrying...")
                    self.processedPairingEndpoints.remove(endpoint)
                    self.restartPairingDiscovery()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connect Discovery
    
    private func startConnectDiscovery() {
        processedConnectHosts.removeAll()
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_adb-tls-connect._tcp", inDomain: "local.")
        self.connectBrowser = browser
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.type.hasPrefix("_adb-tls-pairing") {
            pairingStatus.send("Device found. Resolving IP for \(service.name)...")
        }
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === pairingBrowser else { return }
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        pairingStatus.send("Network discovery failed (code \(code)). Retrying...")
        restartPairingDiscovery()
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if sender.type.hasPrefix("_adb-tls-pairing") {
            handleResolvedPairingService(sender)
        } else {
            handleResolvedConnectService(sender)
        }
        if let idx = resolvingServices.firstIndex(of: sender) { resolvingServices.remove(at: idx) }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        if let idx = resolvingServices.firstIndex(of: sender) { resolvingServices.remove(at: idx) }
    }
    
    private func handleResolvedConnectService(_ sender: NetService) {
        if let host = sender.hostName, sender.port != -1 {
            var cleanHost = host
            if cleanHost.hasSuffix(".") { cleanHost = String(cleanHost.dropLast()) }
            let id = "\(cleanHost):\(sender.port)"
            
            if !processedConnectHosts.contains(id) {
                processedConnectHosts.insert(id)
                connectDevice(ip: cleanHost, port: UInt16(sender.port))
            }
        }
    }
    
    private func connectDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else { return }
        let command = "\(adbPath) connect \"\(ip):\(port)\""
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // On command failure, we just let the browser keep looking
            } receiveValue: { [weak self] output in
                if output.contains("connected to") || output.contains("already connected") {
                    self?.pairingStatus.send("Connected to \(ip)!")
                    self?.adbService.listDevices()
                    
                    // NEW LOGIC: Do NOT stop pairing. Signal completion.
                    self?.pairingComplete.send()
                } else {
                    self?.pairingStatus.send("Connection failed. Waiting...")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Helpers
    
    private static func message(for error: Error) -> String {
        if let adbError = error as? ADBError, case .commandFailed(let detail) = adbError {
            return detail
        }
        return error.localizedDescription
    }
    
    /// Prefers a routable IPv4 address; link-local (169.254.x.x) ones are only a last
    /// resort because they come from a peer-to-peer (AWDL) interface the phone cannot
    /// be reached on.
    private static func preferredIPv4Address(of service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        var fallback: String?
        for address in addresses {
            guard let ip = ipv4String(from: address) else { continue }
            if ip.hasPrefix("169.254.") {
                if fallback == nil { fallback = ip }
                continue
            }
            return ip
        }
        return fallback
    }
    
    private static func ipv4String(from address: Data) -> String? {
        return address.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self)
            guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
            var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }
}
